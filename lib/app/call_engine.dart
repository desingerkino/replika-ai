import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/call_record.dart';

/// Этап постановочного звонка.
enum CallPhase {
  idle,
  incoming,
  outgoing,
  connecting,
  active,
  ended,
}

/// Кто и как звонит. Неизменяемо; для смены материалов — copyWith.
@immutable
class CallSession {
  const CallSession({
    required this.deviceId,
    required this.characterId,
    required this.direction,
    required this.kind,
    required this.displayName,
    this.chatId,
    this.sceneId,
    this.avatarTone,
    this.avatarPath,
    this.peerAudioPath,
    this.peerVideoPath,
    this.mirrorDeviceId,
    this.mirrorCharacterId,
  });

  final String deviceId;
  final String characterId;
  final CallDirection direction;
  final CallKind kind;
  final String displayName;
  final String? chatId;
  final String? sceneId;
  final int? avatarTone;
  final String? avatarPath;

  /// Голос собеседника (файл медиатеки) — звучит в разговоре.
  final String? peerAudioPath;

  /// Видео собеседника — показывается в видеозвонке.
  final String? peerVideoPath;

  /// Профиль собеседника на этом же устройстве: звонок записывается
  /// и в его историю (зеркально). [mirrorCharacterId] — кто для него звонил.
  final String? mirrorDeviceId;
  final String? mirrorCharacterId;

  CallSession copyWith({String? peerAudioPath, String? peerVideoPath}) => CallSession(
        deviceId: deviceId,
        characterId: characterId,
        direction: direction,
        kind: kind,
        displayName: displayName,
        chatId: chatId,
        sceneId: sceneId,
        avatarTone: avatarTone,
        avatarPath: avatarPath,
        peerAudioPath: peerAudioPath ?? this.peerAudioPath,
        peerVideoPath: peerVideoPath ?? this.peerVideoPath,
        mirrorDeviceId: mirrorDeviceId,
        mirrorCharacterId: mirrorCharacterId,
      );
}

/// Запись звонка в историю и в переписку. Отделено для автотестов.
abstract class CallRecorder {
  Future<void> record(CallSession session, CallOutcome outcome, DateTime startedAt, Duration talked);
}

/// Звуки звонка. Отделено для автотестов.
abstract class CallSounds {
  void ringtone();
  void ringback();
  void hangup();
  void stop();
}

/// Подпись звонка в переписке и истории: «Пропущенный видеозвонок»,
/// «Исходящий аудиозвонок · 1:05».
String callSummary(CallDirection direction, CallKind kind, CallOutcome outcome, Duration talked) {
  final what = kind == CallKind.video ? 'видеозвонок' : 'аудиозвонок';
  String clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  if (direction == CallDirection.incoming) {
    return switch (outcome) {
      CallOutcome.answered => 'Входящий $what · ${clock(talked)}',
      CallOutcome.missed => 'Пропущенный $what',
      CallOutcome.declined => 'Отклонённый $what',
      CallOutcome.cancelled => 'Пропущенный $what',
    };
  }
  return switch (outcome) {
    CallOutcome.answered => 'Исходящий $what · ${clock(talked)}',
    CallOutcome.missed => 'Исходящий $what · нет ответа',
    CallOutcome.declined => 'Исходящий $what · отклонён',
    CallOutcome.cancelled => 'Исходящий $what · отменён',
  };
}

/// Call Engine: состояния постановочного звонка отдельно от экрана.
/// Управляют им кнопки экрана звонка, действия сцены и пульт громкостью.
class CallEngine extends ChangeNotifier {
  CallEngine({
    required this.recorder,
    required this.sounds,
    this.ringTimeout = const Duration(seconds: 40),
    this.connectDelay = const Duration(milliseconds: 1200),
    this.endedPause = const Duration(milliseconds: 1600),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CallRecorder recorder;
  final CallSounds sounds;
  final Duration ringTimeout;
  final Duration connectDelay;
  final Duration endedPause;
  final DateTime Function() _clock;

  CallPhase _phase = CallPhase.idle;
  CallSession? _session;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speaker = false;
  DateTime? _startedAt;
  DateTime? _activeSince;
  CallOutcome? _outcome;
  Timer? _timer;
  Timer? _ticker;

  CallPhase get phase => _phase;
  CallSession? get session => _session;
  bool get muted => _muted;
  bool get cameraOff => _cameraOff;

  /// Звук через громкий динамик. Аудиозвонок начинается в разговорном
  /// (верхнем) динамике, как у настоящего телефона; видеозвонок — в громком.
  bool get speaker => _speaker;
  CallOutcome? get outcome => _outcome;
  bool get inCall => _phase != CallPhase.idle && _phase != CallPhase.ended;

  Duration get talked {
    final since = _activeSince;
    return since == null ? Duration.zero : _clock().difference(since);
  }

  void _set(CallPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  void _cancelTimers() {
    _timer?.cancel();
    _ticker?.cancel();
  }

  /// Начать звонок. false — уже идёт другой звонок.
  bool start(CallSession session) {
    if (inCall) return false;
    _cancelTimers();
    _session = session;
    _muted = false;
    _cameraOff = session.kind == CallKind.audio;
    _speaker = session.kind == CallKind.video;
    _startedAt = _clock();
    _activeSince = null;
    _outcome = null;
    if (session.direction == CallDirection.incoming) {
      sounds.ringtone();
      _set(CallPhase.incoming);
    } else {
      sounds.ringback();
      _set(CallPhase.outgoing);
    }
    _timer = Timer(ringTimeout, () {
      if (_phase == CallPhase.incoming || _phase == CallPhase.outgoing) _finish(CallOutcome.missed);
    });
    return true;
  }

  /// Трубку сняли: актёр — на входящем, собеседник — на исходящем.
  void accept() {
    if (_phase != CallPhase.incoming && _phase != CallPhase.outgoing) return;
    _timer?.cancel();
    sounds.stop();
    _set(CallPhase.connecting);
    _timer = Timer(connectDelay, activate);
  }

  /// Разговор начался (без паузы «Соединение…» — для действий сцены).
  void activate() {
    if (!inCall || _phase == CallPhase.active) return;
    _timer?.cancel();
    sounds.stop();
    _activeSince = _clock();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    _set(CallPhase.active);
  }

  /// Отклонить: актёр — входящий, собеседник — исходящий.
  void decline() {
    if (_phase == CallPhase.incoming || _phase == CallPhase.outgoing) {
      _finish(CallOutcome.declined);
    }
  }

  /// Положить трубку (кто угодно).
  void hangUp() {
    switch (_phase) {
      case CallPhase.incoming:
        _finish(CallOutcome.declined);
      case CallPhase.outgoing:
        _finish(CallOutcome.cancelled);
      case CallPhase.connecting:
      case CallPhase.active:
        _finish(CallOutcome.answered);
      case CallPhase.idle:
      case CallPhase.ended:
        break;
    }
  }

  /// Трубку положил собеседник (не тот, чей профиль на экране): пока звонок
  /// не принят — для экрана это пропущенный вызов; в разговоре — завершён.
  void remoteHangUp() {
    switch (_phase) {
      case CallPhase.incoming:
        _finish(CallOutcome.missed);
      case CallPhase.outgoing:
        _finish(CallOutcome.declined);
      case CallPhase.connecting:
      case CallPhase.active:
        _finish(CallOutcome.answered);
      case CallPhase.idle:
      case CallPhase.ended:
        break;
    }
  }

  /// Команда оператора с пульта: «собеседник ответил».
  void operatorNext() {
    if (_phase == CallPhase.outgoing) accept();
  }

  /// Команда оператора с пульта: «собеседник сбросил / положил трубку».
  void operatorBack() {
    if (_phase == CallPhase.outgoing) {
      decline();
    } else if (inCall) {
      hangUp();
    }
  }

  void toggleMute() {
    if (!inCall) return;
    _muted = !_muted;
    notifyListeners();
  }

  void toggleSpeaker() {
    if (!inCall) return;
    _speaker = !_speaker;
    notifyListeners();
  }

  void toggleCamera() {
    if (!inCall || _session?.kind != CallKind.video) return;
    _cameraOff = !_cameraOff;
    notifyListeners();
  }

  /// Сменить голос или видео собеседника прямо во время звонка.
  void setPeerMedia({String? audioPath, String? videoPath}) {
    final session = _session;
    if (session == null) return;
    _session = session.copyWith(peerAudioPath: audioPath, peerVideoPath: videoPath);
    notifyListeners();
  }

  void _finish(CallOutcome outcome) {
    final session = _session;
    _cancelTimers();
    sounds.stop();
    final talked = outcome == CallOutcome.answered ? this.talked : Duration.zero;
    if (outcome == CallOutcome.answered || outcome == CallOutcome.declined) sounds.hangup();
    _outcome = outcome;
    _set(CallPhase.ended);
    if (session != null) {
      unawaited(recorder
          .record(session, outcome, _startedAt ?? _clock(), talked)
          .catchError((Object error) => debugPrint('Звонок не записан: $error')));
    }
    _timer = Timer(endedPause, dismiss);
  }

  /// Убрать экран звонка без записи в историю (например, «СБРОС СЦЕНЫ»).
  void dismiss() {
    _cancelTimers();
    sounds.stop();
    _session = null;
    _activeSince = null;
    _set(CallPhase.idle);
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }
}
