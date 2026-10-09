import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../connect/protocol/protocol.dart';
import '../../connect/security/trust.dart';
import '../../connect/service/connect_service.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../core/util/time_format.dart';
import '../operator/operator_theme.dart';
import 'connect_test_screen.dart';
import '../../core/util/platform_info.dart';

/// Настройки → Дополнения → Connect.
class ConnectSettingsScreen extends StatefulWidget {
  const ConnectSettingsScreen({super.key});

  @override
  State<ConnectSettingsScreen> createState() => _ConnectSettingsScreenState();
}

class _ConnectSettingsScreenState extends State<ConnectSettingsScreen> {
  List<TrustedController> _trusted = const [];

  @override
  void initState() {
    super.initState();
    _reloadTrusted();
  }

  Future<void> _reloadTrusted() async {
    final list = await Services.read(context).connect.trusted();
    if (mounted) setState(() => _trusted = List.of(list));
  }

  Color _stateColor(ConnectState s) => switch (s) {
        ConnectState.connected => OperatorPalette.ready,
        ConnectState.waiting || ConnectState.starting || ConnectState.reconnecting => OperatorPalette.standby,
        ConnectState.error || ConnectState.noNetwork => OperatorPalette.live,
        ConnectState.off => OperatorPalette.textDim,
      };

  Future<void> _rename(ConnectService connect) async {
    final controller = TextEditingController(text: connect.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Имя телефона'),
        content: TextField(controller: controller, autofocus: true, maxLength: 60),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Готово')),
        ],
      ),
    );
    if (name != null) await connect.setDeviceName(name);
  }

  Future<void> _revoke(ConnectService connect, TrustedController c) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Отозвать доступ «${c.name}»?',
      message: 'Устройство отключится и больше не сможет управлять телефоном без нового сопряжения.',
      confirmLabel: 'Отозвать',
      destructive: true,
    );
    if (!ok) return;
    await connect.revoke(c.id);
    await _reloadTrusted();
  }

  @override
  Widget build(BuildContext context) {
    final connect = Services.of(context).connect;
    const dim = TextStyle(color: OperatorPalette.textDim, fontSize: 13);
    const text = TextStyle(color: OperatorPalette.text, fontSize: 16);
    return Theme(
      data: operatorTheme,
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: const BackIconButton(),
          title: const Text('Connect', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        body: ListenableBuilder(
          listenable: connect,
          builder: (context, _) {
            final pending = connect.pendingPairing;
            final sessions = connect.sessions;
            return ListView(
              padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxxl)),
              children: [
                // Статус
                OperatorCard(
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 14, color: _stateColor(connect.state)),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(connect.state.label.toUpperCase(),
                                style: TextStyle(
                                  color: _stateColor(connect.state),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                )),
                            if (sessions.isNotEmpty)
                              Text('Оператор: ${sessions.map((s) => s.name).join(', ')}', style: text),
                            for (final lost in connect.lostSessions.values)
                              Text('Связь с «${lost.name}» потеряна — ждём переподключения до ${formatClock(lost.until)}',
                                  style: dim),
                            if (connect.lastError != null) Text(connect.lastError!, style: dim),
                          ],
                        ),
                      ),
                      Switch(value: connect.enabled, onChanged: connect.setEnabled),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s),
                const Text(
                  'Выключен — телефон работает как обычный реквизит. Включён — принимает команды '
                  'от доверенного Prop Controller в локальной сети, без интернета.',
                  style: dim,
                ),

                // Телефон
                const SectionLabel('Этот телефон'),
                OperatorCard(
                  onTap: () => _rename(connect),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Device ID: ${connect.deviceId ?? '—'}',
                          style: text.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      Text('Имя: ${connect.deviceName} (нажмите, чтобы изменить)', style: dim),
                      const SizedBox(height: Space.xs),
                      Text(
                        connect.addresses.isEmpty
                            ? 'Сеть: адрес не найден — подключите телефон к Wi-Fi'
                            : 'Адрес для Controller: ${connect.addresses.map((a) => '$a:${connect.boundPort ?? defaultConnectPort}').join(', ')}',
                        style: dim,
                      ),
                      Text(
                        connect.discoverable
                            ? 'Виден в сети: Controller находит телефон сам (поиск UDP, порт ${connect.discoveryBoundPort})'
                            : 'Поиск в сети недоступен — подключение по адресу выше',
                        style: dim,
                      ),
                      const Text('Персонаж телефона назначает Controller (ASSIGN_CHARACTER) — '
                          'Device ID с персонажем не связан.', style: dim),
                    ],
                  ),
                ),

                // Сопряжение
                const SectionLabel('Сопряжение'),
                if (pending != null)
                  OperatorCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Подключение устройства «${pending.controllerName}»', style: text),
                        const SizedBox(height: Space.s),
                        const Text('Код подключения:', style: dim),
                        Text(
                          pending.code.replaceRange(3, 3, ' '),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: OperatorPalette.standby,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Text(
                          'Сравните с кодом на экране Controller. Разрешайте, только если коды совпадают.',
                          style: dim,
                        ),
                        const SizedBox(height: Space.m),
                        Row(
                          children: [
                            Expanded(
                              child: PanelButton(
                                label: 'ОТКЛОНИТЬ',
                                color: OperatorPalette.line,
                                height: 52,
                                onPressed: () => connect.answerPairing(false),
                              ),
                            ),
                            const SizedBox(width: Space.s),
                            Expanded(
                              child: PanelButton(
                                label: 'РАЗРЕШИТЬ',
                                color: OperatorPalette.ready,
                                foreground: OperatorPalette.background,
                                height: 52,
                                onPressed: () async {
                                  connect.answerPairing(true);
                                  await Future<void>.delayed(const Duration(milliseconds: 400));
                                  await _reloadTrusted();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  PanelButton(
                    label: connect.pairingOpen ? 'ОЖИДАНИЕ СОПРЯЖЕНИЯ…' : 'РАЗРЕШИТЬ НОВОЕ УСТРОЙСТВО',
                    icon: Icons.link_rounded,
                    color: connect.pairingOpen ? OperatorPalette.standby : OperatorPalette.line,
                    foreground: connect.pairingOpen ? OperatorPalette.background : MediaPalette.onMedia,
                    height: 56,
                    onPressed: connect.state == ConnectState.off
                        ? null
                        : (connect.pairingOpen ? connect.closePairing : connect.openPairing),
                  ),
                const SizedBox(height: Space.s),
                const Text(
                  'Окно сопряжения открыто 2 минуты. Без него телефон не принимает новые устройства — '
                  'даже в той же Wi-Fi.',
                  style: dim,
                ),

                // Доверенные устройства
                SectionLabel('Доверенные устройства (${_trusted.length})'),
                if (_trusted.isEmpty) const Text('Пока нет.', style: dim),
                for (final c in _trusted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: OperatorCard(
                      child: Row(
                        children: [
                          Icon(
                            sessions.any((s) => s.controllerId == c.id)
                                ? Icons.link_rounded
                                : Icons.link_off_rounded,
                            color: sessions.any((s) => s.controllerId == c.id)
                                ? OperatorPalette.ready
                                : OperatorPalette.textDim,
                          ),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: text),
                                Text(
                                  c.lastSeen == null
                                      ? 'ещё не подключалось'
                                      : 'было на связи ${formatChatListTime(c.lastSeen!, DateTime.now())}',
                                  style: dim,
                                ),
                              ],
                            ),
                          ),
                          if (sessions.any((s) => s.controllerId == c.id))
                            TextButton(onPressed: () => connect.disconnect(c.id), child: const Text('Отключить')),
                          TextButton(
                            onPressed: () => _revoke(connect, c),
                            style: TextButton.styleFrom(foregroundColor: OperatorPalette.live),
                            child: const Text('Отозвать'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Фон и съёмка
                const SectionLabel('Работа на площадке'),
                if (isIOS)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: connect.background,
                    onChanged: connect.setBackground,
                    title: const Text('Не гасить экран, пока Connect включён', style: text),
                    subtitle: const Text(
                      'iPhone и iPad приостанавливают приложение при блокировке экрана, поэтому '
                      'Connect работает, только пока «Реплика» открыта на экране. На съёмке включите '
                      '«Гид-доступ» и поставьте Автоблокировку «Никогда».',
                      style: dim,
                    ),
                  )
                else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: connect.background,
                  onChanged: connect.setBackground,
                  title: const Text('Работать при погашенном экране', style: text),
                  subtitle: const Text(
                    'Android требует для этого постоянное уведомление в шторке — без него сеть '
                    'приложения в фоне засыпает. Текст уведомления нейтральный, без имён и сообщений.',
                    style: dim,
                  ),
                ),
                FutureBuilder<bool>(
                  future: connect.ignoringBatteryOptimizations(),
                  builder: (context, snapshot) => snapshot.data == true
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: Space.s),
                          child: Text('Энергосбережение Android не ограничивает Connect.', style: dim),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(bottom: Space.s),
                          child: PanelButton(
                            label: 'НЕ ОГРАНИЧИВАТЬ В ФОНЕ',
                            icon: Icons.battery_saver_outlined,
                            color: OperatorPalette.line,
                            height: 52,
                            onPressed: connect.requestIgnoreBatteryOptimizations,
                          ),
                        ),
                ),
                const Text(
                  'Без этого Android (особенно Xiaomi, Huawei) может усыплять сеть при погашенном экране. '
                  'На некоторых оболочках дополнительно: настройки батареи → «Реплика» → «Без ограничений».',
                  style: dim,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: connect.shooting,
                  onChanged: connect.setShooting,
                  title: const Text('Режим «Съёмка»', style: text),
                  subtitle: const Text('Уведомление — только «Реплика · Активно».', style: dim),
                ),
                ],

                // Проверка и сброс
                const SectionLabel('Проверка'),
                PanelButton(
                  label: 'ПРОВЕРКА CONNECT',
                  icon: Icons.science_outlined,
                  color: OperatorPalette.line,
                  height: 56,
                  onPressed: connect.state == ConnectState.off
                      ? null
                      : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(builder: (_) => const ConnectTestScreen()),
                          ),
                ),
                const SizedBox(height: Space.s),
                PanelButton(
                  label: 'СБРОСИТЬ СЦЕНУ CONNECT',
                  icon: Icons.restart_alt_rounded,
                  color: OperatorPalette.line,
                  height: 52,
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final result = await connect.resetScene();
                    messenger.showSnackBar(SnackBar(content: Text(result)));
                  },
                ),
                const SizedBox(height: Space.xs),
                const Text('Убирает только то, что добавил Connect. Обычные переписки и другие сцены не трогаются.',
                    style: dim),

                // Журнал
                const SectionLabel('Журнал Connect'),
                if (connect.logEntries.isEmpty) const Text('Пусто.', style: dim),
                for (final e in connect.logEntries.take(60))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: Text('${formatClock(e.time)}  ${e.kind}: ${e.text}',
                        style: const TextStyle(color: OperatorPalette.textDim, fontSize: 12.5)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
