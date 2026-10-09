import 'package:flutter/material.dart';

import '../../app/kino.dart';
import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/top_bar.dart';
import '../operator/operator_theme.dart';
import 'fake_status_bar.dart';
import '../../core/util/platform_info.dart';

/// Настройка КИНОРЕЖИМА (операторская → «Кинорежим»).
class KinoScreen extends StatelessWidget {
  const KinoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final kino = Services.of(context).kino;
    return Theme(
      data: operatorTheme,
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: const BackIconButton(),
          title: const Text('Кинорежим', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        body: ValueListenableBuilder<KinoSettings>(
          valueListenable: kino,
          builder: (context, s, _) => ListView(
            padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxxl)),
            children: [
              PanelButton(
                label: s.enabled ? 'КИНОРЕЖИМ ВКЛЮЧЁН' : 'ВКЛЮЧИТЬ КИНОРЕЖИМ',
                icon: Icons.movie_creation_outlined,
                color: s.enabled ? OperatorPalette.live : OperatorPalette.ready,
                foreground: s.enabled ? MediaPalette.onMedia : OperatorPalette.background,
                height: 72,
                onPressed: () => kino.update(s.copyWith(enabled: !s.enabled)),
              ),
              const SizedBox(height: Space.m),
              const Text(
                'В кинорежиме телефон выглядит как телефон персонажа: в настройках '
                'не видно операторской, дополнений, медиатеки и версии приложения, '
                '«назад» на главном экране не закрывает приложение. Вход в операторскую — '
                'только скрыто: удержание «Чаты» 2 секунды или три пальца. '
                'Кнопки громкости работают как обычно для сцены.',
                style: TextStyle(color: OperatorPalette.textDim),
              ),
              const SectionLabel('Строка состояния'),
              _Switch(
                title: 'Своя строка состояния',
                subtitle: isIOS
                    ? 'Системная строка состояния скрывается, приложение рисует свою '
                        'с нужным временем и зарядом (вокруг выреза или Dynamic Island).'
                    : 'Системные панели скрываются, приложение рисует свою строку '
                        'с нужным временем и зарядом. Свайп от края временно показывает системные.',
                value: s.fakeStatusBar,
                onChanged: (v) => kino.update(s.copyWith(fakeStatusBar: v)),
              ),
              if (s.fakeStatusBar) ...[
                const SizedBox(height: Space.s),
                Container(
                  decoration: BoxDecoration(
                    color: MediaPalette.onMedia,
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: FakeStatusBar(settings: s, lightIcons: false),
                ),
                const SizedBox(height: Space.m),
                const Text('Время', style: TextStyle(color: OperatorPalette.textDim)),
                const SizedBox(height: Space.xs),
                for (final c in KinoClock.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => kino.update(s.copyWith(clock: c)),
                    leading: Icon(
                      s.clock == c ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: s.clock == c ? OperatorPalette.standby : OperatorPalette.textDim,
                    ),
                    title: Text(c.label, style: const TextStyle(color: OperatorPalette.text)),
                  ),
                if (s.clock == KinoClock.fixed)
                  OperatorCard(
                    onTap: () async {
                      final parts = s.fixedTime.split(':');
                      final picked = await showTimePicker(
                        context: context,
                        helpText: 'Время на телефоне',
                        cancelText: 'Отмена',
                        confirmText: 'Готово',
                        initialTime: TimeOfDay(
                          hour: int.tryParse(parts.first) ?? 23,
                          minute: int.tryParse(parts.last) ?? 47,
                        ),
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                          child: child ?? const SizedBox.shrink(),
                        ),
                      );
                      if (picked == null) return;
                      final hh = picked.hour.toString().padLeft(2, '0');
                      final mm = picked.minute.toString().padLeft(2, '0');
                      await kino.update(s.copyWith(fixedTime: '$hh:$mm'));
                    },
                    child: Text('Начальное время: ${s.fixedTime} — нажмите, чтобы изменить',
                        style: const TextStyle(color: OperatorPalette.text, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: Space.m),
                Text('Заряд: ${s.battery}%', style: const TextStyle(color: OperatorPalette.text)),
                Slider(
                  value: s.battery.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${s.battery}%',
                  onChanged: (v) => kino.update(s.copyWith(battery: v.round())),
                ),
                _Switch(
                  title: 'Заряжается',
                  value: s.charging,
                  onChanged: (v) => kino.update(s.copyWith(charging: v)),
                ),
                const SizedBox(height: Space.s),
                Text('Сигнал: ${s.signal} из 3', style: const TextStyle(color: OperatorPalette.text)),
                Slider(
                  value: s.signal.toDouble(),
                  min: 0,
                  max: 3,
                  divisions: 3,
                  onChanged: (v) => kino.update(s.copyWith(signal: v.round())),
                ),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final n in KinoNetwork.values)
                      ChoiceChip(
                        label: Text(n == KinoNetwork.none ? 'Без значка сети' : n.label),
                        selected: s.network == n,
                        onSelected: (_) => kino.update(s.copyWith(network: n)),
                      ),
                  ],
                ),
                _Switch(
                  title: 'Wi-Fi',
                  value: s.wifi,
                  onChanged: (v) => kino.update(s.copyWith(wifi: v)),
                ),
              ],
              SectionLabel(isIOS ? 'Перед съёмкой — настройки устройства' : 'Перед съёмкой — настройки Android'),
              Text(
                isIOS
                    ? 'Эти вещи приложение сделать не может — их включают в настройках:\n'
                        '• Фокус «Не беспокоить» — чтобы в кадр не попали уведомления других приложений '
                        '(уведомления «Реплики» при этом тоже скрываются: разрешите их в Фокусе);\n'
                        '• «Гид-доступ» (Универсальный доступ) — чтобы актёр случайно не вышел '
                        'на рабочий стол кнопкой «Домой»;\n'
                        '• Экран и яркость → Автоблокировка → «Никогда», чтобы экран не гас в дубле.'
                    : 'Эти вещи приложение сделать не может — их включают в настройках телефона:\n'
                        '• «Не беспокоить» — чтобы в кадр не попали уведомления других приложений;\n'
                        '• «Закрепление приложений» (безопасность) — чтобы актёр случайно не вышел '
                        'на рабочий стол кнопкой «Домой»;\n'
                        '• тайм-аут экрана — максимальный, чтобы экран не гас в дубле.',
                style: const TextStyle(color: OperatorPalette.textDim, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.title, required this.value, required this.onChanged, this.subtitle});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(color: OperatorPalette.text)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: OperatorPalette.textDim)),
    );
  }
}
