import 'package:sqflite/sqflite.dart';

import '../../core/util/db_values.dart';
import '../../core/util/ids.dart';
import '../../core/util/json.dart';
import '../db/tables.dart';
import '../models/scene.dart';
import '../models/scene_action.dart';
import '../models/take.dart';
import 'repository.dart';
import '../../core/util/media_paths.dart';

/// Сцена в списке операторской: с именем чата и числом действий.
class SceneListItem {
  const SceneListItem({
    required this.scene,
    required this.chatName,
    required this.actionCount,
    this.participantCount = 0,
  });

  final Scene scene;
  final String? chatName;
  final int actionCount;
  final int participantCount;
}

/// Участник сцены глазами телефона сцены.
class SceneParticipantRow {
  const SceneParticipantRow({
    required this.characterId,
    required this.name,
    this.avatarTone,
    this.avatarPath,
  });

  final String characterId;
  final String name;
  final int? avatarTone;
  final String? avatarPath;
}

class SceneRepository extends Repository {
  SceneRepository(super.database);

  /// Сцены телефона (и сцены без телефона), по номеру.
  Future<List<SceneListItem>> list(String deviceId) async {
    final rows = await db.rawQuery('''
      SELECT s.*,
        (SELECT COUNT(*) FROM scene_actions a WHERE a.scene_id = s.id) AS action_count,
        (SELECT COUNT(*) FROM scene_characters sc WHERE sc.scene_id = s.id) AS participant_count,
        COALESCE(dc.display_name, NULLIF(pc.phone, ''),
          NULLIF(TRIM(pc.first_name || ' ' || pc.last_name), ''), ch.title) AS chat_name
      FROM scenes s
      LEFT JOIN chats ch ON ch.id = s.chat_id
      LEFT JOIN characters pc ON pc.id = ch.peer_character_id
      LEFT JOIN device_contacts dc
        ON dc.device_id = ch.device_id AND dc.character_id = ch.peer_character_id
      WHERE s.device_id = ? OR s.device_id IS NULL
      ORDER BY s.created_at
    ''', [deviceId]);
    final items = rows
        .map((row) => SceneListItem(
              scene: Scene.fromRow(row),
              chatName: row['chat_name'] as String?,
              actionCount: readInt(row, 'action_count'),
              participantCount: readInt(row, 'participant_count'),
            ))
        .toList();
    items.sort((a, b) => _compareNumbers(a.scene.number, b.scene.number));
    return items;
  }

  Future<Scene?> byId(String id) async {
    final rows = await db.query(Tables.scenes, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Scene.fromRow(rows.first);
  }

  Future<String> create({
    required String deviceId,
    String? chatId,
    required String number,
    required String name,
    String? id,
  }) async {
    final now = DateTime.now();
    final scene = Scene(
      id: id ?? newId(),
      number: number,
      name: name,
      deviceId: deviceId,
      chatId: chatId,
      status: SceneStatus.ready,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert(Tables.scenes, scene.toRow());
    notify({Tables.scenes});
    return scene.id;
  }

  Future<void> update(String id, Map<String, Object?> fields) async {
    await db.update(
      Tables.scenes,
      {...fields, 'updated_at': dateToInt(DateTime.now())},
      where: 'id = ?',
      whereArgs: [id],
    );
    notify({Tables.scenes});
  }

  Future<void> setStatus(String id, SceneStatus status) => update(id, {'status': status.name});

  Future<void> delete(String id) async {
    await db.delete(Tables.scenes, where: 'id = ?', whereArgs: [id]);
    notify({Tables.scenes, Tables.sceneActions, Tables.takes});
  }

  /// Копия сцены со всеми действиями (ТЗ: «копия сцены»).
  Future<String> duplicate(String id) async {
    final source = await byId(id);
    if (source == null) throw StateError('Сцена не найдена');
    final now = DateTime.now();
    final copyId = newId();
    await db.transaction((txn) async {
      await txn.insert(Tables.scenes, {
        ...source.toRow(),
        'id': copyId,
        'name': '${source.name} (копия)',
        'status': SceneStatus.ready.name,
        'current_position': 0,
        'take_number': 0,
        'copied_from_id': source.id,
        'created_at': dateToInt(now),
        'updated_at': dateToInt(now),
      });
      final people = await txn.query(Tables.sceneCharacters, where: 'scene_id = ?', whereArgs: [id]);
      for (final row in people) {
        await txn.insert(Tables.sceneCharacters, {...row, 'scene_id': copyId});
      }
      final actions = await txn.query(Tables.sceneActions, where: 'scene_id = ?', whereArgs: [id]);
      for (final row in actions) {
        await txn.insert(Tables.sceneActions, {
          ...row,
          'id': newId(),
          'scene_id': copyId,
          'created_at': dateToInt(now),
          'updated_at': dateToInt(now),
        });
      }
    });
    notify({Tables.scenes, Tables.sceneActions});
    return copyId;
  }

  // ---------- Участники ----------

  /// Участники сцены в порядке добавления; имя — как записан на телефоне.
  Future<List<SceneParticipantRow>> participants(String sceneId, String deviceId) async {
    final rows = await db.rawQuery('''
      SELECT sc.character_id,
        COALESCE(dc.display_name, NULLIF(c.phone, ''),
          NULLIF(TRIM(c.first_name || ' ' || c.last_name), ''), 'Без имени') AS name,
        c.avatar_tone, m.path AS avatar_path
      FROM scene_characters sc
      JOIN characters c ON c.id = sc.character_id
      LEFT JOIN device_contacts dc ON dc.device_id = ? AND dc.character_id = sc.character_id
      LEFT JOIN media m ON m.id = c.avatar_media_id
      WHERE sc.scene_id = ?
      ORDER BY sc.rowid
    ''', [deviceId, sceneId]);
    return rows
        .map((r) => SceneParticipantRow(
              characterId: r['character_id'] as String,
              name: readString(r, 'name'),
              avatarTone: readIntOrNull(r, 'avatar_tone'),
              avatarPath: MediaPaths.resolveOrNull(readStringOrNull(r, 'avatar_path')),
            ))
        .toList();
  }

  Future<void> addParticipants(String sceneId, Iterable<String> characterIds) async {
    await db.transaction((txn) async {
      for (final id in characterIds) {
        await txn.insert(
          Tables.sceneCharacters,
          {'scene_id': sceneId, 'character_id': id, 'role': ''},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
    notify({Tables.sceneCharacters, Tables.scenes});
  }

  Future<void> removeParticipant(String sceneId, String characterId) async {
    await db.delete(
      Tables.sceneCharacters,
      where: 'scene_id = ? AND character_id = ?',
      whereArgs: [sceneId, characterId],
    );
    notify({Tables.sceneCharacters, Tables.scenes});
  }

  // ---------- Действия таймлайна ----------

  Future<List<SceneAction>> actions(String sceneId) async {
    final rows = await db.query(
      Tables.sceneActions,
      where: 'scene_id = ?',
      whereArgs: [sceneId],
      orderBy: 'position, created_at',
    );
    return rows.map(SceneAction.fromRow).toList();
  }

  Future<void> saveAction(SceneAction action) async {
    final exists = await db.query(Tables.sceneActions, columns: ['id'], where: 'id = ?', whereArgs: [action.id]);
    if (exists.isEmpty) {
      final last = await db.rawQuery(
        'SELECT COALESCE(MAX(position), -1) AS p FROM scene_actions WHERE scene_id = ?',
        [action.sceneId],
      );
      final position = ((last.first['p'] as num?)?.toInt() ?? -1) + 1;
      await db.insert(Tables.sceneActions, {...action.toRow(), 'position': position});
    } else {
      final row = action.toRow()..remove('position')..remove('created_at');
      await db.update(Tables.sceneActions, row, where: 'id = ?', whereArgs: [action.id]);
    }
    notify({Tables.sceneActions, Tables.scenes});
  }

  Future<void> deleteAction(String id) async {
    await db.delete(Tables.sceneActions, where: 'id = ?', whereArgs: [id]);
    notify({Tables.sceneActions, Tables.scenes});
  }

  /// Новый порядок действий (после перетаскивания).
  Future<void> reorder(List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(Tables.sceneActions, {'position': i}, where: 'id = ?', whereArgs: [orderedIds[i]]);
      }
    });
    notify({Tables.sceneActions});
  }

  // ---------- Дубли ----------

  Future<Take> startTake(String sceneId, Map<String, Object?> log) async {
    late Take take;
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE scenes SET take_number = take_number + 1, status = ? WHERE id = ?',
          [SceneStatus.running.name, sceneId]);
      final rows = await txn.query(Tables.scenes, columns: ['take_number'], where: 'id = ?', whereArgs: [sceneId]);
      final number = rows.isEmpty ? 1 : readInt(rows.first, 'take_number', 1);
      take = Take(
        id: newId(),
        sceneId: sceneId,
        number: number,
        startedAt: DateTime.now(),
        status: TakeStatus.running,
        logJson: encodeJsonMap(log),
      );
      await txn.insert(Tables.takes, take.toRow());
    });
    notify({Tables.takes, Tables.scenes});
    return take;
  }

  Future<void> saveTakeLog(String takeId, Map<String, Object?> log) async {
    await db.update(Tables.takes, {'log_json': encodeJsonMap(log)}, where: 'id = ?', whereArgs: [takeId]);
  }

  Future<void> finishTake(String takeId, TakeStatus status) async {
    await db.update(
      Tables.takes,
      {'status': status.name, 'finished_at': dateToInt(DateTime.now())},
      where: 'id = ?',
      whereArgs: [takeId],
    );
    notify({Tables.takes});
  }

  Future<Take?> lastTake(String sceneId) async {
    final rows = await db.query(
      Tables.takes,
      where: 'scene_id = ?',
      whereArgs: [sceneId],
      orderBy: 'number DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Take.fromRow(rows.first);
  }

  Future<List<Take>> takes(String sceneId) async {
    final rows = await db.query(Tables.takes, where: 'scene_id = ?', whereArgs: [sceneId], orderBy: 'number DESC');
    return rows.map(Take.fromRow).toList();
  }
}

/// «2» < «10» < «12А»: сначала число, потом буквы.
int _compareNumbers(String a, String b) {
  final na = int.tryParse(RegExp(r'^\d+').stringMatch(a) ?? '');
  final nb = int.tryParse(RegExp(r'^\d+').stringMatch(b) ?? '');
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  if (na != null && nb == null) return -1;
  if (na == null && nb != null) return 1;
  return a.compareTo(b);
}
