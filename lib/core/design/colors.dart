import 'package:flutter/material.dart';

/// Смысловые цвета интерфейса «Реплики» для светлой и тёмной темы.
@immutable
class ReplikaColors extends ThemeExtension<ReplikaColors> {
  const ReplikaColors({
    required this.chatBackground,
    required this.bubbleIn,
    required this.bubbleOut,
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

  static const ReplikaColors light = ReplikaColors(
    chatBackground: Color(0xFFE8EDEB),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFF155E75),
    onBubbleIn: Color(0xFF15202B),
    onBubbleOut: Color(0xFFFFFFFF),
    metaIn: Color(0xFF8A969E),
    metaOut: Color(0xFFB7D3DB),
    tickRead: Color(0xFF8CE3D3),
    textPrimary: Color(0xFF15202B),
    textSecondary: Color(0xFF5B6770),
    textTertiary: Color(0xFF98A3AA),
    divider: Color(0xFFE1E6E8),
    surfaceMuted: Color(0xFFF1F4F5),
    badge: Color(0xFF155E75),
    badgeMuted: Color(0xFFA3AEB5),
    onBadge: Color(0xFFFFFFFF),
    draft: Color(0xFFC8372D),
    daySeparator: Color(0xFFD3DCD9),
    onDaySeparator: Color(0xFF4E5B63),
    accent: Color(0xFFE3A13B),
    online: Color(0xFF2F9E6E),
    success: Color(0xFF2F9E6E),
    warning: Color(0xFFD08A1E),
    danger: Color(0xFFC8372D),
    selection: Color(0x1F155E75),
  );

  static const ReplikaColors dark = ReplikaColors(
    chatBackground: Color(0xFF0E1418),
    bubbleIn: Color(0xFF1E272E),
    bubbleOut: Color(0xFF1B6F86),
    onBubbleIn: Color(0xFFE7ECEF),
    onBubbleOut: Color(0xFFFFFFFF),
    metaIn: Color(0xFF7F8C96),
    metaOut: Color(0xFFA9CAD4),
    tickRead: Color(0xFF8CE3D3),
    textPrimary: Color(0xFFE7ECEF),
    textSecondary: Color(0xFF9AA7B1),
    textTertiary: Color(0xFF6B7881),
    divider: Color(0xFF232C33),
    surfaceMuted: Color(0xFF1A2228),
    badge: Color(0xFF3E9BB5),
    badgeMuted: Color(0xFF4A565F),
    onBadge: Color(0xFF06181E),
    draft: Color(0xFFF06A5F),
    daySeparator: Color(0xFF1C262C),
    onDaySeparator: Color(0xFFA7B4BD),
    accent: Color(0xFFE8AE55),
    online: Color(0xFF4CC08A),
    success: Color(0xFF4CC08A),
    warning: Color(0xFFF0A43A),
    danger: Color(0xFFF06A5F),
    selection: Color(0x333E9BB5),
  );

  @override
  ReplikaColors copyWith({
    Color? chatBackground,
    Color? bubbleIn,
    Color? bubbleOut,
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
