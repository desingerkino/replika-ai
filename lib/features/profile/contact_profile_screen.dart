import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/call_record.dart';
import '../../data/models/contact.dart';
import '../calls/calls_screen.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/quick_action.dart';
import '../../data/repositories/story_repository.dart';
import '../stories/story_actions.dart';
import '../stories/story_avatar.dart';
import 'shared_media.dart';

/// Профиль собеседника — так его видит владелец телефона.
/// Служебная заметка оператора здесь не показывается: экран бывает в кадре.
class ContactProfileScreen extends StatefulWidget {
  const ContactProfileScreen({
    super.key,
    required this.deviceId,
    required this.characterId,
  });

  final String deviceId;
  final String characterId;

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  bool _opening = false;

  Future<void> _write() async {
    if (_opening) return;
    _opening = true;
    final services = Services.read(context);
    try {
      final chatId = await services.chats.openOrCreateDirect(
        deviceId: widget.deviceId,
        characterId: widget.characterId,
      );
      if (!mounted) return;
      // Профиль закрывается. Если под ним этот же чат — возвращаемся в него,
      // иначе открываем чат заново.
      var profileRoute = true;
      var fromSameChat = false;
      Navigator.of(context).popUntil((route) {
        if (profileRoute) {
          profileRoute = false;
          return false;
        }
        fromSameChat = route.settings.name == '/chat' && route.settings.arguments == chatId;
        return true;
      });
      if (!fromSameChat) await AppNavigator.openChat(chatId);
    } catch (error) {
      debugPrint('Чат не открыт: $error');
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return LiveQuery<Contact?>(
      tables: const {Tables.characters, Tables.deviceContacts, Tables.media},
      queryKey: widget.characterId,
      load: () => services.contacts.view(widget.deviceId, widget.characterId),
      builder: (context, snapshot) {
        final contact = snapshot.data;
        final Widget body;
        if (contact == null) {
          body = snapshot.error != null
              ? ErrorState(message: 'Не удалось открыть профиль.', onRetry: snapshot.reload)
              : snapshot.isLoading
                  ? const LoadingState()
                  : const EmptyState(icon: AppIcons.profile, title: 'Профиль не найден');
        } else {
          body = _ProfileBody(
            deviceId: widget.deviceId,
            contact: contact,
            onWrite: _write,
            onCall: (kind) => startOutgoingCall(
              context,
              deviceId: widget.deviceId,
              characterId: widget.characterId,
              kind: kind,
            ),
          );
        }
        return Scaffold(
          appBar: ReplikaTopBar(
            leading: const BackIconButton(),
            title: const SizedBox.shrink(),
            actions: [
              if (contact != null)
                TextButton(
                  onPressed: () => AppNavigator.openContactEditor(
                    deviceId: widget.deviceId,
                    characterId: widget.characterId,
                  ),
                  child: Text(contact.saved ? 'Изменить' : 'Добавить'),
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.deviceId,
    required this.contact,
    required this.onWrite,
    required this.onCall,
  });

  final String deviceId;
  final Contact contact;
  final VoidCallback onWrite;
  final ValueChanged<CallKind> onCall;

  Future<void> _more(BuildContext context) async {
    final services = Services.read(context);
    final chatId = await services.chats.findDirect(deviceId: deviceId, characterId: contact.id);
    final header = chatId == null ? null : await services.chats.header(chatId);
    if (!context.mounted) return;
    final muted = header?.chat.muted ?? false;
    final action = await showActionSheet<String>(
      context,
      actions: [
        if (chatId != null)
          SheetAction(
            value: 'mute',
            icon: muted ? Icons.notifications_active_outlined : AppIcons.muted,
            label: muted ? 'Включить уведомления' : 'Без звука',
          ),
        const SheetAction(value: 'story', icon: Icons.add_circle_outline_rounded, label: 'Добавить историю контакта'),
        const SheetAction(value: 'edit', icon: AppIcons.edit, label: 'Изменить контакт'),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'mute':
        if (chatId != null) await services.chats.setMuted(chatId, !muted);
      case 'story':
        await addStory(context, deviceId: deviceId, characterId: contact.id);
      case 'edit':
        await AppNavigator.openContactEditor(deviceId: deviceId, characterId: contact.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final cs = context.cs;
    final services = Services.of(context);
    final character = contact.character;
    final status = character.statusText.trim();
    return ListView(
      padding: listPadding(context, const EdgeInsets.fromLTRB(0, Space.l, 0, Space.xl)),
      children: [
        Center(
          child: LiveQuery<List<StoryAuthor>>(
            tables: const {Tables.stories, Tables.media},
            queryKey: '$deviceId|${contact.id}',
            load: () => services.stories.authorsForDevice(deviceId),
            builder: (context, snapshot) {
              final authors = snapshot.data ?? const <StoryAuthor>[];
              final mine = [for (final a in authors) if (a.characterId == contact.id) a];
              final has = mine.isNotEmpty;
              return GestureDetector(
                onTap: has ? () => openStories(context, deviceId: deviceId, authors: mine) : null,
                child: StoryAvatar(
                  name: contact.shownName,
                  size: 128,
                  imagePath: contact.avatarPath,
                  tone: character.avatarTone,
                  hasStories: has,
                  unseen: has && mine.first.hasUnseen,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.m),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Text(contact.shownName, textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(fontSize: 26)),
        ),
        if (status.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(
            status,
            textAlign: TextAlign.center,
            style: tt.bodyLarge?.copyWith(color: character.isOnline ? cs.primary : rc.textSecondary),
          ),
        ],
        const SizedBox(height: Space.l),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Row(
            children: [
              Expanded(child: QuickAction(icon: Icons.call_outlined, label: 'Звонок', onTap: () => onCall(CallKind.audio))),
              const SizedBox(width: Space.s),
              Expanded(child: QuickAction(icon: Icons.videocam_outlined, label: 'Видео', onTap: () => onCall(CallKind.video))),
              const SizedBox(width: Space.s),
              Expanded(child: QuickAction(icon: Icons.chat_bubble_outline_rounded, label: 'Чат', onTap: onWrite)),
              const SizedBox(width: Space.s),
              Expanded(child: QuickAction(icon: Icons.more_vert_rounded, label: 'Ещё', onTap: () => _more(context))),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        Divider(height: 8, thickness: 8, color: rc.surfaceMuted.withValues(alpha: 0.6)),
        if (character.phone.trim().isNotEmpty)
          _InfoCard(
            label: 'Мобильный',
            value: character.phone,
            accent: true,
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: character.phone));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Номер скопирован')));
              }
            },
          ),
        if (!contact.saved && character.fullName.isNotEmpty) _InfoCard(label: 'Имя', value: character.fullName),
        SharedMediaSection(deviceId: deviceId, characterId: contact.id),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value, this.onLongPress, this.accent = false});

  final String label;
  final String value;
  final VoidCallback? onLongPress;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l + 4, vertical: Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.tt.labelMedium),
            const SizedBox(height: 2),
            Text(value, style: context.tt.bodyLarge?.copyWith(color: accent ? context.cs.primary : null)),
          ],
        ),
      ),
    );
  }
}
