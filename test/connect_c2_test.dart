// Connect C2: поиск в сети, переподключение без потери и дублирования
// команд, синхронный запуск (executeAt), события звонка.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/client/connect_client.dart';
import 'package:replika/connect/discovery/discovery.dart';
import 'package:replika/connect/protocol/protocol.dart';
import 'package:replika/connect/queue/command_queue.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/connect/service/connect_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

class _Fast implements CommandExecutor {
  final List<String> ran = [];
  @override
  Future<CommandResult> execute(CommandRequest request, CancelToken cancel) async {
    ran.add(request.commandId);
    return CommandResult.ok(request.commandId);
  }

  @override
  Future<void> stopAll() async {}
}

late Directory tempDir;
late AppServices s;
late ConnectService connect;
late ConnectClient client;

Future<void> pairAndHello() async {
  connect.openPairing();
  await client.connect('127.0.0.1', port: connect.boundPort!);
  expect(await client.pair(), isTrue);
  await client.hello();
}

Future<int> connectTexts(String text) async =>
    (await s.messages.forChat('chat-veronika')).where((m) => m.text == text && m.sceneId != null).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  group('Без базы', () {
    test('поиск: телефон отвечает на запрос, чужие пакеты игнорирует', () async {
      final discovery = ConnectDiscovery(
        port: 0,
        announce: () => {'deviceId': 'MESSENGER-ABC123', 'deviceName': 'Телефон Ивана', 'port': 47620},
      );
      await discovery.start();
      final junk = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      junk.send(utf8.encode('мусор'), InternetAddress.loopbackIPv4, discovery.boundPort!);
      junk.close();
      final found = await discoverDevices(hosts: const ['127.0.0.1'], port: discovery.boundPort!);
      expect(found.single['deviceId'], 'MESSENGER-ABC123');
      expect(found.single['port'], 47620);
      expect(found.single.keys, isNot(contains('publicKey')), reason: 'в маяке нет секретов');
      await discovery.stop();
    });

    test('executeAt: команда выполняется в назначенный момент', () async {
      final fx = _Fast();
      final q = CommandQueue(fx);
      final at = DateTime.now().millisecondsSinceEpoch + 300;
      final r = await q.submit(CommandRequest(commandId: 'c1', actionType: 'MESSAGE', payload: const {}, executeAt: at));
      expect(r.result['executedAt'] as int, greaterThanOrEqualTo(at));
      expect(r.result['lateMs'] as int, lessThan(250));
    });

    test('executeAt: ожидание прерывается STOP', () async {
      final fx = _Fast();
      final q = CommandQueue(fx);
      final waiting = q.submit(CommandRequest(
        commandId: 'later',
        actionType: 'MESSAGE',
        payload: const {},
        executeAt: DateTime.now().millisecondsSinceEpoch + 5000,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await q.submit(const CommandRequest(commandId: 'stop', actionType: 'STOP', payload: {}));
      expect((await waiting).status, CommandStatus.cancelled);
      expect(fx.ran, isEmpty);
    });

    test('executeAt: слишком далеко или не число — INVALID_REQUEST', () {
      Map<String, Object?> cmd(Object? at) =>
          {'protocolVersion': 1, 'commandId': 'x', 'actionType': 'PING', 'executeAt': at};
      expect(() => CommandRequest.fromJson(cmd(DateTime.now().millisecondsSinceEpoch + 11 * 60 * 1000)),
          throwsA(isA<ConnectException>()));
      expect(() => CommandRequest.fromJson(cmd('завтра')), throwsA(isA<ConnectException>()));
    });
  });

  group('С телефоном', () {
    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('replika_c2_');
      s = await AppServices.open(databasePath: p.join(tempDir.path, 'replika.db'));
      connect = ConnectService(services: s, store: MemorySecretStore(), port: 0, discoveryPortNumber: 0);
      connect.addListener(() {
        if (connect.pendingPairing != null) connect.answerPairing(true);
      });
      await connect.start();
      client = ConnectClient(store: MemorySecretStore(), controllerName: 'Controller C2');
    });

    tearDown(() async {
      await client.close();
      await connect.stop();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await s.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('Controller находит телефон поиском в сети', () async {
      expect(connect.discoverable, isTrue);
      final found = await discoverDevices(hosts: const ['127.0.0.1'], port: connect.discoveryBoundPort!);
      expect(found.single['deviceId'], connect.deviceId);
      expect(found.single['port'], connect.boundPort);
    });

    test('обрыв связи: «потеряна» → переподключение → «подключён»', () async {
      await pairAndHello();
      expect(connect.state, ConnectState.connected);
      await client.close(); // исчез без bye — как при потере Wi-Fi
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(connect.state, ConnectState.reconnecting);
      expect(connect.lostSessions.values.single.name, 'Controller C2');

      await client.reconnect('127.0.0.1', port: connect.boundPort!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(connect.state, ConnectState.connected);
      expect(connect.lostSessions, isEmpty);
      expect(connect.logEntries.any((e) => e.kind == 'Переподключение'), isTrue);
    });

    test('ответ потерян при обрыве — повтор после переподключения не дублирует', () async {
      await pairAndHello();
      const request = CommandRequest(
        commandId: 'scene-7-msg-1',
        actionType: 'MESSAGE',
        payload: {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Ты где?', 'typingMs': 800},
      );
      final first = client.send(request);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await client.close(); // связь пропала до ответа
      await expectLater(first, throwsA(isA<ConnectException>()));

      await client.reconnect('127.0.0.1', port: connect.boundPort!);
      final again = await client.send(request);
      expect(again.status, CommandStatus.alreadyProcessed);
      expect(again.success, isTrue);
      expect(await connectTexts('Ты где?'), 1, reason: 'сообщение одно — не потеряно и не задвоено');
    });

    test('executeAt через сеть: сообщение появляется в назначенный момент', () async {
      await pairAndHello();
      final at = DateTime.now().millisecondsSinceEpoch + 400;
      final r = await client.send(CommandRequest(
        commandId: 'sync-1',
        actionType: 'MESSAGE',
        payload: const {'fromCharacterId': veronika, 'toCharacterId': maxim, 'text': 'Синхронно'},
        executeAt: at,
      ));
      expect(r.success, isTrue);
      expect(r.result['executedAt'] as int, greaterThanOrEqualTo(at));
      expect(await connectTexts('Синхронно'), 1);
    });

    test('события звонка приходят Controller', () async {
      await pairAndHello();
      final events = <Map<String, Object?>>[];
      client.onEvent = events.add;
      await client.command('CALL', {'fromCharacterId': veronika, 'toCharacterId': maxim});
      s.callEngine.accept(); // актёр принял звонок на экране
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await client.command('END_CALL');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final phases = events.where((e) => e['event'] == 'CALL_STATE').map((e) => e['phase']).toList();
      expect(phases, containsAllInOrder(['INCOMING', 'CONNECTING', 'ENDED']));
      expect(events.firstWhere((e) => e['phase'] == 'INCOMING')['characterId'], veronika);
      expect(events.firstWhere((e) => e['phase'] == 'ENDED')['outcome'], 'ANSWERED');
    });
  });
}
