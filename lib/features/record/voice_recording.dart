import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../../app/services.dart';
import '../../data/models/media_item.dart';
import '../media/media_kinds.dart';

/// Состояние записи голосового в поле ввода.
enum VoiceRecState {
  /// Не пишем.
  idle,

  /// Пишем, пока палец держит микрофон: отпустить — отправить.
  holding,

  /// Запись «на замке» (смахнули вверх): палец можно убрать.
  locked,

  /// Запись остановлена: можно прослушать, удалить или отправить.
  stopped,
}

/// Запись голосового: держать — писать, отпустить — отправить, вверх —
/// замок, влево — отмена. Волна строится по настоящей громкости микрофона.
class VoiceRecorderController extends ChangeNotifier {
  VoiceRecorderController(this._services);

  static const Duration maxLength = Duration(minutes: 10);
  static const Duration minLength = Duration(milliseconds: 700);

  final AppServices _services;
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _amplitude;
  Timer? _ticker;

  VoiceRecState _state = VoiceRecState.idle;
  DateTime? _startedAt;
  Duration _recorded = Duration.zero;
  String? _path;
  bool _busy = false;
  bool _finishing = false;
  bool _disposed = false;

  /// Палец ещё держит микрофон (для записи, которая стартует с задержкой:
  /// окно разрешения, медленный диск).
  bool pressed = false;

  /// Сообщение о проблеме (нет доступа к микрофону и т. п.).
  final ValueNotifier<String?> problem = ValueNotifier<String?>(null);

  /// Замеры громкости 0..1 (каждые 80 мс).
  final List<double> levels = [];

  VoiceRecState get state => _state;
  bool get active => _state != VoiceRecState.idle;
  String? get path => _path;

  Duration get elapsed => switch (_state) {
        VoiceRecState.holding || VoiceRecState.locked =>
          _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!),
        _ => _recorded,
      };

  /// Готовый файл для прослушивания перед отправкой.
  MediaItem? get draft {
    final path = _path;
    if (_state != VoiceRecState.stopped || path == null) return null;
    return MediaItem(
      id: 'voice-draft-$path',
      kind: MediaKind.voice,
      path: path,
      durationMs: _recorded.inMilliseconds,
      waveform: downsampleWaveform(levels),
      createdAt: DateTime.now(),
    );
  }

  void _set(VoiceRecState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  /// Начать запись (палец на микрофоне). [locked] — сразу «на замке».
  Future<void> start({bool locked = false}) async {
    if (_state != VoiceRecState.idle || _busy) return;
    _busy = true;
    problem.value = null;
    try {
      await _services.audio.stop();
      final recorder = AudioRecorder();
      _recorder = recorder;
      if (!await recorder.hasPermission()) {
        if (!_disposed) problem.value = 'Нет доступа к микрофону. Разрешите его в настройках устройства.';
        await _disposeRecorder();
        return;
      }
      if (_disposed) {
        await _disposeRecorder();
        return;
      }
      final path = await _services.media.newRecordingPath('.m4a');
      await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (_disposed) {
        try {
          await recorder.cancel();
        } catch (_) {}
        await _disposeRecorder();
        return;
      }
      _path = path;
      levels.clear();
      _startedAt = DateTime.now();
      unawaited(HapticFeedback.mediumImpact());
      _amplitude = recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((a) {
        levels.add(levelFromDb(a.current));
        notifyListeners();
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (elapsed >= maxLength) {
          unawaited(stop());
        } else {
          notifyListeners();
        }
      });
      // Палец отпустили, пока запись запускалась (или жест прервало окно
      // системы): запись не остаётся «висеть» без пальца — ставим её на
      // замок, где есть «Удалить» и «Стоп».
      _set(locked || !pressed ? VoiceRecState.locked : VoiceRecState.holding);
    } catch (error) {
      debugPrint('Запись не началась: $error');
      if (!_disposed) problem.value = 'Не удалось начать запись: микрофон недоступен';
      await _disposeRecorder();
      _set(VoiceRecState.idle);
    } finally {
      _busy = false;
    }
  }

  /// Смахнули вверх: запись продолжается без пальца.
  void lock() {
    if (_state != VoiceRecState.holding) return;
    unawaited(HapticFeedback.selectionClick());
    _set(VoiceRecState.locked);
  }

  Future<void> _stopStreams() async {
    _ticker?.cancel();
    _ticker = null;
    await _amplitude?.cancel();
    _amplitude = null;
  }

  Future<void> _disposeRecorder() async {
    final recorder = _recorder;
    _recorder = null;
    try {
      await recorder?.dispose();
    } catch (_) {}
  }

  /// Остановить запись и оставить её для прослушивания.
  Future<void> stop() async {
    if (_state != VoiceRecState.holding && _state != VoiceRecState.locked) return;
    // Сразу «остановлено»-в-процессе: повторный вызов (двойное касание)
    // не останавливает запись второй раз.
    _recorded = elapsed;
    _state = VoiceRecState.stopped;
    await _stopStreams();
    try {
      final path = await _recorder?.stop();
      if (path != null) _path = path;
    } catch (error) {
      debugPrint('Запись не остановлена: $error');
    }
    await _disposeRecorder();
    if (_recorded < minLength) {
      await cancel();
      return;
    }
    _set(VoiceRecState.stopped);
  }

  /// Удалить запись.
  Future<void> cancel() async {
    final wasRecording = _state == VoiceRecState.holding || _state == VoiceRecState.locked;
    await _stopStreams();
    if (wasRecording) {
      try {
        await _recorder?.cancel();
      } catch (_) {}
    }
    await _disposeRecorder();
    if (_services.audio.currentId?.startsWith('voice-draft-') ?? false) await _services.audio.stop();
    final path = _path;
    if (path != null) {
      try {
        if (File(path).existsSync()) File(path).deleteSync();
      } catch (_) {}
    }
    _path = null;
    levels.clear();
    _recorded = Duration.zero;
    if (wasRecording) unawaited(HapticFeedback.lightImpact());
    _set(VoiceRecState.idle);
  }

  /// Закончить и вернуть готовый файл медиатеки (null — слишком коротко
  /// или ошибка). После вызова контроллер снова свободен.
  Future<MediaItem?> finish() async {
    if (_finishing) return null;
    _finishing = true;
    try {
      return await _finish();
    } finally {
      _finishing = false;
    }
  }

  bool get finishing => _finishing;

  Future<MediaItem?> _finish() async {
    if (_state == VoiceRecState.holding || _state == VoiceRecState.locked) {
      await stop();
    }
    final path = _path;
    if (_state != VoiceRecState.stopped || path == null) return null;
    if (_services.audio.currentId?.startsWith('voice-draft-') ?? false) await _services.audio.stop();
    try {
      final item = await _services.media.registerVoice(
        path,
        duration: _recorded,
        waveform: downsampleWaveform(levels),
      );
      _path = null;
      levels.clear();
      _recorded = Duration.zero;
      _set(VoiceRecState.idle);
      return item;
    } catch (error) {
      debugPrint('Голосовое не сохранено: $error');
      problem.value = 'Не удалось сохранить запись';
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_amplitude?.cancel());
    unawaited(_recorder?.dispose());
    problem.dispose();
    super.dispose();
  }
}
