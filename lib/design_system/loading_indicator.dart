import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// Полоса загрузки «жидкое стекло»: прозрачная капсула и светящееся
/// градиентное заполнение. [progress] — 0…1.
class GlassLoadingBar extends StatelessWidget {
  const GlassLoadingBar({
    super.key,
    required this.progress,
    this.width = 206,
    this.height = 5.2,
  });

  final double progress;
  final double width;
  final double height;

  /// Заполнение (по эталону): фиолетовый → синий → голубой и белая «искра».
  static const List<Color> fillColors = [
    Color(0xFF9A68FD),
    Color(0xFF8C72FD),
    Color(0xFF72ADFD),
    Color(0xFF91F0FC),
    Color(0xFFFAFEFF),
  ];
  static const List<double> fillStops = [0, 0.25, 0.62, 0.93, 1];

  /// Запас вокруг полосы под свечение.
  static const double glowPad = 14;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    final radius = BorderRadius.circular(height / 2);
    return Semantics(
      label: 'Загрузка',
      value: '${(value * 100).round()} %',
      child: SizedBox(
        width: width + glowPad * 2,
        height: height + glowPad * 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Дорожка: стекло — размытие фона под ней и лёгкая подсветка.
            ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x1E96AFFF),
                      borderRadius: radius,
                      border: Border.all(color: const Color(0x26AABEFF), width: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _FillPainter(progress: value, barWidth: width, barHeight: height),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FillPainter extends CustomPainter {
  const _FillPainter({required this.progress, required this.barWidth, required this.barHeight});

  final double progress;
  final double barWidth;
  final double barHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final left = (size.width - barWidth) / 2;
    final top = (size.height - barHeight) / 2;
    final filled = math.max(barHeight, barWidth * progress);
    final rect = Rect.fromLTWH(left, top, filled, barHeight);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(barHeight / 2));

    // Свечение: широкая синяя дымка и плотный ореол у самой полосы.
    canvas.drawRRect(
      shape.inflate(3),
      Paint()
        ..color = const Color(0x992F55FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      shape.inflate(1),
      Paint()
        ..color = const Color(0xE64A6BFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          colors: GlassLoadingBar.fillColors,
          stops: GlassLoadingBar.fillStops,
        ).createShader(rect),
    );
    // «Искра» на конце заполнения.
    canvas.drawCircle(
      Offset(rect.right - barHeight / 2, rect.center.dy),
      barHeight * 0.62,
      Paint()
        ..color = const Color(0xB3E6FDFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
  }

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.progress != progress || old.barWidth != barWidth || old.barHeight != barHeight;
}
