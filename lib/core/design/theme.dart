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
      fontFamily: AppType.fontFamily,
      brightness: brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[rc],
      splashFactory: InkRipple.splashFactory,
      dividerTheme: DividerThemeData(color: rc.divider, thickness: Sizes.line, space: Sizes.line),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: cs.primary,
        selectionColor: cs.primary.withValues(alpha: 0.24),
        selectionHandleColor: cs.primary,
      ),
      // Нижняя навигация и боковая панель iPad: спокойная подсветка выбранного
      // раздела (мягкий прямоугольник вместо пилюли Material), тот же синий для
      // значка и подписи, выбранный раздел — ещё и заполненный значок и жирнее подпись.
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: rc.selection,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed) ? rc.selection : Colors.transparent,
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? cs.primary : rc.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? cs.primary : rc.textSecondary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cs.surface,
        indicatorColor: rc.selection,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
        selectedIconTheme: IconThemeData(size: 24, color: cs.primary),
        unselectedIconTheme: IconThemeData(size: 24, color: rc.textSecondary),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w500,
          color: rc.textSecondary,
        ),
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
    primary: Palette.blue,
    onPrimary: Palette.white,
    primaryContainer: Color(0xFFD6E7F4),
    onPrimaryContainer: Color(0xFF0B3552),
    secondary: Color(0xFF52667A),
    onSecondary: Palette.white,
    secondaryContainer: Color(0xFFDDE6EE),
    onSecondaryContainer: Color(0xFF1B2A36),
    tertiary: Palette.tungsten,
    onTertiary: Color(0xFF2A1A00),
    error: Palette.danger,
    onError: Palette.white,
    surface: Palette.white,
    onSurface: Color(0xFF1B232B),
    onSurfaceVariant: Color(0xFF5A6773),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Palette.white,
    surfaceContainerLow: Color(0xFFF6F9FB),
    surfaceContainer: Color(0xFFEEF3F7),
    surfaceContainerHigh: Color(0xFFE6EDF3),
    surfaceContainerHighest: Color(0xFFDDE5EC),
    outline: Color(0xFFA3B0BC),
    outlineVariant: Color(0xFFDDE5EC),
    inverseSurface: Color(0xFF1F2A33),
    onInverseSurface: Color(0xFFEFF3F5),
    inversePrimary: Palette.blueBright,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Palette.blueBright,
    onPrimary: Color(0xFF06202F),
    primaryContainer: Color(0xFF17496E),
    onPrimaryContainer: Color(0xFFD3E8F7),
    secondary: Color(0xFF9FB2BD),
    onSecondary: Color(0xFF15232B),
    secondaryContainer: Color(0xFF26343C),
    onSecondaryContainer: Color(0xFFDCE6EB),
    tertiary: Color(0xFFE8AE55),
    onTertiary: Color(0xFF2A1A00),
    error: Color(0xFFF06A5F),
    onError: Color(0xFF2B0503),
    surface: Color(0xFF0F151A),
    onSurface: Color(0xFFE8EEF3),
    onSurfaceVariant: Color(0xFF9AA8B5),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFF0B1014),
    surfaceContainerLow: Color(0xFF141C23),
    surfaceContainer: Color(0xFF18222A),
    surfaceContainerHigh: Color(0xFF1D2731),
    surfaceContainerHighest: Color(0xFF25313C),
    outline: Color(0xFF5A6773),
    outlineVariant: Color(0xFF2A3640),
    inverseSurface: Color(0xFFE3E9EC),
    onInverseSurface: Color(0xFF1A2228),
    inversePrimary: Palette.blue,
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
