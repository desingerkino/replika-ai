import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/quick_action.dart';
import '../profile/shared_media.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import '../../data/models/origin.dart';
import '../../data/repositories/chat_repository.dart' show GroupMemberInfo;
import '../chat/chat_screen.dart' show membersLabel;

/// Серая плашка-событие в группе («Вы добавили Машу»).
Future<void> postGroupEvent(AppServices services, String chatId, String text) async {
  await services.messages.insertSceneMessage(
    chatId: chatId,
    senderId: null,
    type: MessageType.system,
    text: text,
    sceneId: null,
    origin: DataOrigin.base,
    state: MessageState.read,
  );
}

/// Выбор контактов телефона (несколько).
Future<Set<String>?> pickContacts(BuildContext context, List<Contact> contacts, {required String title}) {
  final chosen = <String>{};
  return showDialog<Set<String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (contacts.isEmpty) const Text('Все контакты телефона уже здесь.'),
            for (final c in contacts)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: chosen.contains(c.id),
                onChanged: (v) => setLocal(() => v == true ? chosen.add(c.id) : chosen.remove(c.id)),
                title: Text(c.displayName),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(chosen), child: const Text('Готово')),
        ],
      ),
    ),
  );
}

/// Новая группа: название и участники из контактов телефона.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final TextEditingController _title = TextEditingController();
  final Set<String> _chosen = {};
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final services = Services.read(context);
    final title = _title.text.trim();
    if (title.isEmpty || _chosen.isEmpty || _saving) return;
    setState(() => _saving = true);
    final id = await services.chats.createGroup(
      deviceId: services.currentDeviceId.value,
      title: title,
      memberIds: _chosen,
    );
    await postGroupEvent(services, id, 'Вы создали группу «$title»');
    if (!mounted) return;
    Navigator.of(context).pop();
    await AppNavigator.openChat(id);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final deviceId = services.currentDeviceId.value;
    return Scaffold(
      appBar: ReplikaTopBar(
        leading: const BackIconButton(),
        title: Text('Новая группа', style: context.tt.titleMedium),
        actions: [
          TextButton(
            onPressed: _title.text.trim().isEmpty || _chosen.isEmpty || _saving ? null : _create,
            child: const Text('Создать'),
          ),
        ],
      ),
      body: LiveQuery<List<Contact>>(
        tables: const {Tables.deviceContacts, Tables.characters},
        queryKey: deviceId,
        load: () => services.contacts.forDevice(deviceId),
        builder: (context, snapshot) {
          final contacts = snapshot.data;
          if (contacts == null) return const LoadingState();
          return ListView(
            padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxl)),
            children: [
              ReplikaTextField(
                controller: _title,
                label: 'Название группы',
                onChanged: (_) => setState(() {}),
              ),
              SectionLabel('Участники (${_chosen.length})'),
              if (contacts.isEmpty) const Text('На телефоне нет контактов — добавьте их во вкладке «Контакты».'),
              for (final c in contacts)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _chosen.contains(c.id),
                  onChanged: (v) => setState(() => v == true ? _chosen.add(c.id) : _chosen.remove(c.id)),
                  secondary: Avatar(name: c.displayName, size: 40, tone: c.character.avatarTone, imagePath: c.avatarPath),
                  title: Text(c.displayName),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupData {
  const _GroupData(this.title, this.members, this.ownerId, this.deviceId);

  final String title;
  final List<GroupMemberInfo> members;
  final String ownerId;
  final String deviceId;
}

/// Сведения о группе: название, участники, добавить, убрать.
class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({super.key, required this.chatId});

  final String chatId;

  Future<_GroupData?> _load(AppServices services) async {
    final header = await services.chats.header(chatId);
    if (header == null || !header.chat.isGroup) return null;
    return _GroupData(
      header.peer.displayName,
      await services.chats.members(chatId),
      header.ownerCharacterId,
      header.chat.deviceId,
    );
  }

  Future<void> _rename(BuildContext context, _GroupData data) async {
    final services = Services.read(context);
    final controller = TextEditingController(text: data.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Название группы'),
        content: TextField(controller: controller, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: const Text('Готово')),
        ],
      ),
    );
    if (title == null || title.isEmpty || title == data.title) return;
    await services.chats.renameGroup(chatId, title);
    await postGroupEvent(services, chatId, 'Вы изменили название группы на «$title»');
  }

  Future<void> _add(BuildContext context, _GroupData data) async {
    final services = Services.read(context);
    final inGroup = data.members.map((m) => m.characterId).toSet();
    final contacts = (await services.contacts.forDevice(data.deviceId)).where((c) => !inGroup.contains(c.id)).toList();
    if (!context.mounted) return;
    final chosen = await pickContacts(context, contacts, title: 'Добавить участников');
    if (chosen == null) return;
    for (final c in contacts.where((c) => chosen.contains(c.id))) {
      await services.chats.addMember(chatId, c.id);
      await postGroupEvent(services, chatId, 'Вы добавили: ${c.displayName}');
    }
  }

  Future<void> _pickColor(BuildContext context, GroupMemberInfo m) async {
    final services = Services.read(context);
    final tone = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Цвет: ${m.name}'),
        content: Wrap(
          spacing: Space.m,
          runSpacing: Space.m,
          children: [
            for (var i = 0; i < AvatarTones.all.length; i++)
              Semantics(
                button: true,
                selected: i == m.colorTone,
                label: 'Цвет ${i + 1}',
                child: GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(i),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AvatarTones.at(i),
                      shape: BoxShape.circle,
                      border: i == m.colorTone ? Border.all(width: 3, color: Colors.white) : null,
                      boxShadow: i == m.colorTone
                          ? [BoxShadow(color: AvatarTones.at(i), blurRadius: 0, spreadRadius: 2)]
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена'))],
      ),
    );
    if (tone == null || tone == m.colorTone) return;
    await services.chats.setMemberColor(chatId, m.characterId, tone);
  }

  Future<void> _remove(BuildContext context, GroupMemberInfo m) async {
    final services = Services.read(context);
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить ${m.name} из группы?',
      message: 'Сообщения участника в группе останутся.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok) return;
    await services.chats.removeMember(chatId, m.characterId);
    await postGroupEvent(services, chatId, 'Вы удалили: ${m.name}');
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Scaffold(
      appBar: ReplikaTopBar(
        leading: const BackIconButton(),
        title: Text('Группа', style: context.tt.titleMedium),
      ),
      body: LiveQuery<_GroupData?>(
        tables: const {Tables.chats, Tables.chatMembers, Tables.deviceContacts, Tables.characters},
        queryKey: chatId,
        load: () => _load(services),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return snapshot.isLoading ? const LoadingState() : const EmptyState(icon: Icons.group_off_outlined, title: 'Группа не найдена');
          }
          final rc = context.rc;
          final cs = context.cs;
          return ListView(
            padding: listPadding(context, const EdgeInsets.fromLTRB(0, Space.l, 0, Space.xxl)),
            children: [
              Center(child: Avatar(name: data.title, size: 104)),
              const SizedBox(height: Space.m),
              InkWell(
                onTap: () => _rename(context, data),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Column(
                    children: [
                      Text(data.title, textAlign: TextAlign.center, style: context.tt.headlineSmall?.copyWith(fontSize: 26)),
                      const SizedBox(height: 2),
                      Text(membersLabel(data.members.length), style: context.tt.bodyLarge?.copyWith(color: rc.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.l),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                child: LiveQuery<bool>(
                  tables: const {Tables.chats},
                  queryKey: chatId,
                  load: () async => (await services.chats.header(chatId))?.chat.muted ?? false,
                  builder: (context, muted) => Row(
                    children: [
                      Expanded(
                        child: QuickAction(
                          icon: (muted.data ?? false) ? Icons.notifications_off_outlined : Icons.notifications_none_rounded,
                          label: (muted.data ?? false) ? 'Без звука' : 'Звук',
                          active: muted.data ?? false,
                          onTap: () => services.chats.setMuted(chatId, !(muted.data ?? false)),
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: QuickAction(
                          icon: Icons.person_add_alt_rounded,
                          label: 'Добавить',
                          onTap: () => _add(context, data),
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: QuickAction(
                          icon: Icons.edit_outlined,
                          label: 'Название',
                          onTap: () => _rename(context, data),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.s),
              const SectionLabel('Участники'),
              InkWell(
                onTap: () => _add(context, data),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                        child: Icon(Icons.group_add_outlined, color: cs.primary),
                      ),
                      const SizedBox(width: Space.m),
                      Text('Добавить участников', style: context.tt.bodyLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              for (final m in data.members)
                Padding(
                  padding: const EdgeInsets.only(left: Space.l, right: Space.xs),
                  child: Row(
                    children: [
                      Avatar(name: m.name, size: 44, tone: m.tone),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AvatarTones.at(m.colorTone),
                            )),
                            Text(
                              m.characterId == data.ownerId ? 'вы' : 'участник',
                              style: context.tt.bodySmall?.copyWith(color: rc.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (m.characterId == data.ownerId)
                        Padding(
                          padding: const EdgeInsets.only(right: Space.s),
                          child: Text('владелец', style: context.tt.labelMedium?.copyWith(color: rc.textSecondary)),
                        ),
                      IconButton(
                        tooltip: 'Цвет участника',
                        icon: Icon(Icons.circle, color: AvatarTones.at(m.colorTone)),
                        onPressed: () => _pickColor(context, m),
                      ),
                      if (m.characterId != data.ownerId)
                        IconButton(
                          tooltip: 'Удалить из группы',
                          icon: Icon(Icons.remove_circle_outline_rounded, color: rc.textTertiary),
                          onPressed: () => _remove(context, m),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: Space.m),
              SharedMediaSection(deviceId: data.deviceId, chatId: chatId),
            ],
          );
        },
      ),
    );
  }
}
