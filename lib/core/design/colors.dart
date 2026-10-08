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
    required this.alert,
    required this.chatPattern,
    required this.navBar,
    required this.navIndicator,
    required this.onNavIndicator,
    required this.rowHighlight,
    required this.storyRingStart,
    required this.storyRingEnd,
    required this.storySeen,
    required this.groupedBackground,
    required this.groupedCell,
    required this.glass,
    required this.glassBorder,
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

  /// Красный бейдж непрочитанных на значке вкладки «Чаты».
  final Color alert;

  /// Штрих «дудл»-узора на фоне переписки (тема Telegram).
  final Color chatPattern;

  /// Нижняя панель вкладок и её активная «таблетка».
  final Color navBar;
  final Color navIndicator;
  final Color onNavIndicator;

  /// Подсветка закреплённой строки списка.
  final Color rowHighlight;

  /// Кольцо непросмотренной истории (градиент) и просмотренной.
  final Color storyRingStart;
  final Color storyRingEnd;
  final Color storySeen;

  /// Сгруппированные настройки iOS: фон экрана и ячейки-карточки.
  final Color groupedBackground;
  final Color groupedCell;

  /// Стекло плавающих панелей (под размытием) и его тонкая граница.
  final Color glass;
  final Color glassBorder;

  static const ReplikaColors light = ReplikaColors(
    chatBackground: Color(0xFFE9ECF1),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFF3D5CFF),
    onBubbleIn: Color(0xFF15202B),
    onBubbleOut: Color(0xFFFFFFFF),
    metaIn: Color(0xFF8A929C),
    metaOut: Color(0xFFC9D3FF),
    tickRead: Color(0xFF8CE3D3),
    textPrimary: Color(0xFF15202B),
    textSecondary: Color(0xFF646A73),
    textTertiary: Color(0xFF8B919A),
    divider: Color(0xFFE1E4E8),
    surfaceMuted: Color(0xFFEAECF0),
    badge: Color(0xFF3D5CFF),
    badgeMuted: Color(0xFF8E949C),
    onBadge: Color(0xFFFFFFFF),
    draft: Color(0xFFC8372D),
    daySeparator: Color(0xFFD6DBE3),
    onDaySeparator: Color(0xFF4E5662),
    accent: Color(0xFFE3A13B),
    online: Color(0xFF34C759),
    success: Color(0xFF2F9E6E),
    warning: Color(0xFFD08A1E),
    danger: Color(0xFFC8372D),
    selection: Color(0x1F3D5CFF),
    alert: Color(0xFFFF383C),
    chatPattern: Color(0x00000000),
    navBar: Color(0xD6F6F6F6),
    navIndicator: Color(0x12141820),
    onNavIndicator: Color(0xFF3D5CFF),
    rowHighlight: Color(0x00000000),
    storyRingStart: Color(0xFF3D5CFF),
    storyRingEnd: Color(0xFFCB30E0),
    storySeen: Color(0xFFC9CDD4),
    groupedBackground: Color(0xFFF2F2F7),
    groupedCell: Color(0xFFFFFFFF),
    glass: Color(0xD6F6F6F6),
    glassBorder: Color(0x14141820),
  );

  static const ReplikaColors dark = ReplikaColors(
    chatBackground: Color(0xFF0D1015),
    bubbleIn: Color(0xFF1E2229),
    bubbleOut: Color(0xFF3550E0),
    onBubbleIn: Color(0xFFE7ECEF),
    onBubbleOut: Color(0xFFFFFFFF),
    metaIn: Color(0xFF7F8791),
    metaOut: Color(0xFFC2CCFF),
    tickRead: Color(0xFF8CE3D3),
    textPrimary: Color(0xFFE7ECEF),
    textSecondary: Color(0xFF9AA0AA),
    textTertiary: Color(0xFF6B727C),
    divider: Color(0xFF262A31),
    surfaceMuted: Color(0xFF1B1F26),
    badge: Color(0xFF7C93FF),
    badgeMuted: Color(0xFF4A515A),
    onBadge: Color(0xFF0B0C12),
    draft: Color(0xFFF06A5F),
    daySeparator: Color(0xFF1C2028),
    onDaySeparator: Color(0xFFA7AEB9),
    accent: Color(0xFFE8AE55),
    online: Color(0xFF30D158),
    success: Color(0xFF4CC08A),
    warning: Color(0xFFF0A43A),
    danger: Color(0xFFF06A5F),
    selection: Color(0x337C93FF),
    alert: Color(0xFFFF4245),
    chatPattern: Color(0x00000000),
    navBar: Color(0xD11C1F26),
    navIndicator: Color(0x1FFFFFFF),
    onNavIndicator: Color(0xFF7C93FF),
    rowHighlight: Color(0x00000000),
    storyRingStart: Color(0xFF7C93FF),
    storyRingEnd: Color(0xFFCB30E0),
    storySeen: Color(0xFF3A3F47),
    groupedBackground: Color(0xFF0D1015),
    groupedCell: Color(0xFF1B1F26),
    glass: Color(0xD11C1F26),
    glassBorder: Color(0x1FFFFFFF),
  );

  /// Тема «Telegram» (палитра v2): системные поверхности и текст iOS,
  /// синий мессенджера для действий и пузырей.
  static const ReplikaColors telegramLight = ReplikaColors(
    chatBackground: Color(0xFFD5E1EC),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFF2B86FD),
    onBubbleIn: Color(0xFF1C1C1E),
    onBubbleOut: Color(0xFFFFFFFF),
    metaIn: Color(0xFF8E8E93),
    metaOut: Color(0xE6FFFFFF),
    tickRead: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF636366),
    textTertiary: Color(0xFF8E8E93),
    divider: Color(0xFFD1D1D6),
    surfaceMuted: Color(0xFFEFEFF4),
    badge: Color(0xFF007AFF),
    badgeMuted: Color(0xFFAEAEB2),
    onBadge: Color(0xFFFFFFFF),
    draft: Color(0xFFFF3B30),
    daySeparator: Color(0x8C3C3C43),
    onDaySeparator: Color(0xFFFFFFFF),
    accent: Color(0xFF0088FF),
    online: Color(0xFF34C759),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9500),
    danger: Color(0xFFFF3B30),
    selection: Color(0x1F007AFF),
    alert: Color(0xFF007AFF),
    chatPattern: Color(0x4D6E8CAA),
    navBar: Color(0xB8FFFFFF),
    navIndicator: Color(0x1F007AFF),
    onNavIndicator: Color(0xFF007AFF),
    rowHighlight: Color(0xFFF2F2F7),
    storyRingStart: Color(0xFF007AFF),
    storyRingEnd: Color(0xFF5AC8FA),
    storySeen: Color(0xFFC7C7CC),
    groupedBackground: Color(0xFFF2F2F7),
    groupedCell: Color(0xFFFFFFFF),
    glass: Color(0xD6FFFFFF),
    glassBorder: Color(0x2E3C3C43),
  );

  static const ReplikaColors telegramDark = ReplikaColors(
    chatBackground: Color(0xFF0E1117),
    bubbleIn: Color(0xFF2C2C2E),
    bubbleOut: Color(0xFF2B86FD),
    onBubbleIn: Color(0xFFFFFFFF),
    onBubbleOut: Color(0xFFFFFFFF),
    metaIn: Color(0xFF98989F),
    metaOut: Color(0xE6FFFFFF),
    tickRead: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFAEAEB2),
    textTertiary: Color(0xFF8E8E93),
    divider: Color(0xFF38383A),
    surfaceMuted: Color(0xFF1C1C1E),
    badge: Color(0xFF0A84FF),
    badgeMuted: Color(0xFF636366),
    onBadge: Color(0xFFFFFFFF),
    draft: Color(0xFFFF453A),
    daySeparator: Color(0xB3000000),
    onDaySeparator: Color(0xFFFFFFFF),
    accent: Color(0xFF0A84FF),
    online: Color(0xFF30D158),
    success: Color(0xFF30D158),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    selection: Color(0x330A84FF),
    alert: Color(0xFF0A84FF),
    chatPattern: Color(0x26A9B8D8),
    navBar: Color(0xB81C1C1E),
    navIndicator: Color(0x330A84FF),
    onNavIndicator: Color(0xFF0A84FF),
    rowHighlight: Color(0xFF1C1C1E),
    storyRingStart: Color(0xFF0A84FF),
    storyRingEnd: Color(0xFF64D2FF),
    storySeen: Color(0xFF48484A),
    groupedBackground: Color(0xFF000000),
    groupedCell: Color(0xFF1C1C1E),
    glass: Color(0xC71C1C1E),
    glassBorder: Color(0x29FFFFFF),
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
    Color? alert,
    Color? chatPattern,
    Color? navBar,
    Color? navIndicator,
    Color? onNavIndicator,
    Color? rowHighlight,
    Color? storyRingStart,
    Color? storyRingEnd,
    Color? storySeen,
    Color? groupedBackground,
    Color? groupedCell,
    Color? glass,
    Color? glassBorder,
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
      alert: alert ?? this.alert,
      chatPattern: chatPattern ?? this.chatPattern,
      navBar: navBar ?? this.navBar,
      navIndicator: navIndicator ?? this.navIndicator,
      onNavIndicator: onNavIndicator ?? this.onNavIndicator,
      rowHighlight: rowHighlight ?? this.rowHighlight,
      storyRingStart: storyRingStart ?? this.storyRingStart,
      storyRingEnd: storyRingEnd ?? this.storyRingEnd,
      storySeen: storySeen ?? this.storySeen,
      groupedBackground: groupedBackground ?? this.groupedBackground,
      groupedCell: groupedCell ?? this.groupedCell,
      glass: glass ?? this.glass,
      glassBorder: glassBorder ?? this.glassBorder,
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
      alert: mix(alert, other.alert),
      chatPattern: mix(chatPattern, other.chatPattern),
      navBar: mix(navBar, other.navBar),
      navIndicator: mix(navIndicator, other.navIndicator),
      onNavIndicator: mix(onNavIndicator, other.onNavIndicator),
      rowHighlight: mix(rowHighlight, other.rowHighlight),
      storyRingStart: mix(storyRingStart, other.storyRingStart),
      storyRingEnd: mix(storyRingEnd, other.storyRingEnd),
      storySeen: mix(storySeen, other.storySeen),
      groupedBackground: mix(groupedBackground, other.groupedBackground),
      groupedCell: mix(groupedCell, other.groupedCell),
      glass: mix(glass, other.glass),
      glassBorder: mix(glassBorder, other.glassBorder),
    );
  }
}
