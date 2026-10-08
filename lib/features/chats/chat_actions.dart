import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/swipe_actions.dart';
import '../../data/models/chat.dart';

/// Действия со строкой чата: одни и те же для свайпов, меню и архива.
/// Каждое меняет настоящее состояние в базе.
class ChatRowActions {
  ChatRowActions(this.context, this.item);

  final BuildContext context;
  final ChatListItem item;

  AppServices get _s => Services.read(context);
  String get _id => item.chat.id;

  void _snack(String text, {String? undoLabel, VoidCallback? onUndo}) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      action: undoLabel == null ? null : SnackBarAction(label: undoLabel, onPressed: onUndo ?? () {}),
    ));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Действие с чатом не выполнено: $error');
      _snack('Не удалось выполнить действие');
    }
  }

  Future<void> toggleRead() => _guard(() async {
        if (item.chat.unreadCount > 0) {
          await _s.chats.markRead(_id);
        } else {
          await _s.chats.markUnread(_id);
        }
      });

  Future<void> togglePin() => _guard(() => _s.chats.setPinned(_id, !item.chat.isPinned));

  Future<void> toggleMute() => _guard(() => _s.chats.setMuted(_id, !item.chat.muted));

  Future<void> toggleArchive() => _guard(() async {
        final archive = !item.chat.isArchived;
        // Репозиторий берём сразу: строка может исчезнуть из списка раньше,
        // чем нажмут «Отменить».
        final chats = _s.chats;
        await chats.setArchived(_id, archive);
        _snack(
          archive ? 'Чат перенесён в архив' : 'Чат возвращён из архива',
          undoLabel: 'Отменить',
          onUndo: () => chats.setArchived(_id, !archive),
        );
      });

  /// Удаление — настоящее, после подтверждения.
  Future<void> delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Удалить чат?',
      message: 'Переписка с «${item.displayName}» будет удалена с этого '
          'телефона. Вернуть её будет нельзя.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (confirmed) await _guard(() => _s.chats.delete(_id));
  }

  /// Свайп вправо: прочитано / не прочитано и закрепить.
  List<SwipeAction> leading() {
    final cs = context.cs;
    final rc = context.rc;
    final unread = item.chat.unreadCount > 0;
    return [
      SwipeAction(
        icon: unread ? AppIcons.markRead : AppIcons.markUnread,
        label: unread ? 'Прочитано' : 'Не прочитан',
        color: cs.primary,
        onTap: toggleRead,
      ),
      SwipeAction(
        icon: item.chat.isPinned ? AppIcons.pinOff : AppIcons.pin,
        label: item.chat.isPinned ? 'Открепить' : 'Закрепить',
        color: rc.success,
        onTap: togglePin,
      ),
    ];
  }

  /// Свайп влево: звук, удалить, архив.
  List<SwipeAction> trailing() {
    final rc = context.rc;
    return [
      SwipeAction(
        icon: item.chat.muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        label: item.chat.muted ? 'Вкл. звук' : 'Без звука',
        color: rc.warning,
        onTap: toggleMute,
      ),
      SwipeAction(icon: AppIcons.delete, label: 'Удалить', color: rc.danger, onTap: delete),
      SwipeAction(
        icon: item.chat.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
        label: item.chat.isArchived ? 'Из архива' : 'В архив',
        color: rc.badgeMuted,
        onTap: toggleArchive,
      ),
    ];
  }
}
