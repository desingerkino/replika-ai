import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/unread_badge.dart';
import '../../core/util/time_format.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../chat/message_ticks.dart';
import 'chat_filter.dart';

/// Строка списка чатов: крупный аватар, имя, превью со значком типа,
/// время, счётчик или галочки, закреп.
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
    final cs = context.cs;
    final tt = context.tt;
    final style = context.style;
    final chat = item.chat;
    final last = item.lastMessage;
    final draft = chat.draft?.trim() ?? '';
    final hasDraft = draft.isNotEmpty;
    final unread = chat.unreadCount;
    final time = formatChatListTime(item.sortTime, now);
    final divider = showDivider && style.listDividers;

    final previewStyle = tt.bodyMedium?.copyWith(color: rc.textSecondary, height: 20 / 15);
    final accentStyle = previewStyle?.copyWith(color: cs.primary);
    final Widget preview;
    if (typing) {
      preview = Row(
        children: [
          _TypingDots(color: cs.primary),
          const SizedBox(width: 6),
          Flexible(child: Text('печатает…', maxLines: 1, style: accentStyle)),
        ],
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
      final who = last != null &&
              !last.deleted &&
              last.type != MessageType.system &&
              last.type != MessageType.call &&
              (item.chat.isGroup || item.lastIsOutgoing)
          ? (item.lastIsOutgoing ? 'Вы' : item.lastSenderName)
          : null;
      final glyph = previewGlyph(last);
      // Медиа без подписи выделяется цветом акцента, как в Telegram.
      final media = glyph != null && glyph != PreviewGlyph.call && glyph != PreviewGlyph.missedCall;
      preview = Row(
        children: [
          if (glyph != null) ...[
            _Glyph(glyph: glyph),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (who != null) TextSpan(text: '$who: ', style: TextStyle(color: rc.textPrimary)),
                TextSpan(text: plain, style: media && !item.lastIsOutgoing ? accentStyle : null),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: previewStyle,
            ),
          ),
        ],
      );
    }

    final avatarSize = style.avatarList;
    return Material(
      color: chat.isPinned ? rc.rowHighlight : Colors.transparent,
      child: InkWell(
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
                  size: avatarSize,
                  imagePath: item.peer.avatarPath,
                  tone: item.peer.avatarTone,
                  online: item.peer.isOnline,
                ),
                const SizedBox(width: Space.m + 2),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(0, Space.m, Space.l, Space.m),
                    decoration: BoxDecoration(
                      border: divider ? Border(bottom: BorderSide(color: rc.divider, width: 0.6)) : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (chat.isGroup) ...[
                              Icon(Icons.group_rounded, size: 16, color: rc.textPrimary),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                item.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 16.5),
                              ),
                            ),
                            if (chat.muted) ...[
                              const SizedBox(width: Space.xs),
                              Icon(AppIcons.muted, size: 15, color: rc.textTertiary),
                            ],
                            const Spacer(),
                            if (chat.isPinned) ...[
                              const SizedBox(width: Space.s),
                              Icon(AppIcons.pin, size: 14, color: rc.textTertiary),
                            ],
                            const SizedBox(width: Space.xs),
                            Text(
                              time,
                              style: tt.labelMedium?.copyWith(
                                color: unread > 0 && !chat.muted ? cs.primary : rc.textTertiary,
                                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: preview),
                            if (unread > 0) ...[
                              const SizedBox(width: Space.s),
                              UnreadBadge(count: unread, muted: chat.muted),
                            ] else if (item.lastIsOutgoing && !hasDraft && last?.deleted != true) ...[
                              const SizedBox(width: Space.s),
                              MessageTicks(
                                state: last!.state,
                                color: rc.textTertiary,
                                readColor: rc.success,
                              ),
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
      ),
    );
  }
}

/// Значок типа сообщения в превью.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.glyph});

  final PreviewGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    if (glyph == PreviewGlyph.video || glyph == PreviewGlyph.videoNote) {
      // Чёрный кружок с белым треугольником.
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(color: rc.textPrimary, shape: BoxShape.circle),
        child: Icon(Icons.play_arrow_rounded, size: 14, color: context.cs.surface),
      );
    }
    final (IconData icon, Color color) = switch (glyph) {
      PreviewGlyph.photo => (Icons.image_outlined, cs.primary),
      PreviewGlyph.voice => (Icons.mic_none_rounded, cs.primary),
      PreviewGlyph.audio => (Icons.music_note_rounded, cs.primary),
      PreviewGlyph.file => (Icons.insert_drive_file_outlined, rc.textSecondary),
      PreviewGlyph.call => (Icons.call_made_rounded, rc.success),
      PreviewGlyph.missedCall => (Icons.call_missed_rounded, rc.danger),
      _ => (Icons.circle, rc.textSecondary),
    };
    return Icon(icon, size: 18, color: color);
  }
}

/// Три точки «печатает» с бегущей волной.
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.2),
              child: Opacity(
                opacity: 0.35 + 0.65 * _wave((_c.value - i * 0.18) % 1),
                child: Container(
                  width: 4.5,
                  height: 4.5,
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static double _wave(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;
}
