import 'package:flutter/widgets.dart';

/// Цвета фирменного «жидкого стекла».
abstract final class GlassPalette {
  /// Глубокий тёмно-синий фон (не чистый чёрный).
  static const Color navy = Color(0xFF070A18);
  static const Color blue = Color(0xFF5667FF);
  static const Color cyan = Color(0xFF65E8FF);
  static const Color violet = Color(0xFFA078FF);
  static const Color pink = Color(0xFFF4A6FF);
}

/// Фон стартового экрана: тёмно-синяя глубина, синие световые волны и
/// фиолетовое свечение. Волны — фирменная графика из эталона
/// (assets/splash/background.webp, собирается tool/build_splash_assets.py).
///
/// [reveal] (0…1) плавно проявляет волны поверх ровного тёмного фона — такого
/// же, как системный экран запуска, поэтому переход к Flutter не «моргает».
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, this.reveal = 1, this.child});

  static const String asset = 'assets/splash/background.webp';

  /// Пропорции графики (ширина / высота) — их же держит стартовый экран.
  static const Size artSize = Size(686, 1419);

  final double reveal;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: GlassPalette.navy,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: reveal.clamp(0.0, 1.0),
            child: const Image(
              image: AssetImage(asset),
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}
