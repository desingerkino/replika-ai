import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/scene_effects.dart';
import 'package:replika/app/scene_engine.dart';
import 'package:replika/data/models/scene_action.dart';
import 'package:replika/data/models/take.dart';

SceneAction act(String id) => SceneAction(
      id: id,
      sceneId: 's1',
      position: 0,
      typeName: ActionType.showIncoming.name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class Fx implements SceneEffects {
  Fx(this.actions, {this.clockStart});

  final List<SceneAction> actions;
  final DateTime? clockStart;
  final List<String> performed = [];

  @override
  Future<SceneRunInfo> prepare(String sceneId) async => SceneRunInfo(
        sceneId: sceneId,
        sceneTitle: 'Тест',
        deviceId: 'd',
        chatId: 'c',
        ownerId: 'o',
        clockStart: clockStart,
      );

  @override
  Future<List<SceneAction>> loadActions(String sceneId) async => actions;

  @override
  Future<int> beginTake(SceneRunInfo info) async => 1;

  @override
  Future<void> perform(SceneAction action, SceneRunInfo info, bool Function() cancelled) async =>
      performed.add(action.id);

  @override
  Future<void> undoLast(SceneRunInfo info) async => performed.removeLast();

  @override
  Future<void> endTake(SceneRunInfo info, {required bool completed}) async {}

  @override
  Future<void> markTake(SceneRunInfo info, TakeStatus status) async {}

  @override
  Future<void> reset(SceneRunInfo info, {bool restoreScreen = false}) async => performed.clear();
}

void main() {
  test('переход назад отменяет выполненные после шага действия', () async {
    final fx = Fx([act('a'), act('b'), act('c'), act('d')]);
    final engine = SceneEngine(fx);
    await engine.load('s');
    await engine.start();
    await engine.next();
    await engine.next();
    await engine.next();
    expect(fx.performed, ['a', 'b', 'c']);
    await engine.jumpTo(1);
    expect(fx.performed, ['a']);
    expect(engine.index, 1);
    expect(engine.status, EngineStatus.waiting);
  });

  test('переход вперёд пропускает действия, не выполняя их', () async {
    final fx = Fx([act('a'), act('b'), act('c')]);
    final engine = SceneEngine(fx);
    await engine.load('s');
    await engine.start();
    await engine.jumpTo(2);
    await engine.next();
    expect(fx.performed, ['c']);
    expect(engine.status, EngineStatus.finished);
  });

  test('без дубля переход и выполнение вне очереди недоступны', () async {
    final fx = Fx([act('a'), act('b')]);
    final engine = SceneEngine(fx);
    await engine.load('s');
    await engine.jumpTo(1);
    await engine.performNow(1);
    expect(engine.index, 0);
    expect(fx.performed, isEmpty);
  });

  test('вне очереди: позиция не меняется, «Назад» отменяет именно его', () async {
    final fx = Fx([act('a'), act('b'), act('c')]);
    final engine = SceneEngine(fx);
    await engine.load('s');
    await engine.start();
    await engine.next();
    await engine.performNow(2);
    expect(fx.performed, ['a', 'c']);
    expect(engine.index, 1);
    await engine.back();
    expect(fx.performed, ['a']);
  });

  test('«время в кадре» идёт от заданного начала', () async {
    var now = DateTime(2026, 9, 25, 14, 0, 0);
    final engine = SceneEngine(
      Fx([act('a')], clockStart: DateTime(2026, 9, 25, 23, 47)),
      clock: () => now,
    );
    await engine.load('s');
    expect(engine.sceneNow(), isNull, reason: 'до «СТАРТ» время реальное');
    await engine.start();
    now = now.add(const Duration(seconds: 90));
    expect(engine.sceneNow(), DateTime(2026, 9, 25, 23, 48, 30));
  });

  test('без заданного времени сообщения получают реальное', () async {
    final engine = SceneEngine(Fx([act('a')]));
    await engine.load('s');
    await engine.start();
    expect(engine.sceneNow(), isNull);
  });

  test('скорость ограничена разумными пределами', () {
    final engine = SceneEngine(Fx(const []));
    engine.setSpeed(10);
    expect(engine.speed, 4.0);
    engine.setSpeed(0.1);
    expect(engine.speed, 0.25);
  });

  test('разбор «времени в кадре»', () {
    final today = DateTime(2026, 9, 25, 10);
    expect(sceneClockStart('23:47', today), DateTime(2026, 9, 25, 23, 47));
    expect(sceneClockStart('7:05', today), DateTime(2026, 9, 25, 7, 5));
    expect(sceneClockStart('25:00', today), isNull);
    expect(sceneClockStart('', today), isNull);
    expect(sceneClockStart(null, today), isNull);
  });
}
