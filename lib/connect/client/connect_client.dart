import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/util/ids.dart';
import '../protocol/protocol.dart';
import '../security/crypto.dart';
import '../security/secret_store.dart';

/// Клиентская сторона протокола — то, что будет делать Prop Controller.
///
/// Используется экраном «Проверка Connect» и автотестами: проверка идёт
/// через настоящий сокет, сопряжение, ключи и шифрование — без обходов.
class ConnectClient {
  ConnectClient({
    required this.store,
    this.controllerName = 'Проверка Connect',
    this.storeKey = 'connect.testController.v1',
  });

  final SecretStore store;
  final String controllerName;
  final String storeKey;

  WebSocket? _socket;
  FrameCipher? _cipher;
  String? _controllerId;
  KeyPairX? _key;
  String? deviceId;
  String? sessionId;

  final Map<String, Completer<CommandResult>> _pending = {};
  Completer<Map<String, Object?>>? _plainWaiter;

  /// Открытые кадры, пришедшие раньше, чем их начали ждать.
  final List<Map<String, Object?>> _plainBuffer = [];
  Future<void> _inbox = Future.value();
  Future<void> _outbox = Future.value();

  /// Промежуточные статусы (RECEIVED, QUEUED, EXECUTING).
  void Function(String commandId, String status)? onStatus;

  /// События телефона (например, CALL_STATE — актёр ответил на звонок).
  void Function(Map<String, Object?> event)? onEvent;

  /// Соединение закрыто (сервером, сетью или вызовом [close]).
  void Function(String reason)? onClosed;

  bool get connected => _socket != null;
  bool get authenticated => _cipher != null;
  String? get controllerId => _controllerId;

  Future<void> _loadIdentity() async {
    if (_key != null) return;
    final raw = await store.read(storeKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map;
        _controllerId = json['id'] as String;
        _key = await KeyPairX.fromPrivate(fromB64(json['privateKey'], length: 32));
        return;
      } catch (_) {}
    }
    _controllerId = 'controller-${newId().substring(0, 8)}';
    _key = await KeyPairX.generate();
    await store.write(storeKey, jsonEncode({'id': _controllerId, 'privateKey': toB64(_key!.privateKey)}));
  }

  Future<void> connect(String host, {int port = defaultConnectPort}) async {
    await _loadIdentity();
    await close();
    _plainBuffer.clear();
    final socket = await WebSocket.connect('ws://$host:$port$connectPath').timeout(const Duration(seconds: 5));
    _socket = socket;
    socket.listen(
      (data) => _inbox = _inbox.then((_) => _onData(data)),
      onDone: () => _droppedAfterInbox(socket.closeReason ?? 'соединение закрыто'),
      onError: (_) => _droppedAfterInbox('ошибка соединения'),
      cancelOnError: true,
    );
  }

  /// Телефон шлёт кадр с ошибкой («UNAUTHORIZED», «Сопряжение отклонено») и сразу
  /// закрывает соединение. Кадры разбираются по очереди, поэтому о разрыве
  /// сообщаем после них: иначе ожидающий ответа получит «CONNECTION_ERROR»
  /// раньше настоящей причины.
  void _droppedAfterInbox(String reason) {
    _inbox = _inbox.then<void>((_) {}, onError: (Object _) {}).then<void>((_) => _dropped(reason));
  }

  void _dropped(String reason) {
    _socket = null;
    _cipher = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(ConnectException(ConnectError.connectionError, reason));
    }
    _pending.clear();
    final waiter = _plainWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(ConnectException(ConnectError.connectionError, reason));
    }
    onClosed?.call(reason);
  }

  Future<void> _onData(Object? data) async {
    if (data is! String) return;
    final json = Map<String, Object?>.from(jsonDecode(data) as Map);
    final cipher = _cipher;
    if (json['type'] == 'enc' && cipher != null) {
      final inner = await cipher.open(json);
      switch (inner['type']) {
        case 'result':
          final result = CommandResult.fromJson(inner);
          _pending.remove(result.commandId)?.complete(result);
        case 'status':
          onStatus?.call(inner['commandId'] as String? ?? '', inner['status'] as String? ?? '');
        case 'event':
          onEvent?.call(inner);
      }
      return;
    }
    final waiter = _plainWaiter;
    _plainWaiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(json);
    } else {
      _plainBuffer.add(json);
    }
  }

  Future<Map<String, Object?>> _awaitPlain(Duration timeout) {
    if (_plainBuffer.isNotEmpty) return Future.value(_plainBuffer.removeAt(0));
    final c = Completer<Map<String, Object?>>();
    _plainWaiter = c;
    return c.future.timeout(timeout);
  }

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null) throw const ConnectException(ConnectError.connectionError, 'нет соединения');
    socket.add(jsonEncode(message));
  }

  static void _throwIfError(Map<String, Object?> json) {
    if (json['type'] == 'error') {
      throw ConnectException(json['error'] as String? ?? ConnectError.internalError, json['message'] as String? ?? '');
    }
  }

  /// Аутентификация доверенного устройства и сеансовые ключи.
  Future<void> hello() async {
    await _loadIdentity();
    final ephemeral = await KeyPairX.generate();
    final nonce = randomBytes(16);
    final reply = _awaitPlain(const Duration(seconds: 10));
    _send({
      'type': 'hello',
      'protocolVersion': protocolVersion,
      'controllerId': _controllerId,
      'ephemeralKey': toB64(ephemeral.publicKey),
      'nonce': toB64(nonce),
    });
    final ok = await reply;
    _throwIfError(ok);
    final devicePublicStatic = await _devicePublic(ok);
    final sid = ok['sessionId'] as String;
    final keys = await deriveSessionKeys(
      ephemeralShared: await ephemeral.agree(fromB64(ok['ephemeralKey'], length: 32)),
      staticShared: await _key!.agree(devicePublicStatic),
      controllerNonce: nonce,
      deviceNonce: fromB64(ok['nonce'], length: 16),
      sessionId: sid,
    );
    _cipher = FrameCipher(
      sessionId: sid,
      sendKey: keys.controllerToDevice,
      receiveKey: keys.deviceToController,
      sendLabel: 'c2d',
      receiveLabel: 'd2c',
    );
    sessionId = sid;
    deviceId = ok['deviceId'] as String?;
  }

  /// Открытый ключ телефона запоминается при сопряжении.
  Future<List<int>> _devicePublic(Map<String, Object?> hello) async {
    final raw = await store.read('$storeKey.devices');
    final map = raw == null ? <String, Object?>{} : Map<String, Object?>.from(jsonDecode(raw) as Map);
    final id = hello['deviceId'] as String?;
    final key = map[id];
    if (key == null) {
      throw const ConnectException(ConnectError.unauthorized, 'Телефон не сопряжён с этим устройством');
    }
    return fromB64(key, length: 32);
  }

  /// Запомнить открытый ключ телефона после успешного сопряжения
  /// (Controller хранит его, чтобы проверять телефон при каждом hello).
  Future<void> rememberDevice(String deviceId, List<int> publicKey) async {
    final raw = await store.read('$storeKey.devices');
    final map = raw == null ? <String, Object?>{} : Map<String, Object?>.from(jsonDecode(raw) as Map);
    map[deviceId] = toB64(publicKey);
    await store.write('$storeKey.devices', jsonEncode(map));
  }

  List<int>? _pairedDevicePublic;

  /// Сопряжение: [onCode] показывает код, который должен совпасть с кодом
  /// на экране телефона. true — на телефоне нажали «Разрешить»; открытый
  /// ключ телефона запоминается для проверки при каждом hello.
  Future<bool> pair({void Function(String code)? onCode, Duration timeout = const Duration(minutes: 2)}) async {
    await _loadIdentity();
    final nonce = randomBytes(16);
    final challenge = _awaitPlain(const Duration(seconds: 10));
    _send({
      'type': 'pair_request',
      'protocolVersion': protocolVersion,
      'controllerId': _controllerId,
      'controllerName': controllerName,
      'publicKey': toB64(_key!.publicKey),
      'nonce': toB64(nonce),
    });
    final c = await challenge;
    _throwIfError(c);
    _pairedDevicePublic = fromB64(c['publicKey'], length: 32);
    final code = await pairingCode(
      devicePublic: _pairedDevicePublic!,
      controllerPublic: _key!.publicKey,
      deviceNonce: fromB64(c['nonce'], length: 16),
      controllerNonce: nonce,
    );
    deviceId = c['deviceId'] as String?;
    onCode?.call(code);
    final result = await _awaitPlain(timeout);
    _throwIfError(result);
    final accepted = result['accepted'] == true;
    if (accepted && deviceId != null) await rememberDevice(deviceId!, _pairedDevicePublic!);
    return accepted;
  }

  /// Переподключение после обрыва: повторять connect + hello с растущей
  /// паузой. Так должен вести себя Prop Controller после потери Wi-Fi.
  /// После успеха неподтверждённые команды переотправляются с тем же
  /// commandId — телефон не выполнит их второй раз.
  Future<void> reconnect(String host, {int port = defaultConnectPort, int attempts = 10}) async {
    var pause = const Duration(milliseconds: 250);
    for (var i = 1; i <= attempts; i++) {
      try {
        await connect(host, port: port);
        await hello();
        return;
      } catch (_) {
        if (i == attempts) rethrow;
        await Future<void>.delayed(pause);
        pause = pause * 2 > const Duration(seconds: 5) ? const Duration(seconds: 5) : pause * 2;
      }
    }
  }

  /// Отправить команду и дождаться результата.
  Future<CommandResult> send(CommandRequest request, {Duration timeout = const Duration(minutes: 2)}) async {
    final cipher = _cipher;
    if (cipher == null) throw const ConnectException(ConnectError.unauthorized, 'нет сеанса — сначала hello');
    final completer = Completer<CommandResult>();
    _pending[request.commandId] = completer;
    _outbox = _outbox.then((_) async {
      final frame = await cipher.seal(request.toJson());
      _socket?.add(jsonEncode(frame));
    });
    return completer.future.timeout(timeout);
  }

  /// Команда с новым commandId.
  Future<CommandResult> command(String actionType, [Map<String, Object?> payload = const {}]) =>
      send(CommandRequest(commandId: 'cmd-${newId().substring(0, 12)}', actionType: actionType, payload: payload));

  /// Отправить сырой кадр в сеансе (для проверки ошибок протокола).
  Future<void> sendRawSecure(Map<String, Object?> message) async {
    final cipher = _cipher;
    if (cipher == null) return;
    final frame = await cipher.seal(message);
    _socket?.add(jsonEncode(frame));
  }

  /// Отправить сырой текст (для проверки защиты от мусора).
  void sendRawText(String text) => _socket?.add(text);

  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    _cipher = null;
    await socket?.close();
  }
}
