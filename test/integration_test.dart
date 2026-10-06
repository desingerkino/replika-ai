// Интеграционные тесты на настоящей SQLite (через sqflite_common_ffi):
// те же запросы, репозитории, демо-данные и движок сцен, что на телефоне.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/call_services.dart';
import 'package:replika/app/improv.dart';
import 'package:replika/app/improv_sender.dart';
import 'package:replika/app/kino.dart';
import 'package:replika/app/scene_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/data/models/call_record.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/data/models/origin.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/core/util/ids.dart';
import 'package:replika/data/models/scene_action.dart';
import 'package:replika/data/repositories/contact_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const device = 'device-maxim';
const hero = 'char-maxim';
const veronikaChat = 'chat-veronika';
const demoScene = 'scene-demo-12';

late Directory tempDir;
late String dbPath;

Future<AppServices> openApp() => AppServices.open(databasePath: dbPath);

Future<List<Message>> sceneMessages(AppServices s) async =>
    (await s.messages.forChat(veronikaChat)).where((m) => m.origin != DataOrigin.base).toList();

Future<int> unread(AppServices s, String chatId) async =>
    (await s.chats.header(chatId))!.chat.unreadCount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _SilentSounds.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('replika_test_');
    dbPath = p.join(tempDir.path, 'replika.db');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('первый запуск: демо-данные как в ТЗ', () async {
    final s = await openApp();
    final chats = await s.chats.listForDevice(device);
    expect(chats.map((c) => c.displayName), ['Мама', 'Красотка', 'Алексей', 'Работа'],
        reason: 'Мама закреплена сверху, дальше — по времени последнего сообщения');
    expect(chats.map((c) => c.chat.unreadCount), [2, 2, 1, 0]);

    final contacts = await s.contacts.forDevice(device);
    expect(contacts.map((c) => c.displayName), ['Алексей', 'Красотка', 'Мама', 'Работа']);

    final actions = await s.scenes.actions(demoScene);
    expect(actions.length, 6);
    expect((await s.replies.list()).length, 37);
    expect(s.currentDeviceId.value, device);
    await s.close();
  });

  test('повторный запуск не дублирует демо-данные', () async {
    await (await openApp()).close();
    final s = await openApp();
    expect((await s.chats.listForDevice(device)).length, 4);
    expect((await s.replies.list()).length, 37);
    await s.close();
  });

  test('отправка, ответ, черновик, избранное, поиск', () async {
    final s = await openApp();
    await s.chats.saveDraft(veronikaChat, 'Черновик');
    expect(await s.chats.draftOf(veronikaChat), 'Черновик');

    final before = await s.messages.forChat(veronikaChat);
    final sent = await s.messages.sendText(
      chatId: veronikaChat,
      senderId: hero,
      text: 'Уже еду',
      replyToId: before.last.id,
    );
    final after = await s.messages.forChat(veronikaChat);
    expect(after.last.text, 'Уже еду');
    expect(after.last.replyToId, before.last.id);
    expect(await s.chats.draftOf(veronikaChat), isNull, reason: 'отправка очищает черновик');

    final list = await s.chats.listForDevice(device);
    expect(list.firstWhere((c) => c.chat.id == veronikaChat).lastMessage?.text, 'Уже еду');

    await s.messages.setFavorite(sent.id, true);
    expect((await s.chats.favorites(device)).single.message.id, sent.id);

    final hits = await s.chats.searchMessages(device, 'ПЕРЕЗВОНИ');
    expect(hits.single.peer.displayName, 'Алексей', reason: 'поиск без учёта регистра');
    expect((await s.chats.searchMessages(device, 'еще тепло')).length, 1, reason: '«ё» = «е»');
    await s.close();
  });

  test('новый контакт, удаление с телефона — в чате виден номер', () async {
    final s = await openApp();
    final id = await s.contacts.save(
      deviceId: device,
      draft: const CharacterDraft(firstName: 'Лев', phone: '+7 999 000-00-00'),
      displayName: 'Лёва',
    );
    final chatId = await s.chats.openOrCreateDirect(deviceId: device, characterId: id);
    await s.messages.sendText(chatId: chatId, senderId: hero, text: 'Привет');
    expect((await s.chats.listForDevice(device)).any((c) => c.displayName == 'Лёва'), isTrue);

    await s.contacts.removeFromDevice(device, id);
    final list = await s.chats.listForDevice(device);
    expect(list.firstWhere((c) => c.chat.id == chatId).displayName, '+7 999 000-00-00');
    expect((await s.contacts.forDevice(device)).any((c) => c.id == id), isFalse);
    await s.close();
  });

  test('сцена на настоящих данных: «Далее», «Назад», полный сброс', () async {
    final s = await openApp();
    final engine = s.engine..setSpeed(4);
    await engine.load(demoScene);
    final baseMessages = (await s.messages.forChat(veronikaChat)).length;
    expect(await unread(s, veronikaChat), 2);

    await engine.start();
    expect(engine.status, EngineStatus.waiting);

    await engine.next(); // «Ты где сейчас?» с «печатает…»
    var added = await sceneMessages(s);
    expect(added.single.text, 'Ты где сейчас?');
    expect(added.single.origin, DataOrigin.scene);
    expect(await unread(s, veronikaChat), 3, reason: 'чат не открыт — счётчик растёт');

    await engine.next(); // второе входящее
    await engine.next(); // исходящее с галочками
    await engine.next(); // пауза (в ручном режиме пропускается)
    await engine.next(); // «Не ври мне.»
    await engine.next(); // удалить последнее входящее
    added = await sceneMessages(s);
    final lie = added.firstWhere((m) => m.text == 'Не ври мне.');
    expect(lie.deleted, isTrue);
    expect(engine.status, EngineStatus.finished);

    await engine.back(); // «Назад» — удаление отменено
    added = await sceneMessages(s);
    expect(added.firstWhere((m) => m.text == 'Не ври мне.').deleted, isFalse);

    await engine.reset();
    expect(await sceneMessages(s), isEmpty);
    expect((await s.messages.forChat(veronikaChat)).length, baseMessages);
    expect(await unread(s, veronikaChat), 2, reason: 'счётчик вернулся к исходному');
    expect(engine.status, EngineStatus.ready);

    await Future<void>.delayed(const Duration(milliseconds: 400)); // фоновые галочки остановились
    await s.close();
  });

  test('сброс сцены после перезапуска приложения', () async {
    var s = await openApp();
    s.engine.setSpeed(4);
    await s.engine.load(demoScene);
    await s.engine.start();
    await s.engine.next();
    await s.engine.next();
    expect((await sceneMessages(s)).length, 2);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await s.close(); // «приложение закрыли посреди дубля»

    s = await openApp(); // сцена восстановлена из настроек
    expect(s.engine.info?.sceneId, demoScene);
    // Дубль продолжен: выполненные события и позиция сохранились в базе.
    expect(s.engine.hasTake, isTrue);
    expect(s.engine.index, 2);
    expect(s.engine.isExecuted(s.engine.actions[0].id), isTrue);
    expect(s.engine.isExecuted(s.engine.actions[1].id), isTrue);
    expect(s.engine.isExecuted(s.engine.actions[2].id), isFalse);
    await s.engine.reset(); // сброс по журналу дубля из базы
    expect(await sceneMessages(s), isEmpty);
    expect(await unread(s, veronikaChat), 2);

    await s.engine.reset(); // повторный сброс ничего не портит
    expect((await s.chats.listForDevice(device)).length, 4);
    await s.close();
  });

  test('сообщение актёра во время дубля исчезает при сбросе', () async {
    final s = await openApp();
    await s.engine.load(demoScene);
    await s.engine.start();
    await s.messages.sendText(
      chatId: veronikaChat,
      senderId: hero,
      text: 'Импровизация актёра',
      sceneId: s.engine.sceneIdForChat(veronikaChat),
    );
    expect((await sceneMessages(s)).single.text, 'Импровизация актёра');
    await s.engine.reset();
    expect(await sceneMessages(s), isEmpty);
    await s.close();
  });

  test('импровизация: ответ собеседника и «Убрать импровизацию»', () async {
    final s = await openApp();
    final sender = ServicesImprovSender(s);
    await sender.send(veronikaChat, const QueuedReply(text: 'Я у подъезда', typingMs: 0));
    final improv = (await s.messages.forChat(veronikaChat)).where((m) => m.origin == DataOrigin.improv);
    expect(improv.single.senderId, 'char-veronika');
    expect(await s.messages.deleteImprov(veronikaChat), 1);
    await s.close();
  });

  test('пропущенный звонок: история, запись в чате, непрочитанное', () async {
    final s = await openApp();
    await ServicesCallRecorder(s).record(
      const CallSession(
        deviceId: device,
        characterId: 'char-nina',
        direction: CallDirection.incoming,
        kind: CallKind.audio,
        displayName: 'Мама',
        chatId: 'chat-mama',
      ),
      CallOutcome.missed,
      DateTime.now(),
      Duration.zero,
    );
    final calls = await s.calls.forDevice(device);
    expect(calls.single.displayName, 'Мама');
    final last = (await s.messages.forChat('chat-mama')).last;
    expect(last.type, MessageType.call);
    expect(last.text, 'Пропущенный аудиозвонок');
    expect(await unread(s, 'chat-mama'), 3);
    await s.close();
  });

  test('кинорежим и тема сохраняются после перезапуска', () async {
    var s = await openApp();
    await s.kino.update(s.kino.value.copyWith(enabled: true, battery: 17));
    await s.close();
    s = await openApp();
    expect(s.kino.value.enabled, isTrue);
    expect(s.kino.value.battery, 17);
    await s.kino.update(const KinoSettings());
    await s.close();
  });

  test('второй телефон: свои чаты и контакты', () async {
    final s = await openApp();
    final id = await s.devices.create(name: 'Телефон мамы', ownerCharacterId: 'char-nina');
    await s.setCurrentDevice(id);
    expect(await s.chats.listForDevice(id), isEmpty);
    expect(await s.contacts.forDevice(id), isEmpty);
    await s.contacts.save(
      deviceId: id,
      characterId: hero,
      draft: const CharacterDraft(firstName: 'Максим', lastName: 'Ветров', phone: '+7 915 318-42-07'),
      displayName: 'Сынок',
    );
    expect((await s.contacts.forDevice(id)).single.displayName, 'Сынок');
    expect((await s.contacts.forDevice(device)).length, 4, reason: 'на телефоне героя ничего не изменилось');
    await s.close();
  });

  // ---------- Многоконтактная сцена (критерий готовности) ----------

  const aleksey = 'char-aleksey';
  const nina = 'char-nina';
  const veronika = 'char-veronika';

  SceneAction step(String sceneId, ActionType type, String who, [Map<String, Object?> params = const {}]) =>
      SceneAction(
        id: newId(),
        sceneId: sceneId,
        position: 0,
        typeName: type.name,
        params: {'characterId': who, ...params},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  Future<String> meetingScene(AppServices s, {bool withTimeline = true}) async {
    final id = await s.scenes.create(deviceId: device, number: '20', name: 'Встреча');
    await s.scenes.addParticipants(id, [aleksey, nina, veronika]);
    if (withTimeline) {
      for (final a in [
        step(id, ActionType.showIncoming, aleksey, {'text': 'Ты уже приехал?'}),
        step(id, ActionType.incomingAudioCall, nina),
        step(id, ActionType.showIncoming, veronika, {'text': 'Я всё поняла'}),
        step(id, ActionType.showIncoming, aleksey, {'text': 'Открой дверь'}),
        step(id, ActionType.deleteMessage, veronika, {'target': 'lastIncoming'}),
        step(id, ActionType.endCall, nina),
      ]) {
        await s.scenes.saveAction(a);
      }
    }
    return id;
  }

  Future<List<Message>> fromScene(AppServices s, String chatId) async =>
      (await s.messages.forChat(chatId)).where((m) => m.sceneId != null).toList();

  test('одна сцена, три участника: сообщение, звонок, сообщение, второе сообщение, удаление, конец звонка', () async {
    final s = await openApp();
    final sceneId = await meetingScene(s);
    final engine = s.engine..setSpeed(4);
    await engine.load(sceneId);
    expect(engine.info!.participants.map((p) => p.name), ['Алексей', 'Мама', 'Красотка']);

    await engine.start();
    await engine.next(); // Алексей → сообщение
    expect((await fromScene(s, 'chat-aleksey')).single.text, 'Ты уже приехал?');

    await engine.next(); // Мама → входящий звонок
    expect(s.callEngine.phase, CallPhase.incoming);
    expect(s.callEngine.session?.characterId, nina);

    await engine.next(); // Красотка → сообщение (звонок идёт, сцена не заблокирована)
    expect((await fromScene(s, veronikaChat)).single.text, 'Я всё поняла');
    expect(s.callEngine.phase, CallPhase.incoming);

    await engine.next(); // Алексей → второе сообщение
    expect((await fromScene(s, 'chat-aleksey')).map((m) => m.text), ['Ты уже приехал?', 'Открой дверь']);

    await engine.next(); // Красотка → удаляет своё сообщение
    final hers = (await fromScene(s, veronikaChat)).single;
    expect(hers.deleted, isTrue);
    expect(hers.senderId, veronika, reason: 'удалено именно её сообщение');

    await engine.next(); // Мама → завершает звонок
    expect(s.callEngine.phase, CallPhase.ended);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect((await s.calls.forDevice(device)).single.call.characterId, nina);
    expect((await fromScene(s, 'chat-mama')).single.type, MessageType.call);
    expect(engine.status, EngineStatus.finished);

    // Состояние каждого участника сохранено независимо.
    expect(await unread(s, 'chat-aleksey'), 3);
    expect(await unread(s, veronikaChat), 3);
    expect(await unread(s, 'chat-mama'), 3);

    // Сброс возвращает все три чата и историю звонков.
    await engine.reset();
    for (final chat in ['chat-aleksey', veronikaChat, 'chat-mama']) {
      expect(await fromScene(s, chat), isEmpty, reason: chat);
    }
    expect(await unread(s, 'chat-aleksey'), 1);
    expect(await unread(s, veronikaChat), 2);
    expect(await unread(s, 'chat-mama'), 2);
    expect(await s.calls.forDevice(device), isEmpty);
    expect(s.callEngine.phase, CallPhase.idle);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await s.close();
  });

  test('ручной режим: оператор переключает участников, «Назад», запись в таймлайн', () async {
    final s = await openApp();
    final sceneId = await meetingScene(s, withTimeline: false);
    final engine = s.engine..setSpeed(4);
    await engine.load(sceneId);
    expect(engine.hasTake, isFalse);

    Future<void> live(String who, ActionType type, [Map<String, Object?> p = const {}]) async {
      engine.selectParticipant(who);
      expect(engine.activeParticipantId, who);
      final recorded = await engine.performLive(step(sceneId, type, engine.activeParticipantId!, p));
      if (recorded != null) await s.scenes.saveAction(recorded);
    }

    engine.setRecordLive(true);
    await live(aleksey, ActionType.showIncoming, {'text': 'Ты где?'});
    expect(engine.hasTake, isTrue, reason: 'первое ручное действие начинает дубль');
    await live(nina, ActionType.incomingVideoCall);
    await live(veronika, ActionType.showIncoming, {'text': 'Я уже здесь'});
    await live(aleksey, ActionType.showIncoming, {'text': 'Открой дверь'});
    expect((await fromScene(s, 'chat-aleksey')).length, 2, reason: 'переписка Алексея не сбросилась');

    await live(veronika, ActionType.deleteMessage, {'target': 'lastIncoming'});
    expect((await fromScene(s, veronikaChat)).single.deleted, isTrue);
    await engine.back(); // отменить удаление
    expect((await fromScene(s, veronikaChat)).single.deleted, isFalse);
    await live(veronika, ActionType.deleteMessage, {'target': 'lastIncoming'});

    await live(nina, ActionType.endCall);
    expect(s.callEngine.phase, CallPhase.ended);

    // Звонок чужого участника завершить нельзя — ошибка в журнале, сцена идёт.
    await live(aleksey, ActionType.endCall);
    expect(engine.log.first, contains('Ошибка'));

    final timeline = await s.scenes.actions(sceneId);
    expect(timeline.length, 8, reason: 'ручные действия записаны в таймлайн');
    expect(timeline.map((a) => a.characterId).toSet(), {aleksey, nina, veronika});

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await engine.reset();
    expect(await fromScene(s, 'chat-aleksey'), isEmpty);
    expect(await fromScene(s, veronikaChat), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await s.close();
  });
}

class _SilentSounds implements CallSounds {
  @override
  void ringtone() {}
  @override
  void ringback() {}
  @override
  void hangup() {}
  @override
  void stop() {}
}
