import 'package:flutter/material.dart';

/// Краски «светлого жидкого стекла» главных экранов. Светлый вариант — по
/// эталону; тёмный повторяет ту же схему на глубоком тёмно-синем, чтобы экран
/// не слепил, когда в приложении включена тёмная тема.
@immutable
class GlassTheme {
  const GlassTheme({
    required this.dark,
    required this.background,
    required this.blobs,
    required this.surface,
    required this.surfaceStrong,
    required this.border,
    required this.highlight,
    required this.shadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.icon,
  });

  final bool dark;

  /// Вертикальный градиент фона (сверху вниз).
  final List<Color> background;

  /// Мягкие цветные пятна фона: синее, фиолетовое, голубое, розовое.
  final List<Color> blobs;

  /// Заливка стеклянных карточек и кнопок.
  final Color surface;

  /// Более плотное стекло (панель вкладок, поле поиска).
  final Color surfaceStrong;
  final Color border;

  /// Блик по верхнему краю стекла.
  final Color highlight;
  final Color shadow;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Неактивные значки (панель вкладок, поиск).
  final Color icon;

  /// Фирменный градиент Replika: активная вкладка, фильтр, счётчики.
  static const List<Color> accent = [Color(0xFF4A63FF), Color(0xFF5B5BFF), Color(0xFF8E63FF)];
  static const Color accentBlue = Color(0xFF4A63FF);
  static const Color accentGlow = Color(0xFF6C6BFF);
  static const Color online = Color(0xFF2FD071);

  static const GlassTheme day = GlassTheme(
    dark: false,
    background: [Color(0xFFF2F6FF), Color(0xFFE9EEFC), Color(0xFFEEE8FB)],
    blobs: [Color(0xFFB9CDFF), Color(0xFFD8C6FF), Color(0xFFBFE0FF), Color(0xFFEFC6F3)],
    surface: Color(0x8CFFFFFF),
    surfaceStrong: Color(0xA6FFFFFF),
    border: Color(0xCCFFFFFF),
    highlight: Color(0x99FFFFFF),
    shadow: Color(0x1F4F63C8),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF636B7E),
    textTertiary: Color(0xFF8790A5),
    icon: Color(0xFF6A7692),
  );

  static const GlassTheme night = GlassTheme(
    dark: true,
    background: [Color(0xFF0A0E20), Color(0xFF0B1026), Color(0xFF120F2A)],
    blobs: [Color(0xFF24348A), Color(0xFF43278A), Color(0xFF16406E), Color(0xFF5A246E)],
    surface: Color(0x14FFFFFF),
    surfaceStrong: Color(0x24FFFFFF),
    border: Color(0x26FFFFFF),
    highlight: Color(0x1FFFFFFF),
    shadow: Color(0x66000000),
    textPrimary: Color(0xFFF1F4FB),
    textSecondary: Color(0xFFA9B2C8),
    textTertiary: Color(0xFF7D879E),
    icon: Color(0xFF9AA5C0),
  );

  static GlassTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? night : day;

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: accent,
  );
}
