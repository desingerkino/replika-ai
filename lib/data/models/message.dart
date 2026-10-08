import '../../core/util/db_values.dart';
import 'media_item.dart';
import 'origin.dart';

enum MessageType { text, photo, video, audio, voice, videoNote, file, system, call }

/// Статус отправки исходящего сообщения. «Удалено» хранится отдельным
/// флагом [Message.deleted], чтобы удаление можно было отменить,
/// не теряя исходный статус.
enum MessageState { sending, sent, delivered, read, failed }

class Message {
  const Message({
    required this.id,
    required this.chatId,
    this.senderId,
    this.type = MessageType.text,
    this.text = '',
    required this.sentAt,
    this.state = MessageState.sent,
    this.mediaId,
    this.replyToId,
    this.favorite = false,
    this.deleted = false,
    this.edited = false,
    this.origin = DataOrigin.base,
    this.sceneId,
    required this.createdAt,
    this.media,
    this.deliveredAt,
    this.readAt,
    this.deletedAt,
    this.reaction,
  });

  final String id;
  final String chatId;

  /// Персонаж-отправитель; null — системное сообщение.
  final String? senderId;
  final MessageType type;
  final String text;

  /// Время, которое видно в кадре (может отличаться от времени записи).
  final DateTime sentAt;
  final MessageState state;
  final String? mediaId;
  final String? replyToId;
  final bool favorite;
  final bool deleted;
  final bool edited;
  final DataOrigin origin;
  final String? sceneId;

  /// Реальное время создания записи — для устойчивой сортировки.
  final DateTime createdAt;

  /// Файл сообщения (подгружается вместе с лентой, в базу не пишется).
  /// Когда сообщение стало «доставлено», «прочитано», «удалено».
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? deletedAt;

  final MediaItem? media;

  /// Реакция-эмодзи под пузырём (null — нет).
  final String? reaction;

  bool get isMedia =>
      type != MessageType.text && type != MessageType.system && type != MessageType.call;

  factory Message.fromRow(Map<String, Object?> row) => Message(
        id: row['id'] as String,
        chatId: row['chat_id'] as String,
        senderId: readStringOrNull(row, 'sender_id'),
        type: enumByName(MessageType.values, row['type'], MessageType.text),
        text: readString(row, 'text'),
        sentAt: intToDate(row['sent_at']),
        state: enumByName(MessageState.values, row['state'], MessageState.sent),
        mediaId: readStringOrNull(row, 'media_id'),
        replyToId: readStringOrNull(row, 'reply_to_id'),
        favorite: intToBool(row['favorite']),
        deleted: intToBool(row['deleted']),
        edited: intToBool(row['edited']),
        origin: enumByName(DataOrigin.values, row['origin'], DataOrigin.base),
        sceneId: readStringOrNull(row, 'scene_id'),
        createdAt: intToDate(row['created_at']),
        media: MediaItem.fromPrefixedRow(row, 'md_'),
        deliveredAt: row['delivered_at'] == null ? null : intToDate(row['delivered_at']),
        readAt: row['read_at'] == null ? null : intToDate(row['read_at']),
        deletedAt: row['deleted_at'] == null ? null : intToDate(row['deleted_at']),
        reaction: readStringOrNull(row, 'reaction'),
      );

  /// Сообщение из строки, где поля переданы с префиксом (например, «m_»).
  /// Возвращает null, если сообщения нет (LEFT JOIN без совпадения).
  static Message? fromPrefixedRow(Map<String, Object?> row, String prefix) {
    if (row['${prefix}id'] == null) return null;
    return Message.fromRow({
      for (final entry in row.entries)
        if (entry.key.startsWith(prefix))
          entry.key.substring(prefix.length): entry.value,
    });
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'chat_id': chatId,
        'sender_id': senderId,
        'type': type.name,
        'text': text,
        'sent_at': dateToInt(sentAt),
        'state': state.name,
        'media_id': mediaId,
        'reply_to_id': replyToId,
        'favorite': boolToInt(favorite),
        'deleted': boolToInt(deleted),
        'edited': boolToInt(edited),
        'origin': origin.name,
        'scene_id': sceneId,
        'created_at': dateToInt(createdAt),
        // Сообщение, созданное сразу доставленным или прочитанным, получает
        // эти моменты от времени отправки.
        'delivered_at': deliveredAt != null
            ? dateToInt(deliveredAt!)
            : (state == MessageState.delivered || state == MessageState.read ? dateToInt(sentAt) : null),
        'read_at': readAt != null ? dateToInt(readAt!) : (state == MessageState.read ? dateToInt(sentAt) : null),
        'deleted_at': deletedAt != null ? dateToInt(deletedAt!) : (deleted ? dateToInt(sentAt) : null),
        'reaction': reaction,
      };

  Message copyWith({
    String? text,
    DateTime? sentAt,
    MessageState? state,
    bool? favorite,
    bool? deleted,
    bool? edited,
  }) =>
      Message(
        id: id,
        chatId: chatId,
        senderId: senderId,
        type: type,
        text: text ?? this.text,
        sentAt: sentAt ?? this.sentAt,
        state: state ?? this.state,
        mediaId: mediaId,
        replyToId: replyToId,
        favorite: favorite ?? this.favorite,
        deleted: deleted ?? this.deleted,
        edited: edited ?? this.edited,
        origin: origin,
        sceneId: sceneId,
        createdAt: createdAt,
        media: media,
        reaction: reaction,
      );
}
