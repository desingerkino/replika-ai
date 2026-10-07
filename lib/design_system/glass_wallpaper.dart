import 'package:flutter/material.dart';

import 'glass_theme.dart';

/// Фон светлых экранов: бело-голубой градиент с мягкими синими и фиолетовыми
/// пятнами и светлыми «стеклянными» волнами. Рисуется один раз (статичен).
class GlassWallpaper extends StatelessWidget {
  const GlassWallpaper({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WallpaperPainter(glass),
        child: child,
      ),
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  const _WallpaperPainter(this.glass);

  final GlassTheme glass;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: glass.background,
        ).createShader(rect),
    );

    final w = size.width;
    final h = size.height;
    final strength = glass.dark ? 0.55 : 0.6;

    // Цветные пятна: (центр x, центр y, радиус) в долях ширины и высоты.
    void blob(Color color, double cx, double cy, double r, double opacity) {
      final center = Offset(w * cx, h * cy);
      final radius = w * r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: opacity * strength), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    blob(glass.blobs[0], 0.05, 0.06, 0.95, 0.9);
    blob(glass.blobs[1], 1.02, 0.36, 0.8, 0.75);
    blob(glass.blobs[2], -0.05, 0.72, 0.85, 0.7);
    blob(glass.blobs[3], 1.0, 0.95, 0.9, 0.8);
    blob(glass.blobs[0], 0.45, 1.02, 0.7, 0.55);

    // Светлые волны: широкие полупрозрачные ленты, как блики на стекле.
    final sheen = glass.dark ? const Color(0x12FFFFFF) : const Color(0x73FFFFFF);
    Paint wave(double sigma) => Paint()
      ..color = sheen
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

    final top = Path()
      ..moveTo(-w * 0.1, h * 0.02)
      ..cubicTo(w * 0.25, h * 0.10, w * 0.55, -h * 0.04, w * 1.1, h * 0.12)
      ..lineTo(w * 1.1, h * 0.20)
      ..cubicTo(w * 0.6, h * 0.05, w * 0.3, h * 0.2, -w * 0.1, h * 0.12)
      ..close();
    canvas.drawPath(top, wave(w * 0.06));

    final bottom = Path()
      ..moveTo(-w * 0.1, h * 0.80)
      ..cubicTo(w * 0.3, h * 0.72, w * 0.6, h * 0.92, w * 1.1, h * 0.78)
      ..lineTo(w * 1.1, h * 0.88)
      ..cubicTo(w * 0.65, h * 1.0, w * 0.3, h * 0.82, -w * 0.1, h * 0.92)
      ..close();
    canvas.drawPath(bottom, wave(w * 0.07));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) => old.glass != glass;
}
