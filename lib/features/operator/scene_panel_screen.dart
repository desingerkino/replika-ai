import 'dart:async';

import '../../data/db/tables.dart';

import '../../app/live_query.dart';

import 'package:flutter/material.dart';

import '../../app/navigator.dart';
import '../../app/scene_chat_view.dart';
import '../../app/scene_engine.dart';
import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/util/ids.dart';
import '../../data/models/media_item.dart';
import '../../data/models/scene_action.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../core/util/time_format.dart';
import '../../data/models/take.dart';
import 'action_summary.dart';
import 'operator_home_screen.dart';
import 'operator_theme.dart';
import '../../core/design/adaptive.dart';
import '../../core/util/platform_info.dart';

/// Панель оператора: запуск дубля, «Далее», пауза, сброс, отметки дублей.
///
/// С [chatKey] это личный таймлайн чата: его события и привязанные к нему
/// чужие; «ДАЛЕЕ» выполняет следующее событие этого чата. Без [chatKey] —
/// общий таймлайн сцены.
class ScenePanelScreen extends StatefulWidget {
  const ScenePanelScreen({super.key, required this.sceneId, this.chatKey});

  final String sceneId;
  final String? chatKey;

  @override
  State<ScenePanelScreen> createState() => _ScenePanelScreenState();
}

class _ScenePanelScreenState extends State<ScenePanelScreen> {
  Object? _error;
  bool _busy = false;

  /// Названия групповых бесед сцены (id чата → название) для подписей событий.
  final Map<String, String> _groupTitles = {};

  @override
  void initState() {
    super.initState();
    final engine = Services.read(context).engine;
    if (engine.info?.sceneId != widget.sceneId || engine.status == EngineStatus.idle) {
      _load(engine);
    } else {
      // Рабочий чат запоминается: «Далее» из кадра (жест, кнопки) идёт в его
      // личный таймлайн, пока оператор не выберет другой чат или общий.
      engine.setWorkChat(widget.chatKey);
      unawaited(_loadGroupTitles(engine));
    }
  }

  Future<void> _load(SceneEngine engine) async {
    try {
      await engine.load(widget.sceneId);
      engine.setWorkChat(widget.chatKey);
      await _loadGroupTitles(engine);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadGroupTitles(SceneEngine engine) async {
    final chats = Services.read(context).chats;
    final keys = <String>{
      for (final action in engine.actions)
        if (action.params['groupId'] is String) action.params['groupId'] as String,
      for (final key in [widget.chatKey]) if (key != null && isGroupKey(key)) chatKeyId(key),
    };
    for (final id in keys) {
      final header = await chats.header(id);
      if (header != null) _groupTitles[id] = header.peer.displayName;
    }
    if (mounted) setState(() {});
  }

  /// Название чата: имя контакта или название беседы.
  String _chatLabel(String key, SceneRunInfo info) =>
      isGroupKey(key) ? (_groupTitles[chatKeyId(key)] ?? 'Беседа') : info.nameOf(chatKeyId(key));

  /// Подпись события: какому чату оно принадлежит. В беседе — «Беседа · Сергей».
  /// В личном таймлайне своё событие без подписи, чужое — «↗ Красотка».
  String? _tag(SceneEngine engine, SceneRunInfo info, SceneAction action) {
    final key = engine.chatKeyOf(action);
    if (key == null) return null;
    final viewKey = widget.chatKey;
    if (isGroupKey(key)) {
      final who = action.characterId;
      final title = _chatLabel(key, info);
      final name = who == null ? null : (who == info.ownerId ? 'Я' : info.nameOf(who));
      final text = name == null ? title : '$title · $name';
      return viewKey != null && key != viewKey ? '↗ $text' : text;
    }
    if (viewKey == null) return _chatLabel(key, info);
    return key == viewKey ? null : '↗ ${_chatLabel(key, info)}';
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не выполнено: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset(SceneEngine engine) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Сбросить сцену?',
      message: 'Всё, что добавила и изменила сцена, будет отменено. '
          'Переписка вернётся к состоянию до дубля.',
      confirmLabel: 'Сбросить',
      destructive: true,
    );
    if (ok) {
      await _guard(engine.reset);
      await engine.reloadActions();
    }
  }

  Future<void> _stepMenu(SceneEngine engine, int index) async {
    if (!engine.hasTake) {
      _snack('Сначала нажмите СТАРТ');
      return;
    }
    if (engine.status == EngineStatus.running) {
      _snack(engine.manual ? 'Дождитесь окончания действия' : 'Сначала поставьте паузу');
      return;
    }
    if (widget.chatKey != null) {
      // Личный таймлайн: событие выполняется где бы оно ни стояло —
      // чужое остаётся событием своего чата.
      final action = engine.actions[index];
      if (engine.isExecuted(action.id)) {
        _snack('Это событие уже выполнено');
        return;
      }
      final choice = await showActionSheet<String>(
        context,
        header: Text('${index + 1}: ${action.label}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: const [
          SheetAction(value: 'now', icon: Icons.bolt_rounded, label: 'Выполнить это событие'),
        ],
      );
      if (choice == 'now') await _guard(() => engine.performAt(index));
      return;
    }
    final choice = await showActionSheet<String>(
      context,
      header: Text('Шаг ${index + 1}: ${engine.actions[index].label}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: const [
        SheetAction(value: 'jump', icon: Icons.low_priority_rounded, label: 'Перейти сюда'),
        SheetAction(value: 'now', icon: Icons.bolt_rounded, label: 'Выполнить сейчас (вне очереди)'),
      ],
    );
    if (choice == 'jump') await _guard(() => engine.jumpTo(index));
    if (choice == 'now') await _guard(() => engine.performNow(index));
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// «В кадр»: главный чат сцены или чат выбранного участника.
  Future<void> _toFrame(SceneEngine engine) async {
    final info = engine.info;
    if (info == null) return;
    var chatId = info.chatId;
    final who = engine.activeParticipantId;
    if (chatId == null && who != null) {
      chatId = await Services.read(context).chats.openOrCreateDirect(deviceId: info.deviceId, characterId: who);
    }
    if (chatId != null) AppNavigator.showInFrame(chatId);
  }

  // ---------- Ручные действия от имени участника ----------

  SceneAction _action(SceneEngine engine, ActionType type, [Map<String, Object?> params = const {}]) {
    final now = DateTime.now();
    return SceneAction(
      id: newId(),
      sceneId: widget.sceneId,
      position: 0,
      typeName: type.name,
      params: {
        if (participantActionTypes.contains(type)) 'characterId': engine.activeParticipantId,
        ...params,
      },
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _live(SceneEngine engine, SceneAction action) async {
    final services = Services.read(context);
    final recorded = await engine.performLive(action);
    if (recorded != null) await services.scenes.saveAction(recorded);
    if (!mounted) return;
    final last = engine.log.isEmpty ? '' : engine.log.first;
    if (last.contains('Ошибка')) _snack(last.substring(last.indexOf('Ошибка')));
  }

  Future<void> _liveMessage(SceneEngine engine) async {
    final result = await showModalBottomSheet<(String, int, bool)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OperatorPalette.background,
      builder: (_) => _LiveMessageSheet(name: engine.info?.nameOf(engine.activeParticipantId) ?? ''),
    );
    if (result == null) return;
    final (text, typingMs, fromOwner) = result;
    await _live(
      engine,
      _action(engine, fromOwner ? ActionType.showOutgoing : ActionType.showIncoming,
          {'text': text, 'typingMs': typingMs}),
    );
  }

  Future<void> _liveCall(SceneEngine engine) async {
    final type = await showActionSheet<ActionType>(
      context,
      header: Text('Звонок: ${engine.info?.nameOf(engine.activeParticipantId) ?? ''}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: const [
        SheetAction(value: ActionType.incomingAudioCall, icon: Icons.call_received_rounded, label: 'Входящий аудиозвонок'),
        SheetAction(value: ActionType.incomingVideoCall, icon: Icons.video_call_rounded, label: 'Входящий видеозвонок'),
        SheetAction(value: ActionType.outgoingAudioCall, icon: Icons.call_made_rounded, label: 'Исходящий аудиозвонок'),
        SheetAction(value: ActionType.outgoingVideoCall, icon: Icons.videocam_rounded, label: 'Исходящий видеозвонок'),
        SheetAction(value: ActionType.acceptCall, icon: Icons.call_rounded, label: 'Ответить'),
        SheetAction(value: ActionType.declineCall, icon: Icons.phone_disabled_rounded, label: 'Отклонить'),
        SheetAction(value: ActionType.endCall, icon: Icons.call_end_rounded, label: 'Завершить', destructive: true),
      ],
    );
    if (type != null) await _live(engine, _action(engine, type));
  }

  Future<void> _liveMore(SceneEngine engine) async {
    final choice = await showActionSheet<String>(
      context,
      header: Text(engine.info?.nameOf(engine.activeParticipantId) ?? '',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: const [
        SheetAction(value: 'typing', icon: Icons.more_horiz_rounded, label: '«Печатает…»'),
        SheetAction(value: 'read', icon: Icons.done_all_rounded, label: 'Прочитал сообщения владельца'),
        SheetAction(value: 'photo', icon: Icons.photo_rounded, label: 'Фото из медиатеки'),
        SheetAction(value: 'voice', icon: Icons.mic_rounded, label: 'Голосовое из медиатеки'),
        SheetAction(value: 'videoNote', icon: Icons.video_camera_front_rounded, label: 'Видеосообщение из медиатеки'),
        SheetAction(value: 'open', icon: Icons.chat_bubble_outline_rounded, label: 'Открыть его чат на телефоне'),
        SheetAction(value: 'event', icon: Icons.info_outline_rounded, label: 'Событие в чате'),
        SheetAction(value: 'notif', icon: Icons.notifications_outlined, label: 'Уведомление'),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'typing':
        await _live(engine, _action(engine, ActionType.startTyping, {'durationMs': 4000}));
      case 'read':
        await _live(engine, _action(engine, ActionType.setMessageState, {'target': 'lastOutgoing', 'state': 'read'}));
      case 'photo' || 'voice' || 'videoNote':
        final kinds = switch (choice) {
          'photo' => {MediaKind.photo},
          'voice' => {MediaKind.voice, MediaKind.audio},
          _ => {MediaKind.videoNote, MediaKind.video},
        };
        final media = await AppNavigator.pickFromLibrary(kinds);
        if (media == null) return;
        final type = switch (choice) {
          'photo' => ActionType.showPhoto,
          'voice' => ActionType.showVoice,
          _ => ActionType.showVideoNote,
        };
        await _live(engine, _action(engine, type, {
          'mediaId': media.id,
          'mediaName': media.originalName ?? media.kind.label,
          'typingMs': 1500,
        }));
      case 'open':
        await _live(engine, _action(engine, ActionType.openChat));
      case 'event' || 'notif':
        final text = await _askText(choice == 'event' ? 'Текст события' : 'Текст уведомления');
        if (text == null) return;
        await _live(engine, _action(engine, choice == 'event' ? ActionType.showEvent : ActionType.postNotification,
            {'text': text}));
    }
  }

  Future<String?> _askText(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, maxLines: 4, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    return result == null || result.isEmpty ? null : result;
  }

  @override
  Widget build(BuildContext context) {
    final engine = Services.of(context).engine;
    return Theme(
      data: operatorTheme,
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: const BackIconButton(),
          title: ListenableBuilder(
            listenable: engine,
            builder: (context, _) {
              final info = engine.info;
              final key = widget.chatKey;
              if (key == null || info == null) {
                return const Text('Панель сцены', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700));
              }
              return Text('ОПЕРАТОРСКИЙ РЕЖИМ · ${_chatLabel(key, info).toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3));
            },
          ),
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Сцена не готова к запуску: $_error',
                        textAlign: TextAlign.center, style: const TextStyle(color: OperatorPalette.text, fontSize: 16)),
                    const SizedBox(height: Space.l),
                    PanelButton(
                      label: 'ОТКРЫТЬ РЕДАКТОР',
                      color: OperatorPalette.line,
                      height: 56,
                      onPressed: () => AppNavigator.openSceneEditor(widget.sceneId),
                    ),
                  ],
                ),
              );
            }
            final info = engine.info;
            if (info == null || engine.info?.sceneId != widget.sceneId) {
              return const Center(child: CircularProgressIndicator());
            }
            return LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= wideBreakpoint
                  ? _buildPanel(engine, info, wide: true)
                  : ContentWidth(maxWidth: 640, child: _buildPanel(engine, info, wide: false)),
            );
          },
        ),
      ),
    );
  }

  /// Плитка 2×2: ПРЕДЫДУЩЕЕ, ДАЛЕЕ, СТОП, СБРОС СЦЕНЫ. «Предыдущее», «Далее» и
  /// «Стоп» идут через общий слой команд (как жест, клавиатура и Prop
  /// Controller); сброс — с подтверждением, как на узком экране. Запуск дубля
  /// и пауза остаются на большой кнопке выше: у неё свои состояния.
  Widget _operatorPad(SceneEngine engine, bool active) {
    final input = Services.read(context).appInput;
    Widget cell(String label, IconData icon, Color color, VoidCallback? onTap, {Color? foreground}) => Expanded(
          child: PanelButton(
            label: label,
            icon: icon,
            color: color,
            foreground: foreground ?? Colors.white,
            height: 96,
            onPressed: onTap,
          ),
        );
    final canStep = engine.hasTake && !_busy;
    return Column(
      children: [
        Row(
          children: [
            cell('ПРЕДЫДУЩЕЕ', Icons.skip_previous_rounded, OperatorPalette.line, canStep ? input.previous : null),
            const SizedBox(width: Space.m),
            cell('ДАЛЕЕ', Icons.skip_next_rounded, OperatorPalette.standby, canStep ? input.next : null,
                foreground: OperatorPalette.background),
          ],
        ),
        const SizedBox(height: Space.m),
        Row(
          children: [
            cell('СТОП', Icons.stop_rounded, OperatorPalette.line, active && !_busy ? input.stop : null),
            const SizedBox(width: Space.m),
            cell('СБРОС СЦЕНЫ', Icons.restart_alt_rounded, OperatorPalette.live, _busy ? null : () => _reset(engine)),
          ],
        ),
      ],
    );
  }

  Widget _buildPanel(SceneEngine engine, SceneRunInfo info, {required bool wide}) {
    final status = engine.status;
    final active = engine.isActive;

    final (String primaryLabel, IconData primaryIcon, Color primaryColor, VoidCallback? primaryAction) =
        switch (status) {
      EngineStatus.ready || EngineStatus.finished || EngineStatus.idle =>
        ('СТАРТ', Icons.play_arrow_rounded, OperatorPalette.ready, () => _guard(engine.start)),
      EngineStatus.waiting => (
          'ДАЛЕЕ',
          Icons.skip_next_rounded,
          OperatorPalette.standby,
          () => _guard(widget.chatKey == null ? engine.next : () => engine.nextInChat(widget.chatKey!)),
        ),
      EngineStatus.paused => ('ПРОДОЛЖИТЬ', Icons.play_arrow_rounded, OperatorPalette.standby, engine.resume),
      EngineStatus.running => engine.manual
          ? ('ВЫПОЛНЯЕТСЯ…', Icons.hourglass_top_rounded, OperatorPalette.line, null)
          : ('ПАУЗА', Icons.pause_rounded, OperatorPalette.standby, engine.pause),
    };

    final padding = listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxxl));
    final controls = <Widget>[
        Text(info.sceneTitle,
            style: const TextStyle(color: OperatorPalette.text, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(
          'Участников: ${info.participants.length}${engine.takeNumber == null ? '' : ' · дубль ${engine.takeNumber}'}'
          '${info.clockStart == null ? '' : ' · время в кадре ${formatClock(engine.sceneNow() ?? info.clockStart!)}'}',
          style: const TextStyle(color: OperatorPalette.textDim),
        ),
        const SizedBox(height: Space.l),
        Row(
          children: [
            Icon(Icons.circle, size: 16, color: engineStatusColor(status)),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(status.label.toUpperCase(),
                  style: TextStyle(
                    color: engineStatusColor(status),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  )),
            ),
          ],
        ),
        const SizedBox(height: Space.m),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Ручной')),
                ButtonSegment(value: false, label: Text('Авто')),
              ],
              selected: {engine.manual},
              showSelectedIcon: false,
              onSelectionChanged: active ? null : (value) => engine.setManual(value.first),
            ),
        ),
        const SizedBox(height: Space.s),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('🎭 Репетиция')),
              ButtonSegment(value: false, label: Text('🎬 Дубль')),
            ],
            selected: {engine.rehearsal},
            showSelectedIcon: false,
            onSelectionChanged: engine.hasTake ? null : (value) => engine.setRehearsal(value.first),
          ),
        ),
        if (engine.rehearsal)
          const Padding(
            padding: EdgeInsets.only(top: Space.xs),
            child: Text('Репетиция: по окончании все изменения откатятся, профили не изменятся.',
                style: TextStyle(color: OperatorPalette.standby, fontSize: 13)),
          ),
        if (!engine.manual) ...[
          const SizedBox(height: Space.m),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Скорость:', style: TextStyle(color: OperatorPalette.textDim)),
              for (final (value, label) in const [(0.5, '0,5×'), (1.0, '1×'), (1.5, '1,5×'), (2.0, '2×')])
                ChoiceChip(
                  label: Text(label),
                  selected: engine.speed == value,
                  onSelected: (_) => engine.setSpeed(value),
                ),
            ],
          ),
        ],
        if (!engine.manual && engine.remainingMs > 0 && status == EngineStatus.running) ...[
          const SizedBox(height: Space.s),
          Text(
            'Следующее действие через ${secondsLabel(engine.remainingMs)}',
            style: const TextStyle(color: OperatorPalette.standby, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: Space.l),
        PanelButton(
          label: primaryLabel,
          icon: primaryIcon,
          color: primaryColor,
          foreground: OperatorPalette.background,
          height: 88,
          onPressed: _busy ? null : primaryAction,
        ),
        if (status == EngineStatus.finished) ...[
          const SizedBox(height: Space.s),
          PanelButton(
            label: '🔄 ПОВТОРИТЬ СЦЕНУ',
            color: OperatorPalette.line,
            height: 56,
            onPressed: _busy ? null : () => _guard(engine.repeat),
          ),
        ],
        const SizedBox(height: Space.m),
        if (wide) ...[
          // Широкий экран (iPad): плитка 2×2 — все четыре команды оператора.
          _operatorPad(engine, active),
          const SizedBox(height: Space.m),
          PanelButton(
            label: 'В КАДР',
            icon: Icons.smartphone_rounded,
            color: OperatorPalette.line,
            height: 64,
            onPressed: () => unawaited(_toFrame(engine)),
          ),
        ] else ...[
        // «Назад» идёт через слой команд оператора — так же, как жест, клавиатура
        // и Prop Controller; на iOS других кнопок «Назад» у оператора нет.
        PanelButton(
          label: 'НАЗАД',
          icon: Icons.skip_previous_rounded,
          color: OperatorPalette.line,
          height: 64,
          onPressed: engine.hasTake && !_busy ? Services.read(context).appInput.previous : null,
        ),
        const SizedBox(height: Space.m),
        Row(
          children: [
            Expanded(
              child: PanelButton(
                label: 'В КАДР',
                icon: Icons.smartphone_rounded,
                color: OperatorPalette.line,
                height: 64,
                onPressed: () => unawaited(_toFrame(engine)),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: PanelButton(
                label: 'СТОП',
                icon: Icons.stop_rounded,
                color: OperatorPalette.line,
                height: 64,
                onPressed: active && !_busy ? () => _guard(engine.stop) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.m),
        PanelButton(
          label: 'СБРОС СЦЕНЫ',
          icon: Icons.restart_alt_rounded,
          color: OperatorPalette.live,
          height: 64,
          onPressed: _busy ? null : () => _reset(engine),
        ),
        ],
        if (status == EngineStatus.finished) ...[
          const SizedBox(height: Space.m),
          Row(
            children: [
              Expanded(
                child: PanelButton(
                  label: 'ХОРОШИЙ',
                  icon: Icons.thumb_up_alt_rounded,
                  color: OperatorPalette.ready,
                  foreground: OperatorPalette.background,
                  height: 56,
                  onPressed: () => _guard(() => engine.markTake(TakeStatus.good)),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: PanelButton(
                  label: 'БРАК',
                  icon: Icons.thumb_down_alt_rounded,
                  color: OperatorPalette.line,
                  height: 56,
                  onPressed: () => _guard(() => engine.markTake(TakeStatus.bad)),
                ),
              ),
            ],
          ),
        ],
        const _ProfileContext(),
        _LiveControls(
          engine: engine,
          info: info,
          onMessage: () => _liveMessage(engine),
          onCall: () => _liveCall(engine),
          onDelete: () => _live(engine, _action(engine, ActionType.deleteMessage, {'target': 'lastIncoming'})),
          onRead: () => _live(
              engine, _action(engine, ActionType.setMessageState, {'target': 'lastOutgoing', 'state': 'read'})),
          onMore: () => _liveMore(engine),
        ),
        _TakeHistory(sceneId: widget.sceneId),
    ];
    final chatKey = widget.chatKey;
    final view = chatKey == null ? List<int>.generate(engine.actions.length, (i) => i) : engine.chatView(chatKey);
    final nextInView = chatKey == null ? null : engine.nextIndexInChat(chatKey);
    final offsets = timelineOffsets(engine.actions);
    final progress = chatKey == null ? null : engine.chatProgress(chatKey);
    final timeline = <Widget>[
        SectionLabel(chatKey == null
            ? 'Таймлайн'
            : 'Таймлайн · ${_chatLabel(chatKey, info)} · ${progress!.done} из ${progress.total}'),
        if (view.isEmpty)
          Text(
            chatKey == null
                ? 'В сцене нет включённых действий.'
                : 'В этом чате нет событий. Чужое событие можно показать здесь: в редакторе действия '
                    'выберите «Показывать также в чатах».',
            style: const TextStyle(color: OperatorPalette.textDim),
          ),
        for (final i in view)
          _TimelineRow(
            onTap: () => _stepMenu(engine, i),
            index: i,
            label: engine.actions[i].label,
            tag: _tag(engine, info, engine.actions[i]),
            summary: '${offsetLabel(offsets[i])}  '
                '${actionSummary(engine.actions[i], peerName: info.nameOf(engine.actions[i].characterId))}',
            state: chatKey == null
                ? (engine.isExecuted(engine.actions[i].id) || i < engine.index
                    ? _RowState.done
                    : (i == engine.index && active ? _RowState.current : _RowState.upcoming))
                : (engine.isExecuted(engine.actions[i].id)
                    ? _RowState.done
                    : (i == nextInView && active ? _RowState.current : _RowState.upcoming)),
          ),
        const SectionLabel('Журнал'),
        if (engine.log.isEmpty)
          const Text('Пока пусто.', style: TextStyle(color: OperatorPalette.textDim)),
        for (final line in engine.log.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
          ),
        const SizedBox(height: Space.l),
        Text(
          isIOS
              ? 'Шаг таймлайна: нажмите, чтобы перейти к нему или выполнить вне очереди. '
                  'В кадре: касание двумя пальцами — «Далее», свайп двумя пальцами вверх — «Назад»; '
                  'внешняя клавиатура: стрелки — '
                  '«Далее» и «Назад», пробел — «Стоп», удержание Esc — сброс; '
                  'три пальца на 1 секунду — вернуться сюда.'
              : 'Шаг таймлайна: нажмите, чтобы перейти к нему или выполнить вне очереди. '
                  'В кадре: громкость вверх — «Далее», вниз — «Назад», обе 1,2 с — сброс; '
                  'касание двумя пальцами — «Далее», свайп двумя пальцами вверх — «Назад»; '
                  'три пальца на 1 секунду — вернуться сюда.',
          style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13),
        ),
    ];
    if (wide) {
      // Широкий экран: слева управление, справа таймлайн и журнал.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: ListView(padding: padding, children: controls)),
          const VerticalDivider(width: 1, thickness: 0.6, color: OperatorPalette.line),
          Expanded(flex: 6, child: ListView(padding: padding, children: timeline)),
        ],
      );
    }
    return ListView(padding: padding, children: [...controls, ...timeline]);
  }
}

enum _RowState { done, current, upcoming }

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.index,
    required this.label,
    required this.summary,
    required this.state,
    required this.onTap,
    this.tag,
  });

  final VoidCallback onTap;
  final int index;
  final String label;
  final String summary;

  /// Какому чату принадлежит событие («Красотка», «Беседа · Сергей»).
  final String? tag;
  final _RowState state;

  @override
  Widget build(BuildContext context) {
    final current = state == _RowState.current;
    final done = state == _RowState.done;
    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: Space.xs),
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
      decoration: BoxDecoration(
        color: current ? OperatorPalette.standby.withValues(alpha: 0.16) : OperatorPalette.surface,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: current ? OperatorPalette.standby : Colors.transparent),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: done
                ? const Icon(Icons.check_rounded, size: 18, color: OperatorPalette.ready)
                : Text('${index + 1}',
                    style: TextStyle(
                      color: current ? OperatorPalette.standby : OperatorPalette.textDim,
                      fontWeight: FontWeight.w700,
                    )),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tag != null)
                  Text(tag!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OperatorPalette.standby,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      )),
                Text(label,
                    style: TextStyle(
                      color: done ? OperatorPalette.textDim : OperatorPalette.text,
                      fontWeight: FontWeight.w600,
                    )),
                Text(summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: OperatorPalette.textDim, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

/// Участники сцены и ручные действия от имени выбранного.
class _LiveControls extends StatelessWidget {
  const _LiveControls({
    required this.engine,
    required this.info,
    required this.onMessage,
    required this.onCall,
    required this.onDelete,
    required this.onMore,
    required this.onRead,
  });

  final SceneEngine engine;
  final SceneRunInfo info;
  final VoidCallback onMessage;
  final VoidCallback onCall;
  final VoidCallback onDelete;
  final VoidCallback onMore;

  /// «Прочитать»: участник прочитал сообщения владельца телефона.
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final active = engine.activeParticipantId;
    Widget button(String label, IconData icon, VoidCallback? onTap) => Expanded(
          child: PanelButton(label: label, icon: icon, color: OperatorPalette.line, height: 52, onPressed: onTap),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Участники — действия от их имени'),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final p in info.participants)
              ChoiceChip(
                avatar: Avatar(name: p.name, size: 22, tone: p.avatarTone, imagePath: p.avatarPath),
                label: Text(p.name),
                selected: p.characterId == active,
                onSelected: (_) => engine.selectParticipant(p.characterId),
              ),
          ],
        ),
        const SizedBox(height: Space.s),
        Text(
          'От имени: ${info.nameOf(active)}. Переключение участника не прерывает сцену — '
          'каждое действие уходит в чат выбранного, его переписка сохраняется.',
          style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13),
        ),
        const SizedBox(height: Space.m),
        Row(children: [
          button('Сообщение', Icons.chat_rounded, onMessage),
          const SizedBox(width: Space.s),
          button('Звонок', Icons.call_rounded, onCall),
        ]),
        const SizedBox(height: Space.s),
        Row(children: [
          button('Удалить', Icons.delete_outline_rounded, onDelete),
          const SizedBox(width: Space.s),
          button('👁 Прочитать', Icons.done_all_rounded, onRead),
        ]),
        const SizedBox(height: Space.s),
        Row(children: [
          button('↩ Отменить', Icons.undo_rounded, engine.hasTake ? () => engine.back() : null),
          const SizedBox(width: Space.s),
          button('↪ Повторить', Icons.redo_rounded, engine.canRedo ? () => engine.redo() : null),
          const SizedBox(width: Space.s),
          button('Ещё', Icons.more_horiz_rounded, onMore),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: engine.recordLive,
          onChanged: engine.setRecordLive,
          title: const Text('Записывать в таймлайн', style: TextStyle(color: OperatorPalette.text)),
          subtitle: const Text(
            'Ручные действия дописываются в конец таймлайна с паузами, как вы их делали, — '
            'сцену можно отрепетировать вживую, а снимать в автоматическом режиме.',
            style: TextStyle(color: OperatorPalette.textDim),
          ),
        ),
      ],
    );
  }
}

/// Лист «Сообщение от участника»: текст, «печатает…», от кого.
class _LiveMessageSheet extends StatefulWidget {
  const _LiveMessageSheet({required this.name});

  final String name;

  @override
  State<_LiveMessageSheet> createState() => _LiveMessageSheetState();
}

class _LiveMessageSheetState extends State<_LiveMessageSheet> {
  final TextEditingController _text = TextEditingController();
  int _typingMs = 2000;
  bool _fromOwner = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: operatorTheme,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            Space.l, Space.l, Space.l, Space.l + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_fromOwner ? 'Вы → ${widget.name}' : '${widget.name} пишет',
                style: const TextStyle(color: OperatorPalette.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: Space.m),
            ReplikaTextField(controller: _text, label: 'Текст сообщения', maxLines: 5),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                ChoiceChip(
                  label: Text('От ${widget.name}'),
                  selected: !_fromOwner,
                  onSelected: (_) => setState(() => _fromOwner = false),
                ),
                ChoiceChip(
                  label: const Text('От владельца телефона'),
                  selected: _fromOwner,
                  onSelected: (_) => setState(() => _fromOwner = true),
                ),
              ],
            ),
            if (!_fromOwner) ...[
              const SizedBox(height: Space.s),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('«Печатает…»:', style: TextStyle(color: OperatorPalette.textDim)),
                  for (final ms in const [0, 1000, 2000, 3000])
                    ChoiceChip(
                      label: Text(ms == 0 ? 'нет' : secondsLabel(ms)),
                      selected: _typingMs == ms,
                      onSelected: (_) => setState(() => _typingMs = ms),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Space.l),
            PanelButton(
              label: 'ОТПРАВИТЬ',
              icon: Icons.send_rounded,
              color: OperatorPalette.ready,
              foreground: OperatorPalette.background,
              height: 56,
              onPressed: () {
                final text = _text.text.trim();
                if (text.isEmpty) return;
                Navigator.of(context).pop((text, _fromOwner ? 0 : _typingMs, _fromOwner));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// История дублей и репетиций сцены: каждый прогон сохраняется.
class _TakeHistory extends StatelessWidget {
  const _TakeHistory({required this.sceneId});

  final String sceneId;

  static String _mode(Take t) {
    final raw = t.logJson;
    if (raw == null) return 'Дубль';
    return raw.contains('"mode":"rehearsal"') ? 'Репетиция' : 'Дубль';
  }

  static String _status(TakeStatus s) => switch (s) {
        TakeStatus.running => 'идёт',
        TakeStatus.finished => 'завершён',
        TakeStatus.aborted => 'остановлен',
        TakeStatus.good => 'хороший',
        TakeStatus.bad => 'брак',
      };

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return LiveQuery<List<Take>>(
      tables: const {Tables.takes},
      queryKey: sceneId,
      load: () => services.scenes.takes(sceneId),
      builder: (context, snapshot) {
        final takes = snapshot.data ?? const <Take>[];
        if (takes.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel('История прогонов (${takes.length})'),
            for (final t in takes.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Text(
                  '№${t.number} · ${_mode(t)} · ${_status(t.status)} · ${formatClock(t.startedAt)}',
                  style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Контекст перед действием: какой профиль сейчас на экране телефона.
class _ProfileContext extends StatelessWidget {
  const _ProfileContext();

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ValueListenableBuilder<String>(
      valueListenable: services.currentDeviceId,
      builder: (context, currentId, _) => LiveQuery<String>(
        tables: const {Tables.devices, Tables.characters},
        queryKey: currentId,
        load: () async =>
            (await services.devices.profiles()).where((p) => p.device.id == currentId).firstOrNull?.ownerName ?? '—',
        builder: (context, snapshot) => Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: OperatorCard(
            onTap: AppNavigator.openProfiles,
            child: Row(
              children: [
                const Icon(Icons.phone_android_rounded, color: OperatorPalette.standby),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text('ПРОФИЛЬ НА ЭКРАНЕ: 📱 ${snapshot.data ?? '…'}',
                      style: const TextStyle(color: OperatorPalette.text, fontWeight: FontWeight.w700)),
                ),
                const Text('сменить', style: TextStyle(color: OperatorPalette.textDim)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
