import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import 'chat_filter.dart';

/// Вкладки-папки над списком чатов (тема Telegram): закладка «Избранное»,
/// «Все чаты», «Непрочитанные» со счётчиком, «Личные», «Группы» и «+».
///
/// Удержание строки 2 секунды — скрытый вход в операторскую (как удержание
/// заголовка «Чаты» в другой теме); в кадре это ничем не видно.
class ChatFolderTabs extends StatelessWidget {
  const ChatFolderTabs({
    super.key,
    required this.selected,
    required this.unread,
    required this.hasGroups,
    required this.onSelect,
    required this.onFavorites,
    required this.onCompose,
    this.onHold,
  });

  final ChatFolder selected;

  /// Сколько чатов с непрочитанными (бейдж у «Непрочитанные»).
  final int unread;

  /// Есть ли группы (иначе вкладка «Группы» не нужна).
  final bool hasGroups;
  final ValueChanged<ChatFolder> onSelect;
  final VoidCallback onFavorites;
  final VoidCallback onCompose;
  final VoidCallback? onHold;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final folders = [
      ChatFolder.all,
      ChatFolder.unread,
      ChatFolder.personal,
      if (hasGroups || selected == ChatFolder.groups) ChatFolder.groups,
    ];
    // Закладка и «+» закреплены по краям, прокручиваются только папки:
    // так значки не уезжают за край при длинных названиях и счётчиках.
    Widget row = Container(
      height: 48,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rc.divider, width: 0.5))),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Избранное',
            onPressed: onFavorites,
            icon: Icon(Icons.bookmark_border_rounded, color: rc.textSecondary),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final folder in folders)
                  _Tab(
                    label: folder.label,
                    badge: folder == ChatFolder.unread ? unread : 0,
                    selected: folder == selected,
                    onTap: () => onSelect(folder),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Новый чат',
            onPressed: onCompose,
            icon: Icon(Icons.add_rounded, color: rc.textSecondary),
          ),
        ],
      ),
    );
    final hold = onHold;
    if (hold != null) {
      row = RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: const Duration(seconds: 2)),
            (recognizer) => recognizer.onLongPress = hold,
          ),
        },
        child: row,
      );
    }
    return row;
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.badge, required this.selected, required this.onTap});

  final String label;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, $badge' : label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m - 2),
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? cs.primary : rc.textSecondary,
                      ),
                    ),
                    if (badge > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? cs.primary : rc.badgeMuted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badge',
                          style: TextStyle(color: rc.onBadge, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: Motion.normal,
                  curve: Motion.curve,
                  height: 3,
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : Colors.transparent,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
