// Профили персонажей, события на нескольких профилях, статусы сообщений,
// звонки, дубли, репетиция, клонирование, отмена — ТЗ разделы 47–59.
// Настоящая SQLite и настоящий Scene Engine.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/scene_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/core/util/ids.dart';
import 'package:replika/data/models/call_record.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/data/models/scene_action.dart';
import 'package:replika/data/profile_transfer.dart';
import 'package:replika/data/repositories/contact_repository.dart';
import 'package:replika/features/operator/action_summary.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Silent implements CallSounds {
  @override
  void ringtone() {}
  @override
  void ringback() {}
  @override
  void hangup() {}
  @override
  void stop() {}
}

late Directory tempDir;
late AppServices s;

Future<String> ownerOf(String deviceId) async => (await s.devices.byId(deviceId))!.ownerCharacterId;

/// Все сообщения профиля в чате с персонажем.
Future<List<Message>> thread(String deviceId, String peer) async {
  final chat = await s.chats.findDirect(deviceId: deviceId, characterId: peer);
  return chat == null ? const [] : s.messages.forChat(chat);
}

SceneAction ev(String sceneId, ActionType type, Map<String, Object?> params, {int delayMs = 0}) => SceneAction(
      id: newId(),
      sceneId: sceneId,
      position: 0,
      typeName: type.name,
      delayMs: delayMs,
      params: params,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

Future<String> sceneWith(String deviceId, List<SceneAction Function(String sceneId)> steps, {String? participant}) async {
  final id = await s.scenes.create(deviceId: deviceId, number: '24', name: 'Квартира');
  await s.scenes.addParticipants(id, [participant ?? await ownerOf(deviceId)]);
  for (final build in steps) {
    await s.scenes.saveAction(build(id));
  }
  return id;
}

Future<void> runAll(SceneEngine engine) async {
  await engine.start();
  while (engine.status == EngineStatus.waiting) {
    await engine.next();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('replika_master_');
    s = await AppServices.open(databasePath: p.join(tempDir.path, 'replika.db'));
    s.engine.setSpeed(4);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await s.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('47. профили изолированы: свои контакты и чаты, переключение ничего не смешивает', () async {
    final marina = await s.devices.createProfile(firstName: 'Марина');
    final alexeyChats = (await s.chats.listForDevice('device-maxim')).length;
    expect(await s.contacts.forDevice(marina), isEmpty, reason: 'новый профиль — пустой телефон');

    await s.contacts.save(
      deviceId: marina,
      characterId: 'char-maxim',
      displayName: 'Максим',
      draft: const CharacterDraft(firstName: 'Максим', lastName: 'Ветров', phone: '+7 915 318-42-07'),
    );
    final chat = await s.chats.openOrCreateDirect(deviceId: marina, characterId: 'char-maxim');
    await s.messages.sendText(chatId: chat, senderId: await ownerOf(marina), text: 'Привет от Марины');

    await s.setCurrentDevice(marina);
    expect((await s.chats.listForDevice(marina)).single.displayName, 'Максим');
    expect((await s.contacts.forDevice(marina)).map((c) => c.displayName), ['Максим']);

    await s.setCurrentDevice('device-maxim');
    expect((await s.chats.listForDevice('device-maxim')).length, alexeyChats, reason: 'профиль Максима не изменился');
    expect((await s.contacts.forDevice('device-maxim')).any((c) => c.displayName == 'Максим'), isFalse);
  });

  test('48. экспорт → удаление → импорт восстанавливает профиль', () async {
    final before = await s.chats.listForDevice('device-maxim');
    final messagesBefore = [for (final c in before) ...await s.messages.forChat(c.chat.id)].length;
    final json = await s.profiles.export('device-maxim');
    expect(json['format'], profileFormat);

    await s.devices.create(name: 'Запасной', ownerCharacterId: 'char-nina');
    await s.setCurrentDevice((await s.devices.list()).last.id);
    await s.devices.delete('device-maxim');
    expect(await s.devices.byId('device-maxim'), isNull);

    final restored = await s.profiles.import(json);
    final chats = await s.chats.listForDevice(restored);
    expect(chats.length, before.length);
    expect([for (final c in chats) ...await s.messages.forChat(c.chat.id)].length, messagesBefore);
    expect((await s.contacts.forDevice(restored)).length, 4);
    final scenes = await s.scenes.list(restored);
    expect(scenes.single.scene.name, 'Вероника у офиса');
    expect((await s.scenes.actions(scenes.single.scene.id)).length, 6);

    await s.profiles.import(json);
    expect((await s.devices.list()).where((d) => d.ownerCharacterId == 'char-maxim').length, 2,
        reason: 'повторный импорт ничего не перезаписывает');

    expect(() => s.profiles.import({...json, 'formatVersion': 99}), throwsA(isA<ProfileImportException>()));
    expect(() => s.profiles.import({'format': 'что-то'}), throwsA(isA<ProfileImportException>()));
  });

  test('50. состояния сообщения — данные с моментами', () async {
    final m = await s.messages.sendText(chatId: 'chat-veronika', senderId: 'char-maxim', text: 'Ты где?');
    await s.messages.setState(m.id, MessageState.sending);
    var x = (await s.messages.byId(m.id))!;
    expect(x.deliveredAt, isNull);
    await s.messages.setState(m.id, MessageState.delivered);
    x = (await s.messages.byId(m.id))!;
    expect(x.state, MessageState.delivered);
    expect(x.deliveredAt, isNotNull);
    expect(x.readAt, isNull);
    await s.messages.setState(m.id, MessageState.read);
    x = (await s.messages.byId(m.id))!;
    expect(x.readAt, isNotNull);
    await s.messages.setDeleted(m.id, true);
    x = (await s.messages.byId(m.id))!;
    expect(x.deleted, isTrue);
    expect(x.deletedAt, isNotNull);
    expect(x.readAt, isNotNull, reason: 'история: было прочитано, затем удалено');

    final f = await s.messages.sendText(chatId: 'chat-veronika', senderId: 'char-maxim', text: 'Перезвони мне');
    await s.messages.setState(f.id, MessageState.sending);
    await s.messages.setState(f.id, MessageState.failed);
    x = (await s.messages.byId(f.id))!;
    expect(x.state, MessageState.failed);
    expect(x.deliveredAt, isNull);
  });

  test('52–53. общий таймлайн: порядок и события на одном времени', () async {
    final marina = await s.devices.createProfile(firstName: 'Марина');
    final mOwner = await ownerOf(marina);
    final sceneId = await sceneWith('device-maxim', [
      (id) => ev(id, ActionType.message, {'from': 'char-maxim', 'to': mOwner, 'text': 'Один', 'fromName': 'Максим', 'toName': 'Марина'}),
      (id) => ev(id, ActionType.message, {'from': mOwner, 'to': 'char-maxim', 'text': 'Два'}, delayMs: 3000),
      (id) => ev(id, ActionType.message, {'from': 'char-maxim', 'to': mOwner, 'text': 'Три'}, delayMs: 0),
    ]);
    final actions = await s.scenes.actions(sceneId);
    expect(timelineOffsets(actions).map((d) => d.inSeconds), [0, 3, 3], reason: 'два события на 00:03');
    expect(actionSummary(actions.first), 'Максим → Марина: «Один»');
    await s.engine.load(sceneId);
    await runAll(s.engine);
    final texts = (await thread(marina, 'char-maxim')).map((m) => m.text).toList();
    expect(texts.length, 3, reason: 'оба события на 00:03 выполнены');
    expect(texts.toSet(), {'Один', 'Два', 'Три'});
    expect(texts.first, 'Один');
  });

  test('54. повтор сцены: новый дубль, прежний сохранён', () async {
    final sceneId = await sceneWith('device-maxim', [
      (id) => ev(id, ActionType.showIncoming, {'characterId': 'char-veronika', 'text': 'Раз'}),
    ], participant: 'char-veronika');
    await s.engine.load(sceneId);
    await runAll(s.engine);
    expect(s.engine.status, EngineStatus.finished);
    await s.engine.repeat();
    await runAll(s.engine);
    final takes = await s.scenes.takes(sceneId);
    expect(takes.length, 2);
    expect(takes.map((t) => t.number).toSet(), {1, 2});
  });

  test('55. клон сцены независим от оригинала', () async {
    final sceneId = await sceneWith('device-maxim', [
      (id) => ev(id, ActionType.showIncoming, {'characterId': 'char-veronika', 'text': 'Оригинал'}),
    ], participant: 'char-veronika');
    final copy = await s.scenes.duplicate(sceneId);
    final copyAction = (await s.scenes.actions(copy)).single;
    await s.scenes.saveAction(SceneAction(
      id: copyAction.id,
      sceneId: copy,
      position: copyAction.position,
      typeName: copyAction.typeName,
      params: {...copyAction.params, 'text': 'Изменённая копия'},
      createdAt: copyAction.createdAt,
      updatedAt: DateTime.now(),
    ));
    expect((await s.scenes.actions(sceneId)).single.params['text'], 'Оригинал');
    expect((await s.scenes.actions(copy)).single.params['text'], 'Изменённая копия');
    expect((await s.scenes.participants(copy, 'device-maxim')).single.characterId, 'char-veronika');
  });

  test('56. отмена и возврат ручного действия', () async {
    final sceneId = await sceneWith('device-maxim', const [], participant: 'char-veronika');
    await s.engine.load(sceneId);
    await s.engine.performLive(ev(sceneId, ActionType.showIncoming, {'characterId': 'char-veronika', 'text': 'Случайно'}));
    Future<int> count() async => (await s.messages.forChat('chat-veronika')).where((m) => m.text == 'Случайно').length;
    expect(await count(), 1);
    await s.engine.back();
    expect(await count(), 0);
    expect(s.engine.canRedo, isTrue);
    await s.engine.redo();
    expect(await count(), 1);
  });

  test('57–58. репетиция откатывается, дубль — остаётся', () async {
    final sceneId = await sceneWith('device-maxim', [
      (id) => ev(id, ActionType.showIncoming, {'characterId': 'char-veronika', 'text': 'Прогон'}),
    ], participant: 'char-veronika');
    Future<int> count() async => (await s.messages.forChat('chat-veronika')).where((m) => m.text == 'Прогон').length;
    await s.engine.load(sceneId);

    s.engine.setRehearsal(true);
    await runAll(s.engine);
    expect(await count(), 0, reason: 'репетиция не меняет профиль');
    expect(s.engine.status, EngineStatus.ready);
    expect((await s.scenes.takes(sceneId)).single.logJson, contains('"mode":"rehearsal"'));

    s.engine.setRehearsal(false);
    await runAll(s.engine);
    expect(await count(), 1, reason: 'съёмочный дубль меняет телефон по-настоящему');
    expect(s.engine.status, EngineStatus.finished);
  });

  test('59. критический: три профиля, одна сцена, общий таймлайн', () async {
    final alexeyDev = await s.devices.createProfile(firstName: 'Алексей');
    final marinaDev = await s.devices.createProfile(firstName: 'Марина');
    final sergeyDev = await s.devices.createProfile(firstName: 'Сергей');
    final alexey = await ownerOf(alexeyDev);
    final marina = await ownerOf(marinaDev);
    final sergey = await ownerOf(sergeyDev);
    await s.setCurrentDevice(alexeyDev);

    late String first, second, callEvent;
    final sceneId = await sceneWith(alexeyDev, [
      (id) {
        final a = ev(id, ActionType.message, {'from': alexey, 'to': marina, 'text': 'Ты где?', 'state': 'sent'});
        first = a.id;
        return a;
      },
      (id) => ev(id, ActionType.setMessageState, {'refActionId': first, 'state': 'delivered'}, delayMs: 2000),
      (id) {
        final a = ev(id, ActionType.message, {'from': marina, 'to': alexey, 'text': 'Я уже приехала'}, delayMs: 3000);
        second = a.id;
        return a;
      },
      (id) => ev(id, ActionType.setMessageState, {'refActionId': second, 'state': 'read'}, delayMs: 2000),
      (id) {
        final a = ev(id, ActionType.call, {'from': sergey, 'to': alexey}, delayMs: 2000);
        callEvent = a.id;
        return a;
      },
      (id) => ev(id, ActionType.message, {'from': alexey, 'to': marina, 'text': 'Открой дверь', 'state': 'failed'}, delayMs: 3000),
      (id) => ev(id, ActionType.deleteMessage, {'refActionId': second}, delayMs: 3000),
      (id) => ev(id, ActionType.endCall, {'refActionId': callEvent}, delayMs: 2000),
    ], participant: alexey);

    final actions = await s.scenes.actions(sceneId);
    expect(timelineOffsets(actions).map((d) => d.inSeconds), [0, 2, 5, 7, 9, 12, 15, 17]);

    await s.engine.load(sceneId);
    await s.engine.start();
    for (var i = 0; i < 4; i++) {
      await s.engine.next();
    }
    // Оператор в любой момент смотрит любой профиль — сцена идёт.
    await s.setCurrentDevice(marinaDev);
    expect(s.engine.hasTake, isTrue);
    await s.setCurrentDevice(alexeyDev);
    await s.engine.next(); // звонок Сергея — на экране Алексея
    expect(s.callEngine.phase, CallPhase.incoming);
    expect(s.callEngine.session?.characterId, sergey);
    while (s.engine.status == EngineStatus.waiting) {
      await s.engine.next();
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Телефон Алексея
    final aThread = await thread(alexeyDev, marina);
    final tyGde = aThread.firstWhere((m) => m.text == 'Ты где?');
    expect(tyGde.state, MessageState.delivered);
    expect(tyGde.deliveredAt, isNotNull);
    expect(aThread.firstWhere((m) => m.text == 'Я уже приехала').deleted, isTrue, reason: 'Марина удалила у всех');
    expect(aThread.firstWhere((m) => m.text == 'Открой дверь').state, MessageState.failed);

    // Телефон Марины
    final mThread = await thread(marinaDev, alexey);
    expect(mThread.firstWhere((m) => m.text == 'Ты где?').senderId, alexey);
    final her = mThread.firstWhere((m) => m.text == 'Я уже приехала');
    expect(her.state, MessageState.read);
    expect(her.readAt, isNotNull);
    expect(her.deleted, isTrue);
    expect(mThread.any((m) => m.text == 'Открой дверь'), isFalse, reason: 'не доставлено — у Марины нет');

    // Звонок: у Алексея пропущенный входящий, у Сергея — исходящий, отменённый им.
    final aCalls = await s.calls.forDevice(alexeyDev);
    expect(aCalls.single.call.direction, CallDirection.incoming);
    expect(aCalls.single.call.outcome, CallOutcome.missed);
    final sCalls = await s.calls.forDevice(sergeyDev);
    expect(sCalls.single.call.direction, CallDirection.outgoing);
    expect(sCalls.single.call.outcome, CallOutcome.cancelled);

    // Сброс возвращает все три профиля.
    await s.engine.reset();
    expect(await thread(alexeyDev, marina), isEmpty);
    expect(await thread(marinaDev, alexey), isEmpty);
    expect(await s.calls.forDevice(alexeyDev), isEmpty);
    expect(await s.calls.forDevice(sergeyDev), isEmpty);
  });

  test('51. звонки «за кадром»: принятый и завершённый, отклонённый', () async {
    final alexeyDev = await s.devices.createProfile(firstName: 'Алексей');
    final sergeyDev = await s.devices.createProfile(firstName: 'Сергей');
    final alexey = await ownerOf(alexeyDev);
    final sergey = await ownerOf(sergeyDev);
    // На экране — профиль Максима: ни один из участников не на экране.
    late String c1, c2;
    final sceneId = await sceneWith('device-maxim', [
      (id) {
        final a = ev(id, ActionType.call, {'from': sergey, 'to': alexey, 'video': true});
        c1 = a.id;
        return a;
      },
      (id) => ev(id, ActionType.acceptCall, {'refActionId': c1}),
      (id) => ev(id, ActionType.endCall, {'refActionId': c1}),
      (id) {
        final a = ev(id, ActionType.call, {'from': alexey, 'to': sergey});
        c2 = a.id;
        return a;
      },
      (id) => ev(id, ActionType.declineCall, {'refActionId': c2}),
    ]);
    await s.engine.load(sceneId);
    await runAll(s.engine);
    expect(s.callEngine.phase, CallPhase.idle, reason: 'экран Максима звонки не показывает');
    final aCalls = await s.calls.forDevice(alexeyDev);
    expect(aCalls.map((c) => (c.call.direction, c.call.outcome, c.call.kind)).toSet(), {
      (CallDirection.incoming, CallOutcome.answered, CallKind.video),
      (CallDirection.outgoing, CallOutcome.declined, CallKind.audio),
    });
    final sCalls = await s.calls.forDevice(sergeyDev);
    expect(sCalls.map((c) => (c.call.direction, c.call.outcome)).toSet(), {
      (CallDirection.outgoing, CallOutcome.answered),
      (CallDirection.incoming, CallOutcome.declined),
    });
  });
}
