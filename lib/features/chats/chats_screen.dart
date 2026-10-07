import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/chat.dart';
import '../../design_system/glass_controls.dart';
import '../../design_system/glass_theme.dart';
import '../../design_system/glass_wallpaper.dart';
import '../../design_system/orb_refresh.dart';
import '../search/message_hit_tile.dart';
import '../stories/story_viewer.dart';
import 'chat_filter.dart';
import 'chat_tile.dart';
import 'contact_story_bar.dart';
import 'swipe_actions.dart';

enum _ChatAction { pin, read, mute, archive, delete }

enum _MenuAction { newGroup, readAll }

/// Главный экран: список чатов текущего телефона («светлое жидкое стекло»).
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.deviceId});

  final String deviceId;

  /// Поля экрана слева и справа.
  static const double sideMargin = 20;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  ChatFilter _filter = ChatFilter.all;
  Timer? _clock;

  /// Какая строка списка открыта свайпом (одна на весь список).
  final ValueNotifier<String?> _openSwipe = ValueNotifier<String?>(null);

  /// Открытие экрана: шапка съезжает сверху, карточки появляются по очереди.
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: ChatsIntro.duration);
  bool _introStarted = false;

  @override
  void initState() {
    super.initState();
    // Подписи времени («14:05», «Вчера») сами обновляются раз в минуту.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_introStarted) return;
    _introStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _intro.dispose();
    _search.dispose();
    _openSwipe.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Меню «…» в шапке.
  Future<void> _openMenu(List<ChatListItem> all) async {
    HapticFeedback.selectionClick();
    final hasUnread = all.any((item) => item.chat.unreadCount > 0);
    final action = await showActionSheet<_MenuAction>(
      context,
      actions: [
        const SheetAction(value: _MenuAction.newGroup, icon: AppIcons.groupAdd, label: 'Новая группа'),
        if (hasUnread)
          const SheetAction(
            value: _MenuAction.readAll,
            icon: AppIcons.markRead,
            label: 'Отметить все прочитанными',
          ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MenuAction.newGroup:
        await AppNavigator.openNewGroup();
      case _MenuAction.readAll:
        final services = Services.read(context);
        try {
          for (final item in all) {
            if (item.chat.unreadCount > 0) await services.chats.markRead(item.chat.id);
          }
        } catch (error) {
          debugPrint('Чаты не отмечены прочитанными: $error');
          if (mounted) _showSnack('Не удалось выполнить действие');
        }
    }
  }

  Future<void> _openActions(ChatListItem item) async {
    HapticFeedback.selectionClick();
    final pinned = item.chat.isPinned;
    final unread = item.chat.unreadCount > 0;
    final archived = Services.read(context).archive.contains(item.chat.id);

    final action = await showActionSheet<_ChatAction>(
      context,
      header: _SheetHeader(item: item),
      actions: [
        SheetAction(
          value: _ChatAction.pin,
          icon: pinned ? AppIcons.pinOff : AppIcons.pin,
          label: pinned ? 'Открепить' : 'Закрепить',
        ),
        SheetAction(
          value: _ChatAction.read,
          icon: unread ? AppIcons.markRead : AppIcons.markUnread,
          label: unread ? 'Отметить прочитанным' : 'Отметить непрочитанным',
        ),
        SheetAction(
          value: _ChatAction.mute,
          icon: item.chat.muted ? AppIcons.notificationsOn : AppIcons.muted,
          label: item.chat.muted ? 'Включить уведомления' : 'Без звука',
        ),
        SheetAction(
          value: _ChatAction.archive,
          icon: archived ? AppIcons.unarchive : AppIcons.archive,
          label: archived ? 'Вернуть из архива' : 'В архив',
        ),
        const SheetAction(
          value: _ChatAction.delete,
          icon: AppIcons.delete,
          label: 'Удалить чат',
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    await _perform(action, item);
  }

  /// Действие над чатом: из меню по долгому нажатию и из свайпов строки.
  Future<void> _perform(_ChatAction action, ChatListItem item) async {
    final services = Services.read(context);
    final chatId = item.chat.id;
    final pinned = item.chat.isPinned;
    final unread = item.chat.unreadCount > 0;

    try {
      switch (action) {
        case _ChatAction.pin:
          await services.chats.setPinned(chatId, !pinned);
        case _ChatAction.read:
          if (unread) {
            await services.chats.markRead(chatId);
          } else {
            await services.chats.markUnread(chatId);
          }
        case _ChatAction.mute:
          await services.chats.setMuted(chatId, !item.chat.muted);
        case _ChatAction.archive:
          await services.archive.setArchived(chatId, !services.archive.contains(chatId));
        case _ChatAction.delete:
          final confirmed = await showConfirmDialog(
            context,
            title: 'Удалить чат?',
            message: 'Переписка с «${item.displayName}» будет удалена с этого '
                'телефона. Вернуть её будет нельзя.',
            confirmLabel: 'Удалить',
            destructive: true,
          );
          if (confirmed) {
            await services.chats.delete(chatId);
            await services.archive.setArchived(chatId, false);
          }
      }
    } catch (error) {
      debugPrint('Действие с чатом не выполнено: $error');
      if (mounted) _showSnack('Не удалось выполнить действие');
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return GlassWallpaper(
      child: SafeArea(
        bottom: false,
        child: LiveQuery<List<ChatListItem>>(
          tables: const {
            Tables.chats,
            Tables.messages,
            Tables.deviceContacts,
            Tables.characters,
            Tables.media,
            Tables.devices,
          },
          queryKey: widget.deviceId,
          load: () => services.chats.listForDevice(widget.deviceId),
          builder: (context, snapshot) {
            final all = snapshot.data;
            final searching = _query.trim().isNotEmpty;
            return Column(
              children: [
                ChatsHeader(
                  appear: _intro,
                  onTitleHold: AppNavigator.openOperator,
                  onMenu: () => _openMenu(all ?? const <ChatListItem>[]),
                  // Новый чат начинается с выбора контакта.
                  onNewChat: () => AppNavigator.homeTab.value = 2,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(ChatsScreen.sideMargin, 6, ChatsScreen.sideMargin, 0),
                  child: GlassSearchBar(
                    controller: _search,
                    hint: 'Поиск',
                    searchIcon: AppIcons.search,
                    clearIcon: AppIcons.clear,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                // Фильтры: при поиске сворачиваются (поиск идёт по всем чатам).
                AnimatedSize(
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.normal,
                  curve: Motion.curve,
                  alignment: Alignment.topCenter,
                  child: searching
                      ? const SizedBox(width: double.infinity)
                      : ChatFilterBar(
                          selected: _filter,
                          onSelect: (filter) => setState(() {
                            _filter = filter;
                            _openSwipe.value = null;
                          }),
                        ),
                ),
                const SizedBox(height: 10),
                Expanded(child: _list(context, services, snapshot)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(BuildContext context, AppServices services, LiveSnapshot<List<ChatListItem>> snapshot) {
    final all = snapshot.data;
    final bottomInset = MediaQuery.paddingOf(context).bottom + Space.m;
    if (all == null) {
      return snapshot.error != null
          ? ErrorState(
              message: 'Не удалось загрузить список чатов.',
              onRetry: snapshot.reload,
            )
          : const LoadingState();
    }
    if (all.isEmpty) {
      return const EmptyState(
        icon: AppIcons.emptyChats,
        title: 'Чатов пока нет',
        message: 'Откройте контакт, чтобы начать переписку.',
      );
    }
    final now = DateTime.now();
    if (_query.trim().isNotEmpty) {
      return _SearchResults(
        deviceId: widget.deviceId,
        query: _query,
        chats: filterChats(all, _query),
        now: now,
        bottomInset: bottomInset,
        chatTile: (item) => _tile(services, item, now),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([services.typing, services.stories, services.archive]),
      builder: (context, _) {
        final items = applyChatFilter(all, _filter, services.archive.ids);
        if (items.isEmpty) return _emptyFilter();
        return OrbRefresh(
          onRefresh: () async => snapshot.reload(),
          child: ListView.builder(
            // «Пружина» у краёв на любой платформе: за неё тянут, чтобы обновить.
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: bottomInset),
            itemCount: items.length,
            itemBuilder: (context, index) => ChatsIntro.card(
              animation: _intro,
              index: index,
              child: _tile(services, items[index], now),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyFilter() => switch (_filter) {
        ChatFilter.archive => const EmptyState(
            icon: AppIcons.archive,
            title: 'В архиве пусто',
            message: 'Смахните чат влево и выберите «В архив».',
          ),
        ChatFilter.groups => const EmptyState(
            icon: AppIcons.group,
            title: 'Групп пока нет',
            message: 'Создать группу можно через меню «…» вверху.',
          ),
        _ => const EmptyState(
            icon: AppIcons.emptyChats,
            title: 'Здесь пока пусто',
            message: 'Откройте контакт, чтобы начать переписку.',
          ),
      };

  Widget _tile(AppServices services, ChatListItem item, DateTime now) {
    final rc = context.rc;
    final pinned = item.chat.isPinned;
    final unread = item.chat.unreadCount > 0;
    final muted = item.chat.muted;
    final archived = services.archive.contains(item.chat.id);
    final ring = ContactStoryBar.ringFor(item, services.stories);
    return SwipeActionTile(
      key: ValueKey('swipe-${item.chat.id}'),
      id: item.chat.id,
      open: _openSwipe,
      background: Colors.transparent,
      clip: false,
      // Вправо: прочитано / закрепить. Влево: звук / удалить / архив.
      leading: [
        SwipeAction(
          icon: unread ? AppIcons.markRead : AppIcons.markUnread,
          label: unread ? 'Прочитан' : 'Не прочитан',
          color: GlassTheme.accentBlue,
          onTap: () => _perform(_ChatAction.read, item),
        ),
        SwipeAction(
          icon: pinned ? AppIcons.pinOff : AppIcons.pin,
          label: pinned ? 'Открепить' : 'Закрепить',
          color: rc.online,
          onTap: () => _perform(_ChatAction.pin, item),
        ),
      ],
      trailing: [
        SwipeAction(
          icon: muted ? AppIcons.notificationsOn : AppIcons.muted,
          label: muted ? 'Вкл. звук' : 'Без звука',
          color: Palette.tungsten,
          onTap: () => _perform(_ChatAction.mute, item),
        ),
        SwipeAction(
          icon: AppIcons.delete,
          label: 'Удалить',
          color: rc.danger,
          onTap: () => _perform(_ChatAction.delete, item),
        ),
        SwipeAction(
          icon: archived ? AppIcons.unarchive : AppIcons.archive,
          label: archived ? 'Из архива' : 'В архив',
          color: const Color(0xFF8A93A6),
          onTap: () => _perform(_ChatAction.archive, item),
        ),
      ],
      child: ChatTile(
        key: ValueKey(item.chat.id),
        item: item,
        now: now,
        typing: services.typing.isTyping(item.chat.id),
        ring: ring,
        // История открывается нажатием на аватар с кольцом, чат — на карточку.
        onAvatarTap: ring == StoryRing.none
            ? null
            : () => openStoryViewer(
                  context,
                  characterId: item.chat.peerCharacterId!,
                  name: item.displayName,
                  avatarPath: item.peer.avatarPath,
                  avatarTone: item.peer.avatarTone,
                ),
        onTap: () => AppNavigator.openChat(item.chat.id),
        onLongPress: () => _openActions(item),
      ),
    );
  }
}

/// Анимация открытия главного экрана.
abstract final class ChatsIntro {
  static const Duration duration = Duration(milliseconds: 900);

  /// Карточки появляются по очереди с шагом 50 мс.
  static const Duration step = Duration(milliseconds: 50);
  static const Duration cardDuration = Duration(milliseconds: 320);
  static const Duration cardsDelay = Duration(milliseconds: 120);

  /// Сколько первых карточек идут по очереди; остальные — вместе с последней.
  static const int staggered = 9;

  /// Отрезок общей анимации для карточки с номером [index].
  static Interval intervalFor(int index) {
    final total = duration.inMilliseconds;
    final i = index < staggered ? index : staggered;
    final begin = (cardsDelay.inMilliseconds + step.inMilliseconds * i) / total;
    final end = (begin + cardDuration.inMilliseconds / total).clamp(0.0, 1.0);
    return Interval(begin.clamp(0.0, 1.0), end, curve: Curves.easeOutCubic);
  }

  /// Карточка в общей анимации открытия: проявляется и чуть поднимается.
  static Widget card({required Animation<double> animation, required int index, required Widget child}) {
    final curve = CurveTween(curve: intervalFor(index));
    return FadeTransition(
      opacity: animation.drive(curve),
      child: SlideTransition(
        position: animation.drive(Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).chain(curve)),
        child: child,
      ),
    );
  }
}

/// Шапка: заголовок «Чаты» и две круглые стеклянные кнопки.
class ChatsHeader extends StatelessWidget {
  const ChatsHeader({
    super.key,
    required this.onMenu,
    required this.onNewChat,
    this.onTitleHold,
    this.appear,
  });

  final VoidCallback onMenu;
  final VoidCallback onNewChat;

  /// Скрытое действие: удерживать заголовок 2 секунды.
  final VoidCallback? onTitleHold;

  /// Открытие экрана: шапка проявляется и съезжает сверху.
  final Animation<double>? appear;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(ChatsScreen.sideMargin, 8, ChatsScreen.sideMargin, 6),
      child: Row(
        children: [
          Expanded(
            child: TitleHold(
              onHold: onTitleHold,
              child: Semantics(
                header: true,
                child: Text(
                  'Чаты',
                  maxLines: 1,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: glass.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          GlassIconButton(icon: AppIcons.more, label: 'Меню', onPressed: onMenu),
          const SizedBox(width: 12),
          GlassIconButton(icon: AppIcons.plus, label: 'Новый чат', onPressed: onNewChat),
        ],
      ),
    );
    final animation = appear;
    if (animation == null) return header;
    final curve = CurveTween(curve: const Interval(0, 0.45, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: animation.drive(curve),
      child: SlideTransition(
        position: animation.drive(Tween<Offset>(begin: const Offset(0, -0.35), end: Offset.zero).chain(curve)),
        child: header,
      ),
    );
  }
}

/// Фильтры списка: «Все», «Личные», «Группы», «Архив».
class ChatFilterBar extends StatelessWidget {
  const ChatFilterBar({super.key, required this.selected, required this.onSelect});

  final ChatFilter selected;
  final ValueChanged<ChatFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ChatsScreen.sideMargin, 14, ChatsScreen.sideMargin, 0),
      child: Row(
        children: [
          for (final filter in ChatFilter.values) ...[
            if (filter != ChatFilter.values.first) const SizedBox(width: 8),
            Expanded(
              child: GlassChip(
                key: ValueKey('filter-${filter.name}'),
                label: filter.label,
                selected: filter == selected,
                onTap: () => onSelect(filter),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Результаты поиска: подходящие чаты и найденные сообщения.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.deviceId,
    required this.query,
    required this.chats,
    required this.now,
    required this.bottomInset,
    required this.chatTile,
  });

  final String deviceId;
  final String query;
  final List<ChatListItem> chats;
  final DateTime now;
  final double bottomInset;
  final Widget Function(ChatListItem item) chatTile;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return LiveQuery<List<MessageHit>>(
      tables: const {Tables.messages, Tables.chats, Tables.deviceContacts, Tables.characters},
      queryKey: '$deviceId|$query',
      load: () => services.chats.searchMessages(deviceId, query),
      builder: (context, snapshot) {
        final hits = snapshot.data ?? const <MessageHit>[];
        if (chats.isEmpty && hits.isEmpty) {
          if (snapshot.isLoading) return const LoadingState();
          return EmptyState(
            icon: AppIcons.searchOff,
            title: 'Ничего не найдено',
            message: 'Нет чатов и сообщений по запросу «${query.trim()}».',
          );
        }
        return ListenableBuilder(
          listenable: Listenable.merge([services.typing, services.stories, services.archive]),
          builder: (context, _) => ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: bottomInset),
            children: [
              if (chats.isNotEmpty) ...[
                const SectionLabel('Чаты'),
                for (final chat in chats) chatTile(chat),
              ],
              if (hits.isNotEmpty) ...[
                SectionLabel(hits.length >= 100 ? 'Сообщения (первые 100)' : 'Сообщения'),
                for (final hit in hits)
                  MessageHitTile(
                    key: ValueKey('hit-${hit.message.id}'),
                    hit: hit,
                    now: now,
                    query: query,
                    onTap: () => AppNavigator.openChat(
                      hit.message.chatId,
                      revealMessageId: hit.message.id,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.item});

  final ChatListItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Avatar(
          name: item.displayName,
          size: Sizes.avatarHeader,
          imagePath: item.peer.avatarPath,
          tone: item.peer.avatarTone,
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Text(
            item.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.tt.titleMedium,
          ),
        ),
      ],
    );
  }
}
