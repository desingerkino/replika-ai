import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'app_theme_id.dart';

/// Ключи настроек оформления (таблица settings).
abstract final class ThemeSettingKeys {
  static const String themeId = 'theme_id';
  static const String themeMode = 'theme_mode';
}

/// Хранит выбранную тему оформления и яркость, отдаёт готовые ThemeData.
///
/// Сохранение — через [persist] (ключ, значение): менеджер не знает про
/// базу и легко проверяется автотестом.
class ThemeManager extends ChangeNotifier {
  ThemeManager({
    AppThemeId id = AppThemeId.fallback,
    ThemeMode mode = ThemeMode.system,
    Future<void> Function(String key, String value)? persist,
  })  : themeId = ValueNotifier<AppThemeId>(id),
        themeMode = ValueNotifier<ThemeMode>(mode),
        _persist = persist {
    themeId.addListener(notifyListeners);
    themeMode.addListener(notifyListeners);
  }

  /// Восстанавливает выбор из сохранённых строк (null — по умолчанию).
  factory ThemeManager.restore({
    String? savedId,
    String? savedMode,
    Future<void> Function(String key, String value)? persist,
  }) {
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == savedMode,
      orElse: () => ThemeMode.system,
    );
    return ThemeManager(id: AppThemeId.parse(savedId), mode: mode, persist: persist);
  }

  final Future<void> Function(String key, String value)? _persist;

  /// Текущая тема оформления (Replika, Telegram…).
  final ValueNotifier<AppThemeId> themeId;

  /// Как в системе, светлая или тёмная.
  final ValueNotifier<ThemeMode> themeMode;

  AppThemeId get id => themeId.value;
  ThemeMode get mode => themeMode.value;

  ThemeData get light => AppTheme.build(id, Brightness.light);
  ThemeData get dark => AppTheme.build(id, Brightness.dark);

  /// Мгновенное переключение: новое значение сразу уходит в MaterialApp.
  Future<void> setTheme(AppThemeId id) async {
    if (themeId.value == id) return;
    themeId.value = id;
    await _persist?.call(ThemeSettingKeys.themeId, id.name);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (themeMode.value == mode) return;
    themeMode.value = mode;
    await _persist?.call(ThemeSettingKeys.themeMode, mode.name);
  }

  @override
  void dispose() {
    themeId.removeListener(notifyListeners);
    themeMode.removeListener(notifyListeners);
    themeId.dispose();
    themeMode.dispose();
    super.dispose();
  }
}
