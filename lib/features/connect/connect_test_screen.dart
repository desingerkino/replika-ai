import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../connect/client/connect_client.dart';
import '../../connect/discovery/discovery.dart';
import '../../connect/protocol/protocol.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../core/util/time_format.dart';
import '../operator/operator_theme.dart';

/// Проверка Connect без Prop Controller: этот экран — такой же клиент
/// протокола, как будущий Controller. Команды идут через настоящий сокет
/// (127.0.0.1), сопряжение, ключи и шифрование — никаких обходов.
class ConnectTestScreen extends StatefulWidget {
  const ConnectTestScreen({super.key});

  @override
  State<ConnectTestScreen> createState() => _ConnectTestScreenState();
}

class _ConnectTestScreenState extends State<ConnectTestScreen> {
  late final ConnectClient _client = ConnectClient(store: Services.read(context).connect.trust.store)
    ..onEvent = (event) {
      _say('Событие ${event['event']}: ${event['phase'] ?? ''} ${event['outcome'] ?? ''}');
    }
    ..onClosed = (reason) {
      _say('Соединение закрыто: $reason');
    };
  final List<String> _lines = [];
  String? _clientCode;
  bool _busy = false;
  List<Map<String, Object?>> _characters = const [];
  String? _owner;
  CommandRequest? _last;

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  void _say(String line) {
    if (!mounted) return;
    setState(() => _lines.insert(0, '${formatClock(DateTime.now())}  $line'));
  }

  Future<void> _guard(String title, Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } on ConnectException catch (e) {
      _say('$title: ${e.code} — ${e.message}');
    } catch (e) {
      _say('$title: ошибка ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final connect = Services.read(context).connect;
    await _client.connect('127.0.0.1', port: connect.boundPort ?? defaultConnectPort);
  }

  Future<void> _pair() => _guard('Сопряжение', () async {
        final connect = Services.read(context).connect;
        connect.openPairing();
        await _open();
        _say('Запрос сопряжения отправлен');
        final ok = await _client.pair(onCode: (code) {
          if (mounted) setState(() => _clientCode = code);
        });
        if (mounted) setState(() => _clientCode = null);
        _say(ok ? 'Сопряжение разрешено' : 'Сопряжение отклонено');
        if (ok) await _hello();
      });

  Future<void> _hello() async {
    await _client.hello();
    _say('Сеанс открыт (hello → hello_ok), Device ID ${_client.deviceId}');
    final info = await _client.command('DEVICE_INFO');
    _owner = info.result['characterId'] as String?;
    final list = await _client.command('LIST_CHARACTERS');
    _characters = [
      for (final c in (list.result['characters'] as List?) ?? const [])
        if (c is Map) Map<String, Object?>.from(c),
    ];
    _say('Персонаж телефона: ${info.result['characterName'] ?? '—'}; персонажей: ${_characters.length}');
  }

  Future<void> _connect() => _guard('Подключение', () async {
        await _open();
        await _hello();
      });

  /// Поиск телефонов в сети — так Prop Controller находит Messenger.
  Future<void> _discover() => _guard('Поиск', () async {
        final connect = Services.read(context).connect;
        final found = await discoverDevices(
          hosts: const ['127.0.0.1', '255.255.255.255'],
          port: connect.discoveryBoundPort ?? discoveryPort,
        );
        if (found.isEmpty) {
          _say('Поиск: телефоны не найдены (маяк выключен или сеть блокирует UDP)');
        }
        for (final d in found) {
          _say('Найден: ${d['deviceId']} «${d['deviceName']}» ${d['address']}:${d['port']} (v${d['connectVersion']})');
        }
      });

  /// Переподключение, как после потери Wi-Fi: connect + hello с паузами.
  Future<void> _reconnect() => _guard('Переподключение', () async {
        final connect = Services.read(context).connect;
        await _client.close();
        await _client.reconnect('127.0.0.1', port: connect.boundPort ?? defaultConnectPort);
        _say('Переподключено, сеанс ${_client.sessionId?.substring(0, 8)}');
      });

  /// Синхронный запуск: сообщение через 3 секунды по часам телефона.
  Future<void> _scheduled() => _guard('executeAt', () async {
        if (!_client.authenticated) throw const ConnectException(ConnectError.unauthorized, 'сначала подключитесь');
        final at = DateTime.now().millisecondsSinceEpoch + 3000;
        final request = CommandRequest(
          commandId: 'test-${DateTime.now().millisecondsSinceEpoch}',
          actionType: 'MESSAGE',
          payload: {'fromCharacterId': _peer, 'toCharacterId': _owner, 'text': 'Ровно через 3 секунды'},
          executeAt: at,
        );
        _last = request;
        final r = await _client.send(request);
        _say('executeAt: ${r.status}, опоздание ${r.result['lateMs']} мс');
      });

  String get _peer {
    final other = _characters.where((c) => c['characterId'] != _owner && c['contactName'] != null);
    return (other.isNotEmpty ? other.first : _characters.firstWhere((c) => c['characterId'] != _owner))['characterId']
        as String;
  }

  Future<void> _send(String actionType, [Map<String, Object?> payload = const {}]) =>
      _guard(actionType, () async {
        if (!_client.authenticated) throw const ConnectException(ConnectError.unauthorized, 'сначала подключитесь');
        final request = CommandRequest(
          commandId: 'test-${DateTime.now().millisecondsSinceEpoch}',
          actionType: actionType,
          payload: payload,
        );
        _last = request;
        await _report(request);
      });

  Future<void> _report(CommandRequest request) async {
    final r = await _client.send(request);
    _say('${request.actionType} ${request.commandId}: ${r.status}'
        '${r.error == null ? '' : ' ${r.error}'}${r.message.isEmpty ? '' : ' — ${r.message}'}');
  }

  Future<void> _repeat() => _guard('Повтор', () async {
        final last = _last;
        if (last == null) throw const ConnectException(ConnectError.invalidRequest, 'сначала отправьте команду');
        _say('Повтор с тем же commandId ${last.commandId}');
        await _report(last);
      });

  @override
  Widget build(BuildContext context) {
    final connect = Services.of(context).connect;
    const dim = TextStyle(color: OperatorPalette.textDim, fontSize: 13);
    Widget button(String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: PanelButton(
            label: label,
            color: OperatorPalette.line,
            height: 48,
            onPressed: _busy ? null : onTap,
          ),
        );
    final ready = _client.authenticated && _characters.length >= 2 && _owner != null;
    return Theme(
      data: operatorTheme,
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: const BackIconButton(),
          title: const Text('Проверка Connect', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        body: ListenableBuilder(
          listenable: connect,
          builder: (context, _) {
            final pending = connect.pendingPairing;
            return ListView(
              padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxxl)),
              children: [
                const Text(
                  'Этот экран работает как будущий Prop Controller: подключается к Connect через сокет, '
                  'проходит сопряжение и отправляет зашифрованные команды.',
                  style: dim,
                ),
                const SectionLabel('1. Подключение'),
                if (_clientCode != null || pending != null)
                  OperatorCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_clientCode != null)
                          Text('Код на «Controller»: $_clientCode',
                              style: const TextStyle(color: OperatorPalette.text, fontSize: 18)),
                        if (pending != null)
                          Text('Код на телефоне: ${pending.code}',
                              style: const TextStyle(color: OperatorPalette.standby, fontSize: 18)),
                        if (pending != null) ...[
                          const SizedBox(height: Space.s),
                          Row(
                            children: [
                              Expanded(
                                child: PanelButton(
                                  label: 'ОТКЛОНИТЬ',
                                  color: OperatorPalette.line,
                                  height: 48,
                                  onPressed: () => connect.answerPairing(false),
                                ),
                              ),
                              const SizedBox(width: Space.s),
                              Expanded(
                                child: PanelButton(
                                  label: 'РАЗРЕШИТЬ',
                                  color: OperatorPalette.ready,
                                  foreground: OperatorPalette.background,
                                  height: 48,
                                  onPressed: () => connect.answerPairing(true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: Space.s),
                button('СОПРЯЖЕНИЕ (ПЕРВЫЙ РАЗ)', _pair),
                button('ПОДКЛЮЧИТЬСЯ (УЖЕ СОПРЯЖЁН)', _connect),
                button('НАЙТИ ТЕЛЕФОНЫ В СЕТИ (UDP)', _discover),
                button('ПЕРЕПОДКЛЮЧИТЬСЯ (как после потери Wi-Fi)', _reconnect),
                button('ОТКЛЮЧИТЬСЯ', () async {
                  await _client.close();
                  _say('Соединение закрыто');
                  setState(() {});
                }),
                const SectionLabel('2. Команды'),
                if (!ready)
                  const Text('Сначала подключитесь. Для сообщений нужно минимум два персонажа.', style: dim)
                else ...[
                  button('MESSAGE «Тест Connect»',
                      () => _send('MESSAGE', {'fromCharacterId': _peer, 'toCharacterId': _owner, 'text': 'Тест Connect'})),
                  button('TYPING 3 с', () => _send('TYPING', {'fromCharacterId': _peer, 'durationMs': 3000})),
                  button('CALL (входящий)', () => _send('CALL', {'fromCharacterId': _peer, 'toCharacterId': _owner})),
                  button('END_CALL', () => _send('END_CALL')),
                  button('NOTIFICATION',
                      () => _send('NOTIFICATION', {'fromCharacterId': _peer, 'text': 'Уведомление из Connect'})),
                  button('SEQUENCE: сообщение → 2 с → сообщение', () => _send('SEQUENCE', {
                        'steps': [
                          {
                            'actionType': 'MESSAGE',
                            'payload': {'fromCharacterId': _peer, 'toCharacterId': _owner, 'text': 'Ты где?'},
                          },
                          {'actionType': 'DELAY', 'payload': {'ms': 2000}},
                          {
                            'actionType': 'MESSAGE',
                            'payload': {'fromCharacterId': _peer, 'toCharacterId': _owner, 'text': 'Я уже приехала'},
                          },
                        ],
                      })),
                  button('MESSAGE через 3 с (executeAt)', _scheduled),
                  button('RESET_SCENE', () => _send('RESET_SCENE')),
                  const SectionLabel('3. Ошибки и защита'),
                  button('ПОВТОР ПОСЛЕДНЕЙ КОМАНДЫ (тот же commandId)', _repeat),
                  button('НЕИЗВЕСТНАЯ КОМАНДА', () => _send('LAUNCH_ROCKET')),
                  button('ГРУППА: создать «Съёмочная группа»', () => _send('CREATE_CHAT', {
                        'groupId': 'crew-test',
                        'title': 'Съёмочная группа',
                        'memberIds': [_peer],
                      })),
                  button('ГРУППА: сообщение участника',
                      () => _send('MESSAGE', {'groupId': 'crew-test', 'fromCharacterId': _peer, 'text': 'Встречаемся в 19:00'})),
                  button('ПУСТОЙ ТЕКСТ', () => _send('MESSAGE', {'fromCharacterId': _peer, 'toCharacterId': _owner, 'text': ''})),
                ],
                const SectionLabel('Результаты'),
                if (_lines.isEmpty) const Text('Пока пусто.', style: dim),
                for (final line in _lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: Text(line, style: const TextStyle(color: OperatorPalette.text, fontSize: 13)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
