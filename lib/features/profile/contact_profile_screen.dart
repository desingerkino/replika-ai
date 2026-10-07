import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/pressable.dart';
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
                  style: TextButton.styleFrom(
                    splashFactory: NoSplash.splashFactory,
                    minimumSize: const Size(Sizes.minTouch, Sizes.minTouch),
                  ),
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
            online: character.isOnline,
          ),
        ),
        const SizedBox(height: Space.l),
        Text(
          contact.shownName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tt.headlineSmall,
        ),
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
        // Три действия в ряд: значок над подписью, область нажатия не меньше 48 px.
        ProfileActions(onWrite: onWrite, onCall: onCall),
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
    return Pressable(
      onTap: null,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        decoration: BoxDecoration(
          color: rc.surfaceMuted,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: rc.divider, width: Sizes.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Space.l - Sizes.line, vertical: Space.m - Sizes.line),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.tt.labelMedium),
            const SizedBox(height: 2),
            Text(value, style: context.tt.bodyLarge),
          ],
        ),
      ),
    );
  }
}

/// Три действия профиля в ряд: «Написать», «Позвонить», «Видео».
/// Открыт для виджет-тестов (test/ui_regression_test.dart).
class ProfileActions extends StatelessWidget {
  const ProfileActions({super.key, required this.onWrite, required this.onCall});

  final VoidCallback onWrite;
  final void Function(CallKind kind) onCall;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Row(
          children: [
            Expanded(
              child: ProfileAction(
                icon: AppIcons.message,
                label: 'Написать',
                primary: true,
                onTap: onWrite,
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: ProfileAction(
                icon: AppIcons.call,
                label: 'Позвонить',
                onTap: () => onCall(CallKind.audio),
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: ProfileAction(
                icon: AppIcons.video,
                label: 'Видео',
                onTap: () => onCall(CallKind.video),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Действие профиля: значок над подписью. «Написать» — основное (заливка),
/// остальные — спокойные, с рамкой 1 px. Нажатие без Material-волны.
class ProfileAction extends StatelessWidget {
  const ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final foreground = primary ? cs.onPrimary : cs.primary;
    return Pressable(
      tint: false,
      scale: 0.97,
      onTap: onTap,
      semanticsLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.s),
        decoration: BoxDecoration(
          color: primary ? cs.primary : rc.surfaceMuted,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: primary ? cs.primary : rc.divider, width: Sizes.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: foreground),
            const SizedBox(height: Space.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.labelLarge?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
