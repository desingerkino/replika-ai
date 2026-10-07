import 'package:flutter/material.dart';

import '../core/design/widgets/pressable.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';

/// Круглая стеклянная кнопка со значком (меню, новый чат).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
  });

  final IconData icon;

  /// Подпись для экранного диктора и подсказки.
  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    return Tooltip(
      message: label,
      child: Pressable(
        onTap: onPressed,
        tint: false,
        scale: 0.94,
        semanticsLabel: label,
        child: GlassSurface(
          radius: size / 2,
          strong: true,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: size * 0.5, color: glass.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Капсула-фильтр: активная — фирменный градиент, остальные — стекло.
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = 36,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    return Pressable(
      onTap: onTap,
      tint: false,
      scale: 0.96,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GlassSurface(
          radius: height / 2,
          gradient: selected ? GlassTheme.accentGradient : null,
          glow: selected ? GlassTheme.accentGlow.withValues(alpha: 0.45) : null,
          shadow: !selected,
          child: SizedBox(
            height: height,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : glass.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Стеклянное поле поиска 48 пунктов высотой с кнопкой очистки.
class GlassSearchBar extends StatelessWidget {
  const GlassSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.searchIcon,
    required this.clearIcon,
    this.height = 48,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final IconData searchIcon;
  final IconData clearIcon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final style = TextStyle(fontSize: 17, height: 1.25, color: glass.textPrimary);
    return GlassSurface(
      radius: height / 2,
      strong: true,
      blur: 30,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Row(
          children: [
            const SizedBox(width: 18),
            Icon(searchIcon, size: 22, color: glass.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: style,
                cursorColor: GlassTheme.accentBlue,
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: style.copyWith(color: glass.textTertiary),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox(width: 18);
                return IconButton(
                  tooltip: 'Очистить',
                  style: IconButton.styleFrom(splashFactory: NoSplash.splashFactory),
                  icon: Icon(clearIcon, size: 20, color: glass.textSecondary),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
