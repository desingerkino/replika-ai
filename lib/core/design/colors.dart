import 'package:flutter/material.dart';

/// Смысловые цвета интерфейса «Реплики» для светлой и тёмной темы.
@immutable
class ReplikaColors extends ThemeExtension<ReplikaColors> {
  const ReplikaColors({
    required this.chatBackground,
    required this.bubbleIn,
    required this.bubbleOut,
    required this.bubbleInBorder,
    required this.deletedBorder,
    required this.deletedText,
    required this.onBubbleIn,
    required this.onBubbleOut,
    required this.metaIn,
    required this.metaOut,
    required this.tickRead,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.surfaceMuted,
    required this.badge,
    required this.badgeMuted,
    required this.onBadge,
    required this.draft,
    required this.daySeparator,
    required this.onDaySeparator,
    required this.accent,
    required this.online,
    required this.success,
    required this.warning,
    required this.danger,
    required this.selection,
  });

  final Color chatBackground;
  final Color bubbleIn;
  final Color bubbleOut;

  /// Тонкая рамка входящего пузыря (1 px): отделяет белый пузырь от фона чата.
  final Color bubbleInBorder;

  /// Удалённое сообщение: рамка вместо заливки и спокойный серо-голубой текст.
  final Color deletedBorder;
  final Color deletedText;
  final Color onBubbleIn;
  final Color onBubbleOut;
  final Color metaIn;
  final Color metaOut;
  final Color tickRead;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color surfaceMuted;
  final Color badge;
  final Color badgeMuted;
  final Color onBadge;
  final Color draft;
  final Color daySeparator;
  final Color onDaySeparator;
  final Color accent;
  final Color online;
  final Color success;
  final Color warning;
  final Color danger;
  final Color selection;

  /// «Чистый воздух», светлая тема: белые панели, очень светлый холодный
  /// фон чата, графитовый текст, один спокойный синий.
  static const ReplikaColors light = ReplikaColors(
    chatBackground: Color(0xFFEEF3F7),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFF1F6FA8),
    bubbleInBorder: Color(0xFFDDE5EC),
    deletedBorder: Color(0xFFAEBBC7),
    deletedText: Color(0xFF5F6C79),
    onBubbleIn: Color(0xFF1B232B),
    onBubbleOut: Color(0xFFFFFFFF),
    metaIn: Color(0xFF5F6C79),
    metaOut: Color(0xFFE6F1FA),
    tickRead: Color(0xFFB4F2E4),
    textPrimary: Color(0xFF1B232B),
    textSecondary: Color(0xFF5A6773),
    textTertiary: Color(0xFF616D79),
    divider: Color(0xFFDDE5EC),
    surfaceMuted: Color(0xFFEEF3F7),
    badge: Color(0xFF1F6FA8),
    badgeMuted: Color(0xFF66727E),
    onBadge: Color(0xFFFFFFFF),
    draft: Color(0xFFC8372D),
    daySeparator: Color(0xFFDCE6EE),
    onDaySeparator: Color(0xFF44525F),
    accent: Color(0xFFE3A13B),
    online: Color(0xFF2F9E6E),
    success: Color(0xFF2F9E6E),
    warning: Color(0xFFD08A1E),
    danger: Color(0xFFC8372D),
    selection: Color(0x1F1F6FA8),
  );

  /// Тёмная тема: слои синего графита, а не инверсия светлой. Текст не
  /// чисто белый, чтобы не «горел» в кадре.
  static const ReplikaColors dark = ReplikaColors(
    chatBackground: Color(0xFF0B1014),
    bubbleIn: Color(0xFF1D2731),
    bubbleOut: Color(0xFF236FA8),
    bubbleInBorder: Color(0xFF2A3640),
    deletedBorder: Color(0xFF3A4855),
    deletedText: Color(0xFF8D9AA7),
    onBubbleIn: Color(0xFFE8EEF3),
    onBubbleOut: Color(0xFFFFFFFF),
    metaIn: Color(0xFF8D9AA7),
    metaOut: Color(0xFFE8F3FC),
    tickRead: Color(0xFFB4F2E4),
    textPrimary: Color(0xFFE8EEF3),
    textSecondary: Color(0xFF9AA8B5),
    textTertiary: Color(0xFF8794A1),
    divider: Color(0xFF2A3640),
    surfaceMuted: Color(0xFF1D2731),
    badge: Color(0xFF5AA9DE),
    badgeMuted: Color(0xFF7F8C99),
    onBadge: Color(0xFF06202F),
    draft: Color(0xFFF06A5F),
    daySeparator: Color(0xFF18222B),
    onDaySeparator: Color(0xFFA7B4BD),
    accent: Color(0xFFE8AE55),
    online: Color(0xFF4CC08A),
    success: Color(0xFF4CC08A),
    warning: Color(0xFFF0A43A),
    danger: Color(0xFFF06A5F),
    selection: Color(0x335AA9DE),
  );

  @override
  ReplikaColors copyWith({
    Color? chatBackground,
    Color? bubbleIn,
    Color? bubbleOut,
    Color? bubbleInBorder,
    Color? deletedBorder,
    Color? deletedText,
    Color? onBubbleIn,
    Color? onBubbleOut,
    Color? metaIn,
    Color? metaOut,
    Color? tickRead,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? surfaceMuted,
    Color? badge,
    Color? badgeMuted,
    Color? onBadge,
    Color? draft,
    Color? daySeparator,
    Color? onDaySeparator,
    Color? accent,
    Color? online,
    Color? success,
    Color? warning,
    Color? danger,
    Color? selection,
  }) {
    return ReplikaColors(
      chatBackground: chatBackground ?? this.chatBackground,
      bubbleIn: bubbleIn ?? this.bubbleIn,
      bubbleOut: bubbleOut ?? this.bubbleOut,
      bubbleInBorder: bubbleInBorder ?? this.bubbleInBorder,
      deletedBorder: deletedBorder ?? this.deletedBorder,
      deletedText: deletedText ?? this.deletedText,
      onBubbleIn: onBubbleIn ?? this.onBubbleIn,
      onBubbleOut: onBubbleOut ?? this.onBubbleOut,
      metaIn: metaIn ?? this.metaIn,
      metaOut: metaOut ?? this.metaOut,
      tickRead: tickRead ?? this.tickRead,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      badge: badge ?? this.badge,
      badgeMuted: badgeMuted ?? this.badgeMuted,
      onBadge: onBadge ?? this.onBadge,
      draft: draft ?? this.draft,
      daySeparator: daySeparator ?? this.daySeparator,
      onDaySeparator: onDaySeparator ?? this.onDaySeparator,
      accent: accent ?? this.accent,
      online: online ?? this.online,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      selection: selection ?? this.selection,
    );
  }

  @override
  ReplikaColors lerp(ThemeExtension<ReplikaColors>? other, double t) {
    if (other is! ReplikaColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ReplikaColors(
      chatBackground: mix(chatBackground, other.chatBackground),
      bubbleIn: mix(bubbleIn, other.bubbleIn),
      bubbleOut: mix(bubbleOut, other.bubbleOut),
      bubbleInBorder: mix(bubbleInBorder, other.bubbleInBorder),
      deletedBorder: mix(deletedBorder, other.deletedBorder),
      deletedText: mix(deletedText, other.deletedText),
      onBubbleIn: mix(onBubbleIn, other.onBubbleIn),
      onBubbleOut: mix(onBubbleOut, other.onBubbleOut),
      metaIn: mix(metaIn, other.metaIn),
      metaOut: mix(metaOut, other.metaOut),
      tickRead: mix(tickRead, other.tickRead),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      divider: mix(divider, other.divider),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      badge: mix(badge, other.badge),
      badgeMuted: mix(badgeMuted, other.badgeMuted),
      onBadge: mix(onBadge, other.onBadge),
      draft: mix(draft, other.draft),
      daySeparator: mix(daySeparator, other.daySeparator),
      onDaySeparator: mix(onDaySeparator, other.onDaySeparator),
      accent: mix(accent, other.accent),
      online: mix(online, other.online),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      selection: mix(selection, other.selection),
    );
  }
}
