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

/// Фильтр списка чатов (капсулы под поиском).
enum ChatFilter {
  all('Все'),
  personal('Личные'),
  groups('Группы'),
  archive('Архив');

  const ChatFilter(this.label);

  final String label;
}

/// Чаты под фильтром. Архивные видны только в «Архиве»; остальные фильтры
/// показывают то, что не в архиве.
List<ChatListItem> applyChatFilter(
  List<ChatListItem> items,
  ChatFilter filter,
  Set<String> archived,
) {
  bool inArchive(ChatListItem item) => archived.contains(item.chat.id);
  return switch (filter) {
    ChatFilter.all => items.where((i) => !inArchive(i)).toList(),
    ChatFilter.personal => items.where((i) => !inArchive(i) && !i.chat.isGroup).toList(),
    ChatFilter.groups => items.where((i) => !inArchive(i) && i.chat.isGroup).toList(),
    ChatFilter.archive => items.where(inArchive).toList(),
  };
}
