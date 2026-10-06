import 'package:flutter/material.dart';

import '../context.dart';
import '../tokens.dart';

/// Диалог подтверждения. Возвращает true только при явном согласии.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final rc = dialogContext.rc;
      final cs = dialogContext.cs;
      return AlertDialog(
        scrollable: true,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
        title: Text(title, style: dialogContext.tt.titleLarge),
        content: Text(
          message,
          style: dialogContext.tt.bodyMedium?.copyWith(color: rc.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(foregroundColor: rc.textSecondary),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: destructive ? rc.danger : cs.primary,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
