import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/call_record.dart';
import '../../data/models/contact.dart';
import '../calls/calls_screen.dart';
import '../../core/design/widgets/form.dart';

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
  const _ProfileBody({required this.contact, required this.onWrite, required this.onCall});

  final Contact contact;
  final VoidCallback onWrite;
  final ValueChanged<CallKind> onCall;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final character = contact.character;
    final status = character.statusText.trim();
    return ListView(
      padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.xl)),
      children: [
        Center(
          child: Avatar(
            name: contact.shownName,
            size: 104,
            imagePath: contact.avatarPath,
            tone: character.avatarTone,
          ),
        ),
        const SizedBox(height: Space.l),
        Text(contact.shownName, textAlign: TextAlign.center, style: tt.headlineSmall),
        if (status.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(
            status,
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(
              color: character.isOnline ? context.cs.primary : rc.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: Space.xl),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            FilledButton.icon(
              onPressed: onWrite,
              icon: const Icon(AppIcons.message, size: 20),
              label: const Text('Написать'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => onCall(CallKind.audio),
              icon: const Icon(Icons.call_rounded, size: 20),
              label: const Text('Позвонить'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => onCall(CallKind.video),
              icon: const Icon(Icons.videocam_rounded, size: 20),
              label: const Text('Видео'),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        if (character.phone.trim().isNotEmpty)
          _InfoCard(
            label: 'Мобильный',
            value: character.phone,
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: character.phone));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Номер скопирован')));
              }
            },
          ),
        if (!contact.saved && character.fullName.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          _InfoCard(label: 'Имя', value: character.fullName),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value, this.onLongPress});

  final String label;
  final String value;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return Material(
      color: rc.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.tt.labelMedium),
              const SizedBox(height: 2),
              Text(value, style: context.tt.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
