import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/pressable.dart';
import '../../core/util/time_format.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/glass_theme.dart';
import '../chat/message_ticks.dart';
import '../media/media_kinds.dart';
import 'chat_filter.dart';

/// Карточка чата на главном экране: стеклянная плитка с аватаром, именем,
/// превью последнего сообщения, временем и счётчиком.
class ChatTile extends StatefulWidget {
  const ChatTile({
    super.key,
    required this.item,
    required this.now,
    required this.onTap,
    required this.onLongPress,
    this.typing = false,
    this.ring = StoryRing.none,
    this.onAvatarTap,
  });

  final ChatListItem item;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Собеседник печатает — вместо превью «печатает…».
  final bool typing;

  /// Кольцо истории вокруг аватара.
  final StoryRing ring;

  /// Нажатие на аватар (открыть историю). Без него аватар — часть карточки.
  final VoidCallback? onAvatarTap;

  static const double height = 72;
  static const double avatarSize = 58;
  static const double radius = 20;

  /// Поля карточки от краёв экрана и зазор между карточками.
  static const EdgeInsets margin = EdgeInsets.symmetric(horizontal: 20, vertical: 1);

  static const Duration pulseDuration = Duration(milliseconds: 900);

  @override
  State<ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<ChatTile> with SingleTickerProviderStateMixin {
  /// Вспышка при новом входящем: свечение карточки нарастает и гаснет.
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: ChatTile.pulseDuration);

  @override
  void didUpdateWidget(ChatTile old) {
    super.didUpdateWidget(old);
    final grew = widget.item.chat.unreadCount > old.item.chat.unreadCount;
    if (grew && old.item.chat.id == widget.item.chat.id) {
      if (MediaQuery.disableAnimationsOf(context)) return;
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final item = widget.item;
    final chat = item.chat;
    final unread = chat.unreadCount;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

    return Padding(
      padding: ChatTile.margin,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          // 0 → 1 → 0 за время вспышки.
          final t = _pulse.isAnimating ? Curves.easeOut.transform(1 - (2 * _pulse.value - 1).abs()) : 0.0;
          return GlassSurface(
            radius: ChatTile.radius,
            glow: t > 0 ? GlassTheme.accentGlow.withValues(alpha: 0.55 * t) : null,
            child: child!,
          );
        },
        child: Pressable(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(ChatTile.radius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ChatTile.height),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 6, 14, 6),
              child: Row(
                children: [
                  _avatar(context, glass),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                item.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: scaler,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                  color: glass.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatChatCardTime(item.sortTime, widget.now),
                              maxLines: 1,
                              textScaler: scaler,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.25,
                                fontWeight: FontWeight.w400,
                                color: glass.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(child: _preview(context, glass, scaler)),
                            if (chat.muted) ...[
                              const SizedBox(width: 8),
                              Icon(AppIcons.muted, size: 16, color: glass.textTertiary),
                            ],
                            if (unread > 0) ...[
                              const SizedBox(width: 8),
                              _Counter(count: unread),
                            ] else if (chat.isPinned) ...[
                              const SizedBox(width: 8),
                              Icon(AppIcons.pin, size: 16, color: glass.textTertiary),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, GlassTheme glass) {
    final item = widget.item;
    Widget avatar = DecoratedBox(
      // Мягкое свечение вокруг фото.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: glass.shadow, blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Avatar(
        name: item.displayName,
        size: ChatTile.avatarSize,
        imagePath: item.peer.avatarPath,
        tone: item.peer.avatarTone,
        online: item.peer.isOnline,
        ring: widget.ring,
      ),
    );
    if (item.chat.isGroup) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                gradient: GlassTheme.accentGradient,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(AppIcons.group, size: 13, color: Colors.white),
            ),
          ),
        ],
      );
    }
    final onAvatarTap = widget.onAvatarTap;
    if (onAvatarTap == null) return avatar;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAvatarTap,
      child: Semantics(button: true, label: 'История: ${item.displayName}', child: avatar),
    );
  }

  Widget _preview(BuildContext context, GlassTheme glass, TextScaler scaler) {
    final item = widget.item;
    final chat = item.chat;
    final last = item.lastMessage;
    final draft = chat.draft?.trim() ?? '';
    final style = TextStyle(fontSize: 13.5, height: 1.3, color: glass.textSecondary);

    if (widget.typing) {
      return Text(
        'печатает…',
        maxLines: 1,
        textScaler: scaler,
        style: style.copyWith(color: GlassTheme.accentBlue),
      );
    }
    if (draft.isNotEmpty) {
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Черновик: ', style: TextStyle(color: context.rc.draft)),
          TextSpan(text: draft.replaceAll(RegExp(r'\s+'), ' ')),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: scaler,
        style: style,
      );
    }

    final who = chat.isGroup &&
            last != null &&
            !last.deleted &&
            last.type != MessageType.system &&
            last.type != MessageType.call
        ? (item.lastIsOutgoing ? 'Вы' : item.lastSenderName)
        : null;

    if (last?.deleted == true) {
      // Удалённое — системное состояние: приглушённый тон и маленький значок,
      // а не обычное превью. Красный не используется.
      return Row(
        key: const ValueKey('deleted-preview'),
        children: [
          Icon(AppIcons.markDeleted, size: 15, color: glass.textTertiary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              messagePreview(last) ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: scaler,
              style: style.copyWith(color: glass.textTertiary),
            ),
          ),
        ],
      );
    }

    final media = last?.media;
    final fileName = media?.originalName ?? '';
    final String plain;
    if (last != null && last.type == MessageType.file && fileName.isNotEmpty) {
      plain = 'Файл: $fileName';
    } else {
      plain = messagePreview(last) ?? 'Нет сообщений';
    }
    final icon = switch (last?.type) {
      MessageType.voice => AppIcons.waveform,
      MessageType.audio => AppIcons.attachAudio,
      MessageType.file => AppIcons.file,
      MessageType.photo => AppIcons.photo,
      MessageType.video => AppIcons.video,
      MessageType.videoNote => AppIcons.attachVideoNoteFile,
      _ => null,
    };
    final length = last != null &&
            (last.type == MessageType.voice || last.type == MessageType.audio) &&
            media?.duration != null
        ? formatDuration(media!.duration!)
        : null;

    final Widget text = who == null
        ? Text(plain, maxLines: 1, overflow: TextOverflow.ellipsis, textScaler: scaler, style: style)
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: '$who: ', style: TextStyle(color: glass.textPrimary)),
              TextSpan(text: plain),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: scaler,
            style: style,
          );

    final showTicks = item.lastIsOutgoing;
    if (!showTicks && icon == null && length == null) return text;
    return Row(
      children: [
        if (showTicks) ...[
          MessageTicks(state: last!.state, color: glass.textTertiary, readColor: GlassTheme.accentBlue, size: 16),
          const SizedBox(width: 5),
        ],
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: last?.type == MessageType.voice ? GlassTheme.accentBlue : glass.textTertiary,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(child: text),
        if (length != null) ...[
          const SizedBox(width: 10),
          Text(length, maxLines: 1, textScaler: scaler, style: style.copyWith(color: glass.textTertiary)),
        ],
      ],
    );
  }
}

/// Счётчик непрочитанных: светящийся градиентный кружок.
class _Counter extends StatelessWidget {
  const _Counter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: GlassTheme.counterGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: GlassTheme.accentGlow.withValues(alpha: 0.45), blurRadius: 8)],
      ),
      child: Text(
        count > 999 ? '999+' : '$count',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          height: 1.15,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
