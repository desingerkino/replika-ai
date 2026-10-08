import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Знак «Реплики»: плитка с двумя пересекающимися репликами-пузырями.
class ReplikaLogo extends StatelessWidget {
  const ReplikaLogo({super.key, this.size = 64, this.onDark = false});

  final double size;

  /// true — вариант для тёмного фона (светлая плитка).
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

    final tileColor = onDark ? Palette.white : Palette.ink;
    final firstBubble = onDark ? Palette.ink : Palette.white;
    final secondBubble = onDark ? Palette.brand : Palette.brandBright;

    // Плитка.
    canvas.drawRRect(
      RRect.fromLTRBR(0, 0, 100, 100, const Radius.circular(24)),
      Paint()..color = tileColor,
    );

    // Первая реплика (слева сверху).
    final first = Paint()..color = firstBubble;
    canvas.drawRRect(RRect.fromLTRBR(16, 20, 66, 52, const Radius.circular(12)), first);
    canvas.drawPath(
      Path()
        ..moveTo(24, 50)
        ..lineTo(20, 63)
        ..lineTo(36, 50)
        ..close(),
      first,
    );

    // Вторая реплика (справа снизу) с рамкой цвета плитки на пересечении.
    final secondRect = RRect.fromLTRBR(34, 44, 84, 76, const Radius.circular(12));
    final secondTail = Path()
      ..moveTo(76, 74)
      ..lineTo(80, 87)
      ..lineTo(64, 74)
      ..close();
    final gap = Paint()
      ..color = tileColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(secondRect, gap);
    canvas.drawPath(secondTail, gap);
    final second = Paint()..color = secondBubble;
    canvas.drawRRect(secondRect, second);
    canvas.drawPath(secondTail, second);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => oldDelegate.onDark != onDark;
}
