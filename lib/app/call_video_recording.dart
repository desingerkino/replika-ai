import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:replika_recorder/replika_recorder.dart';

/// Что записывающая часть умеет. Отдельный интерфейс — чтобы логику
/// записи звонка можно было проверить автотестом без телефона.
abstract class ScreenRecorderBackend {
  Future<bool> isSupported();
  Future<bool> requestGalleryAccess();
  Future<void> start({required bool microphone});
  Future<String?> stop();
  Future<bool> saveToGallery(String path, String name);
}

/// Настоящая запись: ReplayKit (iPhone) / MediaProjection (Android).
class PluginScreenRecorderBackend implements ScreenRecorderBackend {
  const PluginScreenRecorderBackend();

  @override
  Future<bool> isSupported() => ReplikaRecorder.isSupported();

  @override
  Future<bool> requestGalleryAccess() => ReplikaRecorder.requestGalleryAccess();

  @override
  Future<void> start({required bool microphone}) => ReplikaRecorder.start(microphone: microphone);

  @override
  Future<String?> stop() => ReplikaRecorder.stop();

  @override
  Future<bool> saveToGallery(String path, String name) => ReplikaRecorder.saveToGallery(path, name);
}

/// Итог записи звонка.
enum CallRecordingOutcome {
  /// Видео в галерее («Фото» на iPhone, Movies/Replika на Android).
  savedToGallery,

  /// В галерею не вышло, видео лежит в папке приложения.
  savedLocally,

  /// Записывать было нечего (запись не стартовала или была слишком короткой).
  nothing,

  /// Запись не удалась.
  failed,
}

class CallRecordingResult {
  const CallRecordingResult(this.outcome, {this.path, this.name});

  final CallRecordingOutcome outcome;
  final String? path;
  final String? name;
}

/// Имя файла: Replika_2026-10-07_03-45-12.mp4
String callRecordingFileName(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Replika_${time.year}-${two(time.month)}-${two(time.day)}_'
      '${two(time.hour)}-${two(time.minute)}-${two(time.second)}.mp4';
}

Future<bool> _defaultAskMicrophone() async {
  final recorder = AudioRecorder();
  try {
    return await recorder.hasPermission();
  } catch (_) {
    return false;
  } finally {
    unawaited(recorder.dispose());
  }
}

Future<Directory> _defaultLocalFolder() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'call_recordings'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Автозапись одного видеозвонка в ОДИН mp4: картинка экрана Replika (камера,
/// видео собеседника, кнопки, переключение камеры) и звук.
///
/// Порядок: [start] — когда звонок пошёл; [stopAndSave] — когда закончился,
/// экран закрывается или приложение свернули. Оба метода безопасно вызывать
/// повторно и в любом порядке; запись никогда не бросает исключения наружу —
/// сбой записи не должен ломать сам звонок.
class CallVideoRecording {
  CallVideoRecording({
    ScreenRecorderBackend backend = const PluginScreenRecorderBackend(),
    Future<bool> Function()? askMicrophone,
    Future<Directory> Function()? localFolder,
    DateTime Function()? now,
  })  : _backend = backend,
        _askMicrophone = askMicrophone ?? _defaultAskMicrophone,
        _localFolder = localFolder ?? _defaultLocalFolder,
        _now = now ?? DateTime.now;

  final ScreenRecorderBackend _backend;
  final Future<bool> Function() _askMicrophone;
  final Future<Directory> Function() _localFolder;
  final DateTime Function() _now;

  Future<void>? _starting;
  Future<CallRecordingResult>? _stopping;
  bool _started = false;
  bool _finished = false;
  DateTime? _startedAt;

  /// Идёт запись.
  bool get active => _started && !_finished;

  /// Запись ещё запускается (разрешения, системное окно «Начать запись»).
  bool get starting => _startInFlight;
  bool _startInFlight = false;

  /// Почему запись не началась (для отчёта/диагностики), если не началась.
  String? problem;

  /// Начинает запись. Запрашивает разрешения заранее (галерея, микрофон).
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    _startInFlight = true;
    try {
      if (!await _backend.isSupported()) {
        problem = 'Запись экрана не поддерживается';
        return;
      }
      // Разрешения — до записи, чтобы по окончании звонка не было сюрпризов.
      await _backend.requestGalleryAccess();
      final mic = await _askMicrophone();
      if (_finished) return; // звонок уже закончился, пока шли вопросы
      _startedAt = _now();
      await _backend.start(microphone: mic);
      _started = true;
      if (_finished) {
        // Звонок закончился, пока система показывала своё окно записи.
        await _closeAndSave();
      }
    } on RecorderException catch (e) {
      problem = e.denied ? 'Запись не разрешена' : e.message;
    } catch (e) {
      problem = e.toString();
    } finally {
      _startInFlight = false;
    }
  }

  /// Останавливает запись, закрывает файл и кладёт видео в галерею.
  Future<CallRecordingResult> stopAndSave() => _stopping ??= _stop();

  Future<CallRecordingResult> _stop() async {
    _finished = true;
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {}
    }
    if (!_started) {
      return CallRecordingResult(problem == null ? CallRecordingOutcome.nothing : CallRecordingOutcome.failed);
    }
    return _closeAndSave();
  }

  Future<CallRecordingResult>? _closing;

  /// Закрывает файл ровно один раз, сколько бы раз ни вызвали.
  Future<CallRecordingResult> _closeAndSave() => _closing ??= _doCloseAndSave();

  Future<CallRecordingResult> _doCloseAndSave() async {
    String? path;
    try {
      path = await _backend.stop();
    } catch (e) {
      debugPrint('Запись звонка не закрылась: $e');
      problem = e.toString();
      return const CallRecordingResult(CallRecordingOutcome.failed);
    }
    if (path == null) return const CallRecordingResult(CallRecordingOutcome.nothing);

    final name = callRecordingFileName(_startedAt ?? _now());
    try {
      if (await _backend.saveToGallery(path, name)) {
        await _delete(path);
        return CallRecordingResult(CallRecordingOutcome.savedToGallery, name: name);
      }
    } catch (e) {
      debugPrint('Видео не попало в галерею: $e');
    }
    // Запасной путь: хотя бы папка приложения (в «Файлах» на iPhone её видно не всегда).
    try {
      final dir = await _localFolder();
      final target = p.join(dir.path, name);
      await File(path).copy(target);
      await _delete(path);
      return CallRecordingResult(CallRecordingOutcome.savedLocally, path: target, name: name);
    } catch (e) {
      debugPrint('Видео звонка не сохранено: $e');
      return CallRecordingResult(CallRecordingOutcome.failed, path: path, name: name);
    }
  }

  Future<void> _delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
