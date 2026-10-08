import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/time_format.dart';
import '../../data/models/message.dart';
import '../media/media_content.dart';
import 'chat_rows.dart';
import 'message_labels.dart';
import 'message_ticks.dart';

/// Скругления пузыря: внутри группы соседние углы «стыкуются»,
/// у последнего сообщения группы — острый угол-хвостик.
BorderRadius bubbleRadius({
  required bool outgoing,
  required bool joinsPrevious,
  required bool joinsNext,
  double radius = Radii.bubble,
  double tail = Radii.tail,
}) {
  final round = Radius.circular(radius);
  final top = Radius.circular(joinsPrevious ? Radii.joined : radius);
  final bottom = Radius.circular(joinsNext ? Radii.joined : tail);
  return outgoing
      ? BorderRadius.only(topLeft: round, bottomLeft: round, topRight: top, bottomRight: bottom)
      : BorderRadius.only(topRight: round, bottomRight: round, topLeft: top, bottomLeft: bottom);
}

/// Цитата: на какое сообщение отвечают (в пузыре и над полем ввода).
class QuotedMessage {
  const QuotedMessage({
    required this.messageId,
    required this.author,
    required this.text,
  });

  final String messageId;

  /// «Вы» или имя собеседника, как он записан на телефоне.
  final String author;
  final String text;
}

/// Пузырь сообщения.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.row,
    required this.onLongPress,
    this.onReply,
    this.quote,
    this.onQuoteTap,
    this.selected = false,
    this.senderName,
    this.senderTone,
    this.onDoubleTap,
    this.onReactionTap,
  });

  final MessageRow row;

  /// Двойное касание — быстрая реакция ❤️.
  final VoidCallback? onDoubleTap;

  /// Касание реакции под пузырём — убрать или сменить её.
  final VoidCallback? onReactionTap;
  final VoidCallback onLongPress;

  /// Жест «смахнуть влево» — ответить. null — ответ недоступен.
  final VoidCallback? onReply;
  final QuotedMessage? quote;
  final VoidCallback? onQuoteTap;
  final bool selected;

  /// Имя отправителя в группе (над первым пузырём подряд идущих).
  final String? senderName;

  /// Цвет отправителя в этой группе (индекс AvatarTones). Без него —
  /// цвет по имени.
  final int? senderTone;

  bool get _showSender => senderName != null && !row.outgoing && !row.joinsPrevious;

  Widget _withSenderInside(Widget child) => _showSender
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [_senderLabel(), child],
        )
      : child;

  Widget _senderLabel() => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          senderName!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: senderTone != null ? AvatarTones.at(senderTone!) : AvatarTones.forKey(senderName!),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final message = row.message;
    final outgoing = row.outgoing;

    if (message.type == MessageType.system) {
      return DaySeparator(label: message.text);
    }

    final background = outgoing ? rc.bubbleOut : rc.bubbleIn;
    final foreground = outgoing ? rc.onBubbleOut : rc.onBubbleIn;
    final metaColor = outgoing ? rc.metaOut : rc.metaIn;
    final deleted = message.deleted;

    final String content;
    if (deleted) {
      content = 'Сообщение удалено';
    } else if (message.type == MessageType.text || message.isMedia || message.type == MessageType.call) {
      content = message.text;
    } else {
      content = message.text.trim().isEmpty
          ? messageTypeLabel(message.type)
          : '${messageTypeLabel(message.type)}\n${message.text}';
    }

    final time = formatClock(message.sentAt);
    final state = outgoing && !deleted ? message.state : null;
    final metaWidth = BubbleMeta.estimateWidth(
      context,
      time: time,
      edited: message.edited && !deleted,
      hasTicks: state != null,
      favorite: message.favorite,
    );

    final style = context.style;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = math.min(
      screenWidth * (message.isMedia ? Sizes.mediaMaxWidthFactor : Sizes.bubbleMaxWidthFactor),
      Sizes.bubbleMaxWidthCap,
    );
    final radius = bubbleRadius(
      outgoing: outgoing,
      joinsPrevious: row.joinsPrevious,
      joinsNext: row.joinsNext,
      radius: style.bubbleRadius,
      tail: style.bubbleTail,
    );
    final Widget bubble = !deleted && message.isMedia
        ? (_showSender
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(padding: const EdgeInsets.only(left: Space.s), child: _senderLabel()),
                  _mediaBubble(context, background, foreground, metaColor, radius, maxWidth, time, state, metaWidth),
                ],
              )
            : _mediaBubble(context, background, foreground, metaColor, radius, maxWidth, time, state, metaWidth))
        : Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(Space.m, 7, Space.s + 2, 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        boxShadow: outgoing
            ? null
            : const [BoxShadow(color: Color(0x14000000), blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: _withSenderInside(_withQuote(context, outgoing, Stack(
        children: [
          Text.rich(
            TextSpan(children: [
              if (deleted)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: Icon(AppIcons.markDeleted, size: 15, color: metaColor),
                  ),
                ),
              if (message.type == MessageType.call && !deleted)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: Space.xs + 2),
                    child: Icon(
                      message.text.startsWith('Пропущ') ? Icons.phone_missed_rounded : Icons.call_rounded,
                      size: 17,
                      color: message.text.startsWith('Пропущ') ? rc.danger : foreground,
                    ),
                  ),
                ),
              TextSpan(text: content),
              // Резерв места под время и галочки в последней строке.
              WidgetSpan(child: SizedBox(width: metaWidth + Space.s, height: 1)),
            ]),
            style: AppType.message.copyWith(
              color: deleted ? metaColor : foreground,
              fontStyle: FontStyle.normal,
            ),
            strutStyle: AppType.messageStrut,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: BubbleMeta(
              time: time,
              color: metaColor,
              readColor: rc.tickRead,
              state: state,
              favorite: message.favorite,
              edited: message.edited && !deleted,
            ),
          ),
        ],
      ))),
    );

    return AnimatedContainer(
      duration: Motion.fast,
      margin: EdgeInsets.only(top: row.joinsPrevious ? 2 : Space.s),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? rc.selection : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Align(
        alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Semantics(
          label: outgoing ? 'Исходящее сообщение' : 'Входящее сообщение',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPress,
            onDoubleTap: onDoubleTap,
            child: _withReaction(
              context,
              onReply == null ? bubble : SwipeToReply(onReply: onReply!, child: bubble),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaBubble(
    BuildContext context,
    Color background,
    Color foreground,
    Color metaColor,
    BorderRadius radius,
    double maxWidth,
    String time,
    MessageState? state,
    double metaWidth,
  ) {
    final rc = context.rc;
    final cs = context.cs;
    final message = row.message;
    final outgoing = row.outgoing;
    final media = message.media;
    final caption = message.text.trim();

    BubbleMeta metaIn(Color color, Color readColor) => BubbleMeta(
          time: time,
          color: color,
          readColor: readColor,
          state: state,
          favorite: message.favorite,
          edited: message.edited,
        );

    Widget padded(Widget child) => Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.fromLTRB(Space.m - 2, Space.s, Space.s + 2, 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            boxShadow: outgoing
                ? null
                : const [BoxShadow(color: Color(0x14000000), blurRadius: 1, offset: Offset(0, 1))],
          ),
          child: _withQuote(context, outgoing, child),
        );

    Widget captionBlock() => _CaptionText(
          text: caption,
          color: foreground,
          meta: metaIn(metaColor, rc.tickRead),
          metaWidth: metaWidth,
        );

    if (media == null || !mediaFileExists(media)) {
      return padded(Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MissingMedia(color: metaColor),
          const SizedBox(width: Space.m),
          metaIn(metaColor, rc.tickRead),
        ],
      ));
    }

    switch (message.type) {
      case MessageType.photo:
      case MessageType.video:
        final width = math.min(maxWidth, context.style.mediaMaxWidth) - 6;
        final inner = radius - BorderRadius.circular(3);
        final visual = message.type == MessageType.photo
            ? PhotoContent(media: media, width: width)
            : VideoContent(media: media, width: width);
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: background, borderRadius: radius),
          child: _withQuote(
            context,
            outgoing,
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: caption.isEmpty
                      ? inner
                      : BorderRadius.only(topLeft: inner.topLeft, topRight: inner.topRight),
                  child: Stack(
                    children: [
                      visual,
                      if (caption.isEmpty)
                        Positioned(
                          right: Space.s - 2,
                          bottom: Space.s - 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x80000000),
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: metaIn(MediaPalette.onMedia, MediaPalette.onMedia),
                          ),
                        ),
                    ],
                  ),
                ),
                if (caption.isNotEmpty)
                  SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.s, 6, Space.xs, 4),
                      child: captionBlock(),
                    ),
                  ),
              ],
            ),
          ),
        );
      case MessageType.videoNote:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            VideoNoteContent(media: media),
            const SizedBox(height: Space.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: rc.daySeparator,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: metaIn(rc.onDaySeparator, cs.primary),
            ),
          ],
        );
      case MessageType.voice:
      case MessageType.audio:
        final accent = outgoing ? rc.onBubbleOut : cs.primary;
        final onAccent = outgoing ? rc.bubbleOut : MediaPalette.onMedia;
        final muted = outgoing ? rc.metaOut : rc.metaIn;
        return padded(Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: AudioContent(
                    media: media,
                    voice: message.type == MessageType.voice,
                    foreground: foreground,
                    accent: accent,
                    onAccent: onAccent,
                    muted: muted,
                  ),
                ),
                if (caption.isEmpty) ...[
                  const SizedBox(width: Space.s),
                  metaIn(metaColor, rc.tickRead),
                ],
              ],
            ),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              captionBlock(),
            ],
          ],
        ));
      default:
        return padded(Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FileContent(media: media, foreground: foreground, muted: metaColor),
            const SizedBox(height: Space.xs),
            if (caption.isNotEmpty) captionBlock() else metaIn(metaColor, rc.tickRead),
          ],
        ));
    }
  }

  /// Реакция-эмодзи под пузырём, со стороны отправителя.
  Widget _withReaction(BuildContext context, Widget bubble) {
    final reaction = row.message.reaction;
    if (reaction == null || reaction.isEmpty || row.message.deleted) return bubble;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: row.outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubble,
        Padding(
          padding: const EdgeInsets.only(top: 3, left: Space.xs, right: Space.xs),
          child: ReactionChip(emoji: reaction, onTap: onReactionTap),
        ),
      ],
    );
  }

  Widget _withQuote(BuildContext context, bool outgoing, Widget body) {
    final q = quote;
    if (q == null) return body;
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuoteBlock(quote: q, onBubbleOut: outgoing, onTap: onQuoteTap),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }
}

/// Подпись к медиа с временем в последней строке.
class _CaptionText extends StatelessWidget {
  const _CaptionText({
    required this.text,
    required this.color,
    required this.meta,
    required this.metaWidth,
  });

  final String text;
  final Color color;
  final Widget meta;
  final double metaWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: text),
            WidgetSpan(child: SizedBox(width: metaWidth + Space.s, height: 1)),
          ]),
          style: AppType.message.copyWith(color: color),
          strutStyle: AppType.messageStrut,
        ),
        Positioned(right: 0, bottom: 0, child: meta),
      ],
    );
  }
}

/// Блок цитаты внутри пузыря.
class QuoteBlock extends StatelessWidget {
  const QuoteBlock({
    super.key,
    required this.quote,
    required this.onBubbleOut,
    this.onTap,
  });

  final QuotedMessage quote;
  final bool onBubbleOut;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final accent = onBubbleOut ? rc.onBubbleOut.withValues(alpha: 0.85) : cs.primary;
    final background = onBubbleOut
        ? rc.onBubbleOut.withValues(alpha: 0.12)
        : cs.primary.withValues(alpha: 0.08);
    final textColor = onBubbleOut ? rc.onBubbleOut.withValues(alpha: 0.85) : rc.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.joined),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, 5, Space.s, 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quote.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    height: 17 / 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  quote.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontSize: 14, height: 18 / 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Смахивание пузыря влево — ответить на сообщение.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.onReply, required this.child});

  final VoidCallback onReply;
  final Widget child;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  static const double _max = 72;
  static const double _trigger = 52;

  double _dx = 0;
  bool _dragging = false;
  bool _armed = false;

  void _update(DragUpdateDetails details) {
    final next = (_dx + details.delta.dx).clamp(-_max, 0.0);
    final armed = -next >= _trigger;
    if (armed && !_armed) HapticFeedback.lightImpact();
    setState(() {
      _dx = next;
      _armed = armed;
      _dragging = true;
    });
  }

  void _end() {
    if (_armed) widget.onReply();
    setState(() {
      _dx = 0;
      _armed = false;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (-_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: (_) => _end(),
      onHorizontalDragCancel: _end,
      child: Stack(
        alignment: Alignment.centerRight,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: Space.xs,
            child: Opacity(
              opacity: progress,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.rc.daySeparator,
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.reply, size: 20, color: context.rc.onDaySeparator),
              ),
            ),
          ),
          AnimatedContainer(
            duration: _dragging ? Duration.zero : Motion.normal,
            curve: Motion.curve,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Время, отметки «изменено»/«избранное» и статус внутри пузыря.
class BubbleMeta extends StatelessWidget {
  const BubbleMeta({
    super.key,
    required this.time,
    required this.color,
    required this.readColor,
    this.state,
    this.favorite = false,
    this.edited = false,
  });

  final String time;
  final Color color;
  final Color readColor;
  final MessageState? state;
  final bool favorite;
  final bool edited;

  static const double tickSize = 16;
  static const double starSize = 12;

  static String _label(String time, bool edited) => edited ? 'изм. $time' : time;

  /// Оценка ширины блока — для резерва места в последней строке текста.
  static double estimateWidth(
    BuildContext context, {
    required String time,
    required bool edited,
    required bool hasTicks,
    required bool favorite,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: _label(time, edited), style: AppType.meta),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width.ceilToDouble() +
        (hasTicks ? 3 + tickSize : 0) +
        (favorite ? starSize + 2 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (favorite)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(AppIcons.star, size: starSize, color: color),
          ),
        Text(_label(time, edited), style: AppType.meta.copyWith(color: color)),
        if (state != null) ...[
          const SizedBox(width: 3),
          MessageTicks(state: state!, color: color, readColor: readColor, size: tickSize),
        ],
      ],
    );
  }
}

/// Плашка дня («Сегодня», «10 сентября») и системных событий.
class DaySeparator extends StatelessWidget {
  const DaySeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.m),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
          decoration: BoxDecoration(
            color: rc.daySeparator,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: context.tt.labelMedium?.copyWith(
              color: rc.onDaySeparator,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Быстрые реакции в меню сообщения.
const List<String> quickReactions = ['❤️', '👍', '😂', '🔥', '😮', '😢', '🙏', '👎'];

/// Реакция под пузырём: эмодзи на светлой «таблетке» с тенью.
class ReactionChip extends StatelessWidget {
  const ReactionChip({super.key, required this.emoji, this.onTap});

  final String emoji;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Semantics(
      button: onTap != null,
      label: 'Реакция $emoji',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: cs.surface, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 16, height: 1.2)),
        ),
      ),
    );
  }
}

/// Строка быстрых реакций над меню сообщения.
class ReactionPicker extends StatelessWidget {
  const ReactionPicker({super.key, required this.onPick, this.current});

  final ValueChanged<String> onPick;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final emoji in quickReactions)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: emoji == current ? cs.primaryContainer : cs.surfaceContainerHigh,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onPick(emoji);
                  },
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
