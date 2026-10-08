import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Знак «Реплики» — стеклянная сфера (assets/brand/replika_logo.png).
///
/// [glow] — мягкое сине-фиолетовое свечение вокруг сферы.
/// Для «живого» знака (дыхание, переливание) — [AnimatedReplikaLogo].
class ReplikaLogo extends StatelessWidget {
  const ReplikaLogo({super.key, this.size = 64, this.onDark = false, this.glow = false});

  static const String asset = 'assets/brand/replika_logo.png';

  final double size;

  /// Оставлено для совместимости: сфера одинаково видна на любом фоне.
  final bool onDark;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Логотип',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: glow ? logoGlow(size, 1) : null,
          ),
          child: Image.asset(
            asset,
            width: size,
            height: size,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 512),
            errorBuilder: (context, error, stack) => _FallbackSphere(size: size),
          ),
        ),
      ),
    );
  }
}

/// Свечение сферы: синее снизу-слева, фиолетовое сверху-справа.
List<BoxShadow> logoGlow(double size, double strength) => [
      BoxShadow(
        color: const Color(0xFF3D7BFF).withValues(alpha: 0.42 * strength),
        blurRadius: size * 0.42,
        spreadRadius: size * 0.02,
        offset: Offset(-size * 0.05, size * 0.06),
      ),
      BoxShadow(
        color: const Color(0xFFCB30E0).withValues(alpha: 0.32 * strength),
        blurRadius: size * 0.46,
        offset: Offset(size * 0.06, -size * 0.05),
      ),
    ];

/// Живой знак: медленное «дыхание» свечения и блик, скользящий по стеклу.
/// При «уменьшении движения» в системе знак неподвижен.
class AnimatedReplikaLogo extends StatefulWidget {
  const AnimatedReplikaLogo({super.key, this.size = 96, this.period = const Duration(seconds: 6)});

  final double size;
  final Duration period;

  @override
  State<AnimatedReplikaLogo> createState() => _AnimatedReplikaLogoState();
}

class _AnimatedReplikaLogoState extends State<AnimatedReplikaLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
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
    final size = widget.size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final breath = 0.5 - 0.5 * math.cos(t * 2 * math.pi); // 0 → 1 → 0
        return SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: logoGlow(size, 0.6 + 0.4 * breath)),
            child: Transform.scale(
              scale: 1 + 0.025 * breath,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child!,
                  // Блик: светлая дуга медленно обходит сферу.
                  ClipOval(
                    child: CustomPaint(painter: GlassShinePainter(turn: t)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: ReplikaLogo(size: size),
    );
  }
}

/// Стеклянный блик: полупрозрачная светлая дуга под углом [turn] (0…1).
class GlassShinePainter extends CustomPainter {
  const GlassShinePainter({required this.turn, this.strength = 1});

  final double turn;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final angle = turn * 2 * math.pi;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: GradientRotation(angle),
      colors: [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0.28 * strength),
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.08, 0.18, 1.0],
    ).createShader(rect);
    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(rect.center, size.shortestSide / 2, paint);
  }

  @override
  bool shouldRepaint(GlassShinePainter oldDelegate) => oldDelegate.turn != turn || oldDelegate.strength != strength;
}

/// Если картинка не загрузилась — сфера-градиент тех же цветов.
class _FallbackSphere extends StatelessWidget {
  const _FallbackSphere({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.35),
          radius: 0.9,
          colors: [Color(0xFFEDE7FF), Color(0xFF6E7BFF), Color(0xFF3A1E9E), Color(0xFFCB30E0)],
          stops: [0.0, 0.35, 0.75, 1.0],
        ),
      ),
    );
  }
}
