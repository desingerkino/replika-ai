import 'package:flutter/material.dart';

import '../context.dart';
import '../tokens.dart';

/// Кнопка быстрого действия под профилем: значок цвета акцента и подпись
/// на мягкой подложке («Звонок», «Видео», «Звук», «Ещё»).
class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.label, this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Включённое состояние (например, «Без звука»).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final rc = context.rc;
    return Material(
      color: active ? cs.primaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(Radii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.s + 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: onTap == null ? rc.textTertiary : cs.primary, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelMedium?.copyWith(color: rc.textPrimary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
