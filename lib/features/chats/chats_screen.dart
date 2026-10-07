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
import '../../core/design/widgets/search_field.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/chat.dart';
import 'chat_filter.dart';
import 'chat_tile.dart';
import 'swipe_actions.dart';
import 'contact_story_bar.dart';
import '../stories/story_viewer.dart';
import '../search/message_hit_tile.dart';

enum _ChatAction { pin, read, mute, delete }

/// Список чатов текущего телефона.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  Timer? _clock;

  /// Какая строка списка открыта свайпом (одна на весь список).
  final ValueNotifier<String?> _openSwipe = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    // Подписи времени («14:05», «вчера») сами обновляются раз в минуту.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _search.dispose();
    _openSwipe.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openActions(ChatListItem item) async {
    HapticFeedback.selectionClick();
    final pinned = item.chat.isPinned;
    final unread = item.chat.unreadCount > 0;

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
        case _ChatAction.delete:
          final confirmed = await showConfirmDialog(
            context,
            title: 'Удалить чат?',
            message: 'Переписка с «${item.displayName}» будет удалена с этого '
                'телефона. Вернуть её будет нельзя.',
            confirmLabel: 'Удалить',
            destructive: true,
          );
          if (confirmed) await services.chats.delete(chatId);
      }
    } catch (error) {
      debugPrint('Действие с чатом не выполнено: $error');
      if (mounted) _showSnack('Не удалось выполнить действие');
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final cs = context.cs;
    return ColoredBox(
      color: cs.surface,
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
                const ScreenHeader(
                  title: 'Чаты',
                  onTitleHold: AppNavigator.openOperator,
                  actions: [
                    IconButton(
                      tooltip: 'Новая группа',
                      icon: Icon(AppIcons.groupAdd),
                      onPressed: AppNavigator.openNewGroup,
                    ),
                  ],
                ),
                // Лента контактов: при поиске сворачивается, из дерева не уходит.
                ContactStoryBar(
                  items: all ?? const <ChatListItem>[],
                  visible: !searching && all != null && all.isNotEmpty,
                  onNewChat: () => AppNavigator.homeTab.value = 2,
                  onOpen: AppNavigator.openChat,
                  stories: services.stories,
                  onOpenStory: (item) => openStoryViewer(
                    context,
                    characterId: item.chat.peerCharacterId!,
                    name: item.displayName,
                    avatarPath: item.peer.avatarPath,
                    avatarTone: item.peer.avatarTone,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                  child: SearchField(
                    controller: _search,
                    hint: 'Поиск',
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
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
    final items = filterChats(all, _query);
    final now = DateTime.now();
    if (_query.trim().isEmpty) {
      return ListenableBuilder(
        listenable: services.typing,
        builder: (context, _) => ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: Space.s),
          itemCount: items.length,
          itemBuilder: (context, index) => _tile(
            items[index],
            now,
            showDivider: index < items.length - 1,
          ),
        ),
      );
    }
    return _SearchResults(
      deviceId: widget.deviceId,
      query: _query,
      chats: items,
      now: now,
      chatTile: (item, divider) => _tile(item, now, showDivider: divider),
    );
  }

  Widget _tile(ChatListItem item, DateTime now, {required bool showDivider}) {
    final rc = context.rc;
    final cs = context.cs;
    final pinned = item.chat.isPinned;
    final unread = item.chat.unreadCount > 0;
    final muted = item.chat.muted;
    return SwipeActionTile(
      key: ValueKey('swipe-${item.chat.id}'),
      id: item.chat.id,
      open: _openSwipe,
      // Вправо: прочитано / закрепить. Влево: звук / удалить.
      leading: [
        SwipeAction(
          icon: unread ? AppIcons.markRead : AppIcons.markUnread,
          label: unread ? 'Прочитан' : 'Не прочитан',
          color: cs.primary,
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
      ],
      child: ChatTile(
        key: ValueKey(item.chat.id),
        item: item,
        now: now,
        typing: Services.read(context).typing.isTyping(item.chat.id),
        showDivider: showDivider,
        onTap: () => AppNavigator.openChat(item.chat.id),
        onLongPress: () => _openActions(item),
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
    required this.chatTile,
  });

  final String deviceId;
  final String query;
  final List<ChatListItem> chats;
  final DateTime now;
  final Widget Function(ChatListItem item, bool showDivider) chatTile;

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
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: Space.s),
          children: [
            if (chats.isNotEmpty) ...[
              const SectionLabel('Чаты'),
              for (var i = 0; i < chats.length; i++) chatTile(chats[i], i < chats.length - 1),
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
