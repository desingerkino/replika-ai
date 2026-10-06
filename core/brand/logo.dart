import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Знак «Реплики»: реплика-пузырь с точками «печатает» и открытая хлопушка.
/// Та же геометрия используется в tool/generate_icons.py для иконки.
class ReplikaLogo extends StatelessWidget {
  const ReplikaLogo({super.key, this.size = 64, this.onDark = false});

  final double size;

  /// true — вариант для тёмного фона и иконки (белый пузырь).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Логотип',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _LogoPainter(onDark: onDark)),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.onDark});

  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 100;
    canvas.save();
    canvas.scale(scale);

    final slateColor = onDark ? Palette.tungsten : Palette.ink;
    final stripeColor = onDark ? Palette.ink : Palette.tungsten;
    final bubbleColor = onDark ? Palette.white : Palette.petrol;
    final dotColor = onDark ? Palette.petrol : Palette.white;

    // Планка хлопушки.
    final slate = Path()
      ..moveTo(10, 26)
      ..lineTo(86, 8)
      ..lineTo(89, 19)
      ..lineTo(13, 37)
      ..close();
    canvas.drawPath(slate, Paint()..color = slateColor);

    canvas.save();
    canvas.clipPath(slate);
    final stripe = Paint()
      ..color = stripeColor
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.butt;
    for (double x = 2; x < 100; x += 16) {
      canvas.drawLine(Offset(x, 44), Offset(x + 22, 0), stripe);
    }
    canvas.restore();

    // Пузырь-реплика с хвостиком.
    final bubblePaint = Paint()..color = bubbleColor;
    canvas.drawRRect(
      RRect.fromLTRBR(10, 40, 90, 86, const Radius.circular(16)),
      bubblePaint,
    );
    final tail = Path()
      ..moveTo(22, 84)
      ..lineTo(15, 97)
      ..lineTo(40, 84)
      ..close();
    canvas.drawPath(tail, bubblePaint);

    // Три точки «печатает».
    final dotPaint = Paint()..color = dotColor;
    for (final x in const [34.0, 50.0, 66.0]) {
      canvas.drawCircle(Offset(x, 63), 5.5, dotPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => oldDelegate.onDark != onDark;
}
