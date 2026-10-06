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
    primary: Palette.petrol,
    onPrimary: Palette.white,
    primaryContainer: Color(0xFFD3E8EE),
    onPrimaryContainer: Color(0xFF0B3542),
    secondary: Color(0xFF4F6470),
    onSecondary: Palette.white,
    secondaryContainer: Color(0xFFDDE6EA),
    onSecondaryContainer: Color(0xFF1B2A33),
    tertiary: Palette.tungsten,
    onTertiary: Color(0xFF2A1A00),
    error: Palette.danger,
    onError: Palette.white,
    surface: Palette.white,
    onSurface: Palette.ink,
    onSurfaceVariant: Color(0xFF5B6770),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Palette.white,
    surfaceContainerLow: Color(0xFFF6F8F9),
    surfaceContainer: Color(0xFFF1F4F5),
    surfaceContainerHigh: Color(0xFFEAEEF0),
    surfaceContainerHighest: Color(0xFFE3E8EA),
    outline: Color(0xFFA9B4BA),
    outlineVariant: Color(0xFFDCE2E5),
    inverseSurface: Color(0xFF1F2A33),
    onInverseSurface: Color(0xFFEFF3F5),
    inversePrimary: Color(0xFF8CCBDD),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF5BB3CB),
    onPrimary: Color(0xFF04212A),
    primaryContainer: Color(0xFF16495A),
    onPrimaryContainer: Color(0xFFCDEAF2),
    secondary: Color(0xFF9FB2BD),
    onSecondary: Color(0xFF15232B),
    secondaryContainer: Color(0xFF26343C),
    onSecondaryContainer: Color(0xFFDCE6EB),
    tertiary: Color(0xFFE8AE55),
    onTertiary: Color(0xFF2A1A00),
    error: Color(0xFFF06A5F),
    onError: Color(0xFF2B0503),
    surface: Color(0xFF11181D),
    onSurface: Color(0xFFE7ECEF),
    onSurfaceVariant: Color(0xFF9AA7B1),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFF0B1115),
    surfaceContainerLow: Color(0xFF151D22),
    surfaceContainer: Color(0xFF1A2228),
    surfaceContainerHigh: Color(0xFF20292F),
    surfaceContainerHighest: Color(0xFF273137),
    outline: Color(0xFF56636C),
    outlineVariant: Color(0xFF2B343C),
    inverseSurface: Color(0xFFE3E9EC),
    onInverseSurface: Color(0xFF1A2228),
    inversePrimary: Palette.petrol,
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
