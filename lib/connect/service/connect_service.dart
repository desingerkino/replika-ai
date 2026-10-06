import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/services.dart';
import '../../core/brand/brand.dart';
import '../../data/repositories/settings_repository.dart';
import '../../app/call_engine.dart';
import '../actions/connect_actions.dart';
import '../discovery/discovery.dart';
import '../protocol/protocol.dart';
import '../queue/command_queue.dart';
import '../security/secret_store.dart';
import '../security/trust.dart';
import '../server/connect_server.dart';
import 'foreground.dart';

/// Состояние Connect для экрана и Controller.
enum ConnectState {
  off('Выключен'),
  starting('Запуск…'),
  waiting('Ожидание подключения'),
  connected('Подключён'),
  reconnecting('Связь потеряна — ожидание переподключения'),
  noNetwork('Нет сети — ожидание Wi-Fi'),
  error('Ошибка');

  const ConnectState(this.label);
  final String label;
}

class ConnectLogEntry {
  const ConnectLogEntry(this.time, this.kind, this.text);

  final DateTime time;
  final String kind;
  final String text;
}

/// Запрос сопряжения, ждущий решения оператора на телефоне.
class PendingPairing {
  PendingPairing(this.controllerName, this.code);

  final String controllerName;
  final String code;
  final Completer<bool> _answer = Completer<bool>();
}

class ActiveSession {
  const ActiveSession(this.controllerId, this.name, this.remote, this.since);

  final String controllerId;
  final String name;
  final String remote;
  final DateTime since;
}

/// Controller, с которым оборвалась связь: ждём его переподключения.
class LostSession {
  const LostSession(this.name, this.until);

  final String name;
  final DateTime until;
}

/// Connect на телефоне: сервер, поиск в сети, сопряжение, очередь, журнал.
class ConnectService extends ChangeNotifier implements ConnectHooks {
  ConnectService({
    required this.services,
    required SecretStore store,
    ConnectForeground? foreground,
    this.port = defaultConnectPort,
    this.discoveryPortNumber = discoveryPort,
    this.reconnectGrace = const Duration(seconds: 90),
    this.networkPoll = const Duration(seconds: 4),
  })  : trust = TrustStore(store),
        _foreground = foreground;

  final AppServices services;
  final TrustStore trust;
  final ConnectForeground? _foreground;
  final int port;
  final int discoveryPortNumber;

  /// Сколько ждать переподключения после обрыва связи.
  final Duration reconnectGrace;
  final Duration networkPoll;

  ConnectDiscovery? _discovery;
  Timer? _networkTimer;
  bool _networkUp = true;
  final Map<String, LostSession> _lost = {};
  Timer? _lostTimer;
  AppLifecycleListener? _lifecycle;
  CallPhase? _lastCallPhase;

  late final ConnectActions actions = ConnectActions(services, deviceInfo: deviceInfo);
  CommandQueue? _queue;
  ConnectServer? _server;

  ConnectState _state = ConnectState.off;
  String? _lastError;
  bool _enabled = false;
  bool _background = false;
  bool _shooting = false;
  String _deviceName = 'Телефон-реквизит';
  String? _deviceId;
  DateTime? _pairingUntil;
  Timer? _pairingTimer;
  PendingPairing? _pending;
  List<String> _addresses = const [];
  final Map<String, ActiveSession> _sessions = {};
  final List<ConnectLogEntry> _log = [];

  ConnectState get state => _state;
  String? get lastError => _lastError;
  bool get enabled => _enabled;
  bool get background => _background;
  bool get shooting => _shooting;
  String get deviceName => _deviceName;
  String? get deviceId => _deviceId;
  int? get boundPort => _server?.boundPort;
  List<String> get addresses => _addresses;
  PendingPairing? get pendingPairing => _pending;
  DateTime? get pairingUntil => _pairingUntil;
  List<ActiveSession> get sessions => _sessions.values.toList();
  Map<String, LostSession> get lostSessions => Map.unmodifiable(_lost);
  bool get networkUp => _networkUp;
  bool get discoverable => _discovery?.running ?? false;
  int? get discoveryBoundPort => _discovery?.boundPort;
  /// Журнал Connect для экрана (метод [log] из ConnectHooks — запись в журнал).
  List<ConnectLogEntry> get logEntries => List.unmodifiable(_log);
  CommandQueue get queue => _queue ??= _createQueue(const {});

  CommandQueue _createQueue(Map<String, CommandResult> restored) =>
      CommandQueue(actions, restored: restored, onPersist: _persistDone);

  /// Запуск при старте приложения: восстановить настройки и, если Connect
  /// был включён, снова поднять сервер.
  Future<void> init() async {
    final settings = services.settings;
    _enabled = await settings.getValue(SettingKeys.connectEnabled) == '1';
    _background = await settings.getValue(SettingKeys.connectBackground) == '1';
    _shooting = await settings.getValue(SettingKeys.connectShooting) == '1';
    _deviceName = await settings.getValue(SettingKeys.connectDeviceName) ?? _deviceName;
    _queue ??= _createQueue(_restoreDone(await settings.getValue(SettingKeys.connectDone)));
    try {
      _deviceId = (await trust.identity()).deviceId;
    } catch (error) {
      _lastError = 'Защищённое хранилище недоступно';
      debugPrint('Connect: ключи недоступны: $error');
    }
    notifyListeners();
    if (_enabled) await start();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await services.settings.setValue(SettingKeys.connectEnabled, value ? '1' : '0');
    value ? await start() : await stop();
  }

  Future<void> start() async {
    if (_server?.running ?? false) return;
    _state = ConnectState.starting;
    _lastError = null;
    notifyListeners();
    try {
      _deviceId = (await trust.identity()).deviceId;
      final server = ConnectServer(trust: trust, queue: queue, hooks: this, port: port);
      await server.start();
      _server = server;
      await refreshAddresses();
      _networkUp = _addresses.isNotEmpty;
      await _startDiscovery();
      _networkTimer?.cancel();
      _networkTimer = Timer.periodic(networkPoll, (_) => _checkNetwork());
      services.callEngine.addListener(_onCall);
      _lifecycle ??= AppLifecycleListener(onResume: _onResume);
      _recompute();
      if (_background) await _foreground?.start(shooting: _shooting);
    } catch (error) {
      _state = ConnectState.error;
      _lastError = error is SocketException
          ? 'Порт $port занят или сеть недоступна'
          : 'Connect не запустился';
      log('Ошибка', _lastError!);
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _networkTimer?.cancel();
    _networkTimer = null;
    _lostTimer?.cancel();
    services.callEngine.removeListener(_onCall);
    await _discovery?.stop();
    _discovery = null;
    await _server?.stop();
    _server = null;
    _sessions.clear();
    _lost.clear();
    closePairing();
    await _foreground?.stop();
    _state = ConnectState.off;
    notifyListeners();
  }

  Future<void> _startDiscovery() async {
    final discovery = ConnectDiscovery(
      port: discoveryPortNumber,
      announce: () => {
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'port': boundPort,
        'connectVersion': connectVersion,
        'status': _state.name,
      },
    );
    try {
      await discovery.start();
      _discovery = discovery;
    } catch (_) {
      // Порт поиска занят — телефон всё равно доступен по адресу вручную.
      log('Поиск', 'Порт $discoveryPortNumber занят — поиск в сети недоступен, подключение по адресу работает');
    }
  }

  /// Сеть пропала или вернулась (адреса интерфейсов).
  Future<void> _checkNetwork() async {
    final before = _addresses.join(',');
    await refreshAddresses();
    final up = _addresses.isNotEmpty;
    if (up != _networkUp) {
      _networkUp = up;
      log('Сеть', up ? 'Сеть восстановлена: ${_addresses.join(', ')}' : 'Сеть пропала');
      if (up) await _discovery?.burst();
      _recompute();
    } else if (up && before != _addresses.join(',')) {
      log('Сеть', 'Новый адрес: ${_addresses.join(', ')}');
      await _discovery?.burst();
    }
  }

  /// Вернулись в приложение: если система остановила сервер — поднять снова.
  Future<void> _onResume() async {
    if (!_enabled) return;
    if (!(_server?.running ?? false)) {
      log('Сервер', 'Перезапуск после возврата в приложение');
      await start();
      return;
    }
    await _checkNetwork();
    await _discovery?.burst();
  }

  /// Обратная связь для Controller: что происходит со звонком на телефоне
  /// (в том числе когда актёр сам ответил, отклонил или положил трубку).
  void _onCall() {
    final call = services.callEngine;
    if (call.phase == _lastCallPhase) return;
    _lastCallPhase = call.phase;
    final session = call.session;
    _server?.broadcast({
      'type': 'event',
      'protocolVersion': protocolVersion,
      'event': 'CALL_STATE',
      'phase': call.phase.name.toUpperCase(),
      if (call.outcome != null && call.phase == CallPhase.ended) 'outcome': call.outcome!.name.toUpperCase(),
      if (session != null) 'characterId': session.characterId,
      if (session != null) 'direction': session.direction.name.toUpperCase(),
      if (session != null) 'kind': session.kind.name.toUpperCase(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _recompute() {
    final now = DateTime.now();
    _lost.removeWhere((_, l) => l.until.isBefore(now));
    if (!(_server?.running ?? false)) return;
    if (_sessions.isNotEmpty) {
      _state = ConnectState.connected; // живой сеанс — лучшее доказательство связи
    } else if (_lost.isNotEmpty) {
      _state = ConnectState.reconnecting;
    } else if (!_networkUp) {
      _state = ConnectState.noNetwork;
    } else {
      _state = ConnectState.waiting;
    }
    notifyListeners();
  }

  // ---------- Энергосбережение ----------

  Future<bool> ignoringBatteryOptimizations() async => await _foreground?.ignoringBatteryOptimizations() ?? false;

  Future<void> requestIgnoreBatteryOptimizations() async {
    await _foreground?.requestIgnoreBatteryOptimizations();
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      _addresses = [for (final i in list) for (final a in i.addresses) a.address];
    } catch (_) {
      _addresses = const [];
    }
    notifyListeners();
  }

  // ---------- Сопряжение ----------

  @override
  bool get pairingOpen => _pairingUntil != null && DateTime.now().isBefore(_pairingUntil!);

  /// Открыть окно сопряжения (по умолчанию на 2 минуты).
  void openPairing({Duration duration = const Duration(minutes: 2)}) {
    _pairingUntil = DateTime.now().add(duration);
    _pairingTimer?.cancel();
    _pairingTimer = Timer(duration, closePairing);
    log('Сопряжение', 'Окно сопряжения открыто');
    notifyListeners();
  }

  void closePairing() {
    _pairingTimer?.cancel();
    _pairingUntil = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending._answer.isCompleted) pending._answer.complete(false);
    notifyListeners();
  }

  @override
  Future<bool> askPairing(String controllerName, String code) {
    final previous = _pending;
    if (previous != null && !previous._answer.isCompleted) previous._answer.complete(false);
    final pending = PendingPairing(controllerName, code);
    _pending = pending;
    notifyListeners();
    return pending._answer.future.timeout(const Duration(minutes: 2), onTimeout: () => false);
  }

  /// Оператор сверил коды и нажал «Разрешить» или «Отклонить».
  void answerPairing(bool allow) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending._answer.isCompleted) pending._answer.complete(allow);
    if (allow) closePairing();
    notifyListeners();
  }

  // ---------- Доверенные устройства ----------

  Future<List<TrustedController>> trusted() => trust.trusted();

  /// Отозвать доверие: сеанс закрывается, повторное подключение — UNAUTHORIZED.
  Future<void> revoke(String controllerId) async {
    final c = await trust.find(controllerId);
    await trust.revoke(controllerId);
    await _server?.closeController(controllerId, reason: 'Доступ отозван');
    log('Доступ отозван', c?.name ?? controllerId);
    notifyListeners();
  }

  Future<void> disconnect(String controllerId) async {
    await _server?.closeController(controllerId);
    notifyListeners();
  }

  Future<void> disconnectAll() async {
    await _server?.closeAll();
    notifyListeners();
  }

  // ---------- Настройки ----------

  Future<void> setBackground(bool value) async {
    _background = value;
    await services.settings.setValue(SettingKeys.connectBackground, value ? '1' : '0');
    if (value && (_server?.running ?? false)) {
      await services.notifications.ensurePermission();
      await _foreground?.start(shooting: _shooting);
    } else if (!value) {
      await _foreground?.stop();
    }
    notifyListeners();
  }

  Future<void> setShooting(bool value) async {
    _shooting = value;
    await services.settings.setValue(SettingKeys.connectShooting, value ? '1' : '0');
    if (_background && (_server?.running ?? false)) await _foreground?.start(shooting: value);
    notifyListeners();
  }

  Future<void> setDeviceName(String name) async {
    final value = name.trim();
    if (value.isEmpty) return;
    _deviceName = value.length > 60 ? value.substring(0, 60) : value;
    await services.settings.setValue(SettingKeys.connectDeviceName, _deviceName);
    notifyListeners();
  }

  /// Сброс сцены Connect с экрана телефона.
  Future<String> resetScene() async {
    try {
      final done = await actions.scene.reset();
      log('Сброс', done ? 'Сцена Connect сброшена' : 'Сбрасывать нечего');
      return done ? 'Сцена Connect сброшена' : 'Connect ещё ничего не добавлял';
    } on ConnectException catch (e) {
      log('Ошибка', 'Сброс: ${e.code}');
      return e.message;
    }
  }

  // ---------- Сведения о телефоне (регистрация для Controller) ----------

  Future<Map<String, Object?>> deviceInfo() async {
    final virtualId = services.currentDeviceId.value;
    final device = await services.devices.byId(virtualId);
    String? characterName;
    if (device != null) {
      final all = await services.contacts.allCharacters();
      characterName = all.where((c) => c.id == device.ownerCharacterId).firstOrNull?.fullName;
    }
    return {
      'deviceId': _deviceId,
      'deviceName': _deviceName,
      'characterId': device?.ownerCharacterId,
      'characterName': characterName,
      'virtualPhoneId': virtualId,
      'virtualPhoneName': device?.name,
      'appVersion': Brand.version,
      'connectVersion': connectVersion,
      'protocolVersion': protocolVersion,
      'status': _state.name,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
      'sceneId': actions.scene.sceneId,
      'supportedActions': [
        for (final a in ConnectAction.values)
          if (a.supported) a.wire,
      ],
    };
  }

  // ---------- ConnectHooks ----------

  @override
  void log(String kind, String text) {
    _log.insert(0, ConnectLogEntry(DateTime.now(), kind, text));
    if (_log.length > 200) _log.removeLast();
    notifyListeners();
  }

  @override
  void sessionOpened(String controllerId, String controllerName, String remote) {
    if (_lost.remove(controllerId) != null) log('Переподключение', controllerName);
    _sessions[controllerId] = ActiveSession(controllerId, controllerName, remote, DateTime.now());
    _recompute();
  }

  @override
  void sessionClosed(String controllerId, {required bool expected}) {
    final session = _sessions.remove(controllerId);
    if (!expected && session != null) {
      _lost[controllerId] = LostSession(session.name, DateTime.now().add(reconnectGrace));
      _lostTimer?.cancel();
      _lostTimer = Timer(reconnectGrace + const Duration(milliseconds: 50), _recompute);
    }
    _recompute();
  }

  // ---------- Кэш выполненных команд (защита от повтора после перезапуска) ----------

  void _persistDone(Map<String, CommandResult> done) {
    final recent = done.entries.toList();
    final tail = recent.length > 200 ? recent.sublist(recent.length - 200) : recent;
    final json = jsonEncode({for (final e in tail) e.key: e.value.toJson()});
    unawaited(services.settings.setValue(SettingKeys.connectDone, json).catchError((Object _) {}));
  }

  static Map<String, CommandResult> _restoreDone(String? raw) {
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map;
      return {
        for (final e in map.entries)
          if (e.value is Map) '${e.key}': CommandResult.fromJson(Map<String, Object?>.from(e.value as Map)),
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _networkTimer?.cancel();
    _lostTimer?.cancel();
    super.dispose();
  }
}
