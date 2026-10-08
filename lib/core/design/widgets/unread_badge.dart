import 'package:flutter/material.dart';

import '../context.dart';

/// Счётчик непрочитанных.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, this.muted = false});

  final int count;
  final bool muted;

  static String label(int count) => count > 999 ? '999+' : '$count';

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final rc = context.rc;
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? rc.badgeMuted : rc.badge,
        borderRadius: BorderRadius.circular(11),
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
