import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_backgrounds.dart';

/// Фон переписки. [background] — выбранный для чата фон
/// (chats.background, см. [ChatBackgrounds]); null — «Стандартный»: в теме
/// с узором — лёгкие «дудлы» (звёзды, сердца, луны, кружки) поверх цвета
/// фона, как обои Telegram. Узоры нарисованы кодом: ни файлов, ни сети,
/// чёткие на любом экране. Светлый или тёмный фон вопреки теме
/// перекрашивает и пузыри — текст на нём всегда читается.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, this.background, required this.child});

  final String? background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = ChatBackgrounds.byId(background);
    final theme = themeForBackground(context, spec);
    // Узор кэшируется отдельным слоем, прокрутка ленты его не перерисовывает.
    final painted = theme == null
        ? ChatBackgroundPaint(background: spec, child: child)
        : Theme(
            data: theme,
            child: Builder(builder: (context) => ChatBackgroundPaint(background: spec, child: child)),
          );
    return painted;
  }
}

/// Узор-«дудл» плиткой 120×120.
class DoodlePainter extends CustomPainter {
  const DoodlePainter({required this.background, required this.stroke});

  final Color background;
  final Color stroke;

  static const double tile = 120;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var y = 0.0, row = 0; y < size.height + tile; y += tile, row++) {
      // Чётные ряды сдвинуты на полплитки — узор не выглядит сеткой.
      final shift = row.isEven ? 0.0 : tile / 2;
      for (var x = -shift; x < size.width + tile; x += tile) {
        _tile(canvas, Offset(x, y), paint);
      }
    }
    canvas.restore();
  }

  void _tile(Canvas canvas, Offset o, Paint paint) {
    canvas.drawCircle(o + const Offset(18, 20), 6, paint);
    _star(canvas, o + const Offset(74, 22), 9, paint);
    _heart(canvas, o + const Offset(26, 78), 9, paint);
    _moon(canvas, o + const Offset(88, 80), 10, paint);
    // Крестики-искры.
    _plus(canvas, o + const Offset(54, 54), 4.5, paint);
    _plus(canvas, o + const Offset(104, 46), 3.5, paint);
    canvas.drawCircle(o + const Offset(60, 104), 2.2, paint);
  }

  static void _plus(Canvas canvas, Offset c, double r, Paint paint) {
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), paint);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), paint);
  }

  static void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * radius, math.sin(a) * radius);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  static void _heart(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + r * 0.9)
      ..cubicTo(c.dx - r * 1.4, c.dy, c.dx - r * 0.7, c.dy - r * 1.1, c.dx, c.dy - r * 0.35)
      ..cubicTo(c.dx + r * 0.7, c.dy - r * 1.1, c.dx + r * 1.4, c.dy, c.dx, c.dy + r * 0.9)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void _moon(Canvas canvas, Offset c, double r, Paint paint) {
    final outer = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final inner = Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.45, -r * 0.3), radius: r * 0.82));
    canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), paint);
  }

  @override
  bool shouldRepaint(DoodlePainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.stroke != stroke;
}
