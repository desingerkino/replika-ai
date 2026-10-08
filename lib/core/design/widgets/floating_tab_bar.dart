import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../context.dart';
import '../tokens.dart';
import 'unread_badge.dart';

/// Один пункт плавающей панели вкладок.
class TabBarItem {
  const TabBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Красный счётчик на значке (0 — не показывать).
  final int badge;
}

/// Плавающая капсула с вкладками (узкий экран): размытый фон, тонкая
/// граница, активная вкладка выделена светлой капсулой.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<TabBarItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottom = math.max(safeBottom - 8, Sizes.tabBarMinBottomMargin);
    final radius = BorderRadius.circular(Sizes.tabBar / 2);
    // При крупном шрифте панель растёт, чтобы подписи не обрезались.
    final extra = (MediaQuery.textScalerOf(context).scale(10) - 10).clamp(0.0, 12.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(Sizes.tabBarSideMargin, 0, Sizes.tabBarSideMargin, bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.45 : 0.14),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: Sizes.tabBar + extra * 1.5,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: dark ? const Color(0xD11C1F26) : const Color(0xD6F6F6F6),
                borderRadius: radius,
                border: Border.all(
                  color: dark ? const Color(0x1FFFFFFF) : const Color(0x14141820),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _TabButton(
                        item: items[i],
                        selected: i == index,
                        selectedColor: context.cs.primary,
                        idleColor: rc.textSecondary,
                        highlight: dark ? const Color(0x1FFFFFFF) : const Color(0x12141820),
                        onTap: () => onSelect(i),
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.selectedColor,
    required this.idleColor,
    required this.highlight,
    required this.onTap,
  });

  final TabBarItem item;
  final bool selected;
  final Color selectedColor;
  final Color idleColor;
  final Color highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final color = selected ? selectedColor : idleColor;
    Widget icon = Icon(selected ? item.activeIcon : item.icon, size: 24, color: color);
    if (item.badge > 0) {
      icon = Badge(
        backgroundColor: rc.alert,
        textColor: Colors.white,
        label: Text(UnreadBadge.label(item.badge)),
        child: icon,
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          decoration: BoxDecoration(
            color: selected ? highlight : Colors.transparent,
            borderRadius: BorderRadius.circular((Sizes.tabBar - 12) / 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 10,
                  height: 12 / 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
