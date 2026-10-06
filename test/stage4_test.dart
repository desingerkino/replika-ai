import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/scene_engine.dart';
import 'package:replika/data/models/scene_action.dart';
import 'package:replika/data/models/take.dart';
import 'package:replika/features/operator/action_summary.dart';

SceneAction act(String id, ActionType type, {int delayMs = 0, Map<String, Object?> params = const {}, bool enabled = true}) =>
    SceneAction(
      id: id,
      sceneId: 's1',
      position: 0,
      typeName: type.name,
      delayMs: delayMs,
      params: params,
      enabled: enabled,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// Подделка SceneEffects: записывает, что движок попросил сделать.
class FakeEffects implements SceneEffects {
  FakeEffects(this.actions);

  final List<SceneAction> actions;
  final List<String> performed = [];
  int takes = 0;
  int resets = 0;
  int undone = 0;
  final List<bool> ended = [];
  TakeStatus? marked;

  @override
  Future<SceneRunInfo> prepare(String sceneId) async => SceneRunInfo(
        sceneId: sceneId,
        sceneTitle: '12. Тест',
        deviceId: 'd1',
        chatId: 'c1',
        ownerId: 'hero',
        peerId: 'peer',
      );

  @override
  Future<List<SceneAction>> loadActions(String sceneId) async => actions;

  @override
  Future<int> beginTake(SceneRunInfo info) async => ++takes;

  @override
  Future<void> perform(SceneAction action, SceneRunInfo info, bool Function() cancelled) async {
    if (action.type == ActionType.playAudio) throw StateError('нет файла');
    performed.add(action.id);
  }

  @override
  Future<void> undoLast(SceneRunInfo info) async {
    undone++;
    if (performed.isNotEmpty) performed.removeLast();
  }

  @override
  Future<void> endTake(SceneRunInfo info, {required bool completed}) async => ended.add(completed);

  @override
  Future<void> markTake(SceneRunInfo info, TakeStatus status) async => marked = status;

  @override
  Future<void> reset(SceneRunInfo info, {bool restoreScreen = false}) async {
    resets++;
    performed.clear();
  }
}

Future<void> settle([int ms = 150]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('Движок сцен', () {
    test('автоматический режим: по порядку, выключенные пропускаются', () async {
      final fx = FakeEffects([
        act('a', ActionType.showIncoming),
        act('b', ActionType.showOutgoing, enabled: false),
        act('c', ActionType.startTyping, delayMs: 50),
      ]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      expect(engine.status, EngineStatus.ready);
      expect(engine.actions.length, 2);
      engine.setManual(false);
      await engine.start();
      await settle(300);
      expect(fx.performed, ['a', 'c']);
      expect(engine.status, EngineStatus.finished);
      expect(fx.ended, [true]);
    });

    test('ручной режим: одно действие на каждое «Далее»', () async {
      final fx = FakeEffects([act('a', ActionType.showIncoming), act('b', ActionType.showOutgoing)]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      await engine.start();
      expect(engine.status, EngineStatus.waiting);
      expect(fx.performed, isEmpty);
      await engine.next();
      expect(fx.performed, ['a']);
      expect(engine.status, EngineStatus.waiting);
      await engine.next();
      expect(fx.performed, ['a', 'b']);
      expect(engine.status, EngineStatus.finished);
    });

    test('скрытый жест не запускает сцену случайно', () async {
      final fx = FakeEffects([act('a', ActionType.showIncoming)]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      engine.hiddenNext();
      await settle(50);
      expect(fx.takes, 0);
      expect(engine.status, EngineStatus.ready);
    });

    test('пауза в таймлайне ждёт «Далее» в автоматическом режиме', () async {
      final fx = FakeEffects([
        act('a', ActionType.showIncoming),
        act('p', ActionType.pause),
        act('b', ActionType.showIncoming),
      ]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      engine.setManual(false);
      await engine.start();
      await settle();
      expect(fx.performed, ['a']);
      expect(engine.status, EngineStatus.paused);
      engine.hiddenNext();
      await settle();
      expect(fx.performed, ['a', 'b']);
      expect(engine.status, EngineStatus.finished);
    });

    test('ошибка действия записывается в журнал, сцена идёт дальше', () async {
      final fx = FakeEffects([act('x', ActionType.playAudio), act('b', ActionType.showIncoming)]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      await engine.start();
      await engine.next();
      await engine.next();
      expect(fx.performed, ['b']);
      expect(engine.log.any((line) => line.contains('Ошибка')), isTrue);
    });

    test('сброс отменяет дубль и возвращает к началу', () async {
      final fx = FakeEffects([act('a', ActionType.showIncoming), act('b', ActionType.showIncoming)]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      await engine.start();
      await engine.next();
      await engine.reset();
      expect(fx.resets, 1);
      expect(engine.index, 0);
      expect(engine.status, EngineStatus.ready);
      await engine.start();
      expect(fx.takes, 2);
    });

    test('режим нельзя переключить во время дубля', () async {
      final engine = SceneEngine(FakeEffects([act('a', ActionType.showIncoming)]));
      await engine.load('s1');
      await engine.start();
      engine.setManual(false);
      expect(engine.manual, isTrue);
      await engine.markTake(TakeStatus.good);
    });
  });

  group('«Назад»', () {
    test('отменяет последнее действие, «Далее» выполняет его снова', () async {
      final fx = FakeEffects([
        act('a', ActionType.showIncoming),
        act('b', ActionType.showIncoming),
        act('c', ActionType.showIncoming),
      ]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      await engine.start();
      await engine.next();
      await engine.next();
      expect(fx.performed, ['a', 'b']);
      await engine.back();
      expect(fx.performed, ['a']);
      expect(engine.index, 1);
      expect(engine.status, EngineStatus.waiting);
      await engine.next();
      expect(fx.performed, ['a', 'b']);
    });

    test('в начале сцены и без дубля ничего не делает', () async {
      final fx = FakeEffects([act('a', ActionType.showIncoming)]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      await engine.back();
      expect(fx.undone, 0);
      expect(engine.status, EngineStatus.ready);
      await engine.start();
      await engine.back();
      expect(fx.undone, 0);
      expect(engine.index, 0);
    });

    test('из завершённой сцены можно вернуться к последнему действию', () async {
      final fx = FakeEffects([act('a', ActionType.showIncoming)]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      await engine.start();
      await engine.next();
      expect(engine.status, EngineStatus.finished);
      expect(engine.hasTake, isTrue);
      await engine.back();
      expect(fx.performed, isEmpty);
      expect(engine.status, EngineStatus.waiting);
    });

    test('в автоматическом режиме «Назад» ставит паузу, «Далее» продолжает', () async {
      final fx = FakeEffects([
        act('a', ActionType.showIncoming),
        act('p', ActionType.pause),
        act('b', ActionType.showIncoming),
      ]);
      final engine = SceneEngine(fx);
      await engine.load('s1');
      engine.setManual(false);
      await engine.start();
      await settle();
      await engine.back();
      expect(fx.performed, isEmpty);
      expect(engine.status, EngineStatus.paused);
      engine.hiddenNext();
      await settle();
      expect(fx.performed, ['a']);
      expect(engine.status, EngineStatus.paused);
    });
  });

  group('Таймлайн в редакторе', () {
    test('описания действий', () {
      expect(
        actionSummary(act('a', ActionType.showIncoming, params: {'text': 'Ты где?', 'typingMs': 2500}),
            peerName: 'Красотка'),
        'Красотка: «Ты где?», печатает 2,5 с',
      );
      expect(actionSummary(act('b', ActionType.deleteMessage, params: {'target': 'lastIncoming'}), peerName: 'Марина'),
          'Марина: удалить последнее сообщение участника');
      expect(actionSummary(act('c', ActionType.wait)), 'Ждать 1 с');
    });

    test('звонки и уведомления доступны, «Продолжение» и «Сброс» — кнопками панели', () {
      expect(unavailableReason(ActionType.incomingAudioCall), isNull);
      expect(unavailableReason(ActionType.postNotification), isNull);
      expect(unavailableReason(ActionType.resume), contains('Далее'));
      expect(unavailableReason(ActionType.reset), contains('СБРОС'));
      expect(unavailableReason(ActionType.showIncoming), isNull);
      for (final type in supportedActionTypes) {
        expect(unavailableReason(type), isNull);
      }
    });
  });
}
