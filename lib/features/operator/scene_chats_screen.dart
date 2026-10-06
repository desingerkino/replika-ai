import 'package:flutter/material.dart';

import '../../app/navigator.dart';
import '../../app/scene_chat_view.dart';
import '../../app/scene_engine.dart';
import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/models/scene_action.dart';
import '../chat/chat_screen.dart' show membersLabel;
import 'operator_theme.dart';

/// Выбор рабочего места в сцене: чат (его личный таймлайн) или общий
/// таймлайн. Одна сцена содержит несколько чатов, и у каждого свой
/// прогресс, который сохраняется при переходах между ними.
class SceneChatsScreen extends StatefulWidget {
  const SceneChatsScreen({super.key, required this.sceneId});

  final String sceneId;

  @override
  State<SceneChatsScreen> createState() => _SceneChatsScreenState();
}

class _SceneChatsScreenState extends State<SceneChatsScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    final engine = Services.read(context).engine;
    if (engine.info?.sceneId != widget.sceneId || engine.status == EngineStatus.idle) {
      _load(engine);
    }
  }

  Future<void> _load(SceneEngine engine) async {
    try {
      await engine.load(widget.sceneId);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// Группы сцены: те, к которым обращаются действия таймлайна.
  static List<String> groupIds(List<SceneAction> actions) {
    final ids = <String>[];
    for (final action in actions) {
      final id = action.params['groupId'] as String?;
      if (id != null && !ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final engine = Services.of(context).engine;
    return Theme(
      data: operatorTheme,
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: const BackIconButton(),
          title: const Text('Сцена', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Изменить сцену',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => AppNavigator.openSceneEditor(widget.sceneId),
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: engine,
          builder: (context, _) {
            if (_error != null) {
              return Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Center(
                  child: Text('Сцена не готова к запуску: $_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: OperatorPalette.text, fontSize: 16)),
                ),
              );
            }
            final info = engine.info;
            if (info == null || info.sceneId != widget.sceneId) {
              return const Center(child: CircularProgressIndicator());
            }
            return _content(context, engine, info);
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, SceneEngine engine, SceneRunInfo info) {
    final people = [for (final p in info.participants) if (p.characterId != info.ownerId) p];
    final groups = groupIds(engine.actions);
    final total = engine.actions.where((a) => !engineControlTypes.contains(a.type)).length;
    final done = engine.actions.where((a) => engine.isExecuted(a.id) && !engineControlTypes.contains(a.type)).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxxl),
      children: [
        Text(info.sceneTitle,
            style: const TextStyle(color: OperatorPalette.text, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: Space.xs),
        Text(engine.hasTake ? 'Дубль ${engine.takeNumber ?? ''} · ${engine.status.label}' : 'Дубль не начат',
            style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
        const SectionLabel('Чаты'),
        if (people.isEmpty && groups.isEmpty)
          const Text('В сцене нет чатов: добавьте участников в редакторе сцены.',
              style: TextStyle(color: OperatorPalette.textDim)),
        for (final p in people)
          _tile(
            leading: Avatar(name: p.name, size: 40, tone: p.avatarTone, imagePath: p.avatarPath),
            title: p.name,
            progress: engine.chatProgress(directChatKey(p.characterId)),
            onTap: () => AppNavigator.openScenePanel(widget.sceneId, chatKey: directChatKey(p.characterId)),
          ),
        for (final id in groups)
          _GroupTile(
            groupId: id,
            progress: engine.chatProgress(groupChatKey(id)),
            onTap: () => AppNavigator.openScenePanel(widget.sceneId, chatKey: groupChatKey(id)),
          ),
        const SectionLabel('Сценарий'),
        _tile(
          leading: const Icon(Icons.view_timeline_rounded, color: OperatorPalette.standby, size: 32),
          title: 'Общий таймлайн',
          progress: (done: done, total: total),
          onTap: () => AppNavigator.openScenePanel(widget.sceneId),
        ),
      ],
    );
  }

  Widget _tile({
    required Widget leading,
    required String title,
    required ({int done, int total}) progress,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: OperatorCard(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(width: 40, height: 40, child: Center(child: leading)),
            const SizedBox(width: Space.m),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: OperatorPalette.text, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            Text(progress.total == 0 ? 'нет событий' : '${progress.done} из ${progress.total}',
                style: TextStyle(
                  color: progress.total > 0 && progress.done == progress.total
                      ? OperatorPalette.ready
                      : OperatorPalette.textDim,
                  fontSize: 13,
                )),
            const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
          ],
        ),
      ),
    );
  }
}

/// «Беседа · 5 участников»: название и число участников из реального состава.
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.groupId, required this.progress, required this.onTap});

  final String groupId;
  final ({int done, int total}) progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final services = Services.read(context);
    return FutureBuilder<(String, int)>(
      future: () async {
        final header = await services.chats.header(groupId);
        final members = await services.chats.members(groupId);
        return (header?.peer.displayName ?? 'Беседа', members.length);
      }(),
      builder: (context, snapshot) {
        final (title, count) = snapshot.data ?? ('Беседа', 0);
        final label = snapshot.data == null ? title : '$title · ${membersLabel(count)}';
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: OperatorCard(
            onTap: onTap,
            child: Row(
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.groups_rounded, color: OperatorPalette.standby, size: 32),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: OperatorPalette.text, fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                Text(progress.total == 0 ? 'нет событий' : '${progress.done} из ${progress.total}',
                    style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
                const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
              ],
            ),
          ),
        );
      },
    );
  }
}
