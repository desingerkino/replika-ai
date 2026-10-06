import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/util/json.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/scene.dart';
import '../../data/models/scene_action.dart';
import '../../data/repositories/scene_repository.dart';
import 'action_editor_screen.dart';
import 'action_summary.dart';
import 'operator_theme.dart';

class _EditorData {
  const _EditorData({
    required this.scene,
    required this.actions,
    required this.chatName,
    required this.deviceId,
    required this.participants,
  });

  final Scene scene;
  final List<SceneAction> actions;
  final String? chatName;
  final String deviceId;
  final List<SceneParticipantRow> participants;

  Map<String, String> get names => {for (final p in participants) p.characterId: p.name};

  /// Имя по умолчанию для действий без участника (старые сцены).
  String get defaultName => chatName ?? (participants.isEmpty ? 'Собеседник' : participants.first.name);
}

enum _SceneMenu { copy, delete }

/// Редактор сцены: номер, название, чат и таймлайн действий.
class SceneEditorScreen extends StatefulWidget {
  const SceneEditorScreen({super.key, required this.sceneId});

  final String sceneId;

  @override
  State<SceneEditorScreen> createState() => _SceneEditorScreenState();
}

class _SceneEditorScreenState extends State<SceneEditorScreen> {
  final _number = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _filled = false;
  Timer? _saveTimer;
  AppServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = Services.of(context);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveNow();
    for (final c in [_number, _name, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  void _scheduleSave(String _) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  void _saveNow() {
    final services = _services;
    if (!_filled || services == null) return;
    unawaited(services.scenes.update(widget.sceneId, {
      'number': _number.text.trim(),
      'name': _name.text.trim().isEmpty ? 'Без названия' : _name.text.trim(),
      'description': _description.text.trim(),
    }));
  }

  Future<_EditorData?> _load(AppServices services) async {
    final scene = await services.scenes.byId(widget.sceneId);
    if (scene == null) return null;
    final actions = await services.scenes.actions(scene.id);
    String? chatName;
    if (scene.chatId != null) chatName = (await services.chats.header(scene.chatId!))?.peer.displayName;
    final deviceId = scene.deviceId ?? services.currentDeviceId.value;
    return _EditorData(
      scene: scene,
      actions: actions,
      chatName: chatName,
      deviceId: deviceId,
      participants: await services.scenes.participants(scene.id, deviceId),
    );
  }

  Future<void> _pickChat(Scene scene) async {
    final services = Services.read(context);
    final deviceId = scene.deviceId ?? services.currentDeviceId.value;
    final chats = await services.chats.listForDevice(deviceId);
    if (!mounted) return;
    if (chats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('На этом телефоне нет чатов. Откройте контакт и напишите сообщение.')),
      );
      return;
    }
    final chatId = await showActionSheet<String>(
      context,
      header: const Text('Чат сцены', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: [
        for (final c in chats)
          SheetAction(
            value: c.chat.id,
            icon: Icons.chat_bubble_outline_rounded,
            label: c.displayName,
            selected: c.chat.id == scene.chatId,
          ),
      ],
    );
    if (chatId == null) return;
    await services.scenes.update(scene.id, {'chat_id': chatId, 'device_id': deviceId});
  }

  /// «Время в кадре»: какое время показывают сообщения сцены.
  Future<void> _pickClock(Scene scene) async {
    final services = Services.read(context);
    final current = scene.initialState['clock'] as String?;
    final choice = await showActionSheet<String>(
      context,
      header: const Text('Время в кадре', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: [
        SheetAction(value: 'set', icon: Icons.schedule_rounded, label: 'Задать время', selected: current != null),
        SheetAction(value: 'real', icon: Icons.update_rounded, label: 'Реальное время телефона', selected: current == null),
      ],
    );
    if (choice == null || !mounted) return;
    String? value;
    if (choice == 'set') {
      final parts = (current ?? '23:47').split(':');
      final picked = await showTimePicker(
        context: context,
        helpText: 'Время первого сообщения сцены',
        cancelText: 'Отмена',
        confirmText: 'Готово',
        initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 23, minute: int.tryParse(parts.last) ?? 47),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        ),
      );
      if (picked == null) return;
      value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
    final state = {...scene.initialState}..remove('clock');
    if (value != null) state['clock'] = value;
    await services.scenes.update(scene.id, {'initial_state_json': encodeJsonMap(state)});
    if (services.engine.info?.sceneId == scene.id) await services.engine.refreshInfo();
  }

  Future<void> _addAction() async {
    final type = await pickActionType(context);
    if (type == null || !mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ActionEditorScreen(
        sceneId: widget.sceneId,
        type: type,
        defaultCharacterId: _services?.engine.activeParticipantId,
      ),
    ));
  }

  /// Добавить участников из контактов телефона сцены (сразу несколько).
  Future<void> _addParticipants(_EditorData data) async {
    final services = Services.read(context);
    final contacts = await services.contacts.forDevice(data.deviceId);
    if (!mounted) return;
    final existing = data.participants.map((p) => p.characterId).toSet();
    final available = contacts.where((c) => !existing.contains(c.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Все контакты телефона уже в сцене. Новый контакт добавляется во вкладке «Контакты».'),
      ));
      return;
    }
    final chosen = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          scrollable: true,
          title: const Text('Участники сцены'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in available)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: chosen.contains(c.id),
                  onChanged: (v) => setLocal(() => v == true ? chosen.add(c.id) : chosen.remove(c.id)),
                  title: Text(c.displayName),
                  subtitle: c.character.fullName.isEmpty ? null : Text(c.character.fullName),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Добавить')),
          ],
        ),
      ),
    );
    if (ok != true || chosen.isEmpty) return;
    // У старой сцены участником был собеседник её чата — сохраняем его.
    final legacyPeer = data.participants.isEmpty && data.scene.chatId != null
        ? (await services.chats.header(data.scene.chatId!))?.chat.peerCharacterId
        : null;
    await services.scenes.addParticipants(widget.sceneId, [if (legacyPeer != null) legacyPeer, ...chosen]);
    await services.scenes.update(widget.sceneId, {'device_id': data.deviceId});
    await _refreshEngine();
  }

  Future<void> _removeParticipant(_EditorData data, SceneParticipantRow p) async {
    final services = Services.read(context);
    final used = data.actions.where((a) => a.characterId == p.characterId).length;
    final ok = await showConfirmDialog(
      context,
      title: 'Убрать «${p.name}» из сцены?',
      message: used == 0
          ? 'Контакт и его переписка не изменятся.'
          : 'У участника $used действий в таймлайне — они останутся, но будут выполняться '
              'от имени участника по умолчанию. Лучше сначала поменять им участника.',
      confirmLabel: 'Убрать',
      destructive: true,
    );
    if (!ok) return;
    await services.scenes.removeParticipant(widget.sceneId, p.characterId);
    await _refreshEngine();
  }

  Future<void> _refreshEngine() async {
    final engine = _services?.engine;
    if (engine != null && engine.info?.sceneId == widget.sceneId && !engine.hasTake) {
      try {
        await engine.refreshInfo();
      } catch (_) {
        // Сцена пока без участников — панель покажет подсказку.
      }
    }
  }

  Future<void> _menu(_SceneMenu choice) async {
    final services = Services.read(context);
    switch (choice) {
      case _SceneMenu.copy:
        final id = await services.scenes.duplicate(widget.sceneId);
        if (!mounted) return;
        Navigator.of(context).pop();
        await AppNavigator.openSceneEditor(id);
      case _SceneMenu.delete:
        final ok = await showConfirmDialog(
          context,
          title: 'Удалить сцену?',
          message: 'Сцена, её таймлайн и история дублей будут удалены. Переписки не изменятся.',
          confirmLabel: 'Удалить',
          destructive: true,
        );
        if (!ok || !mounted) return;
        if (services.engine.info?.sceneId == widget.sceneId) await services.engine.stop();
        _filled = false;
        await services.scenes.delete(widget.sceneId);
        if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Theme(
      data: operatorTheme,
      child: LiveQuery<_EditorData?>(
        tables: const {Tables.scenes, Tables.sceneActions, Tables.chats, Tables.deviceContacts, Tables.characters},
        queryKey: widget.sceneId,
        load: () => _load(services),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data != null && !_filled) {
            _number.text = data.scene.number;
            _name.text = data.scene.name;
            _description.text = data.scene.description;
            _filled = true;
          }
          return Scaffold(
            appBar: ReplikaTopBar(
              leading: const BackIconButton(),
              title: const Text('Сцена', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              actions: [
                if (data != null)
                  TextButton.icon(
                    onPressed: data.scene.chatId == null && data.participants.isEmpty
                        ? null
                        : () {
                            _saveNow();
                            AppNavigator.openSceneChats(widget.sceneId);
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Запуск'),
                  ),
                PopupMenuButton<_SceneMenu>(
                  tooltip: 'Ещё',
                  onSelected: _menu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _SceneMenu.copy, child: Text('Копия сцены')),
                    PopupMenuItem(value: _SceneMenu.delete, child: Text('Удалить сцену')),
                  ],
                ),
              ],
            ),
            floatingActionButton: data == null
                ? null
                : FloatingActionButton.extended(
                    backgroundColor: OperatorPalette.standby,
                    foregroundColor: OperatorPalette.background,
                    onPressed: _addAction,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Действие', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
            body: data == null
                ? (snapshot.isLoading
                    ? const LoadingState()
                    : const EmptyState(icon: Icons.movie_filter_outlined, title: 'Сцена не найдена'))
                : _buildBody(data),
          );
        },
      ),
    );
  }

  Widget _buildBody(_EditorData data) {
    final actions = data.actions;
    final names = data.names;
    final offsets = timelineOffsets(actions);
    return ReorderableListView.builder(
      padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 112)),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 96,
                child: ReplikaTextField(
                  controller: _number,
                  label: 'Номер',
                  textCapitalization: TextCapitalization.characters,
                  onChanged: _scheduleSave,
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: ReplikaTextField(controller: _name, label: 'Название', onChanged: _scheduleSave),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          ReplikaTextField(
            controller: _description,
            label: 'Описание для себя',
            maxLines: 3,
            onChanged: _scheduleSave,
          ),
          const SizedBox(height: Space.m),
          SectionLabel('Участники (${data.participants.length})'),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final p in data.participants)
                InputChip(
                  avatar: Avatar(name: p.name, size: 24, tone: p.avatarTone, imagePath: p.avatarPath),
                  label: Text(p.name),
                  onDeleted: () => _removeParticipant(data, p),
                  deleteButtonTooltipMessage: 'Убрать из сцены',
                ),
              ActionChip(
                avatar: const Icon(Icons.person_add_alt_rounded, size: 18),
                label: const Text('Добавить'),
                onPressed: () => _addParticipants(data),
              ),
            ],
          ),
          if (data.participants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(
                data.chatName == null
                    ? 'Добавьте участников: сцена выполняет действия от имени любого из них.'
                    : 'Участник сейчас один — собеседник чата «${data.chatName}». '
                        'Добавьте других, чтобы действовать от их имени.',
                style: const TextStyle(color: OperatorPalette.textDim),
              ),
            ),
          const SizedBox(height: Space.m),
          OperatorCard(
            onTap: () => _pickChat(data.scene),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, color: OperatorPalette.standby),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    data.chatName == null ? 'Чат «В КАДР» — не выбран (необязательно)' : 'Чат «В КАДР»: ${data.chatName}',
                    style: const TextStyle(color: OperatorPalette.text, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
              ],
            ),
          ),
          const SizedBox(height: Space.s),
          OperatorCard(
            onTap: () => _pickClock(data.scene),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: OperatorPalette.standby),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Время в кадре: ${data.scene.initialState['clock'] ?? 'реальное'}',
                        style: const TextStyle(color: OperatorPalette.text, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const Text(
                        'Сообщения сцены показывают это время и идут от него. '
                        'Часы в строке состояния телефона меняет только система.',
                        style: TextStyle(color: OperatorPalette.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
              ],
            ),
          ),
          const SectionLabel('Таймлайн'),
          if (actions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: Space.l),
              child: Text(
                'Добавьте действия кнопкой «Действие». Порядок меняется '
                'перетаскиванием (удерживайте строку).',
                style: TextStyle(color: OperatorPalette.textDim),
              ),
            ),
        ],
      ),
      itemCount: actions.length,
      onReorder: (from, to) {
        final ids = actions.map((a) => a.id).toList();
        final moved = ids.removeAt(from);
        ids.insert(to > from ? to - 1 : to, moved);
        Services.read(context).scenes.reorder(ids);
      },
      itemBuilder: (context, index) {
        final action = actions[index];
        return Padding(
          key: ValueKey(action.id),
          padding: const EdgeInsets.only(bottom: Space.s),
          child: Opacity(
            opacity: action.enabled ? 1 : 0.45,
            child: OperatorCard(
              padding: const EdgeInsets.all(Space.m),
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => ActionEditorScreen(sceneId: widget.sceneId, action: action),
              )),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: OperatorPalette.line,
                    child: Text('${index + 1}',
                        style: const TextStyle(color: OperatorPalette.text, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(action.label,
                            style: const TextStyle(color: OperatorPalette.text, fontWeight: FontWeight.w700)),
                        Text(
                            '${offsetLabel(offsets[index])}  '
                            '${actionSummary(action, peerName: names[action.characterId] ?? data.defaultName)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (action.delayMs > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.s),
                      child: Text('+${secondsLabel(action.delayMs)}',
                          style: const TextStyle(color: OperatorPalette.standby, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
