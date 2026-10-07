import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../data/models/media_item.dart';
import '../media/media_kinds.dart';

/// Этап записи голосового.
/// [holding] — палец на микрофоне, запись идёт; отпустил — отправится.
/// [locked] — запись зафиксирована свайпом вверх; палец можно убрать.
enum VoiceRecState { idle, holding, locked }

/// Источник звука. Отделён от экрана, чтобы состояния записи проверялись
/// автотестами без микрофона.
abstract class VoiceCapture {
  /// true — запись началась; false — нет доступа к микрофону.
  Future<bool> start();

  /// Громкость 0..1 во время записи.
  Stream<double> get levels;

  /// Остановить и вернуть путь к файлу.
  Future<String?> stop();

  /// Остановить и удалить файл.
  Future<void> cancel();

  Future<void> dispose();
}

/// Запись через пакет `record` (AAC, .m4a), как и раньше.
class RecordVoiceCapture implements VoiceCapture {
  RecordVoiceCapture({required this.newPath});

  final Future<String> Function() newPath;
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _levels = StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _amplitude;
  String? _path;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final path = await newPath();
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _path = path;
    _amplitude = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) => _levels.add(levelFromDb(a.current)));
    return true;
  }

  @override
  Future<String?> stop() async {
    await _amplitude?.cancel();
    _amplitude = null;
    return await _recorder.stop() ?? _path;
  }

  @override
  Future<void> cancel() async {
    await _amplitude?.cancel();
    _amplitude = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      final path = _path;
      if (path != null && File(path).existsSync()) File(path).deleteSync();
    }
  }

  @override
  Future<void> dispose() async {
    await _amplitude?.cancel();
    await _levels.close();
    await _recorder.dispose();
  }
}

/// Подсказка, если микрофон только коснулись.
const String voiceHoldHint = 'Удерживайте микрофон, чтобы записать голосовое';

/// Жест записи голосового: нажал и держишь — идёт запись, отпустил — отправка,
/// свайп вверх — фиксация, свайп влево — отмена.
///
/// Контроллер не знает про экран: файл регистрируется через [register],
/// готовое голосовое отдаётся в [onRecorded], проблемы — в [onProblem].
class VoiceRecordingController extends ChangeNotifier {
  VoiceRecordingController({
    required this.capture,
    required this.register,
    required this.onRecorded,
    required this.onProblem,
    DateTime Function()? clock,
    this.minLength = const Duration(milliseconds: 700),
    this.maxLength = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now;

  /// Насколько вверх нужно провести, чтобы запись зафиксировалась.
  static const double lockDistance = 72;

  /// Насколько влево нужно провести, чтобы запись отменилась.
  static const double cancelDistance = 96;

  final VoiceCapture capture;
  final Future<MediaItem> Function(String path, Duration duration, List<double> waveform) register;
  final Future<void> Function(MediaItem item) onRecorded;
  final void Function(String message) onProblem;
  final DateTime Function() _clock;
  final Duration minLength;
  final Duration maxLength;

  VoiceRecState _state = VoiceRecState.idle;
  Offset _origin = Offset.zero;
  double _cancelProgress = 0;
  double _lockProgress = 0;
  DateTime? _startedAt;
  final List<double> _levels = [];
  StreamSubscription<double>? _levelSub;
  Timer? _ticker;
  int _session = 0;
  bool _disposed = false;

  VoiceRecState get state => _state;
  bool get active => _state != VoiceRecState.idle;
  bool get locked => _state == VoiceRecState.locked;

  /// 0..1 — как далеко палец ушёл влево / вверх.
  double get cancelProgress => _cancelProgress;
  double get lockProgress => _lockProgress;

  /// Запись действительно началась (есть доступ к микрофону).
  bool get recording => _startedAt != null;

  Duration get elapsed => _startedAt == null ? Duration.zero : _clock().difference(_startedAt!);

  /// Последние столбики громкости для волны.
  List<double> get recentLevels =>
      _levels.length > 40 ? _levels.sublist(_levels.length - 40) : List<double>.of(_levels);

  /// Сколько столбиков в волне записи: всегда столько, даже в первые доли
  /// секунды, когда замеров ещё один-два.
  static const int liveBars = 40;

  /// Волна записи фиксированной длины: новые замеры приходят справа,
  /// недостающие слева — тихие столбики.
  List<double> get liveWaveform {
    final recent =
        _levels.length > liveBars ? _levels.sublist(_levels.length - liveBars) : _levels;
    return [
      for (var i = recent.length; i < liveBars; i++) 0.05,
      ...recent,
    ];
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Палец лёг на микрофон: запись начинается сразу.
  Future<void> press(Offset position) async {
    if (_state != VoiceRecState.idle) return;
    final session = ++_session;
    _state = VoiceRecState.holding;
    _origin = position;
    _cancelProgress = 0;
    _lockProgress = 0;
    _startedAt = null;
    _levels.clear();
    _changed();
    await _begin(session);
  }

  Future<void> _begin(int session) async {
    var started = false;
    String? problem;
    try {
      started = await capture.start();
      if (!started) problem = 'Нет доступа к микрофону. Разрешите его в настройках устройства.';
    } catch (error) {
      debugPrint('Запись не началась: $error');
      problem = 'Не удалось начать запись';
    }
    if (session != _session) {
      // Жест уже закончился (отпустили или отменили), пока запись стартовала.
      if (started) {
        try {
          await capture.cancel();
        } catch (_) {}
      }
      return;
    }
    if (!started) {
      _resetToIdle();
      if (problem != null) onProblem(problem);
      return;
    }
    _startedAt = _clock();
    _levelSub = capture.levels.listen(_levels.add);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_state == VoiceRecState.idle) return;
      if (elapsed >= maxLength) {
        unawaited(_finish(send: true));
      } else {
        _changed();
      }
    });
    _changed();
  }

  /// Движение пальца (глобальные координаты). Вверх — фиксация, влево — отмена.
  void drag(Offset position) {
    if (_state != VoiceRecState.holding) return;
    final dx = position.dx - _origin.dx;
    final dy = _origin.dy - position.dy;
    final cancel = (-dx / cancelDistance).clamp(0.0, 1.0);
    final lock = (dy / lockDistance).clamp(0.0, 1.0);
    if (lock >= 1) {
      _state = VoiceRecState.locked;
      _cancelProgress = 0;
      _lockProgress = 1;
      _changed();
      return;
    }
    if (cancel >= 1) {
      unawaited(_finish(send: false));
      return;
    }
    if ((cancel - _cancelProgress).abs() >= 0.02 || (lock - _lockProgress).abs() >= 0.02) {
      _cancelProgress = cancel;
      _lockProgress = lock;
      _changed();
    }
  }

  /// Палец поднят. Пока запись не зафиксирована — она завершается и отправляется.
  Future<void> release() async {
    if (_state != VoiceRecState.holding) return;
    await _finish(send: true);
  }

  /// Кнопка «отправить» при зафиксированной записи.
  Future<void> sendLocked() async {
    if (_state != VoiceRecState.locked) return;
    await _finish(send: true);
  }

  /// Отмена: запись удаляется, ничего не отправляется.
  Future<void> cancel() => _finish(send: false);

  void _stopStreams() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_levelSub?.cancel());
    _levelSub = null;
  }

  void _resetToIdle() {
    _stopStreams();
    _state = VoiceRecState.idle;
    _cancelProgress = 0;
    _lockProgress = 0;
    _startedAt = null;
    _changed();
  }

  Future<void> _finish({required bool send}) async {
    if (_state == VoiceRecState.idle) return;
    _session++; // всё, что ещё стартует, будет отменено
    final startedAt = _startedAt;
    final length = startedAt == null ? Duration.zero : _clock().difference(startedAt);
    final waveform = downsampleWaveform(_levels);
    _resetToIdle();
    if (startedAt == null) {
      // Запись ещё не успела начаться: _begin сам её отменит.
      if (send) onProblem(voiceHoldHint);
      return;
    }
    try {
      if (!send) {
        await capture.cancel();
        return;
      }
      if (length < minLength) {
        await capture.cancel();
        onProblem(voiceHoldHint);
        return;
      }
      final path = await capture.stop();
      if (path == null) {
        onProblem('Не удалось сохранить запись');
        return;
      }
      final item = await register(path, length, waveform);
      await onRecorded(item);
    } catch (error) {
      debugPrint('Голосовое не сохранено: $error');
      onProblem('Не удалось сохранить запись');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final wasActive = _state != VoiceRecState.idle;
    _session++;
    _stopStreams();
    _state = VoiceRecState.idle;
    if (wasActive) unawaited(capture.cancel().catchError((Object _) {}));
    unawaited(capture.dispose());
    super.dispose();
  }
}
