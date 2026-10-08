import 'package:flutter/material.dart';

import '../../app/media_store.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/story_repository.dart';
import 'story_viewer.dart';
import '../../core/design/tokens.dart';

enum _StorySource { gallery, library }

/// Опубликовать историю от имени [characterId] (по умолчанию — владельца
/// телефона): фото или видео с телефона или из медиатеки.
Future<bool> addStory(BuildContext context, {required String deviceId, String? characterId}) async {
  final services = Services.read(context);
  final source = await showActionSheet<_StorySource>(
    context,
    header: const Text('Новая история'),
    actions: const [
      SheetAction(value: _StorySource.gallery, icon: Icons.photo_library_rounded, label: 'Фото или видео'),
      SheetAction(value: _StorySource.library, icon: Icons.perm_media_outlined, label: 'Из медиатеки'),
    ],
  );
  if (source == null || !context.mounted) return false;

  MediaItem? media;
  try {
    if (source == _StorySource.gallery) {
      final items = await services.media.pickAndImport(PickSource.media);
      media = items.isEmpty ? null : items.first;
    } else {
      media = await AppNavigator.pickFromLibrary({MediaKind.photo, MediaKind.video});
    }
  } catch (error) {
    debugPrint('Файл для истории не добавлен: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось добавить файл')));
    }
    return false;
  }
  if (media == null) return false;
  if (media.kind != MediaKind.photo && media.kind != MediaKind.video) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для истории подходят только фото и видео')),
      );
    }
    return false;
  }

  try {
    final author = characterId ?? (await services.devices.byId(deviceId))?.ownerCharacterId;
    if (author == null) return false;
    await services.stories.add(deviceId: deviceId, characterId: author, mediaId: media.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('История опубликована')));
    }
    return true;
  } catch (error) {
    debugPrint('История не сохранена: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось опубликовать историю')));
    }
    return false;
  }
}

/// Открыть просмотр историй, начиная с автора [startAuthor].
Future<void> openStories(
  BuildContext context, {
  required String deviceId,
  required List<StoryAuthor> authors,
  int startAuthor = 0,
}) {
  if (authors.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: MediaPalette.background,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondary) =>
          StoryViewer(deviceId: deviceId, authors: authors, startAuthor: startAuthor),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: 0.92, end: 1).animate(curved), child: child),
        );
      },
    ),
  );
}
