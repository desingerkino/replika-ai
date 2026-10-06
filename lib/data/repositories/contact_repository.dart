import 'package:sqflite/sqflite.dart';

import '../../core/util/db_values.dart';
import '../../core/util/ids.dart';
import '../../core/util/text.dart';
import '../db/tables.dart';
import '../models/character.dart';
import '../models/contact.dart';
import 'repository.dart';

/// Поля персонажа, которые редактируются в профиле.
class CharacterDraft {
  const CharacterDraft({
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.statusText = '',
    this.tone,
    this.description = '',
    this.avatarMediaId,
    this.callAudioMediaId,
    this.callVideoMediaId,
  });

  final String firstName;
  final String lastName;
  final String phone;
  final String statusText;
  final int? tone;
  final String description;

  /// Фото профиля из медиатеки; null — аватар из инициалов.
  final String? avatarMediaId;

  /// Голос и видео собеседника для постановочных звонков.
  final String? callAudioMediaId;
  final String? callVideoMediaId;

  Map<String, Object?> toFields() => {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'phone': phone.trim(),
        'status_text': statusText.trim(),
        'avatar_tone': tone,
        'description': description.trim(),
        'avatar_media_id': avatarMediaId,
        'call_audio_media_id': callAudioMediaId,
        'call_video_media_id': callVideoMediaId,
      };
}

class ContactRepository extends Repository {
  ContactRepository(super.database);

  static const String _viewSql = '''
    SELECT c.*, dc.display_name, dc.favorite, m.path AS avatar_path
    FROM characters c
    LEFT JOIN device_contacts dc ON dc.character_id = c.id AND dc.device_id = ?
    LEFT JOIN media m ON m.id = c.avatar_media_id
  ''';

  /// Контакты виртуального телефона, по алфавиту (как они записаны на нём).
  Future<List<Contact>> forDevice(String deviceId) async {
    final rows = await db.rawQuery('''
      SELECT c.*, dc.display_name, dc.favorite, m.path AS avatar_path
      FROM device_contacts dc
      JOIN characters c ON c.id = dc.character_id
      LEFT JOIN media m ON m.id = c.avatar_media_id
      WHERE dc.device_id = ?
    ''', [deviceId]);
    final contacts = rows.map(Contact.fromRow).toList();
    contacts.sort(compareContacts);
    return contacts;
  }

  /// Все персонажи проекта (для выбора владельца нового телефона).
  Future<List<Character>> allCharacters() async {
    final rows = await db.query(Tables.characters, orderBy: 'first_name, last_name');
    return rows.map(Character.fromRow).toList();
  }

  /// Персонаж глазами телефона: записан ли он и под каким именем.
  Future<Contact?> view(String deviceId, String characterId) async {
    final rows = await db.rawQuery(
      '$_viewSql WHERE c.id = ? LIMIT 1',
      [deviceId, characterId],
    );
    return rows.isEmpty ? null : Contact.fromRow(rows.first);
  }

  /// Создаёт или обновляет персонажа. Если передан [displayName],
  /// персонаж записывается в контакты телефона под этим именем.
  Future<String> save({
    required String deviceId,
    String? characterId,
    required CharacterDraft draft,
    String? displayName,
  }) async {
    final now = dateToInt(DateTime.now());
    final id = characterId ?? newId();
    await db.transaction((txn) async {
      final fields = {...draft.toFields(), 'updated_at': now};
      if (characterId == null) {
        await txn.insert(Tables.characters, {...fields, 'id': id, 'created_at': now});
      } else {
        await txn.update(Tables.characters, fields, where: 'id = ?', whereArgs: [id]);
      }
      if (displayName != null) {
        final name = displayName.trim();
        final updated = await txn.update(
          Tables.deviceContacts,
          {'display_name': name},
          where: 'device_id = ? AND character_id = ?',
          whereArgs: [deviceId, id],
        );
        if (updated == 0) {
          await txn.insert(
            Tables.deviceContacts,
            {
              'device_id': deviceId,
              'character_id': id,
              'display_name': name,
              'favorite': 0,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
    notify({Tables.characters, Tables.deviceContacts});
    return id;
  }

  /// Персонаж с заданным id (ключ Prop Controller, Connect 1.3).
  /// Пустая запись создаётся, если её нет; поля заполняет [save].
  /// true — персонаж создан сейчас.
  Future<bool> ensureCharacter(String id) async {
    final rows = await db.query(Tables.characters, columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) return false;
    final now = dateToInt(DateTime.now());
    await db.insert(Tables.characters, {'id': id, 'created_at': now, 'updated_at': now});
    notify({Tables.characters});
    return true;
  }

  /// Удаляет персонажа из контактов телефона. Сам персонаж и переписка
  /// остаются: в списке чатов вместо имени будет виден номер.
  Future<void> removeFromDevice(String deviceId, String characterId) async {
    await db.delete(
      Tables.deviceContacts,
      where: 'device_id = ? AND character_id = ?',
      whereArgs: [deviceId, characterId],
    );
    notify({Tables.deviceContacts});
  }
}

int compareContacts(Contact a, Contact b) =>
    sortKey(a.displayName).compareTo(sortKey(b.displayName));
