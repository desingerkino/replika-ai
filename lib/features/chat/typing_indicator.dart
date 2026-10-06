import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/tokens.dart';

/// Входящий пузырь с тремя «дышащими» точками — собеседник печатает.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return Semantics(
      label: 'Собеседник печатает',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.xs, 1),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: rc.bubbleIn,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(Radii.bubble),
                topRight: Radius.circular(Radii.bubble),
                bottomRight: Radius.circular(Radii.bubble),
                bottomLeft: Radius.circular(Radii.tail),
              ),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Opacity(
                      opacity: _dotOpacity(_controller.value, i),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: rc.metaIn, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Каждая точка вспыхивает со сдвигом на треть цикла.
  static double _dotOpacity(double t, int index) {
    final phase = (t - index / 3) % 1.0;
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 0.3 + 0.7 * wave;
  }
}
