// «Прочитано: ON / OFF» у исходящих и автопрочтение по ответу:
// на настоящей SQLite, настоящих репозиториях и Scene Engine.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/data/models/scene_action.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const veronikaChat = 'chat-veronika';
const veronika = 'char-veronika';
const demoScene = 'scene-demo-12';

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
late String dbPath;

SceneAction act(String id, ActionType type, Map<String, Object?> params) => SceneAction(
      id: id,
      sceneId: demoScene,
      position: 0,
      typeName: type.name,
      params: {'characterId': veronika, ...params},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<AppServices> openApp() => AppServices.open(databasePath: dbPath);

Future<Message> byText(AppServices s, String text) async =>
    (await s.messages.forChat(veronikaChat)).firstWhere((m) => m.text == text);

Future<void> close(AppServices s) async {
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await s.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('replika_read_');
    dbPath = p.join(tempDir.path, 'replika.db');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('Прочитано ON: сообщение прочитано сразу после выполнения, без ответа', () async {
    final s = await openApp();
    await s.engine.load(demoScene);
    await s.engine.performCommand(act('o1', ActionType.showOutgoing, {'text': 'Ты дома?', 'read': true}));
    final m = await byText(s, 'Ты дома?');
    expect(m.state, MessageState.read);
    expect(await s.messages.isReadHeld(m.id), isFalse);
    await close(s);
  });

  test('Прочитано OFF: любое следующее сообщение не читает, ответ на него — читает', () async {
    final s = await openApp();
    await s.engine.load(demoScene);
    await s.engine.performCommand(act('o1', ActionType.showOutgoing, {'text': 'Ты дома?', 'read': false}));
    var m = await byText(s, 'Ты дома?');
    expect(m.state, MessageState.delivered);
    expect(await s.messages.isReadHeld(m.id), isTrue);

    // Входящее без связи — не ответ на это сообщение.
    await s.engine.performCommand(act('i1', ActionType.showIncoming, {'text': 'Привет'}));
    m = await byText(s, 'Ты дома?');
    expect(m.state, MessageState.delivered, reason: 'не «любое следующее сообщение»');

    // Ответ с replyToActionId.
    await s.engine.performCommand(
        act('i2', ActionType.showIncoming, {'text': 'Да, дома', 'replyToActionId': 'o1'}));
    m = await byText(s, 'Ты дома?');
    final reply = await byText(s, 'Да, дома');
    expect(reply.replyToId, m.id, reason: 'связь replyToMessageId');
    expect(m.state, MessageState.read);
    expect(await s.messages.isReadHeld(m.id), isFalse);
    await close(s);
  });

  test('«Назад» отменяет ответ: сообщение снова непрочитано и удерживается', () async {
    final s = await openApp();
    await s.engine.load(demoScene);
    await s.engine.performCommand(act('o1', ActionType.showOutgoing, {'text': 'Ты дома?', 'read': false}));
    await s.engine.performCommand(
        act('i2', ActionType.showIncoming, {'text': 'Да, дома', 'replyToActionId': 'o1'}));
    await s.engine.back();
    final m = await byText(s, 'Ты дома?');
    expect(m.state, MessageState.delivered);
    expect(await s.messages.isReadHeld(m.id), isTrue);
    expect((await s.messages.forChat(veronikaChat)).any((x) => x.text == 'Да, дома'), isFalse);
    await close(s);
  });

  test('отправка с Прочитано ON — сразу «прочитано», с OFF — доставлено и не дальше', () async {
    final s = await openApp();
    s.engine.setSpeed(4);
    await s.engine.load(demoScene);
    await s.engine.performCommand(act('o1', ActionType.sendMessage, {'text': 'Один', 'read': true}));
    await s.engine.performCommand(act('o2', ActionType.sendMessage, {'text': 'Два', 'read': false, 'readMs': 500}));
    expect((await byText(s, 'Один')).state, MessageState.read);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final two = await byText(s, 'Два');
    expect(two.state, MessageState.delivered, reason: 'readMs игнорируется при OFF');
    expect(await s.messages.isReadHeld(two.id), isTrue);
    await close(s);
  });

  test('ответ находит своё сообщение и после перезапуска приложения', () async {
    var s = await openApp();
    await s.engine.load(demoScene);
    await s.engine.performCommand(act('o1', ActionType.showOutgoing, {'text': 'Ты дома?', 'read': false}));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await s.close();

    s = await openApp(); // дубль продолжен, связь «действие → сообщение» из базы
    expect(s.engine.hasTake, isTrue);
    final before = await byText(s, 'Ты дома?');
    expect(before.state, MessageState.delivered);
    expect(await s.messages.isReadHeld(before.id), isTrue, reason: 'флаг хранится в базе');

    await s.engine.performCommand(
        act('i2', ActionType.showIncoming, {'text': 'Да, дома', 'replyToActionId': 'o1'}));
    expect((await byText(s, 'Ты дома?')).state, MessageState.read);
    await close(s);
  });
}
