import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/util/ids.dart';
import '../actions/connect_actions.dart';
import '../protocol/protocol.dart';
import '../queue/command_queue.dart';
import '../security/crypto.dart';
import '../security/trust.dart';

/// Что сервер сообщает приложению (реализует ConnectService).
abstract class ConnectHooks {
  /// Открыто ли окно сопряжения на телефоне.
  bool get pairingOpen;

  /// Показать оператору код и дождаться решения «Разрешить»/«Отклонить».
  Future<bool> askPairing(String controllerName, String code);

  /// Журнал без секретов и без текста сообщений.
  void log(String kind, String text);

  void sessionOpened(String controllerId, String controllerName, String remote);

  /// [expected] — штатное отключение (bye, отзыв, выключение Connect).
  /// false — связь оборвалась (Wi-Fi, сон телефона): Controller, скорее
  /// всего, переподключится.
  void sessionClosed(String controllerId, {required bool expected});
}

/// Локальный WebSocket-сервер Connect (только dart:io, без плагинов).
///
/// Порядок на соединении:
/// 1. `pair_request` → `pair_challenge` → код на обоих экранах →
///    «Разрешить» на телефоне → `pair_result` (только при открытом окне
///    сопряжения);
/// 2. `hello` → `hello_ok` — аутентификация доверенного устройства
///    и сеансовые ключи;
/// 3. дальше только зашифрованные кадры `enc` с командами и ответами.
class ConnectServer {
  ConnectServer({
    required this.trust,
    required this.queue,
    required this.hooks,
    this.port = defaultConnectPort,
    this.sessionTtl = const Duration(hours: 12),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TrustStore trust;
  final CommandQueue queue;
  final ConnectHooks hooks;
  final int port;
  final Duration sessionTtl;
  final DateTime Function() _clock;

  HttpServer? _http;
  final Set<_Connection> _connections = {};

  bool get running => _http != null;
  int? get boundPort => _http?.port;
  int get sessions => _connections.where((c) => c.controller != null).length;

  Future<int> start() async {
    if (_http != null) return _http!.port;
    final http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _http = http;
    http.listen(_onRequest, onError: (Object e) => hooks.log('Ошибка', 'Сервер: ${e.runtimeType}'));
    hooks.log('Сервер', 'Слушает порт ${http.port}');
    return http.port;
  }

  Future<void> stop() async {
    for (final c in _connections.toList()) {
      await c.close(WebSocketStatus.goingAway, 'Connect выключен');
    }
    _connections.clear();
    await _http?.close(force: true);
    _http = null;
    hooks.log('Сервер', 'Остановлен');
  }

  /// Закрыть сеансы устройства (отключение или отзыв доверия).
  Future<void> closeController(String controllerId, {String reason = 'Отключено на телефоне'}) async {
    for (final c in _connections.where((c) => c.controller?.id == controllerId).toList()) {
      await c.close(WebSocketStatus.policyViolation, reason);
    }
  }

  /// Событие всем подключённым Controller (например, актёр ответил на звонок).
  void broadcast(Map<String, Object?> event) {
    for (final c in _connections) {
      if (c.controller != null) c._sendSecure(event);
    }
  }

  Future<void> closeAll() async {
    for (final c in _connections.toList()) {
      await c.close(WebSocketStatus.normalClosure, 'Отключено на телефоне');
    }
  }

  Future<void> _onRequest(HttpRequest request) async {
    if (request.uri.path != connectPath || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = const Duration(seconds: 10);
      final remote = request.connectionInfo?.remoteAddress.address ?? '?';
      final connection = _Connection(this, socket, remote);
      _connections.add(connection);
      connection.listen();
    } catch (_) {
      hooks.log('Ошибка', 'Не удалось принять соединение');
    }
  }
}

class _Connection {
  _Connection(this.server, this.socket, this.remote);

  final ConnectServer server;
  final WebSocket socket;
  final String remote;

  TrustedController? controller;
  FrameCipher? _cipher;
  DateTime? _expiresAt;
  bool _closed = false;
  bool _expected = false;
  Future<void> _inbox = Future.value();
  Future<void> _outbox = Future.value();

  ConnectHooks get hooks => server.hooks;

  void listen() {
    socket.listen(
      (data) => _inbox = _inbox.then((_) => _handle(data)),
      onDone: _onClosed,
      onError: (_) => _onClosed(),
      cancelOnError: true,
    );
  }

  void _onClosed() {
    if (_closed) return;
    _closed = true;
    server._connections.remove(this);
    final c = controller;
    if (c != null) {
      hooks.sessionClosed(c.id, expected: _expected);
      hooks.log(_expected ? 'Отключение' : 'Связь потеряна', c.name);
    }
  }

  Future<void> close(int code, String reason) async {
    if (_closed) return;
    _expected = true;
    try {
      await socket.close(code, reason);
    } catch (_) {}
    _onClosed();
  }

  void _sendPlain(Map<String, Object?> message) {
    if (_closed) return;
    _outbox = _outbox.then((_) {
      if (!_closed) socket.add(jsonEncode(message));
    });
  }

  /// Кадры шифруются и уходят строго по порядку номеров.
  void _sendSecure(Map<String, Object?> message) {
    final cipher = _cipher;
    if (_closed || cipher == null) return;
    _outbox = _outbox.then((_) async {
      final frame = await cipher.seal(message);
      if (!_closed) socket.add(jsonEncode(frame));
    });
  }

  Future<void> _fail(String error, String message) async {
    _sendPlain({'type': 'error', 'protocolVersion': protocolVersion, 'error': error, 'message': message});
    await _outbox;
    await close(WebSocketStatus.policyViolation, error);
  }

  Future<void> _handle(Object? data) async {
    if (_closed) return;
    try {
      if (data is! String || data.length > ConnectLimits.frameBytes) {
        return await _fail(ConnectError.invalidRequest, 'Кадр должен быть текстом до 256 КБ');
      }
      final decoded = jsonDecode(data);
      if (decoded is! Map) return await _fail(ConnectError.invalidRequest, 'Кадр должен быть объектом');
      final json = Map<String, Object?>.from(decoded);
      final cipher = _cipher;
      if (cipher == null) {
        switch (json['type']) {
          case 'pair_request':
            return await _pair(json);
          case 'hello':
            return await _hello(json);
          default:
            return await _fail(ConnectError.unauthorized, 'Сначала сопряжение или hello');
        }
      }
      if (json['type'] != 'enc') return await _fail(ConnectError.invalidRequest, 'В сеансе допускаются только enc-кадры');
      if (server._clock().isAfter(_expiresAt!)) {
        hooks.log('Отказ', 'Сеанс истёк: «${controller?.name}»');
        return await _fail(ConnectError.sessionExpired, 'Сеанс истёк — подключитесь заново (hello)');
      }
      final inner = await cipher.open(json);
      await _inner(inner);
    } on ConnectException catch (e) {
      hooks.log('Отказ', '${e.code} ($remote)');
      await _fail(e.code, e.message);
    } on FormatException {
      await _fail(ConnectError.invalidRequest, 'Кадр не является JSON');
    } catch (_) {
      await _fail(ConnectError.internalError, 'Внутренняя ошибка');
    }
  }

  // ---------- Сопряжение ----------

  Future<void> _pair(Map<String, Object?> json) async {
    if (!hooks.pairingOpen) {
      hooks.log('Отказ', 'Запрос сопряжения при закрытом окне ($remote)');
      return _fail(ConnectError.unauthorized, 'Сопряжение не включено на телефоне');
    }
    final controllerId = json['controllerId'];
    final name = json['controllerName'];
    if (controllerId is! String || controllerId.isEmpty || controllerId.length > 64) {
      return _fail(ConnectError.invalidRequest, 'Нужен controllerId');
    }
    final controllerName = name is String && name.trim().isNotEmpty
        ? (name.length > 60 ? name.substring(0, 60) : name.trim())
        : 'Prop Controller';
    final controllerPublic = fromB64(json['publicKey'], length: 32);
    final controllerNonce = fromB64(json['nonce'], length: 16);

    final identity = await server.trust.identity();
    final deviceNonce = randomBytes(16);
    final code = await pairingCode(
      devicePublic: identity.key.publicKey,
      controllerPublic: controllerPublic,
      deviceNonce: deviceNonce,
      controllerNonce: controllerNonce,
    );
    _sendPlain({
      'type': 'pair_challenge',
      'protocolVersion': protocolVersion,
      'deviceId': identity.deviceId,
      'publicKey': toB64(identity.key.publicKey),
      'nonce': toB64(deviceNonce),
    });
    hooks.log('Сопряжение', 'Запрос от «$controllerName» ($remote)');
    final allowed = await hooks.askPairing(controllerName, code);
    if (_closed) return;
    if (!allowed) {
      hooks.log('Сопряжение', 'Отклонено: «$controllerName»');
      _sendPlain({'type': 'pair_result', 'protocolVersion': protocolVersion, 'accepted': false});
      await _outbox;
      return close(WebSocketStatus.policyViolation, 'Сопряжение отклонено');
    }
    await server.trust.add(TrustedController(
      id: controllerId,
      name: controllerName,
      publicKey: controllerPublic,
      pairedAt: server._clock(),
    ));
    hooks.log('Сопряжение', 'Устройство «$controllerName» стало доверенным');
    _sendPlain({'type': 'pair_result', 'protocolVersion': protocolVersion, 'accepted': true, 'deviceId': identity.deviceId});
  }

  // ---------- Аутентификация сеанса ----------

  Future<void> _hello(Map<String, Object?> json) async {
    final controllerId = json['controllerId'];
    if (controllerId is! String) return _fail(ConnectError.invalidRequest, 'Нужен controllerId');
    final version = json['protocolVersion'];
    if (version is! int || version < 1 || version > protocolVersion) {
      return _fail(ConnectError.invalidRequest, 'Телефон поддерживает протокол версии $protocolVersion');
    }
    final trusted = await server.trust.find(controllerId);
    if (trusted == null) {
      hooks.log('Отказ', 'Неизвестное или отозванное устройство ($remote)');
      return _fail(ConnectError.unauthorized, 'Устройство не доверенное — нужно сопряжение');
    }
    final controllerEphemeral = fromB64(json['ephemeralKey'], length: 32);
    final controllerNonce = fromB64(json['nonce'], length: 16);

    final identity = await server.trust.identity();
    final ephemeral = await KeyPairX.generate();
    final deviceNonce = randomBytes(16);
    final sessionId = newId();
    final keys = await deriveSessionKeys(
      ephemeralShared: await ephemeral.agree(controllerEphemeral),
      staticShared: await identity.key.agree(trusted.publicKey),
      controllerNonce: controllerNonce,
      deviceNonce: deviceNonce,
      sessionId: sessionId,
    );
    final expires = server._clock().add(server.sessionTtl);
    _sendPlain({
      'type': 'hello_ok',
      'protocolVersion': protocolVersion,
      'sessionId': sessionId,
      'deviceId': identity.deviceId,
      'ephemeralKey': toB64(ephemeral.publicKey),
      'nonce': toB64(deviceNonce),
      'expiresAt': expires.millisecondsSinceEpoch,
    });
    // Ключи сеанса есть только у того, кто владеет постоянным ключом
    // доверенного устройства: чужой не расшифрует и не подделает ни кадра.
    _cipher = FrameCipher(
      sessionId: sessionId,
      sendKey: keys.deviceToController,
      receiveKey: keys.controllerToDevice,
      sendLabel: 'd2c',
      receiveLabel: 'c2d',
    );
    _expiresAt = expires;
    controller = trusted;
    await server.trust.touch(trusted.id, server._clock());
    hooks.sessionOpened(trusted.id, trusted.name, remote);
    hooks.log('Подключение', '«${trusted.name}» ($remote)');
  }

  // ---------- Команды ----------

  Future<void> _inner(Map<String, Object?> message) async {
    switch (message['type']) {
      case 'command':
        unawaited(_command(message));
      case 'ping':
        _sendSecure({'type': 'pong', 'deviceTime': DateTime.now().millisecondsSinceEpoch, 'sentAt': message['sentAt']});
      case 'bye':
        await close(WebSocketStatus.normalClosure, 'До свидания');
      default:
        _sendSecure({'type': 'error', 'error': ConnectError.invalidRequest, 'message': 'Неизвестный тип кадра'});
    }
  }

  Future<void> _command(Map<String, Object?> message) async {
    final id = message['commandId'] is String ? message['commandId'] as String : '';
    final CommandRequest request;
    try {
      request = CommandRequest.fromJson(message);
    } on ConnectException catch (e) {
      hooks.log('Ошибка', 'Неверная команда: ${e.code}');
      _sendSecure(CommandResult.error(id, e.code, e.message).toJson());
      return;
    }
    final identity = await server.trust.identity();
    if (request.deviceId != null && request.deviceId != identity.deviceId) {
      _sendSecure(CommandResult.error(id, ConnectError.invalidTarget, 'Команда адресована другому телефону').toJson());
      return;
    }
    // Права: на само действие и на каждый шаг последовательности.
    try {
      _checkScopes(request);
    } on ConnectException catch (e) {
      hooks.log('Отказ', '${request.actionType} ${request.commandId}: ${e.code}');
      _sendSecure(CommandResult.error(id, e.code, e.message).toJson());
      return;
    }
    hooks.log('Команда', '${request.actionType} ${request.commandId}');
    _sendSecure({'type': 'status', 'commandId': id, 'status': CommandStatus.received});
    final result = await server.queue.submit(
      request,
      onStatus: (commandId, status) => _sendSecure({'type': 'status', 'commandId': commandId, 'status': status}),
    );
    hooks.log(
      result.success ? 'Выполнено' : 'Ошибка',
      '${request.actionType} ${request.commandId}: ${result.status}${result.error == null ? '' : ' ${result.error}'}',
    );
    _sendSecure(result.toJson());
  }

  void _checkScopes(CommandRequest request) {
    final scopes = controller?.scopes ?? const <ConnectScope>{};
    final action = request.action;
    if (action == null) return; // исполнитель ответит INVALID_COMMAND
    if (!scopes.contains(action.scope)) {
      throw const ConnectException(ConnectError.unauthorized, 'У устройства нет права на это действие');
    }
    if (action == ConnectAction.sequence) {
      for (final step in sequenceSteps(request.payload)) {
        final a = ConnectAction.parse(step['actionType']);
        if (a != null && !scopes.contains(a.scope)) {
          throw const ConnectException(ConnectError.unauthorized, 'Нет права на один из шагов последовательности');
        }
      }
    }
  }
}
