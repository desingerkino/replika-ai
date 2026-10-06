import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../protocol/protocol.dart';

final X25519 _x25519 = X25519();
final AesGcm _aes = AesGcm.with256bits();
final Random _random = Random.secure();

List<int> randomBytes(int length) => List<int>.generate(length, (_) => _random.nextInt(256));

String toB64(List<int> bytes) => base64Encode(bytes);

/// Байты из base64 с проверкой длины; ошибка формата — INVALID_REQUEST.
List<int> fromB64(Object? value, {int? length}) {
  if (value is! String) {
    throw const ConnectException(ConnectError.invalidRequest, 'ожидалась строка base64');
  }
  try {
    final bytes = base64Decode(value);
    if (length != null && bytes.length != length) {
      throw const ConnectException(ConnectError.invalidRequest, 'неверная длина ключа или nonce');
    }
    return bytes;
  } on FormatException {
    throw const ConnectException(ConnectError.invalidRequest, 'неверный base64');
  }
}

/// Пара ключей X25519 (постоянная — устройства, или разовая — сеанса).
class KeyPairX {
  KeyPairX._(this._keyPair, this.publicKey, this.privateKey);

  final SimpleKeyPair _keyPair;
  final List<int> publicKey;

  /// Только для сохранения в Android Keystore. Никогда не логируется.
  final List<int> privateKey;

  static Future<KeyPairX> generate() async => _wrap(await _x25519.newKeyPair());

  static Future<KeyPairX> fromPrivate(List<int> privateKey) async =>
      _wrap(await _x25519.newKeyPairFromSeed(privateKey));

  static Future<KeyPairX> _wrap(SimpleKeyPair keyPair) async {
    final public = await keyPair.extractPublicKey();
    final private = await keyPair.extractPrivateKeyBytes();
    return KeyPairX._(keyPair, public.bytes, private);
  }

  /// Общий секрет Диффи — Хеллмана с чужим открытым ключом.
  Future<List<int>> agree(List<int> remotePublic) async {
    final secret = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(remotePublic, type: KeyPairType.x25519),
    );
    return secret.extractBytes();
  }
}

/// 6-значный код сопряжения. Его независимо вычисляют оба устройства
/// из открытых ключей и случайных чисел обеих сторон. Если посередине
/// чужое устройство, коды на экранах не совпадут.
Future<String> pairingCode({
  required List<int> devicePublic,
  required List<int> controllerPublic,
  required List<int> deviceNonce,
  required List<int> controllerNonce,
}) async {
  final hash = await Sha256().hash([
    ...utf8.encode('replika-pair-v1'),
    ...devicePublic,
    ...controllerPublic,
    ...deviceNonce,
    ...controllerNonce,
  ]);
  final b = hash.bytes;
  final value = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) & 0x7fffffff;
  return (value % 1000000).toString().padLeft(6, '0');
}

/// Ключи сеанса: отдельные для каждого направления.
class SessionKeys {
  const SessionKeys(this.controllerToDevice, this.deviceToController);

  final List<int> controllerToDevice;
  final List<int> deviceToController;
}

/// Сеансовые ключи из двух обменов: разовых ключей (свежесть сеанса)
/// и постоянных ключей (подтверждение, что это именно доверенный Controller
/// и именно этот телефон).
Future<SessionKeys> deriveSessionKeys({
  required List<int> ephemeralShared,
  required List<int> staticShared,
  required List<int> controllerNonce,
  required List<int> deviceNonce,
  required String sessionId,
}) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
  final key = await hkdf.deriveKey(
    secretKey: SecretKey([...ephemeralShared, ...staticShared]),
    nonce: [...controllerNonce, ...deviceNonce],
    info: utf8.encode('replika-connect-v1|$sessionId'),
  );
  final bytes = await key.extractBytes();
  return SessionKeys(bytes.sublist(0, 32), bytes.sublist(32, 64));
}

/// Шифрование кадров сеанса (AES-256-GCM). Номер кадра входит в проверяемые
/// данные и должен расти: повтор перехваченного кадра отклоняется.
class FrameCipher {
  FrameCipher({
    required this.sessionId,
    required List<int> sendKey,
    required List<int> receiveKey,
    required this.sendLabel,
    required this.receiveLabel,
  })  : _send = SecretKey(sendKey),
        _receive = SecretKey(receiveKey);

  final String sessionId;
  final String sendLabel;
  final String receiveLabel;
  final SecretKey _send;
  final SecretKey _receive;
  int _sendSeq = 0;
  int _lastReceived = 0;

  Future<Map<String, Object?>> seal(Map<String, Object?> message) async {
    final seq = ++_sendSeq;
    final nonce = randomBytes(12);
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(message)),
      secretKey: _send,
      nonce: nonce,
      aad: utf8.encode('$sessionId|$sendLabel|$seq'),
    );
    return {
      'type': 'enc',
      'seq': seq,
      'nonce': toB64(nonce),
      'data': toB64([...box.cipherText, ...box.mac.bytes]),
    };
  }

  Future<Map<String, Object?>> open(Map<String, Object?> frame) async {
    final seq = frame['seq'];
    if (seq is! int) throw const ConnectException(ConnectError.invalidRequest, 'нет номера кадра');
    if (seq <= _lastReceived) {
      throw const ConnectException(ConnectError.unauthorized, 'повтор или устаревший кадр');
    }
    final nonce = fromB64(frame['nonce'], length: 12);
    final data = fromB64(frame['data']);
    if (data.length < 16) throw const ConnectException(ConnectError.invalidRequest, 'кадр слишком короткий');
    final List<int> clear;
    try {
      clear = await _aes.decrypt(
        SecretBox(data.sublist(0, data.length - 16), nonce: nonce, mac: Mac(data.sublist(data.length - 16))),
        secretKey: _receive,
        aad: utf8.encode('$sessionId|$receiveLabel|$seq'),
      );
    } on SecretBoxAuthenticationError {
      throw const ConnectException(ConnectError.unauthorized, 'кадр не прошёл проверку подлинности');
    }
    _lastReceived = seq;
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map) throw const ConnectException(ConnectError.invalidRequest, 'кадр должен быть объектом');
    return Map<String, Object?>.from(decoded);
  }
}
