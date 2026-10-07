import 'package:flutter/material.dart';

import '../core/design/widgets/pressable.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';

/// Раздел плавающей панели вкладок.
@immutable
class GlassTab {
  const GlassTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badge,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Подпись счётчика на значке (null — счётчика нет).
  final String? badge;
}

/// Плавающая стеклянная панель вкладок: капсула 76 пунктов высотой с
/// отступами от краёв; активный раздел — градиентная капсула внутри.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<GlassTab> tabs;

  /// Номер активной вкладки в [tabs].
  final int selected;
  final ValueChanged<int> onSelect;

  static const double height = 76;
  static const double sideMargin = 20;
  static const double minBottomMargin = 20;

  /// Отступ панели от нижнего края: 20 пунктов, а на телефонах с полоской
  /// «домой» — чуть выше неё.
  static double bottomMarginFor(double systemBottom) =>
      systemBottom + 6 > minBottomMargin ? systemBottom + 6 : minBottomMargin;

  /// Сколько места панель занимает над нижним краем экрана.
  static double extentFor(double systemBottom) => height + bottomMarginFor(systemBottom);

  @override
  Widget build(BuildContext context) {
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(sideMargin, 0, sideMargin, bottomMarginFor(systemBottom)),
      child: GlassSurface(
        radius: height / 2,
        blur: 24,
        strong: true,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _TabButton(
                      tab: tabs[i],
                      active: i == selected,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.tab, required this.active, required this.onTap});

  final GlassTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final color = active ? Colors.white : glass.icon;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget icon = Icon(active ? tab.activeIcon : tab.icon, size: 23, color: color);
    final badge = tab.badge;
    if (badge != null) {
      icon = Badge(
        backgroundColor: GlassTheme.accentBlue,
        textColor: Colors.white,
        label: Text(badge),
        child: icon,
      );
    }

    return Pressable(
      onTap: onTap,
      tint: false,
      scale: 0.95,
      child: Semantics(
        button: true,
        selected: active,
        label: tab.label,
        excludeSemantics: true,
        child: Center(
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 66,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: active ? GlassTheme.accentGradient : null,
              border: active ? Border.all(color: const Color(0x59FFFFFF)) : null,
              boxShadow: active
                  ? [BoxShadow(color: GlassTheme.accentGlow.withValues(alpha: 0.5), blurRadius: 14)]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(height: 3),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
