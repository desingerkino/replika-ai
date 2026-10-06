import '../../core/util/db_values.dart';
import '../db/tables.dart';
import '../models/call_record.dart';
import 'repository.dart';
import '../../core/util/media_paths.dart';

/// Строка истории звонков: запись и то, как собеседник записан на телефоне.
class CallListItem {
  const CallListItem({required this.call, required this.displayName, this.avatarTone, this.avatarPath});

  final CallRecord call;
  final String displayName;
  final int? avatarTone;
  final String? avatarPath;
}

class CallRepository extends Repository {
  CallRepository(super.database);

  Future<void> insert(CallRecord call) async {
    await db.insert(Tables.calls, call.toRow());
    notify({Tables.calls});
  }

  Future<List<CallListItem>> forDevice(String deviceId) async {
    final rows = await db.rawQuery('''
      SELECT cl.*,
        COALESCE(dc.display_name, NULLIF(c.phone, ''),
          NULLIF(TRIM(c.first_name || ' ' || c.last_name), ''), 'Неизвестный') AS display_name,
        c.avatar_tone AS avatar_tone, m.path AS avatar_path
      FROM calls cl
      LEFT JOIN characters c ON c.id = cl.character_id
      LEFT JOIN device_contacts dc ON dc.device_id = cl.device_id AND dc.character_id = cl.character_id
      LEFT JOIN media m ON m.id = c.avatar_media_id
      WHERE cl.device_id = ?
      ORDER BY cl.started_at DESC
      LIMIT 300
    ''', [deviceId]);
    return rows
        .map((row) => CallListItem(
              call: CallRecord.fromRow(row),
              displayName: readString(row, 'display_name', 'Неизвестный'),
              avatarTone: readIntOrNull(row, 'avatar_tone'),
              avatarPath: MediaPaths.resolveOrNull(readStringOrNull(row, 'avatar_path')),
            ))
        .toList();
  }

  Future<void> deleteById(String id) => delete(id);

  Future<void> delete(String id) async {
    await db.delete(Tables.calls, where: 'id = ?', whereArgs: [id]);
    notify({Tables.calls});
  }

  /// Звонки, добавленные сценой (для «СБРОС СЦЕНЫ»).
  Future<void> deleteScene(String sceneId) async {
    await db.delete(Tables.calls, where: 'scene_id = ?', whereArgs: [sceneId]);
    notify({Tables.calls});
  }
}
