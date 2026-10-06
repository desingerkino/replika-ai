import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/navigator.dart';
import '../../app/scene_chat_view.dart';
import '../../app/scene_engine.dart' show engineControlTypes;
import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../core/util/ids.dart';
import '../../data/models/media_item.dart';
import '../../data/models/message.dart';
import '../../data/models/scene_action.dart';
import '../../data/repositories/scene_repository.dart';
import 'action_summary.dart';
import 'operator_theme.dart';

/// Выбор типа действия: по группам ТЗ, недоступные — с пояснением.
Future<ActionType?> pickActionType(BuildContext context) {
  return showModalBottomSheet<ActionType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: OperatorPalette.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
    ),
    builder: (sheetContext) => SizedBox(
      height: math.min(MediaQuery.sizeOf(sheetContext).height * 0.8, 720),
      child: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          for (final group in ActionGroup.values) ...[
            SectionLabel(group.label),
            for (final type in ActionType.values.where((t) => t.group == group))
              _TypeRow(type: type, onTap: () => Navigator.of(sheetContext).pop(type)),
          ],
        ],
      ),
    ),
  );
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.onTap});

  final ActionType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reason = unavailableReason(type);
    return InkWell(
      onTap: reason == null ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l + 4, vertical: Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type.label,
                style: TextStyle(
                  color: reason == null ? OperatorPalette.text : OperatorPalette.textDim,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                )),
            if (reason != null)
              Text(reason, style: const TextStyle(color: OperatorPalette.textDim, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Редактор одного действия таймлайна.
class ActionEditorScreen extends StatefulWidget {
  const ActionEditorScreen({
    super.key,
    required this.sceneId,
    this.action,
    this.type,
    this.defaultCharacterId,
  }) : assert(action != null || type != null);

  final String sceneId;
  final SceneAction? action;
  final ActionType? type;

  /// Участник для нового действия (выбранный на панели).
  final String? defaultCharacterId;

  @override
  State<ActionEditorScreen> createState() => _ActionEditorScreenState();
}

class _ActionEditorScreenState extends State<ActionEditorScreen> {
  late final ActionType? _type = widget.action?.type ?? widget.type;
  late final Map<String, Object?> _params = {...?widget.action?.params};
  late final TextEditingController _text = TextEditingController(text: _str('text'));
  late final TextEditingController _caption = TextEditingController(text: _str('caption'));
  late final TextEditingController _title = TextEditingController(text: _str('title'));
  late final TextEditingController _time = TextEditingController(text: _str('time'));
  late final TextEditingController _note = TextEditingController(text: widget.action?.note ?? '');
  late final TextEditingController _delay = _seconds(widget.action?.delayMs ?? 0);
  late final TextEditingController _typing = _seconds(_ms('typingMs', 0));
  late final TextEditingController _duration = _seconds(_ms('durationMs', 4000));
  late final TextEditingController _wait = _seconds(_ms('ms', 1000));
  late final TextEditingController _deliver = _seconds(_ms('deliverMs', 1200));
  late final TextEditingController _read = _seconds(_ms('readMs', 2500));
  late bool _enabled = widget.action?.enabled ?? true;

  /// Участники сцены и выбранный для действия.
  List<SceneParticipantRow> _participants = const [];
  String? _characterId;

  /// «Прочитано» у исходящего: ON — сразу прочитано, OFF — непрочитано, пока
  /// контакт не ответит именно на это сообщение. Для старых действий без
  /// настройки берётся то, что они делали (по статусу).
  late bool _readOn = _initialRead();

  bool _initialRead() {
    final params = widget.action?.params ?? const <String, Object?>{};
    final flag = params['read'];
    if (flag is bool) return flag;
    if (widget.action?.type == ActionType.sendMessage) {
      final ms = params['readMs'];
      return ms is num && ms > 0;
    }
    final state = params['state'];
    return state == null || state == MessageState.read.name;
  }

  /// Входящее — ответ на это исходящее событие сцены (replyToActionId).
  late String? _replyTo = widget.action?.params['replyToActionId'] as String?;
  List<({String id, String label, String? who})> _replyOptions = const [];

  static const Set<ActionType> _mediaMessageTypes = {
    ActionType.showPhoto,
    ActionType.showVideo,
    ActionType.showVoice,
    ActionType.showVideoNote,
  };

  bool _isOutgoingMessage(ActionType? type, Map<String, Object?> params) =>
      type == ActionType.showOutgoing ||
      type == ActionType.sendMessage ||
      (_mediaMessageTypes.contains(type) && params['direction'] == 'out');

  bool _isIncomingMessage(ActionType? type, Map<String, Object?> params) =>
      type == ActionType.showIncoming || (_mediaMessageTypes.contains(type) && params['direction'] != 'out');

  /// Переключатель «Прочитано: ON / OFF» для исходящего сообщения.
  List<Widget> _readSwitch() => [
        const SizedBox(height: Space.m),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _readOn,
          onChanged: (v) => setState(() => _readOn = v),
          title: Text('Прочитано: ${_readOn ? 'ON' : 'OFF'}',
              style: const TextStyle(color: OperatorPalette.text)),
          subtitle: Text(
            _readOn
                ? 'Сразу после выполнения сообщение считается прочитанным.'
                : 'Остаётся непрочитанным, пока контакт не ответит именно на это сообщение: '
                    'в его событии «Входящее» выберите «Ответ на».',
            style: const TextStyle(color: OperatorPalette.textDim),
          ),
        ),
      ];

  /// «Ответ на»: связь входящего с исходящим сообщением (reply_to_id).
  /// Когда входящее выполнено, то исходящее становится прочитанным.
  List<Widget> _replySection() {
    final options = [for (final o in _replyOptions) if (o.who == _characterId) o];
    return [
      const SizedBox(height: Space.m),
      const Text('Ответ на сообщение', style: TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
      const SizedBox(height: Space.xs),
      if (options.isEmpty)
        const Text('Нет исходящих сообщений этого участника выше по таймлайну.',
            style: TextStyle(color: OperatorPalette.textDim))
      else
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            ChoiceChip(
              label: const Text('Не ответ'),
              selected: _replyTo == null,
              onSelected: (_) => setState(() => _replyTo = null),
            ),
            for (final o in options)
              ChoiceChip(
                label: Text(o.label),
                selected: _replyTo == o.id,
                onSelected: (_) => setState(() => _replyTo = o.id),
              ),
          ],
        ),
      const SizedBox(height: Space.xs),
      const Text(
        'Входящее станет ответом (цитатой) на выбранное сообщение, и оно будет прочитано.',
        style: TextStyle(color: OperatorPalette.textDim, fontSize: 12),
      ),
    ];
  }

  /// Чаты, в личных таймлайнах которых показывать событие (кроме своего).
  /// Событие остаётся одним: оно по-прежнему принадлежит своему чату.
  List<({String key, String label})> _alsoOptions = const [];
  late final Set<String> _alsoIn = {...sceneAlsoIn(widget.action ?? _blankAction)};

  static final SceneAction _blankAction = SceneAction(
    id: '',
    sceneId: '',
    position: 0,
    typeName: '',
    createdAt: DateTime(2000),
    updatedAt: DateTime(2000),
  );

  @override
  void initState() {
    super.initState();
    _characterId = widget.action?.characterId ?? widget.defaultCharacterId;
    _loadParticipants();
    _loadPeopleAndEvents();
  }

  Future<void> _loadParticipants() async {
    final services = Services.read(context);
    final scene = await services.scenes.byId(widget.sceneId);
    if (scene == null) return;
    final list = await services.scenes.participants(
      widget.sceneId,
      scene.deviceId ?? services.currentDeviceId.value,
    );
    final deviceId = scene.deviceId ?? services.currentDeviceId.value;
    final chats = await services.chats.listForDevice(deviceId);
    if (!mounted) return;
    setState(() {
      _participants = list;
      final ids = list.map((p) => p.characterId);
      if (_characterId == null || !ids.contains(_characterId)) {
        _characterId = list.isEmpty ? null : list.first.characterId;
      }
      _alsoOptions = [
        for (final p in list) (key: directChatKey(p.characterId), label: p.name),
        for (final item in chats)
          if (item.chat.isGroup) (key: groupChatKey(item.chat.id), label: item.displayName),
      ];
    });
  }

  bool get _needsParticipant =>
      participantActionTypes.contains(_type) && _params['refActionId'] == null;

  /// Персонажи проекта (для «кто → кому»); 📱 — есть профиль-телефон.
  List<({String id, String name, bool phone})> _people = const [];

  /// Предыдущие события сцены «сообщение / звонок» — к ним можно привязать
  /// статус, удаление, правку, ответ и завершение звонка.
  List<({String id, String label, ActionType type})> _events = const [];

  static const Set<ActionType> _messageRefTypes = {
    ActionType.setMessageState,
    ActionType.deleteMessage,
    ActionType.editMessage,
  };
  static const Set<ActionType> _callRefTypes = {
    ActionType.acceptCall,
    ActionType.declineCall,
    ActionType.endCall,
  };

  Future<void> _loadPeopleAndEvents() async {
    final services = Services.read(context);
    final owners = {for (final d in await services.devices.list()) d.ownerCharacterId};
    final people = [
      for (final c in await services.contacts.allCharacters())
        (id: c.id, name: c.fullName.isEmpty ? (c.phone.isEmpty ? 'Без имени' : c.phone) : c.fullName, phone: owners.contains(c.id)),
    ]..sort((a, b) => (b.phone ? 1 : 0) - (a.phone ? 1 : 0));
    final actions = await services.scenes.actions(widget.sceneId);
    final myPosition = widget.action?.position ?? 1 << 30;
    final events = [
      for (final (i, a) in actions.indexed)
        if (a.position < myPosition && (a.type == ActionType.message || a.type == ActionType.call))
          (id: a.id, label: '№${i + 1}', type: a.type!),
    ];
    String preview(SceneAction a) {
      final raw = ((a.params['text'] ?? a.params['caption']) as String?)?.trim() ?? '';
      final text = raw.isEmpty ? a.label : raw;
      return text.length > 28 ? '${text.substring(0, 28)}…' : text;
    }

    final replyOptions = [
      for (final (i, a) in actions.indexed)
        if (a.position < myPosition && _isOutgoingMessage(a.type, a.params))
          (id: a.id, label: '№${i + 1}: ${preview(a)}', who: a.characterId),
    ];
    if (!mounted) return;
    setState(() {
      _people = people;
      _events = events;
      _replyOptions = replyOptions;
    });
  }

  Widget _personChips(String title, String key) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final p in _people)
                ChoiceChip(
                  label: Text('${p.phone ? '📱 ' : ''}${p.name}'),
                  selected: _params[key] == p.id,
                  onSelected: (_) => setState(() {
                    _params[key] = p.id;
                    _params['${key}Name'] = p.name;
                  }),
                ),
            ],
          ),
        ],
      );

  /// Выбор события, к которому относится действие.
  List<Widget> _refChips() {
    final type = _type;
    final wanted = _messageRefTypes.contains(type)
        ? ActionType.message
        : (_callRefTypes.contains(type) ? ActionType.call : null);
    if (wanted == null) return const [];
    final events = _events.where((e) => e.type == wanted).toList();
    if (events.isEmpty) return const [];
    return [
      Text(wanted == ActionType.message ? 'Какое сообщение' : 'Какой звонок',
          style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
      const SizedBox(height: Space.xs),
      Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          ChoiceChip(
            label: Text(wanted == ActionType.message ? 'последнее в чате участника' : 'текущий звонок'),
            selected: _params['refActionId'] == null,
            onSelected: (_) => setState(() {
              _params.remove('refActionId');
              _params.remove('refLabel');
            }),
          ),
          for (final e in events)
            ChoiceChip(
              label: Text('событие ${e.label}'),
              selected: _params['refActionId'] == e.id,
              onSelected: (_) => setState(() {
                _params['refActionId'] = e.id;
                _params['refLabel'] = e.label;
              }),
            ),
        ],
      ),
      const SizedBox(height: Space.l),
    ];
  }

  String _str(String key) => (widget.action?.params[key] as String?) ?? '';
  int _ms(String key, int fallback) => (widget.action?.params[key] as num?)?.toInt() ?? fallback;

  static TextEditingController _seconds(int ms) {
    final s = ms / 1000;
    final text = s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
    return TextEditingController(text: text.replaceAll('.', ','));
  }

  static int _parseMs(TextEditingController c) {
    final value = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (value == null || value < 0) return 0;
    return (value * 1000).round();
  }

  @override
  void dispose() {
    for (final c in [_text, _caption, _title, _time, _note, _delay, _typing, _duration, _wait, _deliver, _read]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isMedia => const {
        ActionType.showPhoto,
        ActionType.showVideo,
        ActionType.showVoice,
        ActionType.showVideoNote,
        ActionType.playAudio,
        ActionType.playCallSound,
        ActionType.showCallVideo,
      }.contains(_type);

  Set<MediaKind> get _mediaKinds => switch (_type) {
        ActionType.showPhoto => {MediaKind.photo},
        ActionType.showVideo => {MediaKind.video},
        ActionType.showVoice => {MediaKind.voice, MediaKind.audio},
        ActionType.showVideoNote => {MediaKind.videoNote, MediaKind.video},
        ActionType.showCallVideo => {MediaKind.video, MediaKind.videoNote},
        _ => {MediaKind.audio, MediaKind.voice},
      };

  Future<void> _pickMedia() async {
    final media = await AppNavigator.pickFromLibrary(_mediaKinds);
    if (media == null) return;
    setState(() {
      _params['mediaId'] = media.id;
      _params['mediaName'] = media.originalName ?? media.kind.label;
    });
  }

  Future<void> _save() async {
    final type = _type;
    if (type == null) return;
    if (_isMedia && _params['mediaId'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите файл из медиатеки')));
      return;
    }
    final params = <String, Object?>{..._params};
    void put(String key, Object? value) => value == null ? params.remove(key) : params[key] = value;
    put('characterId', _needsParticipant ? _characterId : null);
    put('read', _isOutgoingMessage(type, params) ? _readOn : null);
    put('replyToActionId', _isIncomingMessage(type, params) ? _replyTo : null);
    final ownKey = params['groupId'] is String
        ? groupChatKey(params['groupId'] as String)
        : (_characterId == null ? null : directChatKey(_characterId!));
    final also = [for (final key in _alsoIn) if (key != ownKey) key];
    put('alsoIn', also.isEmpty ? null : also);
    if (type == ActionType.message || type == ActionType.call) {
      if (params['from'] == null || params['to'] == null || params['from'] == params['to']) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Выберите, кто и кому (разные персонажи)')));
        return;
      }
    }
    switch (type) {
      case ActionType.message:
        put('text', _text.text.trim());
        put('typingMs', _parseMs(_typing));
      case ActionType.showIncoming:
        put('text', _text.text.trim());
        put('typingMs', _parseMs(_typing));
      case ActionType.showOutgoing:
        put('text', _text.text.trim());
      case ActionType.sendMessage:
        put('text', _text.text.trim());
        put('deliverMs', _parseMs(_deliver));
        put('readMs', _parseMs(_read));
      case ActionType.startTyping:
        put('durationMs', _parseMs(_duration));
      case ActionType.postNotification:
        put('title', _title.text.trim());
        put('text', _text.text.trim());
      case ActionType.updateNotificationText:
      case ActionType.showEvent:
      case ActionType.editMessage:
        put('text', _text.text.trim());
      case ActionType.updateNotificationTime:
        put('time', _time.text.trim());
      case ActionType.wait:
        put('ms', _parseMs(_wait));
      case ActionType.showPhoto:
      case ActionType.showVideo:
      case ActionType.showVoice:
      case ActionType.showVideoNote:
        put('caption', _caption.text.trim());
        put('typingMs', params['direction'] == 'out' ? null : _parseMs(_typing));
      default:
        break;
    }
    final now = DateTime.now();
    final original = widget.action;
    final action = SceneAction(
      id: original?.id ?? newId(),
      sceneId: widget.sceneId,
      position: original?.position ?? 0,
      typeName: original?.typeName ?? type.name,
      delayMs: _parseMs(_delay),
      params: params,
      note: _note.text.trim(),
      enabled: _enabled,
      createdAt: original?.createdAt ?? now,
      updatedAt: now,
    );
    final services = Services.read(context);
    await services.scenes.saveAction(action);
    await services.engine.reloadActions();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final original = widget.action;
    if (original == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить действие?',
      message: original.label,
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final services = Services.read(context);
    await services.scenes.deleteAction(original.id);
    await services.engine.reloadActions();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _chips<T>(String title, Map<T, String> options, T current, ValueChanged<T> onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.xs),
          child: Text(title, style: const TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
        ),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final entry in options.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: entry.key == current,
                onSelected: (_) => setState(() => onSelect(entry.key)),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _fields() {
    const gap = SizedBox(height: Space.m);
    final type = _type;
    final state = (_params['state'] as String?) ?? MessageState.read.name;
    final target = (_params['target'] as String?) ??
        (type == ActionType.setMessageState ? 'lastOutgoing' : 'lastIncoming');
    final direction = (_params['direction'] as String?) ?? 'in';
    final stateOptions = {for (final s in MessageState.values) s.name: messageStateName(s)};

    TextInputType number() => const TextInputType.numberWithOptions(decimal: true);

    return switch (type) {
      ActionType.message => [
          _personChips('От кого', 'from'),
          gap,
          _personChips('Кому', 'to'),
          gap,
          ReplikaTextField(controller: _text, label: 'Текст', maxLines: 5),
          gap,
          _chips<String>('Статус после отправки', stateOptions,
              (_params['state'] as String?) ?? MessageState.delivered.name, (v) => _params['state'] = v),
          gap,
          ReplikaTextField(
            controller: _typing,
            label: '«Печатает…» у получателя, секунд',
            keyboardType: number(),
          ),
          gap,
          const Text(
            'Сообщение появится исходящим на телефоне отправителя и входящим на телефоне получателя '
            '(📱 — у персонажа есть профиль). «Отправляется» и «Не доставлено» до получателя не доходят, '
            'пока событие «Изменить состояние» не сделает сообщение доставленным.',
            style: TextStyle(color: OperatorPalette.textDim),
          ),
        ],
      ActionType.call => [
          _personChips('Кто звонит', 'from'),
          gap,
          _personChips('Кому', 'to'),
          gap,
          _chips<String>('Вид', const {'audio': 'Аудио', 'video': 'Видео'},
              _params['video'] == true ? 'video' : 'audio', (v) => _params['video'] = v == 'video'),
          gap,
          const Text(
            'Если на экране профиль одного из них — появится экран звонка, у второго звонок запишется в историю. '
            'Иначе звонок идёт «за кадром» и попадает в историю обоих по завершении. '
            'Ответ и завершение — событиями «Принять звонок», «Завершить звонок» с выбором этого звонка.',
            style: TextStyle(color: OperatorPalette.textDim),
          ),
        ],
      ActionType.showIncoming => [
          ReplikaTextField(controller: _text, label: 'Текст входящего', maxLines: 5),
          gap,
          ReplikaTextField(
            controller: _typing,
            label: '«Печатает…» перед сообщением, секунд',
            keyboardType: number(),
            helper: '0 — сообщение появится сразу',
          ),
          ..._replySection(),
        ],
      ActionType.showOutgoing => [
          ReplikaTextField(controller: _text, label: 'Текст исходящего', maxLines: 5),
          ..._readSwitch(),
        ],
      ActionType.sendMessage => [
          ReplikaTextField(controller: _text, label: 'Текст исходящего', maxLines: 5),
          gap,
          ReplikaTextField(controller: _deliver, label: 'Через сколько «доставлено», секунд', keyboardType: number()),
          ..._readSwitch(),
        ],
      ActionType.startTyping => [
          ReplikaTextField(controller: _duration, label: 'Сколько печатает, секунд', keyboardType: number()),
        ],
      ActionType.deleteMessage => [
          _chips<String>('Какое сообщение', targetNames, target, (v) => _params['target'] = v),
        ],
      ActionType.editMessage => [
          _chips<String>('Какое сообщение', targetNames, target, (v) => _params['target'] = v),
          gap,
          ReplikaTextField(controller: _text, label: 'Новый текст', maxLines: 5),
          gap,
          const Text('В пузыре появится пометка «изм.», как в настоящем мессенджере.',
              style: TextStyle(color: OperatorPalette.textDim)),
        ],
      ActionType.setMessageState => [
          _chips<String>('Какое сообщение', targetNames, target, (v) => _params['target'] = v),
          gap,
          _chips<String>('Новый статус', stateOptions, state, (v) => _params['state'] = v),
        ],
      ActionType.showPhoto || ActionType.showVideo || ActionType.showVoice || ActionType.showVideoNote => [
          _MediaButton(name: _params['mediaName'] as String?, onTap: _pickMedia),
          gap,
          _chips<String>('Кто отправляет', const {'in': 'Собеседник', 'out': 'Владелец телефона'}, direction,
              (v) => _params['direction'] = v),
          gap,
          ReplikaTextField(controller: _caption, label: 'Подпись (необязательно)', maxLines: 3),
          if (direction == 'in') ...[
            gap,
            ReplikaTextField(controller: _typing, label: '«Печатает…» перед отправкой, секунд', keyboardType: number()),
            ..._replySection(),
          ] else
            ..._readSwitch(),
        ],
      ActionType.playAudio => [
          _MediaButton(name: _params['mediaName'] as String?, onTap: _pickMedia),
          gap,
          const Text('Звук играет через динамик телефона, в переписке ничего не появляется.',
              style: TextStyle(color: OperatorPalette.textDim)),
        ],
      ActionType.playCallSound || ActionType.showCallVideo => [
          _MediaButton(name: _params['mediaName'] as String?, onTap: _pickMedia),
          gap,
          const Text('Действует в идущем звонке: заменяет голос или видео собеседника, '
              'выбранные в его карточке.',
              style: TextStyle(color: OperatorPalette.textDim)),
        ],
      ActionType.incomingAudioCall ||
      ActionType.incomingVideoCall ||
      ActionType.outgoingAudioCall ||
      ActionType.outgoingVideoCall => [
          const Text(
            'Звонит собеседник из чата сцены (или ему звонят). Голос и видео '
            'собеседника берутся из его карточки: «Контакты» → «Изменить» → '
            '«Для постановочных звонков». Без ответа звонок сам завершится через 40 секунд.',
            style: TextStyle(color: OperatorPalette.textDim),
          ),
        ],
      ActionType.postNotification => [
          ReplikaTextField(
            controller: _title,
            label: 'Заголовок',
            helper: 'Пусто — имя собеседника из чата сцены. Можно «Сбербанк», «МТС» и т. п.',
          ),
          gap,
          ReplikaTextField(controller: _text, label: 'Текст уведомления', maxLines: 4),
          gap,
          const Text('Настоящее уведомление: звук, вибрация, список уведомлений. Нажатие открывает чат сцены.',
              style: TextStyle(color: OperatorPalette.textDim)),
        ],
      ActionType.updateNotificationText => [
          ReplikaTextField(controller: _text, label: 'Новый текст последнего уведомления сцены', maxLines: 4),
        ],
      ActionType.updateNotificationTime => [
          ReplikaTextField(
            controller: _time,
            label: 'Время в уведомлении, ЧЧ:ММ',
            keyboardType: TextInputType.datetime,
            helper: 'Меняет время последнего уведомления сцены, например 06:40.',
          ),
        ],
      ActionType.showEvent => [
          ReplikaTextField(controller: _text, label: 'Текст события', maxLines: 3),
          gap,
          const Text('Серая плашка посреди переписки: «Вероника удалила сообщение», «Звонок отклонён»…',
              style: TextStyle(color: OperatorPalette.textDim)),
        ],
      ActionType.wait => [
          ReplikaTextField(controller: _wait, label: 'Ждать, секунд', keyboardType: number()),
          gap,
          const Text('В ручном режиме ожидание пропускается.', style: TextStyle(color: OperatorPalette.textDim)),
        ],
      ActionType.pause => [
          const Text('В автоматическом режиме сцена остановится и будет ждать «Далее» — '
              'кнопкой на панели или касанием двумя пальцами в кадре.',
              style: TextStyle(color: OperatorPalette.textDim)),
        ],
      _ => [
          Text(type == null ? '' : actionSummary(SceneAction(
                id: '', sceneId: '', position: 0, typeName: type.name,
                createdAt: DateTime(2000), updatedAt: DateTime(2000))),
              style: const TextStyle(color: OperatorPalette.textDim)),
        ],
    };
  }

  /// «Показывать также в чатах»: привязка события к личным таймлайнам других
  /// чатов, чтобы выполнить его, не выходя из текущего.
  List<Widget> _alsoInSection() {
    final type = _type;
    if (type == null || engineControlTypes.contains(type)) return const [];
    final own = _params['groupId'] is String
        ? groupChatKey(_params['groupId'] as String)
        : (_characterId == null ? null : directChatKey(_characterId!));
    final options = [for (final o in _alsoOptions) if (o.key != own) o];
    if (options.isEmpty) return const [];
    return [
      const SizedBox(height: Space.l),
      const Text('Показывать также в чатах',
          style: TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
      const SizedBox(height: Space.xs),
      Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          for (final o in options)
            FilterChip(
              label: Text(o.label),
              selected: _alsoIn.contains(o.key),
              onSelected: (on) => setState(() => on ? _alsoIn.add(o.key) : _alsoIn.remove(o.key)),
            ),
        ],
      ),
      const SizedBox(height: Space.xs),
      const Text(
        'Событие останется событием своего чата, но его можно будет выполнить '
        'из личного таймлайна выбранных чатов.',
        style: TextStyle(color: OperatorPalette.textDim, fontSize: 12),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final type = _type;
    return Theme(
      data: operatorTheme,
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: const BackIconButton(),
          title: Text(type?.label ?? 'Действие',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [TextButton(onPressed: type == null ? null : _save, child: const Text('Готово'))],
        ),
        body: ListView(
          padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxxl)),
          children: [
            ..._refChips(),
            if (_needsParticipant) ...[
              const Text('От имени участника', style: TextStyle(color: OperatorPalette.textDim, fontSize: 13)),
              const SizedBox(height: Space.xs),
              if (_participants.isEmpty)
                const Text(
                  'У сцены пока один участник — собеседник её чата. Других добавьте в редакторе сцены.',
                  style: TextStyle(color: OperatorPalette.textDim),
                )
              else
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final p in _participants)
                      ChoiceChip(
                        avatar: Avatar(name: p.name, size: 22, tone: p.avatarTone, imagePath: p.avatarPath),
                        label: Text(p.name),
                        selected: _characterId == p.characterId,
                        onSelected: (_) => setState(() => _characterId = p.characterId),
                      ),
                  ],
                ),
              const SizedBox(height: Space.l),
            ],
            ..._fields(),
            ..._alsoInSection(),
            const SizedBox(height: Space.xl),
            ReplikaTextField(
              controller: _delay,
              label: 'Пауза перед действием, секунд',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              helper: 'Используется в автоматическом режиме',
            ),
            const SizedBox(height: Space.m),
            ReplikaTextField(controller: _note, label: 'Заметка (например, реплика актёра)', maxLines: 3),
            const SizedBox(height: Space.s),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              title: const Text('Действие включено', style: TextStyle(color: OperatorPalette.text)),
              subtitle: const Text('Выключенное остаётся в таймлайне, но не выполняется',
                  style: TextStyle(color: OperatorPalette.textDim)),
            ),
            if (widget.action != null) ...[
              const SizedBox(height: Space.l),
              TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: OperatorPalette.live),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Удалить действие'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaButton extends StatelessWidget {
  const _MediaButton({required this.name, required this.onTap});

  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OperatorCard(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.perm_media_outlined, color: OperatorPalette.standby),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(name ?? 'Выбрать файл из медиатеки',
                style: const TextStyle(color: OperatorPalette.text, fontWeight: FontWeight.w600)),
          ),
          const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
        ],
      ),
    );
  }
}
