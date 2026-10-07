import 'package:flutter/material.dart';

import '../context.dart';
import '../icons.dart';
import '../tokens.dart';
import 'pressable.dart';

/// Поле формы в стиле «Реплики»: заливка без подчёркивания.
class ReplikaTextField extends StatelessWidget {
  const ReplikaTextField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.keyboardType,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.sentences,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    // Метка остаётся внутри заливки: у «подчёркнутой» границы нет разрыва
    // под плавающую метку, в отличие от контурной.
    UnderlineInputBorder border(Color color, double width) => UnderlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
        );
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: 1,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: context.tt.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        filled: true,
        fillColor: rc.surfaceMuted,
        labelStyle: TextStyle(color: rc.textSecondary),
        floatingLabelStyle: TextStyle(color: cs.primary),
        helperStyle: TextStyle(color: rc.textTertiary, fontSize: 12),
        contentPadding: const EdgeInsets.fromLTRB(Space.l, Space.s + 2, Space.l, Space.s + 2),
        border: border(Colors.transparent, 0),
        enabledBorder: border(Colors.transparent, 0),
        focusedBorder: border(cs.primary, 1.5),
      ),
    );
  }
}

/// Подпись раздела на экранах настроек и профиля.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l + 4, Space.xl, Space.l, Space.s),
      child: Text(
        text,
        style: context.tt.labelMedium?.copyWith(
          color: context.cs.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Строка списка настроек.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final color = destructive ? rc.danger : rc.textPrimary;
    return Pressable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l + 4, vertical: Space.m - 2),
          child: Row(
            children: [
              Icon(icon, size: 22, color: destructive ? rc.danger : rc.textSecondary),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tt.bodyLarge?.copyWith(color: color)),
                    if (subtitle != null)
                      Text(subtitle!, style: tt.bodySmall),
                  ],
                ),
              ),
              if (trailing != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: Space.s),
                    child: Text(
                      trailing!,
                      textAlign: TextAlign.end,
                      style: tt.bodyMedium?.copyWith(color: rc.textSecondary),
                    ),
                  ),
                ),
              if (onTap != null && !destructive)
                Icon(AppIcons.chevron, color: rc.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Нижний отступ списка с учётом системной навигации (жесты или кнопки):
/// последний элемент не прячется под панелью телефона.
EdgeInsets listPadding(BuildContext context, EdgeInsets padding) =>
    padding.copyWith(bottom: padding.bottom + MediaQuery.paddingOf(context).bottom);

/// Строка настроек с переключателем; длинное пояснение переносится.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    return Pressable(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l + 4, vertical: Space.m - 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 22, color: rc.textSecondary),
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tt.bodyLarge),
                  if (subtitle != null) Text(subtitle!, style: tt.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
