// Группы (C3): в самом Messenger и через Connect — на настоящей базе,
// настоящем сервере и клиенте.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/client/connect_client.dart';
import 'package:replika/connect/protocol/protocol.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/connect/service/connect_service.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/features/chat/chat_screen.dart' show membersLabel;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const device = 'device-maxim';
const maxim = 'char-maxim';
const veronika = 'char-veronika';
const aleksey = 'char-aleksey';
const nina = 'char-nina';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('replika_groups_');
    s = await AppServices.open(databasePath: p.join(tempDir.path, 'replika.db'));
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await s.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('подписи числа участников', () {
    expect(membersLabel(1), '1 участник');
    expect(membersLabel(3), '3 участника');
    expect(membersLabel(5), '5 участников');
    expect(membersLabel(11), '11 участников');
    expect(membersLabel(22), '22 участника');
  });

  test('группа в Messenger: владелец входит всегда, имена «глазами телефона», превью с отправителем', () async {
    final id = await s.chats.createGroup(deviceId: device, title: 'Съёмочная группа', memberIds: [veronika, aleksey]);
    final members = await s.chats.members(id);
    expect(members.first.name, 'Вы');
    expect(members.map((m) => m.name), containsAll(['Красотка', 'Алексей']));

    await s.messages.insertSceneMessage(
      chatId: id,
      senderId: veronika,
      type: MessageType.text,
      text: 'Встречаемся в 19:00',
      sceneId: null,
    );
    final item = (await s.chats.listForDevice(device)).firstWhere((c) => c.chat.id == id);
    expect(item.chat.isGroup, isTrue);
    expect(item.displayName, 'Съёмочная группа');
    expect(item.lastSenderName, 'Красотка');

    await s.chats.removeMember(id, aleksey);
    expect(await s.chats.isMember(id, aleksey), isFalse);
    await s.chats.renameGroup(id, 'Площадка');
    expect((await s.chats.header(id))!.peer.displayName, 'Площадка');
  });

  group('Через Connect', () {
    late ConnectService connect;
    late ConnectClient client;

    setUp(() async {
      connect = ConnectService(services: s, store: MemorySecretStore(), port: 0, discoveryPortNumber: 0);
      connect.addListener(() {
        if (connect.pendingPairing != null) connect.answerPairing(true);
      });
      await connect.start();
      client = ConnectClient(store: MemorySecretStore(), controllerName: 'Controller C3');
      connect.openPairing();
      await client.connect('127.0.0.1', port: connect.boundPort!);
      expect(await client.pair(), isTrue);
      await client.hello();
    });

    tearDown(() async {
      await client.close();
      await connect.stop();
    });

    Future<List<Message>> groupMessages(String key) => s.messages.forChat('grp:$device:$key');

    test('создание, сообщения участников и владельца, состав, события', () async {
      final created = await client.command('CREATE_CHAT', {
        'groupId': 'crew',
        'title': 'Съёмочная группа',
        'memberIds': [veronika, aleksey],
        'fromCharacterId': veronika,
      });
      expect(created.success, isTrue, reason: created.message);
      expect(created.result['groupId'], 'crew');

      final groups = await client.command('LIST_GROUPS');
      final crew = (groups.result['groups'] as List).cast<Map>().firstWhere((g) => g['groupId'] == 'crew');
      expect((crew['members'] as List).toSet(), {maxim, veronika, aleksey});

      expect((await client.command('MESSAGE', {'groupId': 'crew', 'fromCharacterId': veronika, 'text': 'Встречаемся в 19:00'})).success, isTrue);
      expect((await client.command('MESSAGE', {'groupId': 'crew', 'fromCharacterId': maxim, 'text': 'Буду'})).success, isTrue);
      final notMember = await client.command('MESSAGE', {'groupId': 'crew', 'fromCharacterId': nina, 'text': 'Я тоже'});
      expect(notMember.error, ConnectError.invalidTarget);

      expect((await client.command('ADD_PARTICIPANT', {'groupId': 'crew', 'characterId': nina, 'byCharacterId': veronika})).success, isTrue);
      expect((await client.command('MESSAGE', {'groupId': 'crew', 'fromCharacterId': nina, 'text': 'Я тоже'})).success, isTrue);
      expect((await client.command('REMOVE_PARTICIPANT', {'groupId': 'crew', 'characterId': aleksey})).success, isTrue);
      expect((await client.command('MESSAGE', {'groupId': 'crew', 'fromCharacterId': aleksey, 'text': 'Эй'})).error,
          ConnectError.invalidTarget);

      final messages = await groupMessages('crew');
      final texts = messages.map((m) => m.text).toList();
      expect(texts.first, 'Красотка создал(а) группу «Съёмочная группа»');
      expect(texts, containsAllInOrder(['Встречаемся в 19:00', 'Буду', 'Красотка добавил(а) Мама', 'Я тоже', 'Вы удалили: Алексей']));
      expect(messages.firstWhere((m) => m.text == 'Встречаемся в 19:00').senderId, veronika);
      expect(messages.firstWhere((m) => m.text == 'Буду').senderId, maxim);
    });

    test('ошибки: повтор ключа, неизвестная группа, неверный ключ, пустой состав', () async {
      Future<CommandResult> create(Map<String, Object?> p) => client.command('CREATE_CHAT', p);
      expect((await create({'groupId': 'crew', 'title': 'Группа', 'memberIds': [veronika]})).success, isTrue);
      expect((await create({'groupId': 'crew', 'title': 'Группа', 'memberIds': [veronika]})).error, ConnectError.invalidTarget);
      expect((await create({'groupId': 'пробел и кириллица', 'title': 'Г', 'memberIds': [veronika]})).error,
          ConnectError.invalidRequest);
      expect((await create({'groupId': 'x', 'title': 'Г', 'memberIds': <String>[]})).error, ConnectError.invalidRequest);
      expect((await create({'groupId': 'y', 'title': 'Г', 'memberIds': ['nobody']})).error, ConnectError.invalidTarget);
      expect((await client.command('MESSAGE', {'groupId': 'nope', 'fromCharacterId': veronika, 'text': 'x'})).error,
          ConnectError.invalidTarget);
    });

    test('сообщение группы: правка и удаление по messageId', () async {
      await client.command('CREATE_CHAT', {'groupId': 'crew', 'title': 'Группа', 'memberIds': [veronika]});
      final sent = await client.command('MESSAGE', {'groupId': 'crew', 'fromCharacterId': veronika, 'text': 'Опечатка'});
      final id = sent.result['messageId'] as String;
      expect((await client.command('EDIT_MESSAGE', {'messageId': id, 'text': 'Исправлено'})).success, isTrue);
      expect((await s.messages.byId(id))!.text, 'Исправлено');
      expect((await client.command('DELETE_MESSAGE', {'messageId': id})).success, isTrue);
      expect((await s.messages.byId(id))!.deleted, isTrue);
    });

    test('RESET_SCENE: группа Connect исчезает, состав обычной группы возвращается', () async {
      final manual = await s.chats.createGroup(deviceId: device, title: 'Своя группа', memberIds: [veronika, aleksey]);
      await client.command('CREATE_CHAT', {'groupId': 'crew', 'title': 'Группа', 'memberIds': [veronika]});
      await client.command('MESSAGE', {'groupId': 'crew', 'fromCharacterId': veronika, 'text': 'Раз'});
      final removed = await client.command('REMOVE_PARTICIPANT', {'groupId': manual, 'characterId': aleksey});
      expect(removed.success, isTrue, reason: 'группа, созданная на телефоне, доступна по id');
      expect(await s.chats.isMember(manual, aleksey), isFalse);

      expect((await client.command('RESET_SCENE')).success, isTrue);
      expect(await s.chats.header('grp:$device:crew'), isNull, reason: 'группа Connect удалена');
      expect(await s.chats.isMember(manual, aleksey), isTrue, reason: 'участник обычной группы возвращён');
      expect((await s.messages.forChat(manual)).where((m) => m.sceneId != null), isEmpty);
      expect((await s.chats.header(manual))!.peer.displayName, 'Своя группа');
    });
  });
}
