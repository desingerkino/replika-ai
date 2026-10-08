// Connect 1.3 (для Prop Controller): персонажи с пульта (M1), передача
// медиа (M2), время сообщения (M3), групповой чат и вкладки в OPEN_SCREEN
// (M4). Настоящая база, настоящий сервер и клиент, как в groups_test.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/media_store.dart';
import 'package:replika/app/navigator.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/client/connect_client.dart';
import 'package:replika/connect/protocol/protocol.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/connect/service/connect_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const device = 'device-maxim';
const maxim = 'char-maxim';
const veronika = 'char-veronika';

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

/// Настоящий PNG 1×1.
final List<int> _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

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

  late ConnectService connect;
  late ConnectClient client;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('replika_prep_');
    MediaStore.testDirectory = Directory(p.join(tempDir.path, 'media'));
    s = await AppServices.open(databasePath: p.join(tempDir.path, 'replika.db'));
    connect = ConnectService(services: s, store: MemorySecretStore(), port: 0, discoveryPortNumber: 0);
    connect.addListener(() {
      if (connect.pendingPairing != null) connect.answerPairing(true);
    });
    await connect.start();
    client = ConnectClient(store: MemorySecretStore(), controllerName: 'Prop Controller');
    connect.openPairing();
    await client.connect('127.0.0.1', port: connect.boundPort!);
    expect(await client.pair(), isTrue);
    await client.hello();
  });

  tearDown(() async {
    await client.close();
    await connect.stop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await s.close();
    MediaStore.testDirectory = null;
    AppNavigator.homeTab.value = 0;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('DEVICE_INFO: Connect 1.3 и новые действия в supportedActions', () async {
    final info = await client.command('DEVICE_INFO');
    expect(info.result['connectVersion'], '1.3.0');
    expect(
      info.result['supportedActions'] as List,
      containsAll(['UPSERT_CHARACTER', 'MEDIA_UPLOAD_BEGIN', 'MEDIA_UPLOAD_CHUNK', 'MEDIA_UPLOAD_COMMIT']),
    );
  });

  group('M1: UPSERT_CHARACTER', () {
    test('создаёт персонажа с ключом пульта и записывает в контакты по имени', () async {
      final r = await client.command('UPSERT_CHARACTER', {
        'characterId': 'masha',
        'firstName': 'Маша',
        'lastName': 'Орлова',
        'phone': '+7 900 000-00-01',
      });
      expect(r.success, isTrue, reason: r.message);
      expect(r.result['created'], isTrue);
      final ch = (await s.contacts.allCharacters()).firstWhere((c) => c.id == 'masha');
      expect(ch.fullName, 'Маша Орлова');
      expect(ch.phone, '+7 900 000-00-01');
      final contact = (await s.contacts.forDevice(device)).firstWhere((c) => c.id == 'masha');
      expect(contact.displayName, 'Маша Орлова');
    });

    test('повтор меняет только переданные поля; contactName; addToContacts: false', () async {
      await client.command('UPSERT_CHARACTER', {'characterId': 'masha', 'firstName': 'Маша', 'phone': '111'});
      final again = await client.command('UPSERT_CHARACTER', {'characterId': 'masha', 'contactName': 'Любимая'});
      expect(again.success, isTrue, reason: again.message);
      expect(again.result['created'], isFalse);
      final ch = (await s.contacts.allCharacters()).firstWhere((c) => c.id == 'masha');
      expect(ch.firstName, 'Маша', reason: 'имя не передавали — осталось');
      expect(ch.phone, '111');
      expect((await s.contacts.forDevice(device)).firstWhere((c) => c.id == 'masha').displayName, 'Любимая');

      await client.command('UPSERT_CHARACTER', {'characterId': 'masha', 'addToContacts': false});
      expect((await s.contacts.forDevice(device)).any((c) => c.id == 'masha'), isFalse);
    });

    test('владелец телефона не попадает в свои контакты', () async {
      final r = await client.command('UPSERT_CHARACTER', {'characterId': maxim, 'firstName': 'Максим'});
      expect(r.success, isTrue, reason: r.message);
      expect(r.result['isOwner'], isTrue);
      expect((await s.contacts.forDevice(device)).any((c) => c.id == maxim), isFalse);
    });

    test('ошибки: неверный ключ, нет имени, аватар не загружен', () async {
      expect((await client.command('UPSERT_CHARACTER', {'characterId': 'Маша', 'firstName': 'М'})).error,
          ConnectError.invalidRequest);
      expect((await client.command('UPSERT_CHARACTER', {'characterId': 'x'})).error, ConnectError.invalidRequest);
      expect(
        (await client.command('UPSERT_CHARACTER', {'characterId': 'x', 'firstName': 'X', 'avatarMediaId': 'nope'})).error,
        ConnectError.invalidTarget,
      );
    });

    test('новый персонаж сразу работает в сцене; RESET_SCENE его не удаляет', () async {
      await client.command('UPSERT_CHARACTER', {'characterId': 'masha', 'firstName': 'Маша'});
      final m = await client.command('MESSAGE', {'fromCharacterId': 'masha', 'toCharacterId': maxim, 'text': 'Ты где?'});
      expect(m.success, isTrue, reason: m.message);
      expect((await client.command('RESET_SCENE')).success, isTrue);
      expect((await s.messages.byId(m.result['messageId'] as String)), isNull, reason: 'сообщение сцены убрано');
      expect((await s.contacts.allCharacters()).any((c) => c.id == 'masha'), isTrue, reason: 'персонаж остался');

      final assigned = await client.command('ASSIGN_CHARACTER', {'characterId': 'masha'});
      expect(assigned.success, isTrue, reason: assigned.message);
      expect(assigned.result['characterId'], 'masha');
    });
  });

  group('M2: MEDIA_UPLOAD_*', () {
    Future<String> sha(List<int> bytes) async =>
        (await Sha256().hash(bytes)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    test('BEGIN → CHUNK → COMMIT; фото уходит в чат и в аватар; повтор — exists', () async {
      final half = _png.length ~/ 2;
      final begin = await client.command('MEDIA_UPLOAD_BEGIN', {
        'mediaId': 'pcm-photo1',
        'kind': 'photo',
        'name': 'кадр.png',
        'size': _png.length,
        'sha256': await sha(_png),
      });
      expect(begin.success, isTrue, reason: begin.message);
      expect(begin.result['exists'], isFalse);
      expect(begin.result['received'], 0);

      final c1 = await client.command('MEDIA_UPLOAD_CHUNK',
          {'mediaId': 'pcm-photo1', 'offset': 0, 'data': base64Encode(_png.sublist(0, half))});
      expect(c1.result['received'], half);
      final wrong = await client.command('MEDIA_UPLOAD_CHUNK',
          {'mediaId': 'pcm-photo1', 'offset': 5000, 'data': base64Encode(_png.sublist(half))});
      expect(wrong.error, ConnectError.invalidRequest);
      final c2 = await client.command('MEDIA_UPLOAD_CHUNK',
          {'mediaId': 'pcm-photo1', 'offset': half, 'data': base64Encode(_png.sublist(half))});
      expect(c2.result['received'], _png.length);

      final commit = await client.command('MEDIA_UPLOAD_COMMIT', {'mediaId': 'pcm-photo1'});
      expect(commit.success, isTrue, reason: commit.message);
      final item = await s.media.repository.byId('pcm-photo1');
      expect(item, isNotNull);
      expect(File(item!.path).lengthSync(), _png.length);

      final sent = await client.command('MEDIA', {'fromCharacterId': veronika, 'toCharacterId': maxim, 'mediaId': 'pcm-photo1'});
      expect(sent.success, isTrue, reason: sent.message);
      final avatar = await client.command(
          'UPSERT_CHARACTER', {'characterId': 'masha', 'firstName': 'Маша', 'avatarMediaId': 'pcm-photo1'});
      expect(avatar.success, isTrue, reason: avatar.message);

      final repeat = await client.command('MEDIA_UPLOAD_BEGIN',
          {'mediaId': 'pcm-photo1', 'kind': 'photo', 'name': 'кадр.png', 'size': _png.length});
      expect(repeat.result['exists'], isTrue);
    });

    test('докачка: после обрыва BEGIN сообщает, сколько уже получено', () async {
      final meta = {'mediaId': 'pcm-2', 'kind': 'photo', 'name': 'a.png', 'size': _png.length};
      await client.command('MEDIA_UPLOAD_BEGIN', meta);
      await client.command('MEDIA_UPLOAD_CHUNK', {'mediaId': 'pcm-2', 'offset': 0, 'data': base64Encode(_png.sublist(0, 10))});
      final resumed = await client.command('MEDIA_UPLOAD_BEGIN', meta);
      expect(resumed.result['received'], 10);
      final dup = await client.command(
          'MEDIA_UPLOAD_CHUNK', {'mediaId': 'pcm-2', 'offset': 0, 'data': base64Encode(_png.sublist(0, 10))});
      expect(dup.success, isTrue, reason: 'повтор уже записанного куска не ошибка');
      expect(dup.result['received'], 10);
    });

    test('неверная контрольная сумма — файл не попадает в медиатеку', () async {
      await client.command('MEDIA_UPLOAD_BEGIN',
          {'mediaId': 'pcm-bad', 'kind': 'photo', 'name': 'b.png', 'size': _png.length, 'sha256': 'a' * 64});
      await client.command('MEDIA_UPLOAD_CHUNK', {'mediaId': 'pcm-bad', 'offset': 0, 'data': base64Encode(_png)});
      final commit = await client.command('MEDIA_UPLOAD_COMMIT', {'mediaId': 'pcm-bad'});
      expect(commit.error, ConnectError.actionFailed);
      expect(await s.media.repository.byId('pcm-bad'), isNull);
    });

    test('ошибки BEGIN: вид, размер, ключ', () async {
      Future<String?> begin(Map<String, Object?> p) async => (await client.command('MEDIA_UPLOAD_BEGIN', p)).error;
      expect(await begin({'mediaId': 'x', 'kind': 'file', 'name': 'a.pdf', 'size': 10}), ConnectError.invalidRequest);
      expect(await begin({'mediaId': 'x', 'kind': 'photo', 'name': 'a.png', 'size': 0}), ConnectError.invalidRequest);
      expect(await begin({'mediaId': 'x y', 'kind': 'photo', 'name': 'a.png', 'size': 10}), ConnectError.invalidRequest);
      expect((await client.command('MEDIA_UPLOAD_CHUNK', {'mediaId': 'never', 'offset': 0, 'data': 'AA=='})).error,
          ConnectError.invalidRequest);
    });
  });

  test('M3: messageTime — время у сообщения задаёт пульт', () async {
    final at = DateTime(2026, 9, 26, 23, 47);
    final r = await client.command('MESSAGE', {
      'fromCharacterId': veronika,
      'toCharacterId': maxim,
      'text': 'Не спишь?',
      'messageTime': at.millisecondsSinceEpoch,
    });
    expect(r.success, isTrue, reason: r.message);
    expect((await s.messages.byId(r.result['messageId'] as String))!.sentAt, at);
    final bad = await client.command(
        'MESSAGE', {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'x', 'messageTime': 'вчера'});
    expect(bad.error, ConnectError.invalidRequest);
  });

  test('M4: OPEN_SCREEN — вкладки и групповой чат', () async {
    expect((await client.command('OPEN_SCREEN', {'screen': 'CALLS'})).success, isTrue);
    expect(AppNavigator.homeTab.value, 2);
    expect((await client.command('OPEN_SCREEN', {'screen': 'CONTACTS'})).success, isTrue);
    expect(AppNavigator.homeTab.value, 1);
    expect((await client.command('OPEN_SCREEN', {'screen': 'CHAT_LIST'})).success, isTrue);
    expect(AppNavigator.homeTab.value, 0);

    expect((await client.command('OPEN_SCREEN', {'screen': 'CHAT', 'groupId': 'crew'})).error, ConnectError.invalidTarget);
    await client.command('CREATE_CHAT', {'groupId': 'crew', 'title': 'Съёмочная группа', 'memberIds': [veronika]});
    final opened = await client.command('OPEN_SCREEN', {'screen': 'CHAT', 'groupId': 'crew'});
    expect(opened.success, isTrue, reason: opened.message);
    expect(opened.result['groupId'], 'crew');
  });
}
