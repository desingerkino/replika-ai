// Чаты с эталона главного экрана (docs/brand/chats_reference.png) — для
// тестов и снимка экрана. В приложение эти данные не входят.
import 'package:replika/data/models/chat.dart';
import 'package:replika/data/models/media_item.dart';
import 'package:replika/data/models/message.dart';

const String refOwner = 'hero';

/// «Сейчас» эталона: среда, 7 октября 2026, 09:45.
final DateTime refNow = DateTime(2026, 10, 7, 9, 45);

ChatListItem refChat(
  String id,
  String name, {
  required DateTime at,
  String text = '',
  MessageType type = MessageType.text,
  String? sender,
  String? senderName,
  MessageState state = MessageState.delivered,
  MediaItem? media,
  int unread = 0,
  bool muted = false,
  bool pinned = false,
  bool group = false,
  bool online = false,
  bool deleted = false,
  String? draft,
}) {
  final from = sender ?? (group ? 'member-$id' : 'peer-$id');
  return ChatListItem(
    chat: Chat(
      id: id,
      deviceId: 'device',
      peerCharacterId: group ? null : 'peer-$id',
      title: group ? name : null,
      isGroup: group,
      pinnedAt: pinned ? at : null,
      unreadCount: unread,
      muted: muted,
      draft: draft,
      createdAt: at,
      updatedAt: at,
    ),
    peer: ChatPeer(displayName: name, statusText: online ? 'в сети' : 'был недавно'),
    ownerCharacterId: refOwner,
    lastSenderName: senderName,
    lastMessage: Message(
      id: 'm-$id',
      chatId: id,
      senderId: from,
      type: type,
      text: text,
      state: state,
      media: media,
      deleted: deleted,
      sentAt: at,
      createdAt: at,
    ),
  );
}

/// Семь чатов эталона, сверху вниз.
List<ChatListItem> referenceChats() {
  final today = refNow;
  DateTime at(int daysAgo, int hour, int minute) =>
      DateTime(today.year, today.month, today.day - daysAgo, hour, minute);
  return [
    refChat('anna', 'Анна Смирнова', at: at(0, 9, 41), text: 'Я уже в кафе, ты где?', unread: 3, online: true),
    refChat('alex', 'Алекс', at: at(0, 9, 28), text: 'Буду через 10 минут', unread: 1, online: true),
    refChat(
      'scene7',
      'Проект «Сцена 7»',
      at: at(0, 8, 54),
      text: 'Скинул новые кадры с площадки',
      senderName: 'Игорь',
      unread: 12,
      muted: true,
      group: true,
    ),
    refChat(
      'victoria',
      'Виктория Лебедева',
      at: at(1, 21, 10),
      type: MessageType.voice,
      media: MediaItem(
        id: 'voice',
        kind: MediaKind.voice,
        path: '/nowhere/voice.m4a',
        durationMs: 24000,
        createdAt: at(1, 21, 10),
      ),
    ),
    refChat(
      'dmitry',
      'Дмитрий Кузнецов',
      at: at(1, 18, 2),
      type: MessageType.file,
      media: MediaItem(
        id: 'file',
        kind: MediaKind.file,
        path: '/nowhere/list.pdf',
        originalName: 'Список реквизита.pdf',
        createdAt: at(1, 18, 2),
      ),
      pinned: true,
    ),
    refChat(
      'maria',
      'Мария Ковалева',
      at: at(2, 16, 30),
      text: 'Хорошо, вижу',
      sender: refOwner,
      state: MessageState.read,
    ),
    refChat(
      'team',
      'Команда',
      at: at(2, 11, 5),
      text: 'Завтра в 12 на площадке',
      senderName: 'Данил',
      group: true,
    ),
  ];
}
