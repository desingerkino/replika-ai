// Connect целиком: настоящий WebSocket-сервер на localhost, настоящий клиент
// протокола, настоящая SQLite (sqflite_common_ffi) и существующий Scene Engine.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/client/connect_client.dart';
import 'package:replika/connect/protocol/protocol.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/connect/server/connect_server.dart';
import 'package:replika/connect/service/connect_service.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/data/models/origin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const maxim = 'char-maxim';
const veronika = 'char-veronika';
const aleksey = 'char-aleksey';
const connectScene = 'connect-device-maxim';

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
late ConnectService connect;
late ConnectClient client;
bool? autoAnswer;
String? phoneCode;

Future<void> pairAndHello() async {
  autoAnswer = true;
  connect.openPairing();
  await client.connect('127.0.0.1', port: connect.boundPort!);
  expect(await client.pair(), isTrue);
  await client.hello();
}

Future<CommandResult> send(String type, [Map<String, Object?> payload = const {}, String? id]) => client.send(
      CommandRequest(commandId: id ?? 'cmd-${DateTime.now().microsecondsSinceEpoch}', actionType: type, payload: payload),
    );

Future<List<Message>> connectMessages(String chatId) async =>
    (await s.messages.forChat(chatId)).where((m) => m.sceneId == connectScene).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('replika_connect_');
    s = await AppServices.open(databasePath: p.join(tempDir.path, 'replika.db'));
    connect = ConnectService(services: s, store: MemorySecretStore(), port: 0);
    connect.addListener(() {
      final pending = connect.pendingPairing;
      if (pending != null && autoAnswer != null) {
        phoneCode = pending.code;
        connect.answerPairing(autoAnswer!);
      }
    });
    await connect.start();
    client = ConnectClient(store: MemorySecretStore(), controllerName: 'Тестовый Controller');
    autoAnswer = null;
    phoneCode = null;
  });

  tearDown(() async {
    await client.close();
    await connect.stop();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await s.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Соединение и безопасность', () {
    test('без открытого окна сопряжения новое устройство не принимается', () async {
      await client.connect('127.0.0.1', port: connect.boundPort!);
      expect(() => client.pair(), throwsA(isA<ConnectException>().having((e) => e.code, 'code', 'UNAUTHORIZED')));
    });

    test('сопряжение: коды совпадают; отклонение и разрешение', () async {
      autoAnswer = false;
      connect.openPairing();
      await client.connect('127.0.0.1', port: connect.boundPort!);
      String? controllerCode;
      expect(await client.pair(onCode: (c) => controllerCode = c), isFalse);
      expect(controllerCode, phoneCode, reason: 'оператор сверяет одинаковые коды');
      expect(await connect.trusted(), isEmpty);

      await pairAndHello();
      expect((await connect.trusted()).single.name, 'Тестовый Controller');
      expect(connect.state, ConnectState.connected);
    });

    test('неизвестное устройство не проходит аутентификацию', () async {
      await client.connect('127.0.0.1', port: connect.boundPort!);
      expect(() => client.hello(), throwsA(isA<ConnectException>().having((e) => e.code, 'code', 'UNAUTHORIZED')));
    });

    test('подключение, отключение, повторное подключение — тот же Device ID', () async {
      await pairAndHello();
      final first = (await send('DEVICE_INFO')).result['deviceId'];
      await client.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(connect.sessions, isEmpty);
      await client.connect('127.0.0.1', port: connect.boundPort!);
      await client.hello();
      final info = await send('DEVICE_INFO');
      expect(info.result['deviceId'], first);
      expect(info.result['protocolVersion'], 1);
      expect(info.result['characterId'], maxim);
      expect(info.result['supportedActions'], contains('CREATE_CHAT'));
    });

    test('отозванное устройство отключается и больше не входит', () async {
      await pairAndHello();
      final closed = Completer<void>();
      client.onClosed = (_) => closed.isCompleted ? null : closed.complete();
      await connect.revoke(client.controllerId!);
      await closed.future.timeout(const Duration(seconds: 3));
      await client.connect('127.0.0.1', port: connect.boundPort!);
      expect(() => client.hello(), throwsA(isA<ConnectException>().having((e) => e.code, 'code', 'UNAUTHORIZED')));
    });

    test('истёкший сеанс закрывается', () async {
      await pairAndHello(); // доверие выдано на основном сервере
      await client.close();
      final shortServer = ConnectServer(
        trust: connect.trust,
        queue: connect.queue,
        hooks: connect,
        port: 0,
        sessionTtl: const Duration(milliseconds: 150),
      );
      await shortServer.start();
      await client.connect('127.0.0.1', port: shortServer.boundPort!);
      await client.hello();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(() => send('PING'), throwsA(isA<ConnectException>()));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(connect.logEntries.any((e) => e.text.contains('Сеанс истёк')), isTrue);
      await shortServer.stop();
    });

    test('мусор вместо кадра — соединение закрывается', () async {
      await client.connect('127.0.0.1', port: connect.boundPort!);
      final closed = Completer<void>();
      client.onClosed = (_) => closed.isCompleted ? null : closed.complete();
      client.sendRawText('это не JSON');
      await closed.future.timeout(const Duration(seconds: 3));
    });
  });

  group('Команды через сцену Connect', () {
    test('MESSAGE — настоящее сообщение Messenger; повтор commandId не дублирует', () async {
      await pairAndHello();
      const payload = {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Тест Connect'};
      final r1 = await send('MESSAGE', payload, 'cmd-001');
      expect(r1.success, isTrue);
      expect(r1.status, CommandStatus.executed);
      final created = await connectMessages('chat-veronika');
      expect(created.single.text, 'Тест Connect');
      expect(created.single.senderId, veronika);
      expect(created.single.origin, DataOrigin.scene);
      expect(r1.result['messageId'], created.single.id);

      final r2 = await send('MESSAGE', payload, 'cmd-001');
      expect(r2.status, CommandStatus.alreadyProcessed);
      expect((await connectMessages('chat-veronika')).length, 1, reason: 'не выполнено второй раз');
    });

    test('ошибки: неизвестный персонаж, пустой текст, чужой диалог, неизвестная команда, группы', () async {
      await pairAndHello();
      expect((await send('MESSAGE', {'fromCharacterId': 'nobody', 'toCharacterId': maxim, 'text': 'x'})).error,
          ConnectError.invalidTarget);
      expect((await send('MESSAGE', {'fromCharacterId': veronika, 'toCharacterId': 'nobody', 'text': 'x'})).error,
          ConnectError.invalidTarget);
      expect((await send('MESSAGE', {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': ''})).error,
          ConnectError.invalidRequest);
      expect((await send('MESSAGE', {'fromCharacterId': veronika, 'toCharacterId': aleksey, 'text': 'x'})).error,
          ConnectError.invalidTarget, reason: 'ни один не владелец телефона');
      expect((await send('LAUNCH_ROCKET')).error, ConnectError.invalidCommand);
      final group = await send('CREATE_CHAT', {'title': 'Съёмочная группа'});
      expect(group.error, ConnectError.invalidRequest, reason: 'нет groupId и участников');
      expect((await send('MEDIA', {'fromCharacterId': veronika, 'toCharacterId': maxim, 'mediaId': 'nope'})).error,
          ConnectError.invalidTarget);
      expect(await connectMessages('chat-veronika'), isEmpty);
    });

    test('TYPING, EDIT_MESSAGE, MESSAGE_STATUS, DELETE_MESSAGE', () async {
      await pairAndHello();
      expect((await send('TYPING', {'fromCharacterId': veronika, 'durationMs': 3000})).success, isTrue);
      expect(s.typing.isTyping('chat-veronika'), isTrue);

      final sent = await send('MESSAGE', {'fromCharacterId': maxim, 'toCharacterId': veronika, 'text': 'Еду', 'state': 'SENT'});
      final id = sent.result['messageId'] as String;
      expect((await s.messages.byId(id))!.state, MessageState.sent);
      expect((await send('MESSAGE_STATUS', {'messageId': id, 'state': 'READ'})).success, isTrue);
      expect((await s.messages.byId(id))!.state, MessageState.read);
      expect((await send('EDIT_MESSAGE', {'messageId': id, 'text': 'Уже еду'})).success, isTrue);
      final edited = (await s.messages.byId(id))!;
      expect(edited.text, 'Уже еду');
      expect(edited.edited, isTrue);
      expect((await send('DELETE_MESSAGE', {'messageId': id})).success, isTrue);
      expect((await s.messages.byId(id))!.deleted, isTrue);
    });

    test('CALL и END_CALL, неверный участник', () async {
      await pairAndHello();
      expect((await send('CALL', {'fromCharacterId': veronika, 'toCharacterId': maxim})).success, isTrue);
      expect(s.callEngine.phase, CallPhase.incoming);
      expect(s.callEngine.session?.characterId, veronika);
      expect((await send('END_CALL', {'characterId': aleksey})).error, ConnectError.invalidTarget);
      expect((await send('END_CALL')).success, isTrue);
      expect(s.callEngine.phase, CallPhase.ended);
      expect((await send('END_CALL')).error, ConnectError.invalidTarget, reason: 'звонка уже нет');
    });

    test('NOTIFICATION и OPEN_SCREEN проходят через Scene Engine', () async {
      await pairAndHello();
      expect((await send('NOTIFICATION', {'fromCharacterId': veronika, 'text': 'Новое сообщение'})).success, isTrue);
      expect((await send('OPEN_SCREEN', {'screen': 'CHAT_LIST'})).success, isTrue);
      expect((await send('OPEN_SCREEN', {'screen': 'SETTINGS'})).error, ConnectError.invalidRequest,
          reason: 'разрешены только перечисленные экраны');
    });

    test('SEQUENCE: порядок, DELAY, ошибка внутри останавливает', () async {
      await pairAndHello();
      final watch = Stopwatch()..start();
      final ok = await send('SEQUENCE', {
        'steps': [
          {'actionType': 'MESSAGE', 'payload': {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Ты где?'}},
          {'actionType': 'DELAY', 'payload': {'ms': 300}},
          {'actionType': 'MESSAGE', 'payload': {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Я уже приехала'}},
        ],
      });
      expect(ok.success, isTrue);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(300));
      expect((await connectMessages('chat-veronika')).map((m) => m.text), ['Ты где?', 'Я уже приехала']);

      final bad = await send('SEQUENCE', {
        'steps': [
          {'actionType': 'MESSAGE', 'payload': {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Раз'}},
          {'actionType': 'MESSAGE', 'payload': {'fromCharacterId': 'nobody', 'toCharacterId': maxim, 'text': 'Два'}},
          {'actionType': 'MESSAGE', 'payload': {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Три'}},
        ],
      });
      expect(bad.success, isFalse);
      expect((bad.result['steps'] as List).length, 2);
      expect((await connectMessages('chat-veronika')).map((m) => m.text), isNot(contains('Три')));
    });

    test('STOP прерывает идущую последовательность', () async {
      await pairAndHello();
      final running = send('SEQUENCE', {
        'steps': [
          {'actionType': 'DELAY', 'payload': {'ms': 5000}},
          {'actionType': 'MESSAGE', 'payload': {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Не должно'}},
        ],
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect((await send('STOP')).success, isTrue);
      final result = await running.timeout(const Duration(seconds: 2));
      expect(result.status, CommandStatus.cancelled);
      expect(await connectMessages('chat-veronika'), isEmpty);
    });

    test('RESET_SCENE убирает только данные Connect', () async {
      await pairAndHello();
      final baseVeronika = (await s.messages.forChat('chat-veronika')).length;
      final baseAleksey = (await s.messages.forChat('chat-aleksey')).length;
      final demoActions = (await s.scenes.actions('scene-demo-12')).length;

      await send('MESSAGE', {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Раз'});
      await send('MESSAGE', {'fromCharacterId': aleksey, 'toCharacterId': maxim, 'text': 'Два'});
      await send('CALL', {'fromCharacterId': veronika, 'toCharacterId': maxim});
      await send('END_CALL');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((await s.calls.forDevice('device-maxim')), isNotEmpty);

      final reset = await send('RESET_SCENE');
      expect(reset.success, isTrue);
      expect((await s.messages.forChat('chat-veronika')).length, baseVeronika);
      expect((await s.messages.forChat('chat-aleksey')).length, baseAleksey);
      expect(await s.calls.forDevice('device-maxim'), isEmpty);
      expect((await s.scenes.actions('scene-demo-12')).length, demoActions, reason: 'другие сцены не тронуты');
      expect((await s.chats.listForDevice('device-maxim')).length, 4);
    });

    test('персонаж назначается телефону динамически', () async {
      await pairAndHello();
      final info = await send('ASSIGN_CHARACTER', {'characterId': veronika});
      expect(info.result['characterId'], veronika);
      expect((await send('SET_CONTACT', {'characterId': maxim, 'displayName': 'Максим'})).success, isTrue);
      final r = await send('MESSAGE', {'fromCharacterId': maxim, 'toCharacterId': veronika, 'text': 'Привет'});
      expect(r.success, isTrue, reason: 'на телефоне Вероники это входящее от Максима');
      expect((await send('ASSIGN_CHARACTER', {'characterId': maxim})).result['characterId'], maxim);
    });
  });
}
