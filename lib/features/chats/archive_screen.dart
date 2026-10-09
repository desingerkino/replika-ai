import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/swipe_actions.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/chat.dart';
import 'chat_actions.dart';
import 'chat_tile.dart';

/// Строка «Архив» над списком чатов.
class ArchiveRow extends StatelessWidget {
  const ArchiveRow({super.key, required this.chats, required this.onTap});

  final List<ChatListItem> chats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final unread = chats.fold<int>(0, (sum, c) => sum + c.chat.unreadCount);
    final names = chats.map((c) => c.displayName).join(', ');
    final size = context.style.avatarList;
    return Material(
      color: context.cs.surface,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: Sizes.chatRowMinHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.l),
            child: Row(
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: rc.badgeMuted, shape: BoxShape.circle),
                  child: const Icon(Icons.archive_outlined, color: MediaPalette.onMedia, size: 26),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(right: Space.l),
                    decoration: context.style.listDividers
                        ? BoxDecoration(border: Border(bottom: BorderSide(color: rc.divider, width: 0.5)))
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Архив', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16.5)),
                              const SizedBox(height: 3),
                              Text(
                                names,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodyMedium?.copyWith(color: rc.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (unread > 0)
                          Container(
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: rc.badgeMuted, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: TextStyle(color: rc.onBadge, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          )
                        else
                          Icon(Icons.chevron_right_rounded, color: rc.textTertiary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Архив: чаты, убранные из общего списка. Свайп влево — «Из архива».
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Scaffold(
      appBar: ReplikaTopBar(
        leading: const BackIconButton(),
        title: Text('Архив', style: context.tt.titleMedium),
      ),
      body: LiveQuery<List<ChatListItem>>(
        tables: const {Tables.chats, Tables.messages, Tables.deviceContacts, Tables.characters, Tables.media},
        queryKey: deviceId,
        load: () async => (await services.chats.listForDevice(deviceId)).where((i) => i.chat.isArchived).toList(),
        builder: (context, snapshot) {
          final items = snapshot.data;
          if (items == null) return const LoadingState();
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.archive_outlined,
              title: 'Архив пуст',
              message: 'Смахните чат влево в списке и нажмите «В архив».',
            );
          }
          final now = DateTime.now();
          return ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Space.l),
            children: [
              for (var i = 0; i < items.length; i++)
                Builder(builder: (context) {
                  final actions = ChatRowActions(context, items[i]);
                  return SwipeActionTile(
                    key: ValueKey('archive-${items[i].chat.id}'),
                    leading: actions.leading(),
                    trailing: actions.trailing(),
                    child: ChatTile(
                      item: items[i],
                      now: now,
                      showDivider: i < items.length - 1,
                      onTap: () => AppNavigator.openChat(items[i].chat.id),
                      onLongPress: actions.toggleArchive,
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
