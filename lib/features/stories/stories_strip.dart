import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../data/db/tables.dart';
import '../../data/models/contact.dart';
import '../../data/repositories/story_repository.dart';
import 'story_actions.dart';
import 'story_avatar.dart';

/// Данные ленты историй: истории телефона и владелец (для «Моей истории»).
class StoriesData {
  const StoriesData({required this.authors, required this.owner, required this.ownerId});

  final List<StoryAuthor> authors;
  final Contact? owner;
  final String ownerId;

  StoryAuthor? get mine {
    for (final a in authors) {
      if (a.isOwner) return a;
    }
    return null;
  }

  List<StoryAuthor> get others => [for (final a in authors) if (!a.isOwner) a];
}

Future<StoriesData?> loadStories(AppServices services, String deviceId) async {
  final device = await services.devices.byId(deviceId);
  if (device == null) return null;
  final authors = await services.stories.authorsForDevice(deviceId);
  final owner = await services.contacts.view(deviceId, device.ownerCharacterId);
  return StoriesData(authors: authors, owner: owner, ownerId: device.ownerCharacterId);
}

const Set<String> storyTables = {
  Tables.stories,
  Tables.characters,
  Tables.deviceContacts,
  Tables.media,
  Tables.devices,
};

/// Лента кружков над списком чатов: «Моя история» и истории контактов.
class StoriesStrip extends StatelessWidget {
  const StoriesStrip({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return LiveQuery<StoriesData?>(
      tables: storyTables,
      queryKey: deviceId,
      load: () => loadStories(services, deviceId),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox(height: 0);
        final mine = data.mine;
        final others = data.others;
        // Порядок просмотра: своя (если есть) и дальше все по порядку.
        final viewOrder = [if (mine != null) mine, ...others];
        final ownerName = data.owner?.character.fullName ?? 'Я';
        return SizedBox(
          height: 98,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            children: [
              _Bubble(
                label: 'Моя история',
                child: StoryAvatar(
                  name: ownerName,
                  imagePath: data.owner?.avatarPath,
                  tone: data.owner?.character.avatarTone,
                  hasStories: mine != null,
                  unseen: mine?.hasUnseen ?? false,
                  adding: mine == null,
                ),
                onTap: () => mine == null
                    ? addStory(context, deviceId: deviceId)
                    : openStories(context, deviceId: deviceId, authors: viewOrder),
                onLongPress: () => addStory(context, deviceId: deviceId),
              ),
              for (var i = 0; i < others.length; i++)
                _Bubble(
                  label: others[i].displayName,
                  child: StoryAvatar(
                    name: others[i].displayName,
                    imagePath: others[i].avatarPath,
                    tone: others[i].avatarTone,
                    unseen: others[i].hasUnseen,
                  ),
                  onTap: () => openStories(
                    context,
                    deviceId: deviceId,
                    authors: viewOrder,
                    startAuthor: viewOrder.indexOf(others[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.label, required this.child, required this.onTap, this.onLongPress});

  final String label;
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              child,
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.tt.labelMedium?.copyWith(color: context.rc.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
