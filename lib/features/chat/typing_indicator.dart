import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/glass_theme.dart';
import '../../design_system/replika_logo.dart';
import 'chat_glass.dart';

/// Входящий стеклянный пузырь: сфера Replika и «печатает...».
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
  );

  /// Системное «уменьшить движение»: точки стоят на месте, без бесконечной
  /// анимации.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    return Semantics(
      label: 'Собеседник печатает',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 1),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 16, 7),
              decoration: ChatGlass.bubble(
                context,
                outgoing: false,
                radius: ChatGlass.bubbleRadius(outgoing: false, joinsPrevious: false, joinsNext: false),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Маленькая сфера Replika «дышит» вместе с точками.
                  ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 30,
                      child: OverflowBox(
                        maxWidth: ReplikaOrb.sideFor(24),
                        maxHeight: ReplikaOrb.sideFor(24),
                        child: ReplikaOrb(
                          diameter: 24,
                          glow: _still ? 1 : 0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'печатает',
                    style: TextStyle(color: glass.textSecondary, fontSize: 14.5, height: 20 / 14.5),
                  ),
                  const SizedBox(width: 2),
                  for (var i = 0; i < 3; i++)
                    Opacity(
                      opacity: _still ? 0.65 : _dotOpacity(_controller.value, i),
                      child: Text(
                        '.',
                        style: TextStyle(color: glass.textSecondary, fontSize: 14.5, height: 20 / 14.5),
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

  /// Каждая точка вспыхивает со сдвигом на треть цикла.
  static double _dotOpacity(double t, int index) {
    final phase = (t - index / 3) % 1.0;
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 0.3 + 0.7 * wave;
  }
}
