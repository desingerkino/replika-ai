import 'package:flutter/widgets.dart';

/// Мягкое свечение (bloom) позади [child]: радиальный градиент, который
/// плавно сходит на нет. Яркость задаётся [intensity] (0…1), поэтому
/// свечение можно «дышать» анимацией, не перерисовывая само содержимое.
class GlowEffect extends StatelessWidget {
  const GlowEffect({
    super.key,
    required this.child,
    required this.color,
    this.intensity = 1,
    this.spread = 1,
  });

  final Widget child;
  final Color color;

  /// 0 — свечения нет, 1 — полная яркость.
  final double intensity;

  /// Радиус свечения в долях половины меньшей стороны [child].
  final double spread;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlowPainter(color: color, intensity: intensity.clamp(0.0, 1.0), spread: spread),
      child: child,
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter({required this.color, required this.intensity, required this.spread});

  final Color color;
  final double intensity;
  final double spread;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0 || size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * spread;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: 0.42 * intensity),
        color.withValues(alpha: 0.16 * intensity),
        color.withValues(alpha: 0),
      ],
      stops: const [0.55, 0.8, 1],
    ).createShader(rect);
    canvas.drawCircle(center, radius, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.intensity != intensity || old.color != color || old.spread != spread;
}
