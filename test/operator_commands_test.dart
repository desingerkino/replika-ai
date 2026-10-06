// Слой команд оператора: приоритет «дубль → звонок → импровизация»,
// «Стоп» и «Сброс», клавиатурный источник. Без базы и без платформы.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/improv.dart';
import 'package:replika/app/operator/operator_commands.dart';
import 'package:replika/app/operator/operator_inputs.dart';
import 'package:replika/app/scene_engine.dart';
import 'package:replika/data/models/call_record.dart';
import 'package:replika/data/models/scene_action.dart';

import 'stage4_test.dart' show FakeEffects, act, settle;
import 'stage6_test.dart' show FakeSender;
import 'stage7_test.dart' show Rec, Snd, session;

class _Env {
  _Env({List<SceneAction>? actions}) {
    fx = FakeEffects(actions ?? [act('a', ActionType.showIncoming), act('b', ActionType.showOutgoing)]);
    engine = SceneEngine(fx);
    calls = CallEngine(
      recorder: Rec(),
      sounds: Snd(),
      ringTimeout: const Duration(seconds: 5),
      connectDelay: const Duration(milliseconds: 20),
      endedPause: const Duration(milliseconds: 20),
    );
    sender = FakeSender();
    improv = ImprovController(sender);
    layer = OperatorCommandLayer(
      engine: engine,
      calls: calls,
      improv: improv,
      onResetStart: () => events.add('start'),
      onResetDone: () => events.add('done'),
    );
  }

  late final FakeEffects fx;
  late final SceneEngine engine;
  late final CallEngine calls;
  late final FakeSender sender;
  late final ImprovController improv;
  late final OperatorCommandLayer layer;
  final List<String> events = [];

  void dispose() => calls.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OperatorCommandLayer', () {
    late _Env env;
    setUp(() => env = _Env());
    tearDown(() => env.dispose());

    test('«Далее» ведёт сцену, когда идёт дубль', () async {
      await env.engine.load('s1');
      await env.engine.start();
      expect(env.engine.status, EngineStatus.waiting);
      final out = await env.layer.dispatch(OperatorCommand.next, OperatorInputSource.keyboard);
      await settle();
      expect(out.target, OperatorTarget.scene);
      expect(out.handled, isTrue);
      expect(env.fx.performed, ['a']);
    });

    test('без дубля «Далее» не запускает сцену случайно', () async {
      await env.engine.load('s1');
      final out = await env.layer.dispatch(OperatorCommand.next, OperatorInputSource.app);
      await settle(50);
      expect(out.target, OperatorTarget.none);
      expect(env.fx.takes, 0);
      expect(env.engine.status, EngineStatus.ready);
    });

    test('дубль важнее звонка: пока идёт дубль, команда не уходит в звонок', () async {
      await env.engine.load('s1');
      await env.engine.start();
      env.calls.start(session(CallDirection.outgoing));
      final out = await env.layer.dispatch(OperatorCommand.next, OperatorInputSource.app);
      expect(out.target, OperatorTarget.scene);
      expect(env.calls.phase, CallPhase.outgoing);
    });

    test('без дубля команды управляют звонком', () async {
      env.calls.start(session(CallDirection.outgoing));
      final next = await env.layer.dispatch(OperatorCommand.next, OperatorInputSource.app);
      expect(next.target, OperatorTarget.call);
      expect(env.calls.phase, CallPhase.connecting);
      final back = await env.layer.dispatch(OperatorCommand.previous, OperatorInputSource.app);
      expect(back.target, OperatorTarget.call);
      expect(env.calls.phase, CallPhase.ended);
    });

    test('без дубля и звонка команды управляют очередью импровизации', () async {
      env.improv
        ..setChat('c1')
        ..enqueue(const QueuedReply(text: 'Ты где?'))
        ..arm(true);
      final next = await env.layer.dispatch(OperatorCommand.next, OperatorInputSource.androidVolume);
      await settle(50);
      expect(next.target, OperatorTarget.improv);
      expect(env.sender.chat, ['Ты где?']);
      final back = await env.layer.dispatch(OperatorCommand.previous, OperatorInputSource.androidVolume);
      await settle(50);
      expect(back.target, OperatorTarget.improv);
      expect(env.sender.chat, isEmpty);
    });

    test('«Назад» отменяет последнее действие дубля', () async {
      await env.engine.load('s1');
      await env.engine.start();
      await env.layer.dispatch(OperatorCommand.next, OperatorInputSource.app);
      await settle();
      expect(env.fx.performed, ['a']);
      await env.layer.dispatch(OperatorCommand.previous, OperatorInputSource.app);
      await settle();
      expect(env.fx.undone, 1);
    });

    test('«Стоп» останавливает идущий дубль и ничего не делает без него', () async {
      await env.engine.load('s1');
      final idle = await env.layer.dispatch(OperatorCommand.stop, OperatorInputSource.propController);
      expect(idle.handled, isFalse);
      await env.engine.start();
      final out = await env.layer.dispatch(OperatorCommand.stop, OperatorInputSource.propController);
      expect(out.target, OperatorTarget.scene);
      expect(env.fx.ended, [false]);
      expect(env.engine.status, EngineStatus.ready);
    });

    test('«Сброс» откатывает сцену и даёт отклик до и после', () async {
      await env.engine.load('s1');
      await env.engine.start();
      final out = await env.layer.dispatch(OperatorCommand.reset, OperatorInputSource.keyboard);
      expect(out.target, OperatorTarget.scene);
      expect(env.fx.resets, 1);
      expect(env.events, ['start', 'done']);
    });

    test('«Сброс» без выбранной сцены ничего не делает', () async {
      final out = await env.layer.dispatch(OperatorCommand.reset, OperatorInputSource.keyboard);
      expect(out.handled, isFalse);
      expect(env.events, isEmpty);
    });

    test('canHandle: адресат есть только когда есть что переключать', () async {
      expect(env.layer.canHandle(OperatorCommand.next), isFalse);
      expect(env.layer.canHandle(OperatorCommand.reset), isFalse);
      await env.engine.load('s1');
      expect(env.layer.canHandle(OperatorCommand.reset), isTrue);
      expect(env.layer.canHandle(OperatorCommand.next), isFalse);
      expect(env.layer.canHandle(OperatorCommand.stop), isFalse);
      await env.engine.start();
      expect(env.layer.canHandle(OperatorCommand.next), isTrue);
      expect(env.layer.canHandle(OperatorCommand.stop), isTrue);
    });

    test('журнал хранит источник команды', () async {
      await env.layer.dispatch(OperatorCommand.next, OperatorInputSource.propController);
      expect(env.layer.recent.single.source, OperatorInputSource.propController);
    });
  });

  group('KeyboardInput', () {
    testWidgets('стрелка вправо — «Далее», пока дубль идёт', (tester) async {
      final env = _Env();
      final input = KeyboardInput(env.layer)..attach();
      addTearDown(() {
        input.detach();
        env.dispose();
      });
      await tester.runAsync(() async {
        await env.engine.load('s1');
        await env.engine.start();
      });
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.runAsync(() => settle(100));
      expect(env.fx.performed, ['a']);
    });

    testWidgets('без дубля клавиши остаются системе', (tester) async {
      final env = _Env();
      final input = KeyboardInput(env.layer)..attach();
      addTearDown(() {
        input.detach();
        env.dispose();
      });
      await tester.runAsync(() => env.engine.load('s1'));
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.runAsync(() => settle(50));
      expect(env.fx.takes, 0);
      expect(env.layer.recent, isEmpty);
    });

    testWidgets('в поле ввода пробел и стрелки печатают, а не управляют', (tester) async {
      final env = _Env();
      final input = KeyboardInput(env.layer)..attach();
      addTearDown(() {
        input.detach();
        env.dispose();
      });
      await tester.runAsync(() async {
        await env.engine.load('s1');
        await env.engine.start();
      });
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TextField(autofocus: true))));
      await tester.pump();
      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
      await tester.runAsync(() => settle(50));
      expect(env.engine.isActive, isTrue, reason: 'пробел в поле не должен останавливать дубль');
      expect(env.layer.recent, isEmpty);
    });

    testWidgets('пробел — «Стоп» вне поля ввода', (tester) async {
      final env = _Env();
      final input = KeyboardInput(env.layer)..attach();
      addTearDown(() {
        input.detach();
        env.dispose();
      });
      await tester.runAsync(() async {
        await env.engine.load('s1');
        await env.engine.start();
      });
      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
      await tester.runAsync(() => settle(100));
      expect(env.engine.isActive, isFalse);
      expect(env.fx.ended, [false]);
    });

    testWidgets('короткий Esc не сбрасывает сцену, удержанный — сбрасывает', (tester) async {
      final env = _Env();
      final input = KeyboardInput(env.layer, holdForReset: const Duration(milliseconds: 120))..attach();
      addTearDown(() {
        input.detach();
        env.dispose();
      });
      await tester.runAsync(() async {
        await env.engine.load('s1');
        await env.engine.start();
      });
      // Таймер удержания создаётся в «поддельных» часах теста — двигаем их pump.
      await simulateKeyDownEvent(LogicalKeyboardKey.escape);
      await simulateKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(() => settle(50));
      expect(env.fx.resets, 0);

      await simulateKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      await simulateKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.runAsync(() => settle(100));
      expect(env.fx.resets, 1);
    });
  });
}
