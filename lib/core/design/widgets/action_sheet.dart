import 'package:flutter/material.dart';

import '../context.dart';
import '../icons.dart';
import '../tokens.dart';
import 'pressable.dart';

/// Пункт нижнего меню действий.
class SheetAction<T> {
  const SheetAction({
    required this.value,
    required this.icon,
    required this.label,
    this.destructive = false,
    this.selected = false,
  });

  final T value;
  final IconData icon;
  final String label;
  final bool destructive;

  /// Отметка текущего варианта (например, выбранной темы).
  final bool selected;
}

/// Нижнее меню действий. Возвращает выбранное значение или null.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  Widget? header,
  required List<SheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    backgroundColor: context.cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
    ),
    builder: (sheetContext) {
      final rc = sheetContext.rc;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: Space.s, bottom: Space.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: rc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (header != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l + 4, Space.m, Space.l + 4, Space.m),
                  child: header,
                ),
                Divider(color: rc.divider, height: 1),
              ] else
                const SizedBox(height: Space.s),
              for (final action in actions)
                _SheetTile<T>(
                  action: action,
                  onTap: () => Navigator.of(sheetContext).pop(action.value),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SheetTile<T> extends StatelessWidget {
  const _SheetTile({required this.action, required this.onTap});

  final SheetAction<T> action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final color = action.destructive ? rc.danger : rc.textPrimary;
    return Pressable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l + 4, vertical: Space.m),
          child: Row(
            children: [
              Icon(action.icon, size: 22, color: action.destructive ? rc.danger : rc.textSecondary),
              const SizedBox(width: Space.l),
              Expanded(
                child: Text(
                  action.label,
                  style: context.tt.bodyLarge?.copyWith(color: color),
                ),
              ),
              if (action.selected)
                Icon(AppIcons.check, size: 22, color: context.cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}
