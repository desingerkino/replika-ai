import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/pressable.dart';
import '../../core/design/widgets/unread_badge.dart';
import '../../core/util/time_format.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../chat/message_ticks.dart';
import 'chat_filter.dart';

/// Строка списка чатов.
class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.item,
    required this.now,
    required this.onTap,
    required this.onLongPress,
    this.showDivider = true,
    this.typing = false,
  });

  final ChatListItem item;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool showDivider;

  /// Собеседник печатает — вместо превью «печатает…».
  final bool typing;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final chat = item.chat;
    final last = item.lastMessage;
    final draft = chat.draft?.trim() ?? '';
    final hasDraft = draft.isNotEmpty;
    final unread = chat.unreadCount;
    final time = formatChatListTime(item.sortTime, now);

    // Непрочитанное превью чуть темнее: иерархия имя → превью → время.
    final previewStyle = tt.bodyMedium?.copyWith(
      color: unread > 0 && !chat.muted ? rc.textPrimary : rc.textSecondary,
    );
    final Widget preview;
    if (typing) {
      preview = Text(
        'печатает…',
        maxLines: 1,
        style: previewStyle?.copyWith(color: context.cs.primary),
      );
    } else if (hasDraft) {
      preview = Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Черновик: ', style: TextStyle(color: rc.draft)),
          TextSpan(text: draft.replaceAll(RegExp(r'\s+'), ' ')),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: previewStyle,
      );
    } else {
      final plain = messagePreview(last) ?? 'Нет сообщений';
      final who = item.chat.isGroup &&
              last != null &&
              !last.deleted &&
              last.type != MessageType.system &&
              last.type != MessageType.call
          ? (item.lastIsOutgoing ? 'Вы' : item.lastSenderName)
          : null;
      final text = who == null ? plain : '$who: $plain';
      preview = Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: previewStyle,
      );
    }

    // Мягкая подсветка вместо Material-волны (Pressable, 120 мс).
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.chatRowMinHeight),
        child: Padding(
          padding: const EdgeInsets.only(left: Space.l),
          child: Row(
            children: [
              Avatar(
                name: item.displayName,
                imagePath: item.peer.avatarPath,
                tone: item.peer.avatarTone,
                online: item.peer.isOnline,
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(0, Space.m, Space.l, Space.m),
                  decoration: BoxDecoration(
                    border: showDivider
                        ? Border(bottom: BorderSide(color: rc.divider, width: Sizes.line))
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleMedium,
                            ),
                          ),
                          if (chat.muted) ...[
                            const SizedBox(width: Space.xs),
                            Icon(AppIcons.muted, size: 15, color: rc.textTertiary),
                          ],
                          if (item.lastIsOutgoing && !hasDraft && last?.deleted != true) ...[
                            const SizedBox(width: Space.s),
                            MessageTicks(
                              state: last!.state,
                              color: rc.textTertiary,
                              readColor: rc.badge,
                            ),
                          ],
                          const SizedBox(width: Space.xs),
                          Text(
                            time,
                            style: tt.labelMedium?.copyWith(
                              color: unread > 0 && !chat.muted ? rc.badge : rc.textTertiary,
                              fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(child: preview),
                          if (unread > 0) ...[
                            const SizedBox(width: Space.s),
                            UnreadBadge(count: unread, muted: chat.muted),
                          ] else if (chat.isPinned) ...[
                            const SizedBox(width: Space.s),
                            Icon(AppIcons.pin, size: 16, color: rc.textTertiary),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
