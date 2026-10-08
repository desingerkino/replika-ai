import '../../core/util/text.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../chat/message_labels.dart';

/// Текст превью последнего сообщения в списке чатов.
String? messagePreview(Message? message) {
  if (message == null) return null;
  if (message.deleted) return 'Сообщение удалено';
  if (message.type == MessageType.text || message.type == MessageType.call) {
    return singleLine(message.text);
  }
  final label = messageTypeLabel(message.type);
  final caption = singleLine(message.text);
  return caption.isEmpty ? label : '$label, $caption';
}

/// Поиск по имени собеседника и тексту последнего сообщения.
List<ChatListItem> filterChats(List<ChatListItem> items, String query) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return items;
  return items.where((item) {
    if (normalizeForSearch(item.displayName).contains(q)) return true;
    final preview = messagePreview(item.lastMessage);
    return preview != null && normalizeForSearch(preview).contains(q);
  }).toList();
}

/// Папки над списком чатов.
enum ChatFolder {
  all('Все чаты'),
  unread('Непрочитанные'),
  personal('Личные'),
  groups('Группы');

  const ChatFolder(this.label);
  final String label;
}

/// Чаты, попадающие в папку.
List<ChatListItem> filterByFolder(List<ChatListItem> items, ChatFolder folder) => switch (folder) {
      ChatFolder.all => items,
      ChatFolder.unread => items.where((i) => i.chat.unreadCount > 0).toList(),
      ChatFolder.personal => items.where((i) => !i.chat.isGroup).toList(),
      ChatFolder.groups => items.where((i) => i.chat.isGroup).toList(),
    };

/// Значок типа последнего сообщения в превью (null — без значка).
enum PreviewGlyph { photo, video, videoNote, voice, audio, file, call, missedCall }

PreviewGlyph? previewGlyph(Message? message) {
  if (message == null || message.deleted) return null;
  return switch (message.type) {
    MessageType.photo => PreviewGlyph.photo,
    MessageType.video => PreviewGlyph.video,
    MessageType.videoNote => PreviewGlyph.videoNote,
    MessageType.voice => PreviewGlyph.voice,
    MessageType.audio => PreviewGlyph.audio,
    MessageType.file => PreviewGlyph.file,
    MessageType.call => message.text.startsWith('Пропущ') ? PreviewGlyph.missedCall : PreviewGlyph.call,
    _ => null,
  };
}
