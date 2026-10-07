import 'package:sqflite/sqflite.dart';

import '../db/tables.dart';
import 'repository.dart';

abstract final class SettingKeys {
  static const String currentDeviceId = 'current_device_id';
  static const String seedVersion = 'seed_version';
  static const String themeMode = 'theme_mode';
  static const String activeSceneId = 'active_scene_id';
  static const String volumeKeys = 'volume_keys';
  static const String resetToast = 'reset_toast';
  static const String kino = 'kino_mode';
  static const String notifications = 'notifications';
  static const String connectEnabled = 'connect_enabled';
  static const String connectBackground = 'connect_background';
  static const String connectShooting = 'connect_shooting';
  static const String connectDeviceName = 'connect_device_name';
  static const String connectDone = 'connect_done_commands';
  static const String stories = 'stories_v1';
}

/// Настройки приложения «ключ — значение».
class SettingsRepository extends Repository {
  SettingsRepository(super.database);

  Future<String?> getValue(String key) async {
    final rows = await db.query(
      Tables.settings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setValue(String key, String? value) async {
    if (value == null) {
      await db.delete(Tables.settings, where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert(
        Tables.settings,
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    notify({Tables.settings});
  }
}
