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
