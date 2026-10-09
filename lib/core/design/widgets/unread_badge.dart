import 'package:flutter/material.dart';

import '../context.dart';

/// Счётчик непрочитанных.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, this.muted = false});

  final int count;
  final bool muted;

  static String label(int count) => count > 99 ? '99+' : '$count';

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final rc = context.rc;
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? rc.badgeMuted : rc.badge,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label(count),
        style: TextStyle(
          color: rc.onBadge,
          fontSize: 13,
          height: 1.2,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
