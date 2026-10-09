import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/replika_refresh.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../core/util/time_format.dart';
import '../../data/repositories/story_repository.dart';
import 'stories_strip.dart';
import 'story_actions.dart';
import 'story_avatar.dart';

/// Вкладка «Истории»: своя история и истории контактов — новые сверху,
/// просмотренные ниже. Истории живут сутки.
class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ColoredBox(
      color: context.cs.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              title: 'Истории',
              actions: [
                IconButton(
                  tooltip: 'Добавить историю',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () => addStory(context, deviceId: deviceId),
                ),
              ],
            ),
            Expanded(
              child: LiveQuery<StoriesData?>(
                tables: storyTables,
                queryKey: deviceId,
                load: () => loadStories(services, deviceId),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  if (data == null) {
                    return snapshot.error != null
                        ? ErrorState(message: 'Не удалось загрузить истории.', onRetry: snapshot.reload)
                        : const LoadingState();
                  }
                  final mine = data.mine;
                  final fresh = [for (final a in data.others) if (a.hasUnseen) a];
                  final seen = [for (final a in data.others) if (!a.hasUnseen) a];
                  final order = [if (mine != null) mine, ...fresh, ...seen];
                  final now = DateTime.now();
                  void open(StoryAuthor a) =>
                      openStories(context, deviceId: deviceId, authors: order, startAuthor: order.indexOf(a));
                  return ReplikaRefreshIndicator(
                    onRefresh: () async => snapshot.reload(),
                    child: ListView(
                      padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.paddingOf(context).bottom),
                      children: [
                        _AuthorRow(
                          name: data.owner?.character.fullName ?? 'Я',
                          imagePath: data.owner?.avatarPath,
                          tone: data.owner?.character.avatarTone,
                          title: mine == null ? 'Добавить историю' : 'Моя история',
                          subtitle: mine == null
                              ? 'Исчезает через 24 часа'
                              : '${mine.stories.length} · ${formatAgo(mine.latest, now)}',
                          hasStories: mine != null,
                          unseen: mine?.hasUnseen ?? false,
                          adding: mine == null,
                          onTap: () => mine == null ? addStory(context, deviceId: deviceId) : open(mine),
                          onLongPress: () => addStory(context, deviceId: deviceId),
                        ),
                        if (fresh.isNotEmpty) const SectionLabel('Недавние'),
                        for (final a in fresh)
                          _AuthorRow(
                            name: a.displayName,
                            imagePath: a.avatarPath,
                            tone: a.avatarTone,
                            title: a.displayName,
                            subtitle: formatAgo(a.latest, now),
                            unseen: true,
                            onTap: () => open(a),
                          ),
                        if (seen.isNotEmpty) const SectionLabel('Просмотренные'),
                        for (final a in seen)
                          _AuthorRow(
                            name: a.displayName,
                            imagePath: a.avatarPath,
                            tone: a.avatarTone,
                            title: a.displayName,
                            subtitle: formatAgo(a.latest, now),
                            onTap: () => open(a),
                          ),
                        if (data.others.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxl, Space.xl, 0),
                            child: Text(
                              'Историй контактов пока нет. Добавить историю от имени '
                              'контакта можно в его профиле.',
                              textAlign: TextAlign.center,
                              style: context.tt.bodyMedium?.copyWith(color: context.rc.textSecondary),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({
    required this.name,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.imagePath,
    this.tone,
    this.hasStories = true,
    this.unseen = false,
    this.adding = false,
    this.onLongPress,
  });

  final String name;
  final String? imagePath;
  final int? tone;
  final String title;
  final String subtitle;
  final bool hasStories;
  final bool unseen;
  final bool adding;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: Row(
          children: [
            StoryAvatar(
              name: name,
              imagePath: imagePath,
              tone: tone,
              size: 58,
              hasStories: hasStories,
              unseen: unseen,
              adding: adding,
            ),
            const SizedBox(width: Space.m + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
