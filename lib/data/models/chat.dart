import '../../core/util/db_values.dart';
import 'message.dart';
import '../../core/util/media_paths.dart';

class Chat {
  const Chat({
    required this.id,
    required this.deviceId,
    this.peerCharacterId,
    this.title,
    this.isGroup = false,
    this.pinnedAt,
    this.unreadCount = 0,
    this.muted = false,
    this.draft,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String deviceId;
  final String? peerCharacterId;
  final String? title;
  final bool isGroup;
  final DateTime? pinnedAt;
  final int unreadCount;
  final bool muted;
  final String? draft;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPinned => pinnedAt != null;

  factory Chat.fromRow(Map<String, Object?> row) => Chat(
        id: row['id'] as String,
        deviceId: row['device_id'] as String,
        peerCharacterId: readStringOrNull(row, 'peer_character_id'),
        title: readStringOrNull(row, 'title'),
        isGroup: intToBool(row['is_group']),
        pinnedAt: intToDateOrNull(row['pinned_at']),
        unreadCount: readInt(row, 'unread_count'),
        muted: intToBool(row['muted']),
        draft: readStringOrNull(row, 'draft'),
        createdAt: intToDate(row['created_at']),
        updatedAt: intToDate(row['updated_at']),
      );
}

/// Сведения о собеседнике, общие для списка чатов и шапки чата.
class ChatPeer {
  const ChatPeer({
    required this.displayName,
    this.avatarPath,
    this.avatarTone,
    this.statusText = '',
    this.phone = '',
  });

  final String displayName;
  final String? avatarPath;
  final int? avatarTone;
  final String statusText;
  final String phone;

  bool get isOnline => statusText.trim().toLowerCase() == 'в сети';

  factory ChatPeer.fromRow(Map<String, Object?> row) => ChatPeer(
        displayName: readString(row, 'display_name', 'Без имени'),
        avatarPath: MediaPaths.resolveOrNull(readStringOrNull(row, 'peer_avatar_path')),
        avatarTone: readIntOrNull(row, 'peer_avatar_tone'),
        statusText: readString(row, 'peer_status'),
        phone: readString(row, 'peer_phone'),
      );
}

/// Строка списка чатов.
class ChatListItem {
  const ChatListItem({
    required this.chat,
    required this.peer,
    required this.ownerCharacterId,
    this.lastMessage,
    this.lastSenderName,
  });

  final Chat chat;
  final ChatPeer peer;
  final String ownerCharacterId;
  final Message? lastMessage;

  /// Как отправитель последнего сообщения записан на телефоне (для групп).
  final String? lastSenderName;

  String get displayName => peer.displayName;

  bool get lastIsOutgoing =>
      lastMessage != null && lastMessage!.senderId == ownerCharacterId;

  DateTime get sortTime => lastMessage?.sentAt ?? chat.updatedAt;

  factory ChatListItem.fromRow(Map<String, Object?> row) => ChatListItem(
        chat: Chat.fromRow(row),
        peer: ChatPeer.fromRow(row),
        ownerCharacterId: row['owner_character_id'] as String,
        lastMessage: Message.fromPrefixedRow(row, 'm_'),
        lastSenderName: row['m_sender_name'] as String?,
      );
}

/// Шапка открытого чата.
class ChatHeader {
  const ChatHeader({
    required this.chat,
    required this.peer,
    required this.ownerCharacterId,
  });

  final Chat chat;
  final ChatPeer peer;
  final String ownerCharacterId;

  factory ChatHeader.fromRow(Map<String, Object?> row) => ChatHeader(
        chat: Chat.fromRow(row),
        peer: ChatPeer.fromRow(row),
        ownerCharacterId: row['owner_character_id'] as String,
      );
}

/// Сообщение в результатах поиска и в «Избранном».
class MessageHit {
  const MessageHit({
    required this.message,
    required this.peer,
    required this.ownerCharacterId,
  });

  final Message message;
  final ChatPeer peer;
  final String ownerCharacterId;

  bool get outgoing => message.senderId == ownerCharacterId;

  factory MessageHit.fromRow(Map<String, Object?> row) => MessageHit(
        message: Message.fromPrefixedRow(row, 'm_')!,
        peer: ChatPeer.fromRow(row),
        ownerCharacterId: row['owner_character_id'] as String,
      );
}
