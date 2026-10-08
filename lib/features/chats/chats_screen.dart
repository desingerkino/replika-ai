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
import '../../core/design/widgets/replika_refresh.dart';
import '../../core/theme/app_style.dart';
import '../stories/stories_strip.dart';
import 'chat_folder_tabs.dart';
import '../../core/design/widgets/search_field.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/chat.dart';
import 'chat_filter.dart';
import 'chat_tile.dart';
import '../search/message_hit_tile.dart';

enum _ChatAction { pin, read, mute, delete }

enum _ComposeAction { chat, group }

/// Список чатов текущего телефона.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  ChatFolder _folder = ChatFolder.all;
  Timer? _clock;

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
    _searchFocus.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _compose() async {
    final action = await showActionSheet<_ComposeAction>(
      context,
      actions: const [
        SheetAction(
          value: _ComposeAction.chat,
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Новый чат',
        ),
        SheetAction(
          value: _ComposeAction.group,
          icon: Icons.group_add_outlined,
          label: 'Новая группа',
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _ComposeAction.chat:
        // Чат начинается с выбора контакта.
        AppNavigator.homeTab.value = 1;
      case _ComposeAction.group:
        await AppNavigator.openNewGroup();
    }
  }

  Future<void> _openActions(ChatListItem item) async {
    HapticFeedback.selectionClick();
    final services = Services.read(context);
    final chatId = item.chat.id;
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
          icon: item.chat.muted ? Icons.notifications_active_outlined : AppIcons.muted,
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
    final searchFirst = context.style.chatListHeader == ChatListHeaderLook.searchFirst;
    final search = SearchField(
      controller: _search,
      focusNode: _searchFocus,
      hint: 'Поиск',
      onChanged: (value) => setState(() => _query = value),
    );
    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (searchFirst)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
                child: search,
              )
            else ...[
              ScreenHeader(
                title: 'Чаты',
                onTitleHold: AppNavigator.openOperator,
                actions: [
                  IconButton(
                    tooltip: 'Поиск',
                    icon: const Icon(AppIcons.search),
                    onPressed: _searchFocus.requestFocus,
                  ),
                  IconButton(
                    tooltip: 'Новый чат',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _compose,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                child: search,
              ),
            ],
            Expanded(
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
                  if (all == null) {
                    return snapshot.error != null
                        ? ErrorState(
                            message: 'Не удалось загрузить список чатов.',
                            onRetry: snapshot.reload,
                          )
                        : const LoadingState();
                  }
                  final searching = _query.trim().isNotEmpty;
                  final tabs = searchFirst && !searching
                      ? ChatFolderTabs(
                          selected: _folder,
                          unread: all.where((i) => i.chat.unreadCount > 0).length,
                          hasGroups: all.any((i) => i.chat.isGroup),
                          onSelect: (folder) => setState(() => _folder = folder),
                          onFavorites: () => AppNavigator.openFavorites(widget.deviceId),
                          onCompose: _compose,
                          onHold: AppNavigator.openOperator,
                        )
                      : null;
                  Widget body;
                  if (all.isEmpty) {
                    body = ListView(
                      children: [
                        StoriesStrip(deviceId: widget.deviceId),
                        SizedBox(
                          height: 360,
                          child: EmptyState(
                            icon: AppIcons.emptyChats,
                            title: 'Чатов пока нет',
                            message: 'Откройте контакт, чтобы начать переписку.',
                            action: FilledButton(
                              onPressed: () => AppNavigator.homeTab.value = 1,
                              child: const Text('Новый чат'),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else if (!searching) {
                    final items = filterByFolder(all, searchFirst ? _folder : ChatFolder.all);
                    final now = DateTime.now();
                    final pinned = items.where((item) => item.chat.isPinned).toList();
                    final others = items.where((item) => !item.chat.isPinned).toList();
                    final sections = !searchFirst && pinned.isNotEmpty && others.isNotEmpty;
                    body = ListenableBuilder(
                      listenable: services.typing,
                      builder: (context, _) => ListView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.only(bottom: Space.s + MediaQuery.paddingOf(context).bottom),
                        children: [
                          if (_folder == ChatFolder.all || !searchFirst) StoriesStrip(deviceId: widget.deviceId),
                          if (sections) const SectionLabel('Закреплённые'),
                          for (var i = 0; i < pinned.length; i++)
                            _tile(
                              pinned[i],
                              now,
                              showDivider: sections || i < pinned.length - 1 || others.isNotEmpty,
                            ),
                          if (sections) const SectionLabel('Все чаты'),
                          for (var i = 0; i < others.length; i++)
                            _tile(others[i], now, showDivider: i < others.length - 1),
                          if (items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(Space.xxl),
                              child: Text(
                                'В папке «${_folder.label}» пока пусто',
                                textAlign: TextAlign.center,
                                style: context.tt.bodyMedium?.copyWith(color: context.rc.textSecondary),
                              ),
                            ),
                        ],
                      ),
                    );
                  } else {
                    final now = DateTime.now();
                    body = _SearchResults(
                      deviceId: widget.deviceId,
                      query: _query,
                      chats: filterChats(all, _query),
                      now: now,
                      chatTile: (item, divider) => _tile(item, now, showDivider: divider),
                    );
                  }
                  return Column(
                    children: [
                      if (tabs != null) tabs,
                      Expanded(
                        child: ReplikaRefreshIndicator(
                          onRefresh: () async => snapshot.reload(),
                          child: body,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ChatListItem item, DateTime now, {required bool showDivider}) {
    return ChatTile(
      key: ValueKey(item.chat.id),
      item: item,
      now: now,
      typing: Services.read(context).typing.isTyping(item.chat.id),
      showDivider: showDivider,
      onTap: () => AppNavigator.openChat(item.chat.id),
      onLongPress: () => _openActions(item),
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
          padding: EdgeInsets.only(bottom: Space.s + MediaQuery.paddingOf(context).bottom),
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
