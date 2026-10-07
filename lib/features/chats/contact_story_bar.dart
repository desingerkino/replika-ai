import 'package:flutter/material.dart';

import '../../app/story_store.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/pressable.dart';
import '../../data/models/chat.dart';

/// Горизонтальная лента контактов над поиском.
///
/// Первый элемент — «Новый чат», дальше собеседники из уже загруженного
/// списка чатов (личные): сначала с непрочитанными, потом «в сети», потом
/// остальные в прежнем порядке. Порядок только для показа, список чатов и
/// база не меняются. При поиске лента плавно сворачивается ([visible]),
/// из дерева не убирается.
class ContactStoryBar extends StatelessWidget {
  const ContactStoryBar({
    super.key,
    required this.items,
    required this.visible,
    required this.onNewChat,
    required this.onOpen,
    required this.stories,
    required this.onOpenStory,
  });

  /// Высота ленты вместе с отступами.
  static const double height = 96;
  static const double avatarSize = 56;
  static const double _cellWidth = 68;
  static const int _maxContacts = 30;

  final List<ChatListItem> items;
  final bool visible;
  final VoidCallback onNewChat;
  final ValueChanged<String> onOpen;

  /// Истории контактов: от них зависят кольца.
  final StoryStore stories;

  /// Нажатие на контакт с историей открывает её просмотр.
  final ValueChanged<ChatListItem> onOpenStory;

  /// Состояние кольца задают только истории: есть новая — живой градиент,
  /// все просмотрены — спокойное кольцо, историй нет — без кольца.
  static StoryRing ringFor(ChatListItem item, StoryStore stories) {
    final id = item.chat.peerCharacterId;
    if (id == null || !stories.has(id)) return StoryRing.none;
    return stories.hasUnviewed(id) ? StoryRing.unviewed : StoryRing.viewed;
  }

  /// Личные чаты: с новой историей, затем непрочитанные, «в сети», остальные.
  static List<ChatListItem> ordered(List<ChatListItem> all, [StoryStore? stories]) {
    final direct = all.where((item) => !item.chat.isGroup).toList();
    // С новой историей — первыми, дальше непрочитанные, «в сети», остальные.
    int rank(ChatListItem item) {
      final id = item.chat.peerCharacterId;
      if (stories != null && id != null && stories.hasUnviewed(id)) return 0;
      return item.chat.unreadCount > 0 ? 1 : (item.peer.isOnline ? 2 : 3);
    }
    final indexed = [for (var i = 0; i < direct.length; i++) (i, direct[i])];
    indexed.sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed.take(_maxContacts)) entry.$2];
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ordered(items, stories);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return ListenableBuilder(
      listenable: stories,
      builder: (context, _) => _buildBar(context, contacts, duration),
    );
  }

  Widget _buildBar(BuildContext context, List<ChatListItem> contacts, Duration duration) {
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: visible ? 1 : 0,
            duration: duration,
            curve: Motion.curve,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              curve: Motion.curve,
              child: SizedBox(
                height: height,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.m),
                  itemCount: contacts.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return _NewChatCell(onTap: onNewChat);
                    final item = contacts[index - 1];
                    final ring = ringFor(item, stories);
                    return _ContactCell(
                      key: ValueKey('story-${item.chat.id}'),
                      item: item,
                      ring: ring,
                      onTap: () => ring == StoryRing.none ? onOpen(item.chat.id) : onOpenStory(item),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ячейка ленты: аватар с запасом под кольцо и подпись в одну строку.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.avatar,
    required this.label,
    required this.labelStyle,
    required this.onTap,
    required this.semantics,
  });

  final Widget avatar;
  final String label;
  final TextStyle? labelStyle;
  final VoidCallback onTap;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    const box = ContactStoryBar.avatarSize + 2 * Avatar.ringExtent;
    return Pressable(
      tint: false,
      scale: 0.94,
      onTap: onTap,
      semanticsLabel: semantics,
      child: SizedBox(
        width: ContactStoryBar._cellWidth,
        child: Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Column(
            children: [
              SizedBox(width: box, height: box, child: Center(child: avatar)),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                style: labelStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactCell extends StatelessWidget {
  const _ContactCell({super.key, required this.item, required this.ring, required this.onTap});

  final ChatListItem item;
  final StoryRing ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = item.chat.unreadCount > 0;
    final base = context.tt.labelMedium;
    return _Cell(
      onTap: onTap,
      semantics: ring == StoryRing.unviewed
          ? '${item.displayName}, новая история'
          : (unread ? '${item.displayName}, есть непрочитанные' : item.displayName),
      label: item.displayName,
      labelStyle: base?.copyWith(
        color: context.rc.textPrimary,
        fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
      ),
      avatar: Avatar(
        name: item.displayName,
        size: ContactStoryBar.avatarSize,
        imagePath: item.peer.avatarPath,
        tone: item.peer.avatarTone,
        online: item.peer.isOnline,
        ring: ring,
      ),
    );
  }
}

/// «Новый чат»: спокойный круг с плюсом, тише обычного контакта.
class _NewChatCell extends StatelessWidget {
  const _NewChatCell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return _Cell(
      onTap: onTap,
      semantics: 'Новый чат',
      label: 'Новый чат',
      labelStyle: context.tt.labelMedium?.copyWith(color: rc.textSecondary),
      avatar: Container(
        width: ContactStoryBar.avatarSize,
        height: ContactStoryBar.avatarSize,
        decoration: BoxDecoration(
          color: rc.surfaceMuted,
          shape: BoxShape.circle,
          border: Border.all(color: rc.divider, width: Sizes.line),
        ),
        child: Icon(AppIcons.plus, size: 26, color: context.cs.primary),
      ),
    );
  }
}
