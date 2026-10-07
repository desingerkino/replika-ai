import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'glass_theme.dart';

/// Стеклянная поверхность: полупрозрачная заливка, светлая кромка, блик
/// сверху и мягкая тень.
///
/// [blur] > 0 размывает то, что под стеклом (BackdropFilter). Он нужен там,
/// где под поверхностью движется содержимое (панель вкладок над списком).
/// Карточки списка лежат на ровном градиенте — размытие там ничего не меняет,
/// а стоит дорого при прокрутке, поэтому по умолчанию оно выключено.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = 0,
    this.strong = false,
    this.shadow = true,
    this.gradient,
    this.glow,
    this.padding,
  });

  final Widget child;
  final double radius;
  final double blur;

  /// Более плотное стекло (панель вкладок, поиск).
  final bool strong;
  final bool shadow;

  /// Заливка градиентом вместо стекла (активные элементы).
  final Gradient? gradient;

  /// Цветное свечение вокруг (активные элементы, вспышка новой реплики).
  final Color? glow;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final shape = BorderRadius.circular(radius);
    final filled = gradient != null;

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? null : (strong ? glass.surfaceStrong : glass.surface),
        gradient: gradient,
        borderRadius: shape,
        border: Border.all(
          color: filled ? const Color(0x59FFFFFF) : glass.border,
          width: 1,
        ),
      ),
      // Блик: светлая полоса у верхней кромки, сходящая на нет.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              filled ? const Color(0x40FFFFFF) : glass.highlight,
              const Color(0x00FFFFFF),
            ],
            stops: const [0, 0.55],
          ),
        ),
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );

    if (blur > 0) {
      body = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: body,
        ),
      );
    }

    final shadows = <BoxShadow>[
      if (shadow) BoxShadow(color: glass.shadow, blurRadius: 18, offset: const Offset(0, 6)),
      if (glow != null) BoxShadow(color: glow!, blurRadius: 16, spreadRadius: 0.5),
    ];
    if (shadows.isEmpty) return body;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadows),
      child: body,
    );
  }
}
