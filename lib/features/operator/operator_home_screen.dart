import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/scene_engine.dart';
import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/device.dart';
import '../../data/repositories/scene_repository.dart';
import 'operator_theme.dart';
import '../../core/design/adaptive.dart';

class _HomeData {
  const _HomeData({required this.devices, required this.scenes});

  final List<Device> devices;
  final List<SceneListItem> scenes;
}

/// Операторская: телефон (точка зрения), список сцен, вход в панель.
class OperatorHomeScreen extends StatefulWidget {
  const OperatorHomeScreen({super.key});

  @override
  State<OperatorHomeScreen> createState() => _OperatorHomeScreenState();
}

class _OperatorHomeScreenState extends State<OperatorHomeScreen> {
  @override
  void initState() {
    super.initState();
    AppNavigator.operatorOpen = true;
  }

  @override
  void dispose() {
    AppNavigator.operatorOpen = false;
    super.dispose();
  }

  Future<void> _newScene(String deviceId, int count) async {
    final services = Services.read(context);
    final chats = await services.chats.listForDevice(deviceId);
    final id = await services.scenes.create(
      deviceId: deviceId,
      chatId: chats.isEmpty ? null : chats.first.chat.id,
      number: '${count + 1}',
      name: 'Новая сцена',
    );
    await AppNavigator.openSceneEditor(id);
  }

  Future<void> _pickDevice(List<Device> devices, String currentId) async {
    final services = Services.read(context);
    final choice = await showActionSheet<String>(
      context,
      header: const Text('Телефон в кадре', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: [
        for (final d in devices)
          SheetAction(value: d.id, icon: Icons.smartphone_rounded, label: d.name, selected: d.id == currentId),
        const SheetAction(value: '+', icon: Icons.add_rounded, label: 'Новый телефон'),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == '+') {
      await _newDevice();
    } else {
      await services.setCurrentDevice(choice);
    }
  }

  Future<void> _newDevice() async {
    final services = Services.read(context);
    final characters = await services.contacts.allCharacters();
    if (!mounted || characters.isEmpty) return;
    final ownerId = await showActionSheet<String>(
      context,
      header: const Text('Чей это телефон?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: [
        for (final c in characters)
          SheetAction(value: c.id, icon: Icons.person_rounded, label: c.fullName.isEmpty ? c.phone : c.fullName),
      ],
    );
    if (ownerId == null || !mounted) return;
    final owner = characters.firstWhere((c) => c.id == ownerId);
    final id = await services.devices.create(
      name: 'Телефон: ${owner.firstName.isEmpty ? owner.fullName : owner.firstName}',
      ownerCharacterId: ownerId,
    );
    await services.setCurrentDevice(id);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Theme(
      data: operatorTheme,
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: IconButton(
            tooltip: 'Вернуться в телефон',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text('Операторская', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        body: ContentWidth(maxWidth: 640, child: ValueListenableBuilder<String>(
          valueListenable: services.currentDeviceId,
          builder: (context, deviceId, _) => LiveQuery<_HomeData>(
            tables: const {
              Tables.scenes,
              Tables.sceneActions,
              Tables.devices,
              Tables.chats,
              Tables.deviceContacts,
              Tables.characters,
            },
            queryKey: deviceId,
            load: () async => _HomeData(
              devices: await services.devices.list(),
              scenes: await services.scenes.list(deviceId),
            ),
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null) {
                return snapshot.error != null
                    ? ErrorState(message: 'Не удалось открыть операторскую.', onRetry: snapshot.reload)
                    : const LoadingState();
              }
              final device = data.devices.where((d) => d.id == deviceId).firstOrNull;
              return ListView(
                padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxxl)),
                children: [
                  OperatorCard(
                    onTap: () => _pickDevice(data.devices, deviceId),
                    child: Row(
                      children: [
                        const Icon(Icons.smartphone_rounded, color: OperatorPalette.standby),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Телефон в кадре', style: TextStyle(color: OperatorPalette.textDim, fontSize: 12)),
                              Text(device?.name ?? '—',
                                  style: const TextStyle(color: OperatorPalette.text, fontSize: 17, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        const Text('Сменить', style: TextStyle(color: OperatorPalette.standby, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  ListenableBuilder(
                    listenable: services.engine,
                    builder: (context, _) {
                      final engine = services.engine;
                      final info = engine.info;
                      if (info == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: Space.m),
                        child: OperatorCard(
                          onTap: () => AppNavigator.openSceneChats(info.sceneId),
                          child: Row(
                            children: [
                              Icon(Icons.circle,
                                  size: 14,
                                  color: engine.isActive ? OperatorPalette.live : OperatorPalette.ready),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Text('${info.sceneTitle} — ${engine.status.label}',
                                    style: const TextStyle(color: OperatorPalette.text, fontWeight: FontWeight.w600)),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: Space.m),
                  ValueListenableBuilder(
                    valueListenable: services.kino,
                    builder: (context, kino, _) => OperatorCard(
                      onTap: AppNavigator.openKino,
                      child: Row(
                        children: [
                          Icon(Icons.movie_creation_outlined,
                              color: kino.enabled ? OperatorPalette.live : OperatorPalette.standby),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(kino.enabled ? 'КИНОРЕЖИМ ВКЛЮЧЁН' : 'Кинорежим',
                                    style: TextStyle(
                                      color: kino.enabled ? OperatorPalette.live : OperatorPalette.text,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    )),
                                const Text('Своя строка состояния, скрытые служебные пункты',
                                    style: TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.m),
                  ListenableBuilder(
                    listenable: services.connect,
                    builder: (context, _) => OperatorCard(
                      onTap: AppNavigator.openConnect,
                      child: Row(
                        children: [
                          Icon(Icons.settings_remote_outlined,
                              color: services.connect.enabled ? OperatorPalette.ready : OperatorPalette.standby),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Connect',
                                    style: TextStyle(color: OperatorPalette.text, fontSize: 17, fontWeight: FontWeight.w700)),
                                Text(
                                  services.connect.state.label,
                                  style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.m),
                  ListenableBuilder(
                    listenable: services.improv,
                    builder: (context, _) => OperatorCard(
                      onTap: AppNavigator.openImprov,
                      child: Row(
                        children: [
                          const Icon(Icons.keyboard_alt_outlined, color: OperatorPalette.standby),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Импровизация',
                                    style: TextStyle(color: OperatorPalette.text, fontSize: 17, fontWeight: FontWeight.w700)),
                                Text(
                                  services.improv.armed
                                      ? 'Очередь взведена: ${services.improv.queue.length} ответов'
                                      : 'Ответы вручную, заготовки, очередь для кадра',
                                  style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
                        ],
                      ),
                    ),
                  ),
                  const SectionLabel('Сцены'),
                  if (data.scenes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Space.l),
                      child: Text(
                        'Сцен пока нет. Создайте первую: выберите чат и соберите таймлайн '
                        'из действий — входящие, «печатает…», медиа, паузы.',
                        style: TextStyle(color: OperatorPalette.textDim),
                      ),
                    ),
                  for (final item in data.scenes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s),
                      child: _SceneCard(item: item),
                    ),
                  const SizedBox(height: Space.m),
                  PanelButton(
                    label: 'НОВАЯ СЦЕНА',
                    icon: Icons.add_rounded,
                    color: OperatorPalette.line,
                    height: 56,
                    onPressed: () => _newScene(deviceId, data.scenes.length),
                  ),
                  const SizedBox(height: Space.xl),
                  const _GestureHint(),
                ],
              );
            },
          ),
        )),
      ),
    );
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.item});

  final SceneListItem item;

  @override
  Widget build(BuildContext context) {
    final scene = item.scene;
    final title = scene.number.isEmpty ? scene.name : '${scene.number}. ${scene.name}';
    final details = [
      if (item.participantCount > 0)
        'участников: ${item.participantCount}'
      else
        'чат: ${item.chatName ?? 'не выбран'}',
      '${item.actionCount} ${_actionsWord(item.actionCount)}',
      if (scene.takeNumber > 0) 'дублей: ${scene.takeNumber}',
    ].join(' · ');
    return OperatorCard(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xs, Space.m),
      onTap: () => AppNavigator.openSceneEditor(scene.id),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: OperatorPalette.text, fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(details, style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Панель запуска',
            iconSize: 34,
            icon: const Icon(Icons.play_circle_fill_rounded, color: OperatorPalette.ready),
            onPressed: item.scene.chatId == null && item.participantCount == 0
                ? null
                : () => AppNavigator.openSceneChats(scene.id),
          ),
        ],
      ),
    );
  }
}

String _actionsWord(int n) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'действие';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'действия';
  return 'действий';
}

class _GestureHint extends StatelessWidget {
  const _GestureHint();

  @override
  Widget build(BuildContext context) {
    return const OperatorCard(
      child: Text(
        'Скрытые жесты в кадре:\n'
        '• касание двумя пальцами — «Далее» (когда дубль идёт);\n'
        '• три пальца, удерживать 1 секунду — операторская.\n'
        'Вход без жестов: удерживать заголовок «Чаты» 2 секунды.',
        style: TextStyle(color: OperatorPalette.textDim, height: 1.45),
      ),
    );
  }
}

/// Цвет статуса движка для панели.
Color engineStatusColor(EngineStatus status) => switch (status) {
      EngineStatus.running => OperatorPalette.live,
      EngineStatus.waiting || EngineStatus.paused => OperatorPalette.standby,
      EngineStatus.ready => OperatorPalette.ready,
      _ => OperatorPalette.textDim,
    };
