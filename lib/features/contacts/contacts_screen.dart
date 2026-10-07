import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/pressable.dart';
import '../../core/design/widgets/search_field.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/contact.dart';
import 'contact_filter.dart';

enum _ContactAction { write, profile, edit, remove }

/// Контакты текущего телефона. Нажатие открывает переписку,
/// долгое нажатие — действия с контактом.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _opening = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openChat(Contact contact) async {
    if (_opening) return;
    _opening = true;
    final services = Services.read(context);
    try {
      final chatId = await services.chats.openOrCreateDirect(
        deviceId: widget.deviceId,
        characterId: contact.id,
      );
      if (!mounted) return;
      await AppNavigator.openChat(chatId);
    } catch (error) {
      debugPrint('Чат не открыт: $error');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Не удалось открыть чат')));
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _actions(Contact contact) async {
    HapticFeedback.selectionClick();
    final services = Services.read(context);
    final action = await showActionSheet<_ContactAction>(
      context,
      header: Text(contact.displayName, style: context.tt.titleMedium),
      actions: const [
        SheetAction(value: _ContactAction.write, icon: AppIcons.message, label: 'Написать'),
        SheetAction(value: _ContactAction.profile, icon: AppIcons.profile, label: 'Профиль'),
        SheetAction(value: _ContactAction.edit, icon: AppIcons.edit, label: 'Изменить'),
        SheetAction(
          value: _ContactAction.remove,
          icon: AppIcons.removeContact,
          label: 'Удалить из контактов',
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _ContactAction.write:
        await _openChat(contact);
      case _ContactAction.profile:
        await AppNavigator.openProfile(deviceId: widget.deviceId, characterId: contact.id);
      case _ContactAction.edit:
        await AppNavigator.openContactEditor(deviceId: widget.deviceId, characterId: contact.id);
      case _ContactAction.remove:
        final confirmed = await showConfirmDialog(
          context,
          title: 'Удалить из контактов?',
          message: '«${contact.displayName}» исчезнет из контактов этого телефона. '
              'Переписка останется, в ней будет виден номер.',
          confirmLabel: 'Удалить',
          destructive: true,
        );
        if (confirmed) await services.contacts.removeFromDevice(widget.deviceId, contact.id);
    }
  }

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
              title: 'Контакты',
              actions: [
                IconButton(
                  tooltip: 'Новый контакт',
                  style: quietButtonStyle,
                  icon: const Icon(AppIcons.add),
                  onPressed: () => AppNavigator.openContactEditor(deviceId: widget.deviceId),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: SearchField(
                controller: _search,
                hint: 'Имя или номер',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: LiveQuery<List<Contact>>(
                tables: const {Tables.deviceContacts, Tables.characters, Tables.media},
                queryKey: widget.deviceId,
                load: () => services.contacts.forDevice(widget.deviceId),
                builder: (context, snapshot) {
                  final all = snapshot.data;
                  if (all == null) {
                    return snapshot.error != null
                        ? ErrorState(
                            message: 'Не удалось загрузить контакты.',
                            onRetry: snapshot.reload,
                          )
                        : const LoadingState();
                  }
                  if (all.isEmpty) {
                    return const EmptyState(
                      icon: AppIcons.emptyContacts,
                      title: 'Контактов нет',
                      message: 'Добавьте первый контакт кнопкой вверху справа.',
                    );
                  }
                  final found = filterContacts(all, _query);
                  if (found.isEmpty) {
                    return EmptyState(
                      icon: AppIcons.searchOff,
                      title: 'Ничего не найдено',
                      message: 'Нет контактов по запросу «${_query.trim()}».',
                    );
                  }
                  return _ContactList(
                    contacts: found,
                    withSections: _query.trim().isEmpty,
                    onTap: _openChat,
                    onLongPress: _actions,
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

class _ContactList extends StatelessWidget {
  const _ContactList({
    required this.contacts,
    required this.withSections,
    required this.onTap,
    required this.onLongPress,
  });

  final List<Contact> contacts;
  final bool withSections;
  final ValueChanged<Contact> onTap;
  final ValueChanged<Contact> onLongPress;

  @override
  Widget build(BuildContext context) {
    final rows = <Object>[];
    String? currentLetter;
    for (final contact in contacts) {
      if (withSections) {
        final letter = sectionLetter(contact.displayName);
        if (letter != currentLetter) {
          currentLetter = letter;
          rows.add(letter);
        }
      }
      rows.add(contact);
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: Space.s),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is String) return _SectionHeader(letter: row);
        final contact = row as Contact;
        return _ContactTile(
          key: ValueKey(contact.id),
          contact: contact,
          onTap: () => onTap(contact),
          onLongPress: () => onLongPress(contact),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l + 4, Space.m + 2, Space.l, Space.xs),
      child: Text(
        letter,
        style: context.tt.labelMedium?.copyWith(
          color: context.cs.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    super.key,
    required this.contact,
    required this.onTap,
    required this.onLongPress,
  });

  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final character = contact.character;
    final subtitle = character.isOnline ? 'в сети' : character.phone;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: Row(
          children: [
            Avatar(
              name: contact.displayName,
              size: Sizes.avatarContact,
              imagePath: contact.avatarPath,
              tone: character.avatarTone,
            ),
            const SizedBox(width: Space.m + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: character.isOnline ? context.cs.primary : rc.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
