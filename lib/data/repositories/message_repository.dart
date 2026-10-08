import 'package:sqflite/sqflite.dart';

import '../../core/util/db_values.dart';
import '../../core/util/ids.dart';
import '../db/tables.dart';
import '../models/media_item.dart';
import '../models/message.dart';
import '../models/origin.dart';
export '../models/origin.dart' show DataOrigin;
import 'repository.dart';

class MessageRepository extends Repository {
  MessageRepository(super.database);

  /// Сообщения чата в хронологическом порядке.
  Future<List<Message>> forChat(String chatId) async {
    final rows = await db.rawQuery('''
      SELECT m.*,
        md.id AS md_id, md.kind AS md_kind, md.path AS md_path,
        md.original_name AS md_original_name, md.mime AS md_mime,
        md.size_bytes AS md_size_bytes, md.duration_ms AS md_duration_ms,
        md.width AS md_width, md.height AS md_height,
        md.thumb_path AS md_thumb_path, md.waveform AS md_waveform,
        md.created_at AS md_created_at
      FROM messages m
      LEFT JOIN media md ON md.id = m.media_id
      WHERE m.chat_id = ?
      ORDER BY m.sent_at ASC, m.created_at ASC
    ''', [chatId]);
    return rows.map(Message.fromRow).toList();
  }

  /// Отправка медиа владельцем телефона (подпись — необязательный текст).
  Future<Message> sendMedia({
    required String chatId,
    required String senderId,
    required MediaItem media,
    required MessageType type,
    String caption = '',
    String? replyToId,
    String? sceneId,
    DateTime? sentAt,
  }) async {
    final now = DateTime.now();
    final message = Message(
      id: newId(),
      chatId: chatId,
      senderId: senderId,
      type: type,
      text: caption.trim(),
      sentAt: sentAt ?? now,
      state: MessageState.sent,
      mediaId: media.id,
      replyToId: replyToId,
      origin: sceneId == null ? DataOrigin.base : DataOrigin.scene,
      sceneId: sceneId,
      createdAt: now,
      media: media,
    );
    await db.transaction((txn) async {
      await txn.insert(Tables.messages, message.toRow());
      await txn.update(
        Tables.chats,
        {'updated_at': dateToInt(now)},
        where: 'id = ?',
        whereArgs: [chatId],
      );
    });
    notify({Tables.messages, Tables.chats});
    return message;
  }

  /// Отправка текста владельцем телефона. Запись сообщения, обновление
  /// чата и очистка черновика — одной транзакцией.
  Future<Message> sendText({
    required String chatId,
    required String senderId,
    required String text,
    String? replyToId,
    String? sceneId,
    DateTime? sentAt,
  }) async {
    final now = DateTime.now();
    final message = Message(
      id: newId(),
      chatId: chatId,
      senderId: senderId,
      text: text,
      sentAt: sentAt ?? now,
      state: MessageState.sent,
      replyToId: replyToId,
      origin: sceneId == null ? DataOrigin.base : DataOrigin.scene,
      sceneId: sceneId,
      createdAt: now,
    );
    await db.transaction((txn) async {
      await txn.insert(Tables.messages, message.toRow());
      await txn.update(
        Tables.chats,
        {'updated_at': dateToInt(now), 'draft': null},
        where: 'id = ?',
        whereArgs: [chatId],
      );
    });
    notify({Tables.messages, Tables.chats});
    return message;
  }

  // ---------- Для движка сцен ----------

  /// Время, показанное у сообщения («23:47»). Для команд Connect
  /// (`messageTime`); сообщение переезжает на своё место в переписке.
  Future<void> setSentAt(String messageId, DateTime at) async {
    await db.update(Tables.messages, {'sent_at': dateToInt(at)}, where: 'id = ?', whereArgs: [messageId]);
    notify({Tables.messages, Tables.chats});
  }

  /// Сообщение, добавленное сценой (сбрасывается «СБРОС СЦЕНЫ»).
  Future<Message> insertSceneMessage({
    required String chatId,
    required String? senderId,
    required MessageType type,
    required String? sceneId,
    String text = '',
    String? mediaId,
    MessageState state = MessageState.delivered,
    DateTime? sentAt,
    DataOrigin origin = DataOrigin.scene,
    String? replyToId,
  }) async {
    final now = DateTime.now();
    final message = Message(
      id: newId(),
      chatId: chatId,
      senderId: senderId,
      type: type,
      text: text,
      sentAt: sentAt ?? now,
      state: state,
      mediaId: mediaId,
      replyToId: replyToId,
      origin: origin,
      sceneId: sceneId,
      createdAt: now,
    );
    await db.transaction((txn) async {
      await txn.insert(Tables.messages, message.toRow());
      await txn.update(Tables.chats, {'updated_at': dateToInt(now)}, where: 'id = ?', whereArgs: [chatId]);
    });
    notify({Tables.messages, Tables.chats});
    return message;
  }

  Future<Message?> byId(String id) async {
    final rows = await db.query(Tables.messages, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Message.fromRow(rows.first);
  }

  /// Изменить текст сообщения («изм.» в пузыре — по флагу [edited]).
  Future<void> updateText(String id, String text, {required bool edited}) async {
    await db.update(
      Tables.messages,
      {'text': text, 'edited': boolToInt(edited)},
      where: 'id = ?',
      whereArgs: [id],
    );
    notify({Tables.messages, Tables.chats});
  }

  /// Последнее сообщение чата: 'last', 'lastIncoming' или 'lastOutgoing'.
  Future<Message?> findTarget(String chatId, String target, String ownerId) async {
    final condition = switch (target) {
      'lastIncoming' => 'AND sender_id IS NOT NULL AND sender_id <> ?',
      'lastOutgoing' => 'AND sender_id = ?',
      _ => '',
    };
    final rows = await db.rawQuery(
      'SELECT * FROM messages WHERE chat_id = ? $condition '
      'ORDER BY sent_at DESC, created_at DESC LIMIT 1',
      [chatId, if (condition.isNotEmpty) ownerId],
    );
    return rows.isEmpty ? null : Message.fromRow(rows.first);
  }

  /// Собеседник ответил — исходящие становятся прочитанными.
  /// Возвращает прежние статусы для отмены при сбросе сцены.
  ///
  /// Сообщения с «Прочитано: OFF» (read_hold) не затрагиваются: их читает
  /// только ответ именно на них.
  Future<List<(String, String)>> markOutgoingRead(String chatId, String ownerId) async {
    final rows = await db.query(
      Tables.messages,
      columns: ['id', 'state'],
      where: "chat_id = ? AND sender_id = ? AND state IN ('sent', 'delivered') AND read_hold = 0",
      whereArgs: [chatId, ownerId],
    );
    if (rows.isEmpty) return const [];
    await db.rawUpdate(
      "UPDATE messages SET state = 'read' "
      "WHERE chat_id = ? AND sender_id = ? AND state IN ('sent', 'delivered') AND read_hold = 0",
      [chatId, ownerId],
    );
    notify({Tables.messages});
    return [for (final r in rows) (r['id'] as String, r['state'] as String)];
  }

  /// «Прочитано: OFF»: сообщение удерживается непрочитанным до ответа на него.
  Future<void> setReadHold(String id, bool hold) async {
    await db.update(Tables.messages, {'read_hold': hold ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    notify({Tables.messages});
  }

  Future<bool> isReadHeld(String id) async {
    final rows = await db.query(Tables.messages, columns: ['read_hold'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty && rows.first['read_hold'] == 1;
  }

  /// Удаляет всё, что добавила сцена, включая импровизацию во время дубля.
  Future<int> deleteSceneMessages(String sceneId) async {
    final count = await db.delete(
      Tables.messages,
      where: "scene_id = ? AND origin IN ('scene', 'improv')",
      whereArgs: [sceneId],
    );
    notify({Tables.messages, Tables.chats});
    return count;
  }

  /// Убирает из чата все сообщения импровизации.
  Future<int> deleteImprov(String chatId) async {
    final count = await db.delete(
      Tables.messages,
      where: "chat_id = ? AND origin = 'improv'",
      whereArgs: [chatId],
    );
    notify({Tables.messages, Tables.chats});
    return count;
  }

  Future<void> setFavorite(String id, bool favorite) =>
      _updateFlag(id, 'favorite', favorite);

  /// «Удалено» — сообщение остаётся в переписке с пометкой
  /// «Сообщение удалено», его можно вернуть.
  /// «Удалено» — с моментом удаления; возврат снимает его.
  Future<void> setDeleted(String id, bool deleted) async {
    await db.rawUpdate(
      'UPDATE messages SET deleted = ?, '
      'deleted_at = CASE WHEN ? = 1 THEN COALESCE(deleted_at, ?) ELSE NULL END WHERE id = ?',
      [boolToInt(deleted), boolToInt(deleted), dateToInt(DateTime.now()), id],
    );
    notify({Tables.messages, Tables.chats});
  }

  /// Состояние сообщения — реальные данные: «доставлено» и «прочитано»
  /// получают свои моменты; возврат к более раннему состоянию их снимает
  /// (отправляется → доставлено → прочитано; отправляется → не доставлено).
  Future<void> setState(String id, MessageState state) async {
    final now = dateToInt(DateTime.now());
    await db.rawUpdate(
      'UPDATE messages SET state = ?, '
      "delivered_at = CASE WHEN ? IN ('delivered', 'read') THEN COALESCE(delivered_at, ?) ELSE NULL END, "
      "read_at = CASE WHEN ? = 'read' THEN COALESCE(read_at, ?) ELSE NULL END "
      'WHERE id = ?',
      [state.name, state.name, now, state.name, now, id],
    );
    notify({Tables.messages});
  }

  /// Полное удаление сообщения из переписки.
  Future<void> delete(String id) async {
    await db.delete(Tables.messages, where: 'id = ?', whereArgs: [id]);
    notify({Tables.messages, Tables.chats});
  }

  /// Возврат полностью удалённого сообщения (кнопка «Вернуть»).
  Future<void> restore(Message message) async {
    await db.insert(
      Tables.messages,
      message.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    notify({Tables.messages, Tables.chats});
  }

  /// Реакция-эмодзи на сообщение; null — убрать.
  Future<void> setReaction(String id, String? reaction) async {
    await db.update(Tables.messages, {'reaction': reaction}, where: 'id = ?', whereArgs: [id]);
    notify({Tables.messages});
  }

  Future<void> _updateFlag(String id, String column, bool value) async {
    await db.update(
      Tables.messages,
      {column: boolToInt(value)},
      where: 'id = ?',
      whereArgs: [id],
    );
    notify({Tables.messages});
  }
}
