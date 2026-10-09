import 'package:flutter_test/flutter_test.dart';
import 'package:replika/connect/protocol/protocol.dart';
import 'package:replika/connect/security/crypto.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/connect/security/trust.dart';

Future<(FrameCipher, FrameCipher)> pairOfCiphers() async {
  final device = await KeyPairX.generate();
  final controller = await KeyPairX.generate();
  final eDevice = await KeyPairX.generate();
  final eController = await KeyPairX.generate();
  final nc = randomBytes(16);
  final nd = randomBytes(16);
  final onDevice = await deriveSessionKeys(
    ephemeralShared: await eDevice.agree(eController.publicKey),
    staticShared: await device.agree(controller.publicKey),
    controllerNonce: nc,
    deviceNonce: nd,
    sessionId: 's1',
  );
  final onController = await deriveSessionKeys(
    ephemeralShared: await eController.agree(eDevice.publicKey),
    staticShared: await controller.agree(device.publicKey),
    controllerNonce: nc,
    deviceNonce: nd,
    sessionId: 's1',
  );
  return (
    FrameCipher(sessionId: 's1', sendKey: onDevice.deviceToController, receiveKey: onDevice.controllerToDevice, sendLabel: 'd2c', receiveLabel: 'c2d'),
    FrameCipher(sessionId: 's1', sendKey: onController.controllerToDevice, receiveKey: onController.deviceToController, sendLabel: 'c2d', receiveLabel: 'd2c'),
  );
}

void main() {
  test('код сопряжения совпадает на обоих устройствах и зависит от ключей', () async {
    final d = await KeyPairX.generate();
    final c = await KeyPairX.generate();
    final nd = randomBytes(16);
    final nc = randomBytes(16);
    final a = await pairingCode(devicePublic: d.publicKey, controllerPublic: c.publicKey, deviceNonce: nd, controllerNonce: nc);
    final b = await pairingCode(devicePublic: d.publicKey, controllerPublic: c.publicKey, deviceNonce: nd, controllerNonce: nc);
    expect(a, b);
    expect(a, matches(RegExp(r'^\d{6}$')));
    final intruder = await KeyPairX.generate();
    final m = await pairingCode(devicePublic: d.publicKey, controllerPublic: intruder.publicKey, deviceNonce: nd, controllerNonce: nc);
    expect(m, isNot(a), reason: 'подмена ключа посередине меняет код');
  });

  test('зашифрованный кадр читает только собеседник', () async {
    final (device, controller) = await pairOfCiphers();
    // Длинная метка: короткая («c1») случайно встречается в base64 шифротекста.
    const secret = 'commandId-SECRET-PLAINTEXT-42';
    final frame = await controller.seal({'type': 'command', 'commandId': secret});
    expect(frame.toString(), isNot(contains(secret)), reason: 'в кадре нет открытого текста');
    expect(frame.toString(), isNot(contains('command')), reason: 'тип команды тоже зашифрован');
    expect((await device.open(frame))['commandId'], secret);
  });

  test('повтор перехваченного кадра отклоняется', () async {
    final (device, controller) = await pairOfCiphers();
    final frame = await controller.seal({'type': 'command'});
    await device.open(frame);
    expect(() => device.open(frame),
        throwsA(isA<ConnectException>().having((e) => e.code, 'code', ConnectError.unauthorized)));
  });

  test('подделанный кадр и чужой ключ отклоняются', () async {
    final (device, controller) = await pairOfCiphers();
    final frame = await controller.seal({'type': 'command'});
    final tampered = Map<String, Object?>.from(frame);
    final data = fromB64(frame['data']);
    data[0] ^= 0xff;
    tampered['data'] = toB64(data);
    expect(() => device.open(tampered), throwsA(isA<ConnectException>()));

    final (strangerDevice, _) = await pairOfCiphers();
    final foreign = await controller.seal({'type': 'x'});
    expect(() => strangerDevice.open(foreign), throwsA(isA<ConnectException>()));
  });

  test('Device ID стабилен, ключ хранится только в защищённом хранилище', () async {
    final store = MemorySecretStore();
    final first = await TrustStore(store).identity();
    final second = await TrustStore(store).identity();
    expect(first.deviceId, second.deviceId);
    expect(first.deviceId, matches(RegExp(r'^MESSENGER-[0-9A-F]{6}$')));
    expect(first.key.publicKey, second.key.publicKey);
  });

  test('доверие выдаётся и отзывается', () async {
    final store = MemorySecretStore();
    final trust = TrustStore(store);
    final key = await KeyPairX.generate();
    await trust.add(TrustedController(id: 'pc-1', name: 'Prop Controller', publicKey: key.publicKey, pairedAt: DateTime(2026)));
    expect(await TrustStore(store).find('pc-1'), isNotNull, reason: 'переживает перезапуск');
    await trust.revoke('pc-1');
    expect(await TrustStore(store).find('pc-1'), isNull);
  });
}
