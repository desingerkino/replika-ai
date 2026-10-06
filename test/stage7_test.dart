import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/call_engine.dart';
import 'package:replika/data/models/call_record.dart';

class Rec implements CallRecorder {
  final List<(CallOutcome, Duration)> calls = [];

  @override
  Future<void> record(CallSession session, CallOutcome outcome, DateTime startedAt, Duration talked) async =>
      calls.add((outcome, talked));
}

class Snd implements CallSounds {
  final List<String> log = [];
  @override
  void ringtone() => log.add('ring');
  @override
  void ringback() => log.add('back');
  @override
  void hangup() => log.add('hangup');
  @override
  void stop() => log.add('stop');
}

CallSession session(CallDirection direction, {CallKind kind = CallKind.audio}) => CallSession(
      deviceId: 'd',
      characterId: 'c',
      direction: direction,
      kind: kind,
      displayName: 'Красотка',
    );

void main() {
  late Rec rec;
  late Snd snd;
  late DateTime now;
  late CallEngine engine;

  setUp(() {
    rec = Rec();
    snd = Snd();
    now = DateTime(2026, 9, 25, 20, 0);
    engine = CallEngine(
      recorder: rec,
      sounds: snd,
      ringTimeout: const Duration(milliseconds: 80),
      connectDelay: const Duration(milliseconds: 20),
      endedPause: const Duration(milliseconds: 20),
      clock: () => now,
    );
  });

  tearDown(() => engine.dispose());

  test('входящий: звонок, ответ, соединение, разговор, завершение', () async {
    expect(engine.start(session(CallDirection.incoming)), isTrue);
    expect(engine.phase, CallPhase.incoming);
    expect(snd.log.first, 'ring');
    engine.accept();
    expect(engine.phase, CallPhase.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(engine.phase, CallPhase.active);
    now = now.add(const Duration(seconds: 42));
    engine.hangUp();
    expect(engine.phase, CallPhase.ended);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(engine.phase, CallPhase.idle);
    expect(rec.calls, [(CallOutcome.answered, const Duration(seconds: 42))]);
  });

  test('без ответа — пропущенный', () async {
    engine.start(session(CallDirection.incoming));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(rec.calls.single.$1, CallOutcome.missed);
  });

  test('исходящий: пульт оператора — «ответил» и «сбросил»', () async {
    engine.start(session(CallDirection.outgoing));
    expect(snd.log.first, 'back');
    engine.operatorNext();
    expect(engine.phase, CallPhase.connecting);
    engine.activate();
    engine.operatorBack();
    expect(rec.calls.single.$1, CallOutcome.answered);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    engine.start(session(CallDirection.outgoing));
    engine.operatorBack();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(rec.calls.last.$1, CallOutcome.declined);
  });

  test('отмена своего вызова и второй звонок поверх первого', () async {
    engine.start(session(CallDirection.outgoing));
    expect(engine.start(session(CallDirection.incoming)), isFalse);
    engine.hangUp();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(rec.calls.single.$1, CallOutcome.cancelled);
  });

  test('сброс сцены убирает звонок без записи в историю', () {
    engine.start(session(CallDirection.incoming, kind: CallKind.video));
    expect(engine.cameraOff, isFalse);
    engine.dismiss();
    expect(engine.phase, CallPhase.idle);
    expect(rec.calls, isEmpty);
  });

  test('микрофон и камера', () {
    engine.start(session(CallDirection.outgoing));
    engine.toggleMute();
    expect(engine.muted, isTrue);
    engine.toggleCamera();
    expect(engine.cameraOff, isTrue, reason: 'в аудиозвонке камера не включается');
  });

  test('подписи звонков в переписке', () {
    expect(callSummary(CallDirection.incoming, CallKind.audio, CallOutcome.missed, Duration.zero),
        'Пропущенный аудиозвонок');
    expect(callSummary(CallDirection.outgoing, CallKind.video, CallOutcome.answered, const Duration(minutes: 1, seconds: 5)),
        'Исходящий видеозвонок · 1:05');
    expect(callSummary(CallDirection.outgoing, CallKind.audio, CallOutcome.missed, Duration.zero),
        'Исходящий аудиозвонок · нет ответа');
  });
}
