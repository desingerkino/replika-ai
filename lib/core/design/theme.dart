import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

/// Темы приложения. Цветовая схема задана полностью вручную, без генерации
/// из одного цвета: так интерфейс не выглядит «шаблонным» Material.
abstract final class AppTheme {
  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final rc = isDark ? ReplikaColors.dark : ReplikaColors.light;
    final cs = isDark ? _darkScheme : _lightScheme;
    final text = AppType.textTheme(primary: rc.textPrimary, secondary: rc.textSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[rc],
      splashFactory: InkRipple.splashFactory,
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
