import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/context.dart';
import '../../core/design/tokens.dart';

/// Что прикрепить к сообщению.
enum AttachChoice { photo, video, voice, file, library, recordVideoNote, videoNote }

/// Лист вложений в стиле iOS: ручка, скруглённый верх, закрывается
/// смахиванием вниз и касанием снаружи. Главное — сеткой 2×2, остальное
/// — строками ниже.
Future<AttachChoice?> showAttachSheet(BuildContext context) {
  return showModalBottomSheet<AttachChoice>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: context.rc.groupedBackground,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    builder: (context) => const _AttachSheet(),
  );
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  void _pick(BuildContext context, AttachChoice choice) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    Widget cell(AttachChoice c, IconData icon, String label) => Expanded(
          child: _GridCell(icon: icon, label: label, onTap: () => _pick(context, c)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            cell(AttachChoice.photo, Icons.photo_outlined, 'Фото'),
            const SizedBox(width: Space.m),
            cell(AttachChoice.video, Icons.videocam_outlined, 'Видео'),
          ]),
          const SizedBox(height: Space.m),
          Row(children: [
            cell(AttachChoice.voice, Icons.mic_none_rounded, 'Голос'),
            const SizedBox(width: Space.m),
            cell(AttachChoice.file, Icons.insert_drive_file_outlined, 'Файл'),
          ]),
          const SizedBox(height: Space.l),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card - 2),
            child: Material(
              color: rc.groupedCell,
              child: Column(
                children: [
                  _Row(
                    icon: Icons.perm_media_outlined,
                    label: 'Из медиатеки',
                    onTap: () => _pick(context, AttachChoice.library),
                  ),
                  Divider(height: 0.5, thickness: 0.5, indent: 56, color: rc.divider),
                  _Row(
                    icon: Icons.radio_button_checked_rounded,
                    label: 'Записать видеосообщение',
                    onTap: () => _pick(context, AttachChoice.recordVideoNote),
                  ),
                  Divider(height: 0.5, thickness: 0.5, indent: 56, color: rc.divider),
                  _Row(
                    icon: Icons.video_camera_front_outlined,
                    label: 'Видеосообщение из файла',
                    onTap: () => _pick(context, AttachChoice.videoNote),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: rc.groupedCell,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 92,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, color: cs.primary, size: 24),
                ),
                const SizedBox(height: Space.s),
                Text(label, style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: rc.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Row(
            children: [
              Icon(icon, size: 22, color: rc.textSecondary),
              const SizedBox(width: Space.l),
              Expanded(child: Text(label, style: context.tt.bodyLarge)),
              Icon(Icons.chevron_right_rounded, color: rc.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
