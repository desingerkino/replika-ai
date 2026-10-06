import '../../core/util/time_format.dart';
import '../../data/models/message.dart';

/// Строка ленты чата: разделитель дня или сообщение.
sealed class ChatRow {
  const ChatRow();
}

final class DaySeparatorRow extends ChatRow {
  const DaySeparatorRow(this.day, this.label);

  final DateTime day;
  final String label;
}

/// Плашка «Непрочитанные сообщения» перед первым непрочитанным.
final class UnreadSeparatorRow extends ChatRow {
  const UnreadSeparatorRow(this.count);

  final int count;
}

final class MessageRow extends ChatRow {
  const MessageRow({
    required this.message,
    required this.outgoing,
    required this.joinsPrevious,
    required this.joinsNext,
  });

  final Message message;
  final bool outgoing;

  /// Сообщение продолжает группу (тот же отправитель, разрыв ≤ 5 минут).
  final bool joinsPrevious;
  final bool joinsNext;
}

/// Максимальный разрыв между сообщениями одной группы.
const Duration groupGap = Duration(minutes: 5);

/// Строит ленту из сообщений в хронологическом порядке.
List<ChatRow> buildChatRows(
  List<Message> messages, {
  required String? ownerId,
  required DateTime now,
  int unreadCount = 0,
}) {
  final firstUnread = _firstUnreadIndex(messages, ownerId, unreadCount);
  final rows = <ChatRow>[];
  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    final previous = i > 0 ? messages[i - 1] : null;
    final next = i + 1 < messages.length ? messages[i + 1] : null;

    if (previous == null || daysBetween(previous.sentAt, message.sentAt) != 0) {
      final at = message.sentAt;
      rows.add(DaySeparatorRow(
        DateTime(at.year, at.month, at.day),
        formatDaySeparator(at, now),
      ));
    }
    if (i == firstUnread) rows.add(UnreadSeparatorRow(unreadCount));
    rows.add(MessageRow(
      message: message,
      outgoing: ownerId != null && message.senderId == ownerId,
      joinsPrevious: previous != null && joinsGroup(previous, message),
      joinsNext: next != null && joinsGroup(message, next),
    ));
  }
  return rows;
}

/// Идут ли сообщения [a] и [b] (b после a) одной группой.
bool joinsGroup(Message a, Message b) {
  if (a.senderId == null || a.senderId != b.senderId) return false;
  if (a.type == MessageType.system || b.type == MessageType.system) return false;
  if (daysBetween(a.sentAt, b.sentAt) != 0) return false;
  return b.sentAt.difference(a.sentAt) <= groupGap;
}

/// Индекс первого из [count] последних входящих сообщений или -1.
int _firstUnreadIndex(List<Message> messages, String? ownerId, int count) {
  if (count <= 0) return -1;
  var found = 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    final sender = messages[i].senderId;
    if (sender != null && sender != ownerId) {
      found++;
      if (found == count) return i;
    }
  }
  return found > 0 ? messages.indexWhere((m) => m.senderId != null && m.senderId != ownerId) : -1;
}
