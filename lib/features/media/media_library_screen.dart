import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/media_store.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/media_item.dart';
import 'media_content.dart' show VideoFrame;
import 'media_kinds.dart';
import 'media_viewer.dart';
import '../../core/design/adaptive.dart';

IconData mediaKindIcon(MediaKind kind) => switch (kind) {
      MediaKind.photo => Icons.photo_rounded,
      MediaKind.video => Icons.movie_rounded,
      MediaKind.audio => Icons.music_note_rounded,
      MediaKind.voice => Icons.mic_rounded,
      MediaKind.videoNote => Icons.video_camera_front_rounded,
      MediaKind.file => Icons.insert_drive_file_rounded,
    };

/// Откуда выбирать файл для каждого вида медиа.
PickSource pickSourceFor(MediaKind kind) => switch (kind) {
      MediaKind.photo => PickSource.image,
      MediaKind.video || MediaKind.videoNote => PickSource.video,
      MediaKind.audio || MediaKind.voice => PickSource.audio,
      MediaKind.file => PickSource.any,
    };

/// Добавляет файлы нужного вида в медиатеку с показом ошибки.
Future<List<MediaItem>> importMedia(BuildContext context, MediaKind kind) async {
  final services = Services.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    return await services.media.pickAndImport(pickSourceFor(kind), preferred: kind);
  } catch (error) {
    debugPrint('Файл не добавлен: $error');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Не удалось добавить файл')));
    return const [];
  }
}

/// Медиатека: все файлы для сцен и переписок. В режиме выбора
/// ([pickKinds] задан) нажатие возвращает файл вызывающему экрану.
class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({super.key, this.pickKinds});

  final Set<MediaKind>? pickKinds;

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  MediaKind? _filter;
  bool _importing = false;

  bool get _picking => widget.pickKinds != null;

  List<MediaKind> get _kinds => widget.pickKinds?.toList() ?? MediaKind.values;

  Future<void> _add() async {
    var kind = _filter;
    if (kind == null) {
      kind = await showActionSheet<MediaKind>(
        context,
        header: Text('Что добавить', style: context.tt.titleMedium),
        actions: [
          for (final k in _kinds)
            SheetAction(value: k, icon: mediaKindIcon(k), label: k.label),
        ],
      );
      if (kind == null || !mounted) return;
    }
    setState(() => _importing = true);
    await importMedia(context, kind);
    if (mounted) setState(() => _importing = false);
  }

  Future<void> _open(MediaItem item) async {
    if (_picking) {
      Navigator.of(context).pop(item);
      return;
    }
    switch (item.kind) {
      case MediaKind.photo:
        await openPhotoViewer(context, item);
      case MediaKind.video:
      case MediaKind.videoNote:
        await openVideoViewer(context, item);
      case MediaKind.audio:
      case MediaKind.voice:
        try {
          await Services.read(context).audio.toggle(item);
        } catch (_) {
          // Ошибку показывает строка файла — проигрывание не началось.
        }
      case MediaKind.file:
        break;
    }
  }

  Future<void> _delete(MediaItem item) async {
    final services = Services.read(context);
    final used = await services.media.repository.usageCount(item.id);
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Удалить файл?',
      message: used == 0
          ? 'Файл «${item.originalName ?? item.kind.label}» будет удалён с телефона.'
          : 'Файл используется ($used). В переписках вместо него будет «Файл удалён», '
              'у аватаров вернутся инициалы.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (confirmed) await services.media.delete(item);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Scaffold(
      appBar: ReplikaTopBar(
        leading: const BackIconButton(),
        title: Text(_picking ? 'Выбор из медиатеки' : 'Медиатека', style: context.tt.titleMedium),
        actions: [
          IconButton(
            tooltip: 'Добавить файл',
            onPressed: _importing ? null : _add,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ContentWidth(maxWidth: 720, child: Column(
        children: [
          if (_importing) const LinearProgressIndicator(minHeight: 2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
            child: Row(
              children: [
                if (_kinds.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: ChoiceChip(
                      label: const Text('Все'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                  ),
                for (final kind in _kinds)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: ChoiceChip(
                      label: Text(kind.label),
                      selected: _filter == kind || _kinds.length == 1,
                      onSelected: (_) => setState(() => _filter = kind),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LiveQuery<List<MediaItem>>(
              tables: const {Tables.media},
              queryKey: _filter,
              load: () async {
                final all = await services.media.repository.list(kind: _filter);
                final allowed = widget.pickKinds;
                return allowed == null ? all : all.where((m) => allowed.contains(m.kind)).toList();
              },
              builder: (context, snapshot) {
                final items = snapshot.data;
                if (items == null) {
                  return snapshot.error != null
                      ? ErrorState(message: 'Не удалось открыть медиатеку.', onRetry: snapshot.reload)
                      : const LoadingState();
                }
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.perm_media_outlined,
                    title: 'Здесь пока пусто',
                    message: 'Добавьте фото, видео или аудио кнопкой «+» вверху. '
                        'Файлы копируются в приложение и не пропадут, '
                        'если удалить их из галереи.',
                  );
                }
                // Фото и видео — сеткой, как галерея; остальное — списком.
                final visual = [for (final m in items) if (m.kind == MediaKind.photo || m.kind == MediaKind.video) m];
                final others = [for (final m in items) if (m.kind != MediaKind.photo && m.kind != MediaKind.video) m];
                return CustomScrollView(
                  slivers: [
                    if (visual.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.all(2),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 160,
                            mainAxisSpacing: 2,
                            crossAxisSpacing: 2,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = visual[index];
                              return _MediaCell(
                                key: ValueKey(item.id),
                                item: item,
                                onTap: () => _open(item),
                                onLongPress: _picking ? null : () => _delete(item),
                              );
                            },
                            childCount: visual.length,
                          ),
                        ),
                      ),
                    SliverList.builder(
                      itemCount: others.length,
                      itemBuilder: (context, index) {
                        final item = others[index];
                        return _MediaTile(
                          key: ValueKey(item.id),
                          item: item,
                          onTap: () => _open(item),
                          onLongPress: _picking ? null : () => _delete(item),
                        );
                      },
                    ),
                    SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Space.l)),
                  ],
                );
              },
            ),
          ),
        ],
      )),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({super.key, required this.item, required this.onTap, this.onLongPress});

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final details = <String>[
      item.kind.label,
      if (item.duration != null) formatDuration(item.duration!),
      if (item.sizeBytes != null) formatBytes(item.sizeBytes!),
    ].join(' · ');
    final Widget leading = item.kind == MediaKind.photo
        ? ClipRRect(
            borderRadius: BorderRadius.circular(Radii.control),
            child: Image.file(
              File(item.path),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              cacheWidth: 160,
              errorBuilder: (context, error, stack) => _IconBox(icon: mediaKindIcon(item.kind)),
            ),
          )
        : _IconBox(icon: mediaKindIcon(item.kind));
    final playback = Services.of(context).audio;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: Row(
          children: [
            leading,
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.originalName ?? item.kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.bodyLarge,
                  ),
                  Text(details, style: context.tt.bodySmall?.copyWith(color: rc.textSecondary)),
                ],
              ),
            ),
            if (item.kind == MediaKind.audio || item.kind == MediaKind.voice)
              ListenableBuilder(
                listenable: playback,
                builder: (context, _) => Icon(
                  playback.isPlaying(item.id) ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  color: context.cs.primary,
                  size: 30,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Квадрат сетки: превью фото или первый кадр видео с длительностью.
class _MediaCell extends StatelessWidget {
  const _MediaCell({super.key, required this.item, required this.onTap, this.onLongPress});

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final video = item.kind == MediaKind.video;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            if (video)
              VideoFrame(media: item, width: constraints.maxWidth, height: constraints.maxHeight)
            else
              Image.file(
                File(item.path),
                fit: BoxFit.cover,
                cacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round(),
                errorBuilder: (context, error, stack) => _IconBox(icon: mediaKindIcon(item.kind)),
              ),
            if (video)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: MediaPalette.scrim, borderRadius: BorderRadius.circular(Radii.pill)),
                  child: Text(
                    item.duration == null ? 'Видео' : formatDuration(item.duration!),
                    style: const TextStyle(color: MediaPalette.onMedia, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: context.rc.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Icon(icon, color: context.rc.textSecondary),
    );
  }
}
