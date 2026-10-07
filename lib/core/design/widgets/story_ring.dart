import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Состояние кольца вокруг аватара в ленте контактов.
/// [none] — без кольца, [unviewed] — живой градиент (есть новая история),
/// [viewed] — спокойное серо-голубое кольцо без движения.
enum StoryRing { none, unviewed, viewed }

/// Цвета непросмотренной истории: синий → фиолетовый → розово-фиолетовый →
/// зелёный → снова синий. Приглушённые, без неона; первый и последний цвета
/// совпадают, чтобы кольцо замыкалось без шва.
const List<Color> storyRingColors = [
  Color(0xFF2F7FD0),
  Color(0xFF7C5CD6),
  Color(0xFFB057C4),
  Color(0xFF2FA67A),
  Color(0xFF2F7FD0),
];

/// Полный цикл переливания градиента по кольцу.
const Duration storyRingCycle = Duration(seconds: 4);

/// Кольцо истории. Рисует только само кольцо: аватар внутри не двигается
/// и не перерисовывается. Градиент медленно «течёт» по окружности (сдвиг
/// фазы), отдельный слой перерисовывается только им. При отключённых
/// анимациях градиент остаётся, но стоит на месте.
class StoryRingView extends StatefulWidget {
  const StoryRingView({
    super.key,
    required this.ring,
    required this.width,
    required this.viewedColor,
  });

  final StoryRing ring;
  final double width;
  final Color viewedColor;

  @override
  State<StoryRingView> createState() => _StoryRingViewState();
}

class _StoryRingViewState extends State<StoryRingView> with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(vsync: this, duration: storyRingCycle);

  void _sync() {
    final animate = widget.ring == StoryRing.unviewed && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_phase.isAnimating) {
      _phase.repeat();
    } else if (!animate && _phase.isAnimating) {
      _phase.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StoryRingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _StoryRingPainter(
          phase: _phase,
          ring: widget.ring,
          width: widget.width,
          viewedColor: widget.viewedColor,
        ),
      ),
    );
  }
}

class _StoryRingPainter extends CustomPainter {
  _StoryRingPainter({
    required this.phase,
    required this.ring,
    required this.width,
    required this.viewedColor,
  }) : super(repaint: phase);

  final Animation<double> phase;
  final StoryRing ring;
  final double width;
  final Color viewedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true;
    if (ring == StoryRing.unviewed) {
      paint.shader = SweepGradient(
        colors: storyRingColors,
        transform: GradientRotation(phase.value * 2 * math.pi),
      ).createShader(rect);
    } else {
      paint.color = viewedColor;
    }
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(_StoryRingPainter oldDelegate) =>
      oldDelegate.ring != ring || oldDelegate.width != width || oldDelegate.viewedColor != viewedColor;
}
