import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/icons.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/chat.dart';
import '../search/message_hit_tile.dart';

/// «Избранное» — отмеченные звёздочкой сообщения из всех чатов телефона.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.deviceId});

  final String deviceId;

  Future<void> _actions(BuildContext context, MessageHit hit) async {
    final services = Services.read(context);
    final remove = await showActionSheet<bool>(
      context,
      actions: const [
        SheetAction(value: true, icon: AppIcons.starOutline, label: 'Убрать из избранного'),
      ],
    );
    if (remove == true) await services.messages.setFavorite(hit.message.id, false);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Scaffold(
      appBar: ReplikaTopBar(
        leading: const BackIconButton(),
        title: Text('Избранное', style: Theme.of(context).textTheme.titleMedium),
      ),
      body: LiveQuery<List<MessageHit>>(
        tables: const {Tables.messages, Tables.chats, Tables.deviceContacts, Tables.characters},
        queryKey: deviceId,
        load: () => services.chats.favorites(deviceId),
        builder: (context, snapshot) {
          final hits = snapshot.data;
          if (hits == null) {
            return snapshot.error != null
                ? ErrorState(message: 'Не удалось загрузить избранное.', onRetry: snapshot.reload)
                : const LoadingState();
          }
          if (hits.isEmpty) {
            return const EmptyState(
              icon: AppIcons.starOutline,
              title: 'В избранном пусто',
              message: 'Нажмите и удерживайте сообщение в чате, затем выберите «В избранное».',
            );
          }
          final now = DateTime.now();
          return ListView.builder(
            itemCount: hits.length,
            itemBuilder: (context, index) {
              final hit = hits[index];
              return MessageHitTile(
                key: ValueKey(hit.message.id),
                hit: hit,
                now: now,
                maxLines: 3,
                onTap: () => AppNavigator.openChat(
                  hit.message.chatId,
                  revealMessageId: hit.message.id,
                ),
                onLongPress: () => _actions(context, hit),
              );
            },
          );
        },
      ),
    );
  }
}
