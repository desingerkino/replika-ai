// SCENE_NEXT / SCENE_PREVIOUS / SCENE_STOP: Connect → PropControllerInput →
// слой команд оператора. Настоящая база, сервер и клиент, как в connect_prep_test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/media_store.dart';
import 'package:replika/app/navigator.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/client/connect_client.dart';
import 'package:replika/data/models/call_record.dart';
import 'package:replika/connect/protocol/protocol.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/connect/service/connect_service.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  late Directory tempDir;
  late AppServices s;
  late ConnectService connect;
  late ConnectClient client;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('replika_scene_cmd_');
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

  test('DEVICE_INFO объявляет новые команды, версия протокола прежняя', () async {
    final info = await client.command('DEVICE_INFO');
    expect(
      info.result['supportedActions'] as List,
      containsAll(['SCENE_NEXT', 'SCENE_PREVIOUS', 'SCENE_STOP', 'RESET_SCENE', 'STOP']),
    );
    expect(info.result['protocolVersion'], protocolVersion);
  });

  test('без адресата пульт получает handled: false, а не ошибку', () async {
    for (final wire in ['SCENE_NEXT', 'SCENE_PREVIOUS', 'SCENE_STOP']) {
      final r = await client.command(wire);
      expect(r.success, isTrue, reason: wire);
      expect(r.result['handled'], isFalse, reason: wire);
      expect(r.result['target'], 'none', reason: wire);
    }
  });

  test('при звонке SCENE_NEXT — «ответил», SCENE_PREVIOUS — «положил трубку»', () async {
    s.callEngine.start(CallSession(
      deviceId: s.currentDeviceId.value,
      characterId: 'char-veronika',
      direction: CallDirection.outgoing,
      kind: CallKind.audio,
      displayName: 'Тест',
    ));
    final next = await client.command('SCENE_NEXT');
    expect(next.result['handled'], isTrue);
    expect(next.result['target'], 'call');
    expect(s.callEngine.phase, CallPhase.connecting);
    final back = await client.command('SCENE_PREVIOUS');
    expect(back.result['target'], 'call');
    expect(s.callEngine.phase, CallPhase.ended);
  });

  test('старый STOP по-прежнему не останавливает движок сцен', () async {
    final r = await client.command('STOP');
    expect(r.success, isTrue);
    expect(r.result.containsKey('cancelledCommands'), isTrue);
    expect(r.result.containsKey('handled'), isFalse);
  });

  test('SCENE_* нельзя вкладывать в SEQUENCE', () async {
    final r = await client.command('SEQUENCE', {
      'steps': [
        {'actionType': 'SCENE_NEXT', 'payload': <String, Object?>{}},
      ],
    });
    expect(r.success, isFalse);
    expect(r.error, ConnectError.invalidRequest);
  });
}
