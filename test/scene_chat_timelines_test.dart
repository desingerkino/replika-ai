// Личные таймлайны чатов: событие одно, прогресс у каждого чата свой,
// чужое событие выполняется из чата, к которому оно привязано.
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/scene_chat_view.dart';
import 'package:replika/app/scene_engine.dart';
import 'package:replika/data/models/scene_action.dart';
import 'package:replika/data/models/take.dart';

SceneAction act(String id, ActionType type, {Map<String, Object?> params = const {}}) => SceneAction(
      id: id,
      sceneId: 's1',
      position: 0,
      typeName: type.name,
      params: params,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// Подделка с хранением хода дубля — как база между запусками.
class Fx implements SceneEffects, SceneProgressStore {
  Fx(this.actions);

  final List<SceneAction> actions;
  final List<String> performed = [];
  Map<String, Object?>? saved;
  bool resumable = false;
  int takes = 0;

  @override
  Future<SceneRunInfo> prepare(String sceneId) async => SceneRunInfo(
        sceneId: sceneId,
        sceneTitle: '12. Тест',
        deviceId: 'd1',
        ownerId: 'hero',
        peerId: 'mama',
      );

  @override
  Future<List<SceneAction>> loadActions(String sceneId) async => actions;

  @override
  Future<int> beginTake(SceneRunInfo info) async {
    resumable = true;
    saved = null;
    return ++takes;
  }

  @override
  Future<void> perform(SceneAction action, SceneRunInfo info, bool Function() cancelled) async =>
      performed.add(action.id);

  @override
  Future<void> undoLast(SceneRunInfo info) async {
    if (performed.isNotEmpty) performed.removeLast();
  }

  @override
  Future<void> endTake(SceneRunInfo info, {required bool completed}) async => resumable = false;

  @override
  Future<void> markTake(SceneRunInfo info, TakeStatus status) async {}

  @override
  Future<void> reset(SceneRunInfo info, {bool restoreScreen = false}) async {
    performed.clear();
    resumable = false;
    saved = null;
  }

  @override
  Future<void> saveProgress(SceneRunInfo info, Map<String, Object?> progress) async => saved = progress;

  @override
  Future<ResumedTake?> resumeTake(SceneRunInfo info) async =>
      resumable && saved != null ? ResumedTake(number: takes, startedAt: DateTime(2026), progress: saved!) : null;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

List<SceneAction> scene() => [
      act('m1', ActionType.showOutgoing, params: {'characterId': 'mama', 'text': 'Мам, ты дома?'}),
      act('c1', ActionType.incomingAudioCall, params: {
        'characterId': 'krasotka',
        'alsoIn': ['c:mama'],
      }),
      act('m2', ActionType.showIncoming, params: {'characterId': 'mama', 'text': 'Да'}),
      act('s1', ActionType.showIncoming, params: {'characterId': 'sergey', 'text': 'Есть новости'}),
      act('w', ActionType.wait),
    ];

void main() {
  test('личный таймлайн: свои события и привязанные чужие, управляющие — только в общем', () {
    final actions = scene();
    List<int> view(String key) => sceneChatView(actions, key, ownerId: 'hero', defaultPeerId: 'mama');
    expect(view('c:mama'), [0, 1, 2]);
    expect(view('c:krasotka'), [1]);
    expect(view('c:sergey'), [3]);
    expect(sceneChatKeyOf(actions[4], ownerId: 'hero'), isNull);
  });

  test('«кто → кому», группа и ссылка на событие определяют чат', () {
    final msg = act('x', ActionType.message, params: {'from': 'sergey', 'to': 'hero'});
    final group = act('g', ActionType.showIncoming, params: {'groupId': 'crew', 'characterId': 'sergey'});
    final ref = act('r', ActionType.endCall, params: {'refActionId': 'c1'});
    final byId = {for (final a in scene()) a.id: a};
    expect(sceneChatKeyOf(msg, ownerId: 'hero'), 'c:sergey');
    expect(sceneChatKeyOf(group, ownerId: 'hero'), 'g:crew');
    expect(sceneChatKeyOf(ref, ownerId: 'hero', byId: byId), 'c:krasotka');
  });

  test('чужое событие выполняется из чата Мама и становится выполненным везде', () async {
    final fx = Fx(scene());
    final engine = SceneEngine(fx);
    await engine.load('s1');
    await engine.start();

    await engine.nextInChat('c:mama'); // m1
    await engine.nextInChat('c:mama'); // c1 — звонок Красотки из таймлайна Мамы
    expect(fx.performed, ['m1', 'c1']);
    expect(engine.isExecuted('c1'), isTrue);
    expect(engine.chatProgress('c:krasotka'), (done: 1, total: 1), reason: 'тот же Event, а не копия');
    expect(engine.chatProgress('c:mama'), (done: 2, total: 3));
    expect(engine.index, 2, reason: 'общий таймлайн ушёл вперёд за выполненными');

    await engine.next(); // m2 — «Далее» общего таймлайна работает как раньше
    expect(fx.performed, ['m1', 'c1', 'm2']);
  });

  test('«Далее» из любого источника идёт в личный таймлайн выбранного чата', () async {
    final fx = Fx(scene());
    final engine = SceneEngine(fx);
    await engine.load('s1');
    await engine.start();
    engine.setWorkChat('c:sergey');
    await engine.next(); // s1, а не m1
    expect(fx.performed, ['s1']);
    engine.setWorkChat(null); // общий таймлайн: как раньше
    await engine.next();
    expect(fx.performed, ['s1', 'm1']);
  });

  test('каждый чат продолжает с того места, где остановился', () async {
    final fx = Fx(scene());
    final engine = SceneEngine(fx);
    await engine.load('s1');
    await engine.start();

    await engine.nextInChat('c:mama'); // m1
    await engine.nextInChat('c:sergey'); // s1
    expect(engine.nextIndexInChat('c:mama'), 1, reason: 'Мама стоит на привязанном звонке');
    await engine.nextInChat('c:mama'); // c1
    await engine.nextInChat('c:mama'); // m2
    expect(fx.performed, ['m1', 's1', 'c1', 'm2']);
    expect(engine.nextIndexInChat('c:mama'), isNull);
  });

  test('событие из чата вне очереди: общий «Далее» его не повторяет', () async {
    final fx = Fx(scene());
    final engine = SceneEngine(fx);
    await engine.load('s1');
    await engine.start();

    await engine.nextInChat('c:sergey'); // s1 (индекс 3) первым
    expect(engine.index, 0);
    await engine.next(); // m1
    await engine.next(); // c1
    await engine.next(); // m2
    await engine.next(); // s1 пропущен как выполненный, wait выполнен
    expect(fx.performed.where((id) => id == 's1').length, 1);
    expect(engine.status, EngineStatus.finished);
  });

  test('«Назад» снимает статус и не уводит общий таймлайн вперёд', () async {
    final fx = Fx(scene());
    final engine = SceneEngine(fx);
    await engine.load('s1');
    await engine.start();

    await engine.nextInChat('c:sergey');
    expect(engine.isExecuted('s1'), isTrue);
    await engine.back();
    expect(engine.isExecuted('s1'), isFalse);
    expect(engine.index, 0);
    expect(fx.performed, isEmpty);
  });

  test('сброс сцены очищает статусы всех чатов', () async {
    final fx = Fx(scene());
    final engine = SceneEngine(fx);
    await engine.load('s1');
    await engine.start();
    await engine.nextInChat('c:mama');
    await engine.nextInChat('c:sergey');
    await engine.reset();
    expect(engine.chatProgress('c:mama').done, 0);
    expect(engine.chatProgress('c:sergey').done, 0);
  });

  test('после перезапуска дубль продолжается: статусы и позиция на месте', () async {
    final fx = Fx(scene());
    var engine = SceneEngine(fx);
    await engine.load('s1');
    await engine.start();
    await engine.nextInChat('c:mama'); // m1
    await engine.nextInChat('c:sergey'); // s1
    await settle();

    engine = SceneEngine(fx); // новое приложение, те же данные
    await engine.load('s1');
    expect(engine.hasTake, isTrue);
    expect(engine.takeNumber, 1);
    expect(engine.isExecuted('m1'), isTrue);
    expect(engine.isExecuted('s1'), isTrue);
    expect(engine.chatProgress('c:mama'), (done: 1, total: 3));
    expect(engine.nextIndexInChat('c:mama'), 1);

    await engine.back(); // шаги «Назад» тоже восстановлены
    expect(engine.isExecuted('s1'), isFalse);
  });

  test('без сохранённого хода (старый дубль) всё как раньше: «готово», без дубля', () async {
    final fx = Fx(scene());
    final engine = SceneEngine(fx);
    await engine.load('s1');
    expect(engine.hasTake, isFalse);
    expect(engine.status, EngineStatus.ready);
  });
}
