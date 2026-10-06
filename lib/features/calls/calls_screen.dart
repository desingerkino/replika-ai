import 'package:flutter/material.dart';

import '../../app/call_engine.dart';
import '../../app/live_query.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../core/util/time_format.dart';
import '../../data/db/tables.dart';
import '../../data/models/call_record.dart';
import '../../data/repositories/call_repository.dart';

/// Позвонить персонажу с текущего телефона (из чата, профиля, истории).
Future<void> startOutgoingCall(
  BuildContext context, {
  required String deviceId,
  required String characterId,
  required CallKind kind,
  String? chatId,
}) async {
  final services = Services.read(context);
  final contact = await services.contacts.view(deviceId, characterId);
  if (contact == null) return;
  final character = contact.character;
  final audio = character.callAudioMediaId == null
      ? null
      : await services.media.repository.byId(character.callAudioMediaId!);
  final video = character.callVideoMediaId == null
      ? null
      : await services.media.repository.byId(character.callVideoMediaId!);
  services.callEngine.start(CallSession(
    deviceId: deviceId,
    characterId: characterId,
    direction: CallDirection.outgoing,
    kind: kind,
    displayName: contact.shownName,
    chatId: chatId,
    sceneId: chatId == null ? null : services.engine.sceneIdForChat(chatId),
    avatarTone: character.avatarTone,
    avatarPath: contact.avatarPath,
    peerAudioPath: audio?.path,
    peerVideoPath: video?.path,
  ));
}

/// Вкладка «Звонки»: история постановочных звонков телефона.
class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key, required this.deviceId});

  final String deviceId;

  Future<void> _actions(BuildContext context, CallListItem item) async {
    final services = Services.read(context);
    final choice = await showActionSheet<String>(
      context,
      header: Text(item.displayName, style: context.tt.titleMedium),
      actions: const [
        SheetAction(value: 'audio', icon: Icons.call_rounded, label: 'Аудиозвонок'),
        SheetAction(value: 'video', icon: Icons.videocam_rounded, label: 'Видеозвонок'),
        SheetAction(value: 'delete', icon: Icons.delete_outline_rounded, label: 'Удалить из истории', destructive: true),
      ],
    );
    if (choice == null || !context.mounted) return;
    final characterId = item.call.characterId;
    if (choice == 'delete') {
      await services.calls.delete(item.call.id);
    } else if (characterId != null) {
      await startOutgoingCall(
        context,
        deviceId: deviceId,
        characterId: characterId,
        kind: choice == 'video' ? CallKind.video : CallKind.audio,
      );
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
            const ScreenHeader(title: 'Звонки'),
            Expanded(
              child: LiveQuery<List<CallListItem>>(
                tables: const {Tables.calls, Tables.characters, Tables.deviceContacts, Tables.media},
                queryKey: deviceId,
                load: () => services.calls.forDevice(deviceId),
                builder: (context, snapshot) {
                  final items = snapshot.data;
                  if (items == null) {
                    return snapshot.error != null
                        ? ErrorState(message: 'Не удалось загрузить звонки.', onRetry: snapshot.reload)
                        : const LoadingState();
                  }
                  if (items.isEmpty) {
                    return const EmptyState(
                      icon: Icons.call_outlined,
                      title: 'Звонков пока нет',
                      message: 'Позвоните из чата или профиля — звонок появится здесь.',
                    );
                  }
                  final now = DateTime.now();
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) => _CallTile(
                      item: items[index],
                      now: now,
                      onTap: () => _actions(context, items[index]),
                    ),
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

class _CallTile extends StatelessWidget {
  const _CallTile({required this.item, required this.now, required this.onTap});

  final CallListItem item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final call = item.call;
    final incoming = call.direction == CallDirection.incoming;
    final missed = incoming && call.outcome != CallOutcome.answered;
    final what = call.kind == CallKind.video ? 'видео' : 'аудио';
    final detail = [
      if (missed) 'пропущенный' else if (incoming) 'входящий' else 'исходящий',
      what,
      if (call.durationMs > 0) callClock(Duration(milliseconds: call.durationMs)),
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: Row(
          children: [
            Avatar(name: item.displayName, size: Sizes.avatarContact, tone: item.avatarTone, imagePath: item.avatarPath),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(color: missed ? rc.danger : null),
                  ),
                  Row(
                    children: [
                      Icon(
                        incoming ? Icons.call_received_rounded : Icons.call_made_rounded,
                        size: 16,
                        color: missed ? rc.danger : rc.textSecondary,
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(child: Text(detail, style: tt.bodySmall)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            Text(formatChatListTime(call.startedAt, now), style: tt.labelMedium),
          ],
        ),
      ),
    );
  }
}

/// «0:42», «12:05».
String callClock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
