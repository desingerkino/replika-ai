import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_style.dart';
import '../theme/app_theme_id.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

/// Темы приложения. Цветовая схема задана полностью вручную, без генерации
/// из одного цвета: так интерфейс не выглядит «шаблонным» Material.
///
/// [build] собирает ThemeData для пары «тема оформления + яркость».
/// Готовые ThemeData кэшируются: переключение темы мгновенное.
abstract final class AppTheme {
  /// Фирменная тема «Реплики» (оператор, автотесты, экран запуска).
  static final ThemeData light = build(AppThemeId.replika, Brightness.light);
  static final ThemeData dark = build(AppThemeId.replika, Brightness.dark);

  static final Map<(AppThemeId, Brightness), ThemeData> _cache = {};

  static ThemeData build(AppThemeId id, Brightness brightness) =>
      _cache[(id, brightness)] ??= _build(id, brightness);

  static (ColorScheme, ReplikaColors) _palette(AppThemeId id, bool isDark) => switch (id) {
        AppThemeId.replika => isDark ? (_darkScheme, ReplikaColors.dark) : (_lightScheme, ReplikaColors.light),
        AppThemeId.telegram =>
          isDark ? (_telegramDarkScheme, ReplikaColors.telegramDark) : (_telegramLightScheme, ReplikaColors.telegramLight),
      };

  static ThemeData _build(AppThemeId id, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final (cs, rc) = _palette(id, isDark);
    final style = AppStyle.of(id);
    final text = AppType.textTheme(primary: rc.textPrimary, secondary: rc.textSecondary);

    return ThemeData(
      useMaterial3: true,
      // Один шрифт на обеих платформах: Roboto из ресурсов приложения.
      fontFamily: AppType.family,
      brightness: brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[rc, style],
      splashFactory: InkRipple.splashFactory,
      // Переходы и прокрутка как в iOS на обеих платформах.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? cs.onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? cs.primary : null,
        ),
      ),
      dividerTheme: DividerThemeData(color: rc.divider, thickness: 0.6, space: 0.6),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: cs.primary,
        selectionColor: cs.primary.withValues(alpha: 0.24),
        selectionHandleColor: cs.primary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? cs.onPrimaryContainer : rc.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? rc.textPrimary : rc.textSecondary,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        modalBackgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: TextStyle(color: cs.onInverseSurface, fontSize: 15, height: 20 / 15),
        actionTextColor: cs.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, Sizes.minTouch),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Нажатая кнопка темнеет (#0066D6 для синего iOS), а не «плывёт» волной.
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.black,
          minimumSize: const Size(64, Sizes.minTouch),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
        ),
      ),
    );
  }

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Palette.brand,
    onPrimary: Palette.white,
    primaryContainer: Color(0xFFDDE3FF),
    onPrimaryContainer: Color(0xFF0F1F70),
    secondary: Color(0xFF4F5663),
    onSecondary: Palette.white,
    secondaryContainer: Color(0xFFE3E6EC),
    onSecondaryContainer: Color(0xFF1B212B),
    tertiary: Palette.tungsten,
    onTertiary: Color(0xFF2A1A00),
    error: Palette.danger,
    onError: Palette.white,
    surface: Palette.white,
    onSurface: Palette.ink,
    onSurfaceVariant: Color(0xFF646A73),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Palette.white,
    surfaceContainerLow: Color(0xFFF6F7F9),
    surfaceContainer: Color(0xFFF1F3F6),
    surfaceContainerHigh: Color(0xFFEAECF0),
    surfaceContainerHighest: Color(0xFFE1E4E8),
    outline: Color(0xFFA7ADB6),
    outlineVariant: Color(0xFFE1E4E8),
    inverseSurface: Color(0xFF1F242C),
    onInverseSurface: Color(0xFFEFF1F5),
    inversePrimary: Palette.brandBright,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Palette.brandBright,
    onPrimary: Color(0xFF0B1030),
    primaryContainer: Color(0xFF27338A),
    onPrimaryContainer: Color(0xFFDDE3FF),
    secondary: Color(0xFFA3AAB6),
    onSecondary: Color(0xFF151A22),
    secondaryContainer: Color(0xFF282D36),
    onSecondaryContainer: Color(0xFFDCE1EA),
    tertiary: Color(0xFFE8AE55),
    onTertiary: Color(0xFF2A1A00),
    error: Color(0xFFF06A5F),
    onError: Color(0xFF2B0503),
    surface: Color(0xFF0D1015),
    onSurface: Color(0xFFE7ECEF),
    onSurfaceVariant: Color(0xFF9AA0AA),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFF080A0E),
    surfaceContainerLow: Color(0xFF12151B),
    surfaceContainer: Color(0xFF171A21),
    surfaceContainerHigh: Color(0xFF1B1F26),
    surfaceContainerHighest: Color(0xFF242830),
    outline: Color(0xFF5A606A),
    outlineVariant: Color(0xFF262A31),
    inverseSurface: Color(0xFFE3E7EE),
    onInverseSurface: Color(0xFF1B1F26),
    inversePrimary: Palette.brand,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  /// Telegram, светлая (палитра v2): фон #FFFFFF, вторичный #F2F2F7,
  /// текст #1C1C1E / #636366 / #8E8E93, разделители #D1D1D6, синий #007AFF.
  static const ColorScheme _telegramLightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF007AFF),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE5F1FF),
    onPrimaryContainer: Color(0xFF003A7A),
    secondary: Color(0xFF636366),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF2F2F7),
    onSecondaryContainer: Color(0xFF1C1C1E),
    tertiary: Color(0xFFFF9500),
    onTertiary: Color(0xFF3A2200),
    error: Color(0xFFFF3B30),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1C1C1E),
    onSurfaceVariant: Color(0xFF636366),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF9F9FB),
    surfaceContainer: Color(0xFFF2F2F7),
    surfaceContainerHigh: Color(0xFFEFEFF4),
    surfaceContainerHighest: Color(0xFFE5E5EA),
    outline: Color(0xFFC7C7CC),
    outlineVariant: Color(0xFFD1D1D6),
    inverseSurface: Color(0xFF1C1C1E),
    onInverseSurface: Color(0xFFF2F2F7),
    inversePrimary: Color(0xFF0A84FF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme _telegramDarkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF0A84FF),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF0A3A6B),
    onPrimaryContainer: Color(0xFFD6E9FF),
    secondary: Color(0xFF8E8E93),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF2C2C2E),
    onSecondaryContainer: Color(0xFFFFFFFF),
    tertiary: Color(0xFFFF9F0A),
    onTertiary: Color(0xFF3A2200),
    error: Color(0xFFFF453A),
    onError: Color(0xFF2B0503),
    surface: Color(0xFF000000),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFAEAEB2),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF0E0E10),
    surfaceContainer: Color(0xFF1C1C1E),
    surfaceContainerHigh: Color(0xFF232325),
    surfaceContainerHighest: Color(0xFF2C2C2E),
    outline: Color(0xFF545458),
    outlineVariant: Color(0xFF38383A),
    inverseSurface: Color(0xFFF2F2F7),
    onInverseSurface: Color(0xFF1C1C1E),
    inversePrimary: Color(0xFF007AFF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  /// Стиль системных панелей: прозрачные, значки контрастны теме.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final iconBrightness =
        brightness == Brightness.dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
    );
  }
}
