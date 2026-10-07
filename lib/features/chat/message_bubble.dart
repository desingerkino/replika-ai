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
}) {
  const round = Radius.circular(Radii.bubble);
  final top = Radius.circular(joinsPrevious ? Radii.joined : Radii.bubble);
  final bottom = Radius.circular(joinsNext ? Radii.joined : Radii.tail);
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
  });

  final MessageRow row;
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

    final deleted = message.deleted;
    // Удалённое — отдельное состояние мессенджера: без заливки, с рамкой и
    // спокойным серо-голубым текстом, одинаково для входящих и исходящих.
    final background = deleted ? Colors.transparent : (outgoing ? rc.bubbleOut : rc.bubbleIn);
    final foreground = deleted ? rc.deletedText : (outgoing ? rc.onBubbleOut : rc.onBubbleIn);
    final metaColor = deleted ? rc.deletedText : (outgoing ? rc.metaOut : rc.metaIn);

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

    final maxWidth = math.min(MediaQuery.sizeOf(context).width * Sizes.bubbleMaxWidthFactor, Sizes.bubbleMaxWidthCap);
    final radius = bubbleRadius(
      outgoing: outgoing,
      joinsPrevious: row.joinsPrevious,
      joinsNext: row.joinsNext,
    );
    // Рамка есть у всех пузырей, чтобы размер не зависел от состояния:
    // у входящего она видимая, у исходящего сливается с заливкой, у
    // удалённого — толще (1.5 px). Отступы внутри уменьшены на её ширину.
    final borderWidth = deleted ? Sizes.lineStrong : Sizes.line;
    final borderColor = deleted ? rc.deletedBorder : (outgoing ? background : rc.bubbleInBorder);
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
      padding: EdgeInsets.fromLTRB(
        Space.m - borderWidth,
        7 - borderWidth,
        Space.s + 2 - borderWidth,
        7 - borderWidth,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: bubbleRadius(
          outgoing: outgoing,
          joinsPrevious: row.joinsPrevious,
          joinsNext: row.joinsNext,
        ),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: (outgoing || deleted)
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
                    child: Icon(AppIcons.markDeleted, size: 16, color: rc.deletedText),
                  ),
                ),
              if (message.type == MessageType.call && !deleted)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: Space.xs + 2),
                    child: Icon(
                      message.text.startsWith('Пропущ') ? AppIcons.callMissed : AppIcons.call,
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

    // «Не отправлено»: красный маркер повтора рядом с пузырём и подпись под ним.
    final failed = outgoing && !deleted && message.state == MessageState.failed;
    final Widget shown = failed ? _FailedMarker(child: bubble) : bubble;

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
            child: onReply == null
                ? shown
                : SwipeToReply(onReply: onReply!, child: shown),
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
          padding: const EdgeInsets.fromLTRB(
            Space.m - 2 - Sizes.line,
            Space.s - Sizes.line,
            Space.s + 2 - Sizes.line,
            7 - Sizes.line,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: Border.all(color: outgoing ? background : rc.bubbleInBorder, width: Sizes.line),
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
        final width = math.min(maxWidth, 280.0) - 6;
        final inner = radius - BorderRadius.circular(3);
        final visual = message.type == MessageType.photo
            ? PhotoContent(media: media, width: width)
            : VideoContent(media: media, width: width);
        return Container(
          padding: const EdgeInsets.all(3 - Sizes.line),
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: Border.all(color: outgoing ? background : rc.bubbleInBorder, width: Sizes.line),
          ),
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
                            child: metaIn(Colors.white, Colors.white),
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
        final onAccent = outgoing ? rc.bubbleOut : Colors.white;
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
          MessageTicks(
            state: state!,
            // До прочтения галочки спокойнее, «прочитано» — ярче и другого оттенка.
            color: color.withValues(alpha: 0.8),
            readColor: readColor,
            failedColor: color,
            size: tickSize,
          ),
        ],
      ],
    );
  }
}

/// Состояние «не отправлено»: красный круглый значок повтора слева от
/// пузыря и подпись под ним. Только оформление: повторной отправки в
/// приложении нет, значок ничего не запускает.
class _FailedMarker extends StatelessWidget {
  const _FailedMarker({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: messageStateLabel(MessageState.failed),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: rc.danger, shape: BoxShape.circle),
                child: Icon(AppIcons.retry, size: 16, color: context.cs.onError),
              ),
            ),
            const SizedBox(width: Space.s),
            Flexible(child: child),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, right: Space.xs),
          child: Text(
            messageStateLabel(MessageState.failed),
            style: context.tt.labelMedium?.copyWith(color: rc.danger, fontWeight: FontWeight.w600),
          ),
        ),
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
