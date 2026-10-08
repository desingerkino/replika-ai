import 'package:flutter/material.dart';

import '../../core/brand/brand.dart';
import '../../core/brand/logo.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';

/// Стартовый экран: сфера появляется из лёгкого размытия, «дышит» и
/// переливается, пока открываются данные.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.cs;
    final appear = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.75, curve: Curves.easeOutBack));
    final fade = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.5, curve: Curves.easeOut));
    final title = CurvedAnimation(parent: _intro, curve: const Interval(0.45, 1, curve: Curves.easeOut));
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF161A3A), Color(0xFF070918)]
                : [cs.surface, cs.secondaryContainer],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: fade,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1).animate(appear),
                  child: const AnimatedReplikaLogo(size: 112),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: title,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(title),
                  child: Text(
                    Brand.name,
                    style: context.tt.headlineSmall?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: dark ? MediaPalette.onMedia : context.rc.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
