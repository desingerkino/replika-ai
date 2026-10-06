import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/util/ids.dart';
import 'db/db_changes.dart';
import 'db/schema.dart';
import 'db/tables.dart';
import '../core/util/media_paths.dart';

/// Формат файла профиля.
const String profileFormat = 'replika-profile';
const int profileFormatVersion = 1;

/// Ошибка импорта с понятным текстом.
class ProfileImportException implements Exception {
  const ProfileImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Экспорт и импорт профиля (виртуального телефона персонажа).
///
/// В файл входит всё содержимое телефона: владелец и персонажи его
/// контактов, контакты, чаты и участники групп, сообщения, звонки, сцены
/// этого телефона (участники, события, история дублей) и — по желанию —
/// файлы вложений.
///
/// При импорте всё, что принадлежит профилю, получает новые id: один файл
/// можно импортировать повторно, ничего не перезаписав. Персонажи проекта
/// общие для всех профилей: существующий персонаж используется как есть.
class ProfileTransfer {
  ProfileTransfer(this.db, this.changes, {required this.mediaDir});

  final Database db;
  final DbChanges changes;

  /// Папка медиатеки (для записи файлов вложений при импорте).
  final Future<Directory> Function() mediaDir;

  Future<List<Map<String, Object?>>> _q(String sql, [List<Object?> args = const []]) async =>
      [for (final r in await db.rawQuery(sql, args)) Map<String, Object?>.from(r)];

  static String _in(int n) => List.filled(n, '?').join(', ');

  Future<Map<String, Object?>> export(String deviceId, {bool includeMedia = true}) async {
    final device = await _q('SELECT * FROM devices WHERE id = ?', [deviceId]);
    if (device.isEmpty) throw const ProfileImportException('Профиль не найден');
    final chats = await _q('SELECT * FROM chats WHERE device_id = ?', [deviceId]);
    final chatIds = [for (final c in chats) c['id'] as String];
    final members = chatIds.isEmpty
        ? <Map<String, Object?>>[]
        : await _q('SELECT * FROM chat_members WHERE chat_id IN (${_in(chatIds.length)})', chatIds);
    final messages = chatIds.isEmpty
        ? <Map<String, Object?>>[]
        : await _q('SELECT * FROM messages WHERE chat_id IN (${_in(chatIds.length)})', chatIds);
    final contacts = await _q('SELECT * FROM device_contacts WHERE device_id = ?', [deviceId]);
    final calls = await _q('SELECT * FROM calls WHERE device_id = ?', [deviceId]);
    final scenes = await _q('SELECT * FROM scenes WHERE device_id = ?', [deviceId]);
    final sceneIds = [for (final s in scenes) s['id'] as String];
    Future<List<Map<String, Object?>>> byScene(String table) async => sceneIds.isEmpty
        ? <Map<String, Object?>>[]
        : await _q('SELECT * FROM $table WHERE scene_id IN (${_in(sceneIds.length)})', sceneIds);
    final sceneCharacters = await byScene(Tables.sceneCharacters);
    final sceneActions = await byScene(Tables.sceneActions);
    final takes = await byScene(Tables.takes);

    // Персонажи: владелец и все, кто встречается в данных телефона.
    final characterIds = <String>{
      device.first['owner_character_id'] as String,
      for (final c in contacts) c['character_id'] as String,
      for (final c in chats)
        if (c['peer_character_id'] != null) c['peer_character_id'] as String,
      for (final m in members) m['character_id'] as String,
      for (final m in messages)
        if (m['sender_id'] != null) m['sender_id'] as String,
      for (final c in calls)
        if (c['character_id'] != null) c['character_id'] as String,
      for (final s in sceneCharacters) s['character_id'] as String,
    };
    final characters = await _q(
        'SELECT * FROM characters WHERE id IN (${_in(characterIds.length)})', characterIds.toList());

    // Вложения: из сообщений, аватаров и материалов звонков, событий сцен.
    final mediaIds = <String>{
      for (final m in messages)
        if (m['media_id'] != null) m['media_id'] as String,
      for (final c in characters)
        for (final key in const ['avatar_media_id', 'call_audio_media_id', 'call_video_media_id'])
          if (c[key] != null) c[key] as String,
      for (final a in sceneActions)
        if (_params(a)['mediaId'] is String) _params(a)['mediaId'] as String,
    };
    final media = <Map<String, Object?>>[];
    if (includeMedia && mediaIds.isNotEmpty) {
      for (final row in await _q('SELECT * FROM media WHERE id IN (${_in(mediaIds.length)})', mediaIds.toList())) {
        final file = File(MediaPaths.resolve(row['path'] as String));
        media.add({...row, if (file.existsSync()) 'data': base64Encode(await file.readAsBytes())});
      }
    }

    return {
      'format': profileFormat,
      'formatVersion': profileFormatVersion,
      'schemaVersion': Schema.version,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'device': device.first,
      'characters': characters,
      'deviceContacts': contacts,
      'chats': chats,
      'chatMembers': members,
      'messages': messages,
      'calls': calls,
      'media': media,
      'scenes': scenes,
      'sceneCharacters': sceneCharacters,
      'sceneActions': sceneActions,
      'takes': takes,
    };
  }

  static Map<String, Object?> _params(Map<String, Object?> action) {
    final raw = action['params_json'];
    if (raw is! String || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  static List<Map<String, Object?>> _list(Map<String, Object?> json, String key) => [
        for (final r in (json[key] as List?) ?? const [])
          if (r is Map) Map<String, Object?>.from(r),
      ];

  /// Импорт профиля. Возвращает id нового телефона.
  Future<String> import(Map<String, Object?> json) async {
    if (json['format'] != profileFormat) {
      throw const ProfileImportException('Это не файл профиля «Реплики»');
    }
    final formatVersion = json['formatVersion'];
    final schemaVersion = json['schemaVersion'];
    if (formatVersion is! int || formatVersion > profileFormatVersion) {
      throw const ProfileImportException('Профиль сохранён более новой версией приложения — обновите «Реплику»');
    }
    if (schemaVersion is! int || schemaVersion > Schema.version) {
      throw const ProfileImportException('Данные профиля новее этой версии приложения — обновите «Реплику»');
    }
    final device = json['device'];
    if (device is! Map) throw const ProfileImportException('В файле нет профиля');

    final ids = <String, String>{}; // старый id → новый (всё, кроме персонажей)
    String remap(Object? old) => ids.putIfAbsent(old as String, newId);
    String? remapOrNull(Object? old) => old == null ? null : ids[old as String];

    // Файлы вложений пишутся до транзакции (файловая система не откатывается,
    // но лишний файл безвреднее потерянного).
    final mediaRows = <Map<String, Object?>>[];
    final withFiles = _list(json, 'media').where((m) => m['data'] is String).toList();
    final dir = withFiles.isEmpty ? null : await mediaDir();
    for (final m in withFiles) {
      final data = m.remove('data') as String;
      final id = remap(m['id']);
      final ext = p.extension(m['path'] as String? ?? '');
      final file = File(p.join(dir!.path, '$id$ext'));
      await file.writeAsBytes(base64Decode(data));
      mediaRows.add({...m, 'id': id, 'path': file.path, 'thumb_path': null});
    }

    final newDevice = newId();
    await db.transaction((txn) async {
      for (final m in mediaRows) {
        await txn.insert(Tables.media, m);
      }
      String? media(Object? old) => remapOrNull(old);

      for (final c in _list(json, 'characters')) {
        final exists = await txn.query(Tables.characters, where: 'id = ?', whereArgs: [c['id']], limit: 1);
        if (exists.isNotEmpty) continue;
        await txn.insert(Tables.characters, {
          ...c,
          'avatar_media_id': media(c['avatar_media_id']),
          'call_audio_media_id': media(c['call_audio_media_id']),
          'call_video_media_id': media(c['call_video_media_id']),
        });
      }

      final names = {for (final r in await txn.query(Tables.devices, columns: ['name'])) r['name']};
      var name = device['name'] as String? ?? 'Профиль';
      if (names.contains(name)) name = '$name (импорт)';
      final order = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM devices')) ?? 0;
      await txn.insert(Tables.devices, {
        ...Map<String, Object?>.from(device),
        'id': newDevice,
        'name': name,
        'sort_order': order,
      });

      for (final c in _list(json, 'deviceContacts')) {
        await txn.insert(Tables.deviceContacts, {...c, 'device_id': newDevice},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final c in _list(json, 'chats')) {
        await txn.insert(Tables.chats, {...c, 'id': remap(c['id']), 'device_id': newDevice});
      }
      for (final m in _list(json, 'chatMembers')) {
        await txn.insert(Tables.chatMembers, {...m, 'chat_id': ids[m['chat_id']]},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      final scenes = _list(json, 'scenes');
      for (final s in scenes) {
        remap(s['id']);
      }
      for (final a in _list(json, 'sceneActions')) {
        remap(a['id']);
      }
      for (final s in scenes) {
        await txn.insert(Tables.scenes, {
          ...s,
          'id': ids[s['id']],
          'device_id': newDevice,
          'chat_id': remapOrNull(s['chat_id']),
          'copied_from_id': null,
          'status': 'ready',
        });
      }
      for (final sc in _list(json, 'sceneCharacters')) {
        await txn.insert(Tables.sceneCharacters, {...sc, 'scene_id': ids[sc['scene_id']]},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final a in _list(json, 'sceneActions')) {
        final params = _params(a);
        for (final key in const ['mediaId', 'groupId', 'refActionId']) {
          if (params[key] is String && ids.containsKey(params[key])) params[key] = ids[params[key]];
        }
        await txn.insert(Tables.sceneActions, {
          ...a,
          'id': ids[a['id']],
          'scene_id': ids[a['scene_id']],
          'params_json': jsonEncode(params),
        });
      }
      // История дублей переносится, но её журналы отмены ссылаются на
      // данные другого устройства — они помечены как уже сброшенные.
      for (final t in _list(json, 'takes')) {
        await txn.insert(Tables.takes, {
          ...t,
          'id': newId(),
          'scene_id': ids[t['scene_id']],
          'log_json': jsonEncode({'imported': true, 'reset': true}),
        });
      }

      final messages = _list(json, 'messages');
      for (final m in messages) {
        remap(m['id']);
      }
      for (final m in messages) {
        await txn.insert(Tables.messages, {
          ...m,
          'id': ids[m['id']],
          'chat_id': ids[m['chat_id']],
          'reply_to_id': remapOrNull(m['reply_to_id']),
          'media_id': media(m['media_id']),
          'scene_id': remapOrNull(m['scene_id']),
        });
      }
      for (final c in _list(json, 'calls')) {
        await txn.insert(Tables.calls, {
          ...c,
          'id': newId(),
          'device_id': newDevice,
          'scene_id': remapOrNull(c['scene_id']),
        });
      }
    });
    changes.notify({
      Tables.media, Tables.characters, Tables.devices, Tables.deviceContacts, Tables.chats,
      Tables.chatMembers, Tables.messages, Tables.calls, Tables.scenes, Tables.sceneCharacters,
      Tables.sceneActions, Tables.takes,
    });
    return newDevice;
  }
}
