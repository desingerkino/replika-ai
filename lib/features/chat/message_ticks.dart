import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../data/models/message.dart';
import 'message_labels.dart';

/// Статус исходящего: часы — отправляется, одна галочка — отправлено,
/// две — доставлено, две яркие цветные — прочитано, знак ошибки — не отправлено.
///
/// [color] — спокойный цвет до прочтения, [readColor] — заметнее него
/// (светлее и с другим оттенком). [failedColor] — цвет знака ошибки;
/// по умолчанию красный, внутри цветного пузыря его задают светлым,
/// потому что красный на синем не читается (красный маркер рисуется рядом
/// с пузырём).
class MessageTicks extends StatelessWidget {
  const MessageTicks({
    super.key,
    required this.state,
    required this.color,
    required this.readColor,
    this.failedColor,
    this.size = 16,
  });

  final MessageState state;
  final Color color;
  final Color readColor;
  final Color? failedColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      MessageState.sending => Icon(AppIcons.sending, size: size - 3, color: color),
      MessageState.sent => Icon(AppIcons.tickSent, size: size, color: color),
      MessageState.delivered => Icon(AppIcons.tickDouble, size: size, color: color),
      MessageState.read => Icon(AppIcons.tickDouble, size: size, color: readColor),
      MessageState.failed => Icon(AppIcons.error, size: size, color: failedColor ?? context.rc.danger),
    };
    return Semantics(
      label: messageStateLabel(state),
      child: SizedBox(width: size, height: size, child: Center(child: icon)),
    );
  }
}
