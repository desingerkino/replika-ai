import 'package:flutter/material.dart';

import '../../core/design/colors.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';

/// Операторская всегда тёмная: не бликует на площадке и сразу
/// отличается от «телефона в кадре».
final ThemeData operatorTheme = AppTheme.dark.copyWith(
  scaffoldBackgroundColor: OperatorPalette.background,
  canvasColor: OperatorPalette.background,
  colorScheme: AppTheme.dark.colorScheme.copyWith(
    surface: OperatorPalette.background,
    onSurface: OperatorPalette.text,
    surfaceContainerHighest: OperatorPalette.surface,
    outlineVariant: OperatorPalette.line,
  ),
  extensions: <ThemeExtension<dynamic>>[
    ReplikaColors.dark.copyWith(
      surfaceMuted: OperatorPalette.surface,
      divider: OperatorPalette.line,
      textPrimary: OperatorPalette.text,
      textSecondary: OperatorPalette.textDim,
    ),
  ],
);

/// Большая кнопка панели: хорошо попадать пальцем на бегу.
class PanelButton extends StatelessWidget {
  const PanelButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
    this.icon,
    this.height = 72,
    this.foreground = Colors.white,
  });

  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Material(
        color: enabled ? color : OperatorPalette.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height - Space.l),
              child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: enabled ? foreground : OperatorPalette.textDim, size: 26),
                  const SizedBox(width: Space.s),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: enabled ? foreground : OperatorPalette.textDim,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка на тёмном фоне.
class OperatorCard extends StatelessWidget {
  const OperatorCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OperatorPalette.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding ?? const EdgeInsets.all(Space.l), child: child),
      ),
    );
  }
}
