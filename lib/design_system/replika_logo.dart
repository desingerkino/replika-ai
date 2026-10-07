import 'package:flutter/widgets.dart';

import 'glass_background.dart';
import 'glow_effect.dart';

/// Фирменная сфера Replika: стеклянный шар с двумя световыми лентами
/// (assets/splash/orb.webp — вырезана из эталона вместе с ореолом).
///
/// [appear] 0…1 — появление: масштаб 0.95 → 1 и прозрачность 0 → 1.
/// [glow] 0…1 — «дыхание»: яркость сферы 70 % → 100 %.
class ReplikaOrb extends StatelessWidget {
  const ReplikaOrb({
    super.key,
    required this.diameter,
    this.appear = 1,
    this.glow = 1,
  });

  static const String asset = 'assets/splash/orb.webp';

  /// Сторона картинки и диаметр самой сферы на ней, в пикселях графики:
  /// вокруг сферы оставлено место под ореол.
  static const double artSide = 496;
  static const double artSphere = 430;

  static const double minScale = 0.95;
  static const double minBrightness = 0.7;

  /// Диаметр стеклянной сферы (ореол выходит за него).
  final double diameter;
  final double appear;
  final double glow;

  /// Сторона всего виджета вместе с ореолом.
  static double sideFor(double diameter) => diameter * artSide / artSphere;

  /// Масштаб при появлении.
  static double scaleFor(double appear) => minScale + (1 - minScale) * appear.clamp(0.0, 1.0);

  /// Непрозрачность сферы: появление, умноженное на «дыхание».
  static double opacityFor(double appear, double glow) =>
      appear.clamp(0.0, 1.0) * (minBrightness + (1 - minBrightness) * glow.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final side = sideFor(diameter);
    return Semantics(
      label: 'Replika',
      image: true,
      child: SizedBox.square(
        dimension: side,
        child: Transform.scale(
          scale: scaleFor(appear),
          child: GlowEffect(
            color: GlassPalette.blue,
            // Дополнительный ореол растёт вместе с яркостью сферы.
            intensity: appear.clamp(0.0, 1.0) * glow.clamp(0.0, 1.0) * 0.22,
            spread: 1.12,
            child: Opacity(
              opacity: opacityFor(appear, glow),
              child: const Image(
                image: AssetImage(asset),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
