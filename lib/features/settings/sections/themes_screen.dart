import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/context.dart';
import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/form.dart';
import '../../../core/theme/app_style.dart';
import '../../../core/theme/app_theme_id.dart';
import '../../../core/theme/theme_provider.dart';
import '../settings_screen.dart' show themeModeLabel;
import 'settings_page.dart';

/// Настройки → Темы: выбор темы оформления (меняет всё приложение сразу)
/// и яркости.
class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = ThemeProvider.of(context);
    final brightness = Theme.of(context).brightness;
    return SettingsPage(
      title: 'Темы',
      children: [
        const SectionLabel('Текущая тема'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Row(
            children: [
              for (final id in AppThemeId.values) ...[
                if (id != AppThemeId.values.first) const SizedBox(width: Space.m),
                Expanded(
                  child: _ThemeCard(
                    id: id,
                    brightness: brightness,
                    selected: manager.id == id,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      manager.setTheme(id);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final id in AppThemeId.values)
          _ThemeRadio(
            id: id,
            selected: manager.id == id,
            onTap: () => manager.setTheme(id),
          ),
        const SectionLabel('Оформление'),
        for (final (mode, icon) in const [
          (ThemeMode.system, AppIcons.themeSystem),
          (ThemeMode.light, AppIcons.themeLight),
          (ThemeMode.dark, AppIcons.themeDark),
        ])
          _ModeTile(
            icon: icon,
            label: themeModeLabel(mode),
            selected: manager.mode == mode,
            onTap: () => manager.setMode(mode),
          ),
        const SettingsNote(
          'Тема меняет всё приложение: список чатов, переписку, пузыри, '
          'навигацию, профили и настройки. Скоро — тёмная «Кино» и свои темы.',
        ),
      ],
    );
  }
}

class _ThemeRadio extends StatelessWidget {
  const _ThemeRadio({required this.id, required this.selected, required this.onTap});

  final AppThemeId id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l + 4, vertical: Space.m),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? cs.primary : rc.textTertiary,
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(id.label, style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  Text(id.description, style: context.tt.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l + 4),
          child: Row(
            children: [
              Icon(icon, size: 22, color: rc.textSecondary),
              const SizedBox(width: Space.l),
              Expanded(child: Text(label, style: context.tt.bodyLarge)),
              if (selected) Icon(AppIcons.check, color: context.cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Миниатюра темы: маленький «телефон» с её цветами — поиск, строки чатов,
/// пузыри и нижняя панель.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.id, required this.brightness, required this.selected, required this.onTap});

  final AppThemeId id;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.build(id, brightness);
    final cs = context.cs;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Тема ${id.label}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.normal,
          curve: Motion.curve,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card + 4),
            border: Border.all(color: selected ? cs.primary : context.rc.divider, width: selected ? 2.5 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: Theme(
              data: theme,
              child: Builder(builder: (context) => _Preview(id: id)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.id});

  final AppThemeId id;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final style = context.style;
    Widget line(double w, Color c, {double h = 6}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        );
    Widget row(Color avatar) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(width: 20, height: 20, decoration: BoxDecoration(color: avatar, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [line(44, rc.textPrimary), const SizedBox(height: 3), line(64, rc.textTertiary, h: 4)],
                ),
              ),
            ],
          ),
        );
    return AspectRatio(
      aspectRatio: 0.62,
      child: ColoredBox(
        color: cs.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (style.chatListHeader == ChatListHeaderLook.largeTitle) ...[
                line(40, rc.textPrimary, h: 9),
                const SizedBox(height: 6),
              ],
              Container(
                height: 14,
                decoration: BoxDecoration(
                  color: rc.surfaceMuted,
                  borderRadius: BorderRadius.circular(style.searchRadius >= 100 ? 7 : 4),
                ),
              ),
              const SizedBox(height: 6),
              row(const Color(0xFFFFD9F1)),
              row(const Color(0xFFD4E3FF)),
              const SizedBox(height: 4),
              // Кусочек переписки.
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: rc.chatBackground, borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 50,
                        height: 12,
                        decoration: BoxDecoration(color: rc.bubbleIn, borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 60,
                        height: 12,
                        decoration: BoxDecoration(color: rc.bubbleOut, borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                height: 18,
                margin: EdgeInsets.only(bottom: style.tabBar == TabBarLook.floating ? 6 : 0),
                decoration: BoxDecoration(
                  color: rc.navBar,
                  borderRadius: BorderRadius.circular(style.tabBar == TabBarLook.floating ? 9 : 0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(
                      width: 16,
                      height: 9,
                      decoration: BoxDecoration(color: rc.navIndicator, borderRadius: BorderRadius.circular(5)),
                    ),
                    for (var i = 0; i < 3; i++) line(8, rc.textTertiary, h: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
