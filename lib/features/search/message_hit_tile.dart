import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/pressable.dart';
import '../../core/util/text.dart';
import '../../core/util/time_format.dart';
import '../../data/models/chat.dart';
import '../chats/chat_filter.dart';

/// Найденное или избранное сообщение: собеседник, время, текст
/// с подсветкой совпадения.
class MessageHitTile extends StatelessWidget {
  const MessageHitTile({
    super.key,
    required this.hit,
    required this.now,
    required this.onTap,
    this.onLongPress,
    this.query = '',
    this.maxLines = 1,
  });

  final MessageHit hit;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String query;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final message = hit.message;
    final source = message.text.trim().isEmpty ? (messagePreview(message) ?? '') : message.text;
    final text = query.trim().isEmpty ? singleLine(source) : excerpt(source, query);
    final base = tt.bodyMedium?.copyWith(color: rc.textSecondary);
    final match = findMatch(text, query);

    final spans = <TextSpan>[
      if (hit.outgoing) TextSpan(text: 'Вы: ', style: TextStyle(color: rc.textTertiary)),
      if (match == null)
        TextSpan(text: text)
      else ...[
        TextSpan(text: text.substring(0, match.start)),
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(color: context.cs.primary, fontWeight: FontWeight.w700),
        ),
        TextSpan(text: text.substring(match.end)),
      ],
    ];

    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m - 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(
              name: hit.peer.displayName,
              size: Sizes.avatarContact,
              imagePath: hit.peer.avatarPath,
              tone: hit.peer.avatarTone,
              online: hit.peer.isOnline,
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          hit.peer.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall,
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      Text(
                        formatChatListTime(message.sentAt, now),
                        style: tt.labelMedium?.copyWith(color: rc.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: spans),
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: base,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
