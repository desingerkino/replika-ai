import 'package:sqflite/sqflite.dart';
import '../../core/design/tokens.dart';
import '../../core/util/db_values.dart';
import '../../core/util/ids.dart';
import '../../core/util/text.dart';
import '../db/tables.dart';
import '../models/chat.dart';
import 'repository.dart';

/// Участник группы: имя как на телефоне, цвет внутри группы, признак
/// «удалён из состава» (его старые сообщения остаются).
typedef GroupMemberInfo = ({String characterId, String name, int? tone, int colorTone, bool removed});

class ChatRepository extends Repository {
  ChatRepository(super.database);

  /// Общая часть запроса: чат + как собеседник записан на этом телефоне.
  /// Если контакт удалён с телефона, вместо имени виден номер — как в жизни.
  static const String selectSql = '''
    SELECT ch.*,
      CASE WHEN ch.is_group = 1 THEN COALESCE(ch.title, 'Группа')
      ELSE COALESCE(
        dc.display_name,
        NULLIF(pc.phone, ''),
        NULLIF(TRIM(pc.first_name || ' ' || pc.last_name), ''),
        ch.title,
        'Без имени'
      ) END AS display_name,
      pc.avatar_tone AS peer_avatar_tone,
      am.path AS peer_avatar_path,
      pc.status_text AS peer_status,
      pc.phone AS peer_phone,
      d.owner_character_id AS owner_character_id
    FROM chats ch
    JOIN devices d ON d.id = ch.device_id
    LEFT JOIN characters pc ON pc.id = ch.peer_character_id
    LEFT JOIN device_contacts dc
      ON dc.device_id = ch.device_id AND dc.character_id = ch.peer_character_id
    LEFT JOIN media am ON am.id = pc.avatar_media_id
  ''';

  /// Поля сообщения с префиксом «m_» (см. Message.fromPrefixedRow).
  static const String _messageColumns = '''
      m.id AS m_id, m.chat_id AS m_chat_id, m.sender_id AS m_sender_id,
      m.type AS m_type, m.text AS m_text, m.sent_at AS m_sent_at,
      m.state AS m_state, m.media_id AS m_media_id,
      m.reply_to_id AS m_reply_to_id, m.favorite AS m_favorite,
      m.deleted AS m_deleted, m.edited AS m_edited, m.origin AS m_origin,
      m.scene_id AS m_scene_id, m.created_at AS m_created_at,
      m.delivered_at AS m_delivered_at, m.read_at AS m_read_at, m.deleted_at AS m_deleted_at''';

  /// Сообщения телефона вместе со сведениями о собеседнике.
  static const String _hitsSql = '''
    SELECT base.display_name, base.peer_avatar_tone, base.peer_avatar_path,
      base.peer_status, base.peer_phone, base.owner_character_id,
      $_messageColumns
    FROM messages m
    JOIN ($selectSql WHERE ch.device_id = ?) AS base ON base.id = m.chat_id
  ''';

  static const String _listSql = '''
    SELECT base.*, $_messageColumns,
      COALESCE(sdc.display_name, NULLIF(TRIM(sc.first_name), ''), NULLIF(sc.phone, '')) AS m_sender_name
    FROM ($selectSql WHERE ch.device_id = ?) AS base
    LEFT JOIN messages m ON m.id = (
      SELECT id FROM messages
      WHERE chat_id = base.id
      ORDER BY sent_at DESC, created_at DESC
      LIMIT 1
    )
    LEFT JOIN characters sc ON sc.id = m.sender_id
    LEFT JOIN device_contacts sdc ON sdc.device_id = base.device_id AND sdc.character_id = m.sender_id
    WHERE m.id IS NOT NULL
      OR base.pinned_at IS NOT NULL
      OR (base.draft IS NOT NULL AND base.draft <> '')
    ORDER BY (base.pinned_at IS NULL), base.pinned_at DESC,
      COALESCE(m.sent_at, base.updated_at) DESC
  ''';

  /// Чаты телефона: закреплённые сверху, остальные — по последнему сообщению.
  /// Пустые чаты (без сообщений, черновика и закрепления) не показываются,
  /// как в настоящих мессенджерах.
  Future<List<ChatListItem>> listForDevice(String deviceId) async {
    final rows = await db.rawQuery(_listSql, [deviceId]);
    return rows.map(ChatListItem.fromRow).toList();
  }

  /// Избранные сообщения телефона, новые сверху.
  Future<List<MessageHit>> favorites(String deviceId) async {
    final rows = await db.rawQuery(
      '$_hitsSql WHERE m.favorite = 1 ORDER BY m.sent_at DESC, m.created_at DESC',
      [deviceId],
    );
    return rows.map(MessageHit.fromRow).toList();
  }

  /// Поиск по тексту сообщений. Сравнение делается в Dart: встроенный
  /// LIKE в SQLite не учитывает регистр кириллицы и букву «ё».
  Future<List<MessageHit>> searchMessages(
    String deviceId,
    String query, {
    int limit = 100,
  }) async {
    final needle = foldForMatch(query.trim());
    if (needle.isEmpty) return const [];
    final rows = await db.rawQuery(
      "$_hitsSql WHERE m.deleted = 0 AND m.text <> '' "
      'ORDER BY m.sent_at DESC, m.created_at DESC LIMIT 5000',
      [deviceId],
    );
    final hits = <MessageHit>[];
    for (final row in rows) {
      if (foldForMatch(row['m_text'] as String? ?? '').contains(needle)) {
        hits.add(MessageHit.fromRow(row));
        if (hits.length >= limit) break;
      }
    }
    return hits;
  }

  Future<ChatHeader?> header(String chatId) async {
    final rows = await db.rawQuery('$selectSql WHERE ch.id = ? LIMIT 1', [chatId]);
    return rows.isEmpty ? null : ChatHeader.fromRow(rows.first);
  }

  Future<String?> draftOf(String chatId) async {
    final rows = await db.query(
      Tables.chats,
      columns: ['draft'],
      where: 'id = ?',
      whereArgs: [chatId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['draft'] as String?;
  }

  // ---------- Группы ----------

  /// Участники группы глазами телефона: как записаны в контактах, иначе
  /// имя или номер. Владелец телефона — «Вы».
  ///
  /// [includeRemoved] — вместе с удалёнными из группы: нужно, чтобы старые
  /// сообщения бывших участников сохранили имя и цвет.
  Future<List<GroupMemberInfo>> members(String chatId, {bool includeRemoved = false}) async {
    final rows = await db.rawQuery('''
      SELECT cm.character_id, c.avatar_tone, cm.color_tone, cm.removed_at,
        CASE WHEN cm.character_id = d.owner_character_id THEN 'Вы'
        ELSE COALESCE(dc.display_name, NULLIF(TRIM(c.first_name || ' ' || c.last_name), ''), NULLIF(c.phone, ''), 'Без имени')
        END AS name
      FROM chat_members cm
      JOIN chats ch ON ch.id = cm.chat_id
      JOIN devices d ON d.id = ch.device_id
      JOIN characters c ON c.id = cm.character_id
      LEFT JOIN device_contacts dc ON dc.device_id = ch.device_id AND dc.character_id = cm.character_id
      WHERE cm.chat_id = ?${includeRemoved ? '' : ' AND cm.removed_at IS NULL'}
      ORDER BY (cm.removed_at IS NOT NULL), (cm.character_id = d.owner_character_id) DESC, name
    ''', [chatId]);
    return [
      for (final r in rows)
        (
          characterId: r['character_id'] as String,
          name: r['name'] as String,
          tone: r['avatar_tone'] as int?,
          // Без сохранённого цвета (старые группы) — цвет по имени, как раньше.
          colorTone: (r['color_tone'] as int?) ?? AvatarTones.indexForKey(r['name'] as String),
          removed: r['removed_at'] != null,
        ),
    ];
  }

  /// Первый цвет палитры, не занятый в группе (в том числе бывшими
  /// участниками, чтобы их старые сообщения не путались с новыми).
  /// Если палитра исчерпана — наименее используемый.
  Future<int> _freeTone(String chatId) async {
    final used = <int, int>{};
    for (final m in await members(chatId, includeRemoved: true)) {
      used[m.colorTone] = (used[m.colorTone] ?? 0) + 1;
    }
    var best = 0;
    var bestCount = 1 << 30;
    for (var i = 0; i < AvatarTones.all.length; i++) {
      final count = used[i] ?? 0;
      if (count < bestCount) {
        best = i;
        bestCount = count;
      }
    }
    return best;
  }

  /// Оператор вручную меняет цвет участника в этой группе.
  Future<void> setMemberColor(String chatId, String characterId, int tone) async {
    await db.update(Tables.chatMembers, {'color_tone': tone % AvatarTones.all.length},
        where: 'chat_id = ? AND character_id = ?', whereArgs: [chatId, characterId]);
    notify({Tables.chatMembers});
  }

  /// Создать группу на телефоне. Владелец телефона входит в неё всегда.
  Future<String> createGroup({
    required String deviceId,
    required String title,
    required Iterable<String> memberIds,
    String? id,
  }) async {
    final device = await db.query(Tables.devices, where: 'id = ?', whereArgs: [deviceId], limit: 1);
    if (device.isEmpty) throw StateError('Телефон не найден');
    final owner = device.first['owner_character_id'] as String;
    final chatId = id ?? newId();
    final now = dateToInt(DateTime.now());
    await db.transaction((txn) async {
      await txn.insert(Tables.chats, {
        'id': chatId,
        'device_id': deviceId,
        'peer_character_id': null,
        'title': title,
        'is_group': 1,
        'unread_count': 0,
        'muted': 0,
        'created_at': now,
        'updated_at': now,
      });
      var tone = 0;
      for (final m in {owner, ...memberIds}) {
        await txn.insert(Tables.chatMembers,
            {'chat_id': chatId, 'character_id': m, 'color_tone': tone % AvatarTones.all.length},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        tone++;
      }
    });
    notify({Tables.chats, Tables.chatMembers});
    return chatId;
  }

  Future<bool> isMember(String chatId, String characterId) async {
    final rows = await db.query(Tables.chatMembers,
        where: 'chat_id = ? AND character_id = ? AND removed_at IS NULL',
        whereArgs: [chatId, characterId],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// Добавить участника. Новому достаётся свободный цвет; вернувшийся
  /// в группу участник получает свой прежний цвет.
  Future<void> addMember(String chatId, String characterId) async {
    final existing = await db.query(Tables.chatMembers,
        where: 'chat_id = ? AND character_id = ?', whereArgs: [chatId, characterId], limit: 1);
    if (existing.isEmpty) {
      await db.insert(Tables.chatMembers,
          {'chat_id': chatId, 'character_id': characterId, 'color_tone': await _freeTone(chatId)});
    } else if (existing.first['removed_at'] != null) {
      await db.update(Tables.chatMembers, {'removed_at': null},
          where: 'chat_id = ? AND character_id = ?', whereArgs: [chatId, characterId]);
    }
    notify({Tables.chatMembers, Tables.chats});
  }

  /// Убрать участника из состава. Строка остаётся (removed_at), поэтому его
  /// старые сообщения сохраняют автора, имя и цвет.
  ///
  /// [forget] — отмена только что сделанного добавления (шаг «Назад», сброс
  /// сцены): если у участника нет сообщений в этом чате, строка удаляется
  /// совсем, чтобы не оставлять «призрака» в истории группы.
  Future<void> removeMember(String chatId, String characterId, {bool forget = false}) async {
    final softRemove = !forget ||
        (await db.query(Tables.messages,
                columns: ['id'],
                where: 'chat_id = ? AND sender_id = ?',
                whereArgs: [chatId, characterId],
                limit: 1))
            .isNotEmpty;
    if (softRemove) {
      await db.update(Tables.chatMembers, {'removed_at': dateToInt(DateTime.now())},
          where: 'chat_id = ? AND character_id = ? AND removed_at IS NULL', whereArgs: [chatId, characterId]);
    } else {
      await db.delete(Tables.chatMembers,
          where: 'chat_id = ? AND character_id = ?', whereArgs: [chatId, characterId]);
    }
    notify({Tables.chatMembers, Tables.chats});
  }

  Future<void> renameGroup(String chatId, String title) async {
    await db.update(Tables.chats, {'title': title, 'updated_at': dateToInt(DateTime.now())},
        where: 'id = ? AND is_group = 1', whereArgs: [chatId]);
    notify({Tables.chats});
  }

  /// Группы телефона (для Connect: LIST_GROUPS).
  Future<List<({String id, String title})>> groupsForDevice(String deviceId) async {
    final rows = await db.query(Tables.chats,
        columns: ['id', 'title'], where: 'device_id = ? AND is_group = 1', whereArgs: [deviceId], orderBy: 'created_at');
    return [for (final r in rows) (id: r['id'] as String, title: r['title'] as String? ?? 'Группа')];
  }

  /// Личный чат с персонажем на телефоне, если он уже есть.
  Future<String?> findDirect({required String deviceId, required String characterId}) async {
    final rows = await db.query(
      Tables.chats,
      columns: ['id'],
      where: 'device_id = ? AND peer_character_id = ? AND is_group = 0',
      whereArgs: [deviceId, characterId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  /// Находит личный чат с персонажем на этом телефоне или создаёт его.
  Future<String> openOrCreateDirect({
    required String deviceId,
    required String characterId,
  }) async {
    var created = false;
    final id = await db.transaction<String>((txn) async {
      final existing = await txn.query(
        Tables.chats,
        columns: ['id'],
        where: 'device_id = ? AND peer_character_id = ? AND is_group = 0',
        whereArgs: [deviceId, characterId],
        limit: 1,
      );
      if (existing.isNotEmpty) return existing.first['id'] as String;

      final device = await txn.query(
        Tables.devices,
        columns: ['owner_character_id'],
        where: 'id = ?',
        whereArgs: [deviceId],
        limit: 1,
      );
      if (device.isEmpty) {
        throw StateError('Телефон не найден');
      }
      final ownerId = device.first['owner_character_id'] as String;
      final now = dateToInt(DateTime.now());
      final chatId = newId();
      await txn.insert(Tables.chats, {
        'id': chatId,
        'device_id': deviceId,
        'peer_character_id': characterId,
        'is_group': 0,
        'unread_count': 0,
        'muted': 0,
        'created_at': now,
        'updated_at': now,
      });
      for (final member in {ownerId, characterId}) {
        await txn.insert(Tables.chatMembers, {
          'chat_id': chatId,
          'character_id': member,
        });
      }
      created = true;
      return chatId;
    });
    if (created) notify({Tables.chats, Tables.chatMembers});
    return id;
  }

  Future<void> setPinned(String chatId, bool pinned) async {
    await db.update(
      Tables.chats,
      {'pinned_at': pinned ? dateToInt(DateTime.now()) : null},
      where: 'id = ?',
      whereArgs: [chatId],
    );
    notify({Tables.chats});
  }

  Future<void> markRead(String chatId) async {
    final count = await db.rawUpdate(
      'UPDATE chats SET unread_count = 0 WHERE id = ? AND unread_count <> 0',
      [chatId],
    );
    if (count > 0) notify({Tables.chats});
  }

  Future<void> markUnread(String chatId) async {
    await db.rawUpdate(
      'UPDATE chats SET unread_count = MAX(unread_count, 1) WHERE id = ?',
      [chatId],
    );
    notify({Tables.chats});
  }

  Future<void> setMuted(String chatId, bool muted) async {
    await db.update(
      Tables.chats,
      {'muted': boolToInt(muted)},
      where: 'id = ?',
      whereArgs: [chatId],
    );
    notify({Tables.chats});
  }

  /// Сохраняет черновик. Пустая строка удаляет его.
  /// Оповещает экраны, только если значение действительно изменилось.
  Future<void> saveDraft(String chatId, String draft) async {
    final value = draft.trim().isEmpty ? null : draft;
    final count = await db.rawUpdate(
      "UPDATE chats SET draft = ? WHERE id = ? AND COALESCE(draft, '') <> COALESCE(?, '')",
      [value, chatId, value],
    );
    if (count > 0) notify({Tables.chats});
  }

  /// Снимок состояния чата перед дублем.
  Future<Map<String, Object?>> snapshot(String chatId) async {
    final rows = await db.query(
      Tables.chats,
      columns: ['unread_count', 'pinned_at', 'draft', 'muted'],
      where: 'id = ?',
      whereArgs: [chatId],
      limit: 1,
    );
    return rows.isEmpty ? <String, Object?>{} : Map<String, Object?>.from(rows.first);
  }

  Future<void> restoreSnapshot(String chatId, Map<String, Object?> snapshot) async {
    if (snapshot.isEmpty) return;
    await db.update(Tables.chats, snapshot, where: 'id = ?', whereArgs: [chatId]);
    notify({Tables.chats});
  }

  Future<void> decrementUnread(String chatId) async {
    await db.rawUpdate('UPDATE chats SET unread_count = MAX(unread_count - 1, 0) WHERE id = ?', [chatId]);
    notify({Tables.chats});
  }

  Future<void> incrementUnread(String chatId) async {
    await db.rawUpdate('UPDATE chats SET unread_count = unread_count + 1 WHERE id = ?', [chatId]);
    notify({Tables.chats});
  }

  /// Удаляет чат вместе с сообщениями (каскадом).
  Future<void> delete(String chatId) async {
    await db.delete(Tables.chats, where: 'id = ?', whereArgs: [chatId]);
    notify({Tables.chats, Tables.messages, Tables.chatMembers});
  }

  /// В архив и обратно. Архивный чат не показывается в общем списке и не
  /// попадает в счётчик на вкладке.
  Future<void> setArchived(String chatId, bool archived) async {
    await db.update(
      Tables.chats,
      {'archived_at': archived ? dateToInt(DateTime.now()) : null},
      where: 'id = ?',
      whereArgs: [chatId],
    );
    notify({Tables.chats});
  }

  /// Фон переписки; null — «Стандартный».
  Future<void> setBackground(String chatId, String? background) async {
    await db.update(Tables.chats, {'background': background}, where: 'id = ?', whereArgs: [chatId]);
    notify({Tables.chats});
  }

  /// Сумма непрочитанных для значка на вкладке «Чаты» (без чатов без звука).
  Future<int> totalUnread(String deviceId) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(unread_count), 0) AS n FROM chats '
      'WHERE device_id = ? AND muted = 0 AND archived_at IS NULL',
      [deviceId],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }
}
