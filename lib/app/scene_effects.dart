import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/util/json.dart';
import '../data/models/media_item.dart';
import '../data/models/message.dart';
import '../data/models/scene.dart';
import '../data/models/scene_action.dart';
import '../data/models/take.dart';
import '../data/models/call_record.dart';
import 'call_engine.dart';
import 'call_services.dart';
import 'navigator.dart';
import 'notifications.dart';
import '../features/chat/message_labels.dart';
import 'scene_engine.dart';
import 'services.dart';
import '../data/repositories/settings_repository.dart';

/// Действия сцены над настоящими данными: сообщения пишутся в базу
/// с пометкой «сцена», а экраны обновляются сами.
///
/// Сцена — это участники. Каждое действие выполняется от имени своего
/// участника в его личном чате на телефоне сцены. Если чата ещё нет,
/// он создаётся. Всё, что сцена меняет, записывается в журнал дубля:
/// «Назад» отменяет последний шаг, «СБРОС СЦЕНЫ» — все шаги во всех
/// чатах. Это работает и после перезапуска приложения.
class SceneDataEffects implements SceneEffects, SceneProgressStore {
  SceneDataEffects(this.services);

  final AppServices services;

  String? _takeId;

  /// Последнее сообщение, созданное действием (Connect возвращает его id).
  String? lastCreatedMessageId;

  /// Последняя группа, созданная действием.
  String? lastCreatedChatId;

  /// Режим прогона в журнале: 'take' или 'rehearsal'.
  String _mode = 'take';

  // События на нескольких профилях (в пределах прогона):
  // id события → все копии сообщения, исходящая копия отправителя,
  // недоставленное (копии получателя ещё нет), звонки.
  final Map<String, List<String>> _eventMessages = {};
  final Map<String, String> _eventOutgoing = {};
  final Map<String, ({String device, String from, String to, String text})> _eventPending = {};
  final Map<String, _VirtualCall> _virtualCalls = {};
  final Map<String, _VirtualCall> _finishedCalls = {};
  /// Звонки событий, показанные на экране: кто звонит и чей профиль на экране.
  final Map<String, ({String from, bool screenIsCaller})> _screenCalls = {};

  void _clearEvents() {
    _eventMessages.clear();
    _eventOutgoing.clear();
    _eventPending.clear();
    _virtualCalls.clear();
    _finishedCalls.clear();
    _screenCalls.clear();
  }

  /// Снимки чатов до первого изменения в дубле: чат → поля.
  final Map<String, Map<String, Object?>> _snapshots = {};
  String? _openChatAtStart;

  /// Шаги дубля: для каждого выполненного действия — список операций отмены.
  final List<List<Map<String, Object?>>> _steps = [];

  void _record(Map<String, Object?> op) {
    if (_steps.isEmpty) _steps.add([]);
    _steps.last.add(op);
  }

  @override
  Future<SceneRunInfo> prepare(String sceneId) async {
    final scene = await services.scenes.byId(sceneId);
    if (scene == null) throw StateError('Сцена не найдена');
    final deviceId = scene.deviceId ?? services.currentDeviceId.value;
    final device = await services.devices.byId(deviceId);
    if (device == null) throw StateError('Телефон сцены удалён');

    final rows = await services.scenes.participants(sceneId, deviceId);
    final participants = [
      for (final r in rows)
        SceneParticipant(
          characterId: r.characterId,
          name: r.name,
          avatarTone: r.avatarTone,
          avatarPath: r.avatarPath,
        ),
    ];

    // Главный чат («В КАДР») необязателен. У старых сцен без участников
    // единственный участник — собеседник этого чата.
    String? mainChat = scene.chatId;
    String? mainPeer;
    String mainName = '';
    if (mainChat != null) {
      final header = await services.chats.header(mainChat);
      if (header == null) {
        mainChat = null;
      } else {
        mainPeer = header.chat.peerCharacterId;
        mainName = header.peer.displayName;
        if (participants.isEmpty && mainPeer != null) {
          participants.add(SceneParticipant(
            characterId: mainPeer,
            name: header.peer.displayName,
            avatarTone: header.peer.avatarTone,
            avatarPath: header.peer.avatarPath,
          ));
        }
      }
    }
    if (participants.isEmpty) {
      throw StateError('Добавьте в сцену участников или выберите чат');
    }

    final chatIds = <String>{};
    for (final p in participants) {
      final chat = await services.chats.findDirect(deviceId: deviceId, characterId: p.characterId);
      if (chat != null) chatIds.add(chat);
    }

    // Запоминаем сцену: после перезапуска сброс кнопками продолжит работать.
    await services.settings.setValue(SettingKeys.activeSceneId, sceneId);
    final title = scene.number.isEmpty ? scene.name : '${scene.number}. ${scene.name}';
    return SceneRunInfo(
      sceneId: scene.id,
      sceneTitle: title,
      deviceId: deviceId,
      ownerId: device.ownerCharacterId,
      chatId: mainChat,
      peerId: mainPeer ?? participants.first.characterId,
      chatName: mainChat != null ? mainName : participants.map((p) => p.name).join(', '),
      clockStart: sceneClockStart(scene.initialState['clock'], DateTime.now()),
      participants: participants,
      chatIds: chatIds,
    );
  }

  @override
  Future<List<SceneAction>> loadActions(String sceneId) => services.scenes.actions(sceneId);

  /// Сообщения, созданные исходящими действиями: id действия → id сообщения.
  /// По этой связи ответ контакта (replyToActionId) находит своё сообщение.
  final Map<String, String> _actionMessages = {};

  /// Ход дубля от движка: выполненные события, шаги «Назад», позиция.
  /// Хранится в журнале дубля, поэтому переживает перезапуск приложения.
  Map<String, Object?> _progress = const {};

  Map<String, Object?> get _log => {
        'mode': _mode,
        'snapshots': _snapshots,
        'steps': _steps,
        'openChatAtStart': _openChatAtStart,
        'progress': _progress,
        'actionMessages': _actionMessages,
      };

  @override
  Future<void> saveProgress(SceneRunInfo info, Map<String, Object?> progress) async {
    _progress = progress;
    await _saveLog();
  }

  /// Незавершённый дубль из базы: журнал отмены, снимки чатов и ход дубля
  /// возвращаются в память, и сцена продолжается с того же места.
  /// Репетиции и дубли без сохранённого хода не продолжаются — как раньше,
  /// их можно только сбросить.
  @override
  Future<ResumedTake?> resumeTake(SceneRunInfo info) async {
    if (_takeId != null) return null;
    final last = await services.scenes.lastTake(info.sceneId);
    if (last == null || last.status != TakeStatus.running) return null;
    final log = decodeJsonMap(last.logJson);
    final progress = log['progress'];
    if (log['reset'] == true || log['mode'] == 'rehearsal' || progress is! Map) return null;

    List<Map<String, Object?>> ops(Object? list) => [
          for (final entry in (list as List?) ?? const [])
            if (entry is Map) Map<String, Object?>.from(entry),
        ];
    _snapshots.clear();
    final stored = log['snapshots'];
    if (stored is Map) {
      for (final e in stored.entries) {
        if (e.value is Map) _snapshots['${e.key}'] = Map<String, Object?>.from(e.value as Map);
      }
    }
    _steps
      ..clear()
      ..addAll([for (final step in (log['steps'] as List?) ?? const []) ops(step)]);
    _clearEvents();
    _mode = 'take';
    _openChatAtStart = log['openChatAtStart'] as String?;
    _actionMessages.clear();
    final linked = log['actionMessages'];
    if (linked is Map) {
      for (final e in linked.entries) {
        if (e.value is String) _actionMessages['${e.key}'] = e.value as String;
      }
    }
    _takeId = last.id;
    _progress = Map<String, Object?>.from(progress);
    info.chatIds.addAll(_snapshots.keys);
    return ResumedTake(number: last.number, startedAt: last.startedAt, progress: _progress);
  }

  @override
  Future<int> beginTake(SceneRunInfo info) async {
    _snapshots.clear();
    _steps.clear();
    _clearEvents();
    _progress = const {};
    _actionMessages.clear();
    _mode = info.rehearsal ? 'rehearsal' : 'take';
    _openChatAtStart = services.openChatId.value;
    for (final chatId in info.chatIds) {
      _snapshots[chatId] = await services.chats.snapshot(chatId);
    }
    final take = await services.scenes.startTake(info.sceneId, _log);
    _takeId = take.id;
    return take.number;
  }

  Future<void> _saveLog() async {
    final id = _takeId;
    if (id != null) await services.scenes.saveTakeLog(id, _log);
  }

  /// Чат участника: запомнить состояние до первого изменения в дубле.
  Future<void> _touch(SceneRunInfo info, String chatId) async {
    info.chatIds.add(chatId);
    if (_snapshots.containsKey(chatId)) return;
    _snapshots[chatId] = await services.chats.snapshot(chatId);
  }

  /// Участник действия и его чат на телефоне сцены. С параметром groupId —
  /// групповой чат, где участник должен состоять (владелец — «от себя»).
  Future<({String chatId, String peerId})> _target(SceneRunInfo info, SceneAction action) async {
    final groupId = action.params['groupId'] as String?;
    if (groupId != null) {
      final group = await _group(info, groupId);
      final who = action.characterId ?? info.ownerId;
      if (!await services.chats.isMember(group, who)) {
        throw StateError('«${await _contactName(info, who)}» не состоит в группе');
      }
      await _touch(info, group);
      return (chatId: group, peerId: who);
    }
    final peer = action.characterId ?? info.peerId;
    if (peer == null) throw StateError('у действия не выбран участник');
    final chatId = await services.chats.openOrCreateDirect(deviceId: info.deviceId, characterId: peer);
    await _touch(info, chatId);
    return (chatId: chatId, peerId: peer);
  }

  bool _chatOpen(String chatId) => services.openChatId.value == chatId;

  Future<String> _group(SceneRunInfo info, String groupId) async {
    final header = await services.chats.header(groupId);
    if (header == null || !header.chat.isGroup || header.chat.deviceId != info.deviceId) {
      throw StateError('группа не найдена на этом телефоне');
    }
    return groupId;
  }

  /// Как персонаж записан на телефоне сцены («Мама», номер, имя).
  Future<String> _contactName(SceneRunInfo info, String characterId) async {
    if (characterId == info.ownerId) return 'Вы';
    final contact = await services.contacts.view(info.deviceId, characterId);
    return contact?.shownName ?? 'Участник';
  }

  /// Паузы внутри действия идут с той же скоростью, что и таймлайн.
  Future<void> _wait(int ms, bool Function() cancelled) async {
    var left = (ms / services.engine.speed).round();
    while (left > 0 && !cancelled()) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      left -= 50;
    }
  }

  static String _text(SceneAction a, [String key = 'text']) => (a.params[key] as String?)?.trim() ?? '';
  static int _int(SceneAction a, String key, int fallback) {
    final v = a.params[key];
    return v is num ? v.toInt() : fallback;
  }

  static MessageState _state(SceneAction a, MessageState fallback) {
    final name = a.params['state'];
    for (final s in MessageState.values) {
      if (s.name == name) return s;
    }
    return fallback;
  }

  /// «Прочитано» ON/OFF у исходящего. null — не задано: прежнее поведение
  /// (по статусу и по ответу собеседника).
  static bool? _readFlag(SceneAction a) {
    final value = a.params['read'];
    return value is bool ? value : null;
  }

  /// Исходящее сообщение действия с учётом «Прочитано»:
  /// ON — сразу прочитано; OFF — доставлено и удерживается непрочитанным
  /// до ответа на него. Запоминает связь «действие → сообщение».
  Future<String> _insertOutgoing(
    SceneRunInfo info,
    String chatId,
    SceneAction action, {
    required MessageType type,
    String text = '',
    String? mediaId,
    required MessageState fallback,
  }) async {
    final flag = _readFlag(action);
    final state = flag == null ? fallback : (flag ? MessageState.read : MessageState.delivered);
    final id = await _insert(info, chatId,
        senderId: info.ownerId, type: type, text: text, mediaId: mediaId, state: state);
    if (flag == false) await services.messages.setReadHold(id, true);
    _actionMessages[action.id] = id;
    return id;
  }

  /// Сообщение, на которое отвечает входящее действие (replyToActionId).
  Future<Message?> _replyTarget(SceneAction action, String chatId) async {
    final ref = action.params['replyToActionId'] as String?;
    final id = ref == null ? null : _actionMessages[ref];
    if (id == null) return null;
    final message = await services.messages.byId(id);
    return message != null && message.chatId == chatId && !message.deleted ? message : null;
  }

  /// Ответ контакта читает именно то сообщение, на которое он отвечает.
  Future<void> _readByReply(Message original) async {
    final fresh = await services.messages.byId(original.id) ?? original;
    if (fresh.state != MessageState.read) {
      _record({'op': 'state', 'id': fresh.id, 'state': fresh.state.name});
      await services.messages.setState(fresh.id, MessageState.read);
    }
    if (await services.messages.isReadHeld(fresh.id)) {
      _record({'op': 'hold', 'id': fresh.id, 'value': true});
      await services.messages.setReadHold(fresh.id, false);
    }
  }

  Future<String> _insert(
    SceneRunInfo info,
    String chatId, {
    required String? senderId,
    required MessageType type,
    String text = '',
    String? mediaId,
    MessageState state = MessageState.delivered,
    String? replyToId,
  }) async {
    final message = await services.messages.insertSceneMessage(
      chatId: chatId,
      senderId: senderId,
      type: type,
      text: text,
      mediaId: mediaId,
      sceneId: info.sceneId,
      state: state,
      sentAt: services.engine.sceneNow(),
      replyToId: replyToId,
    );
    _record({'op': 'delete', 'id': message.id});
    lastCreatedMessageId = message.id;
    return message.id;
  }

  /// Входящее от участника: «печатает…», сообщение, прочтение исходящих,
  /// счётчик и уведомление, если его чат не открыт.
  Future<void> _incoming(
    SceneRunInfo info,
    ({String chatId, String peerId}) target,
    SceneAction action,
    bool Function() cancelled, {
    required MessageType type,
    String text = '',
    String? mediaId,
  }) async {
    final chatId = target.chatId;
    final typingMs = _int(action, 'typingMs', 0);
    if (typingMs > 0) {
      _record({'op': 'typing', 'chatId': chatId});
      services.typing.start(
        chatId,
        duration: Duration(milliseconds: (typingMs / services.engine.speed).round() + 1500),
      );
      await _wait(typingMs, cancelled);
      services.typing.stop(chatId);
      if (cancelled()) return;
    }
    final reply = await _replyTarget(action, chatId);
    final previous = await services.messages.markOutgoingRead(chatId, info.ownerId);
    for (final (id, state) in previous) {
      _record({'op': 'state', 'id': id, 'state': state});
    }
    await _insert(info, chatId,
        senderId: target.peerId, type: type, text: text, mediaId: mediaId, replyToId: reply?.id);
    if (reply != null && reply.senderId == info.ownerId) await _readByReply(reply);
    if (!_chatOpen(chatId)) {
      await services.chats.incrementUnread(chatId);
      _record({'op': 'unreadDec', 'chatId': chatId});
      _record({'op': 'chatNotif', 'chatId': chatId});
      final shown = text.isNotEmpty ? text : messageTypeLabelFor(type);
      final inGroup = action.params['groupId'] != null;
      unawaited(services.notifyIncoming(
        chatId,
        shown,
        time: services.engine.sceneNow(),
        senderName: inGroup ? await _contactName(info, target.peerId) : null,
      ));
    }
  }

  Future<MediaItem> _media(SceneAction action) async {
    final id = action.params['mediaId'] as String?;
    final media = id == null ? null : await services.media.repository.byId(id);
    if (media == null) throw StateError('файл не выбран или удалён из медиатеки');
    return media;
  }

  @override
  Future<void> perform(SceneAction action, SceneRunInfo info, bool Function() cancelled) async {
    _steps.add([]);
    try {
      await _perform(action, info, cancelled);
    } finally {
      await _saveLog();
    }
  }

  /// Сообщение, к которому относится действие: по id (Connect) или
  /// последнее подходящее в чате участника (таймлайн).
  Future<Message> _findMessage(
    SceneRunInfo info,
    ({String chatId, String peerId}) target,
    SceneAction action,
  ) async {
    final id = action.params['messageId'] as String?;
    if (id != null) {
      final message = await services.messages.byId(id);
      if (message == null || message.chatId != target.chatId) {
        throw StateError('сообщение не найдено в чате «${info.nameOf(target.peerId)}»');
      }
      return message;
    }
    final which = (action.params['target'] as String?) ??
        (action.type == ActionType.setMessageState ? 'lastOutgoing' : 'lastIncoming');
    final message = await services.messages.findTarget(target.chatId, which, info.ownerId);
    if (message == null) throw StateError('в чате «${info.nameOf(target.peerId)}» нет подходящего сообщения');
    return message;
  }

  /// Звонок участника: действие касается звонка именно этого участника.
  void _checkCallOwner(SceneRunInfo info, SceneAction action) {
    final who = action.characterId;
    final session = services.callEngine.session;
    if (session == null) throw StateError('сейчас нет звонка');
    if (who != null && session.characterId != who) {
      throw StateError('звонок идёт не с «${info.nameOf(who)}», а с «${session.displayName}»');
    }
  }

  Future<void> _perform(SceneAction action, SceneRunInfo info, bool Function() cancelled) async {
    switch (action.type) {
      case ActionType.showIncoming:
        final target = await _target(info, action);
        await _incoming(info, target, action, cancelled, type: MessageType.text, text: _text(action));

      case ActionType.showOutgoing:
        final target = await _target(info, action);
        await _insertOutgoing(info, target.chatId, action,
            type: MessageType.text, text: _text(action), fallback: _state(action, MessageState.read));

      case ActionType.sendMessage:
        final target = await _target(info, action);
        final flag = _readFlag(action);
        if (flag == true) {
          // Прочитано: ON — сразу прочитано, без анимации статусов.
          await _insertOutgoing(info, target.chatId, action,
              type: MessageType.text, text: _text(action), fallback: MessageState.read);
        } else {
          final id = await _insert(info, target.chatId,
              senderId: info.ownerId, type: MessageType.text, text: _text(action), state: MessageState.sending);
          _actionMessages[action.id] = id;
          if (flag == false) await services.messages.setReadHold(id, true);
          unawaited(_trackMessageState(id, action, cancelled, allowRead: flag == null));
        }

      case ActionType.startTyping:
        final target = await _target(info, action);
        _record({'op': 'typing', 'chatId': target.chatId});
        services.typing.start(
          target.chatId,
          duration: Duration(milliseconds: _int(action, 'durationMs', 4000)),
        );

      case ActionType.message:
        await _crossMessage(info, action, cancelled);

      case ActionType.call:
        await _crossCall(info, action);

      case ActionType.deleteMessage || ActionType.setMessageState || ActionType.editMessage
          when action.params['refActionId'] != null:
        await _messageByRef(info, action);

      case ActionType.acceptCall || ActionType.declineCall || ActionType.endCall
          when action.params['refActionId'] != null && _virtualCalls.containsKey(action.params['refActionId']):
        await _virtualCallControl(info, action);

      case ActionType.acceptCall || ActionType.declineCall || ActionType.endCall
          when action.params['refActionId'] != null:
        final screen = _screenCalls[action.params['refActionId']];
        if (screen == null || !services.callEngine.inCall) {
          throw StateError('звонок этого события ещё не начат или уже завершён');
        }
        // «Завершить» по умолчанию — со стороны звонящего; «by» — явно кто.
        final by = action.params['by'] as String? ?? screen.from;
        final byScreenOwner = screen.screenIsCaller ? by == screen.from : by != screen.from;
        switch (action.type) {
          case ActionType.acceptCall:
            services.callEngine.accept();
          case ActionType.declineCall:
            services.callEngine.decline();
          default:
            byScreenOwner ? services.callEngine.hangUp() : services.callEngine.remoteHangUp();
        }

      case ActionType.deleteMessage:
      case ActionType.setMessageState:
      case ActionType.editMessage:
        final target = await _target(info, action);
        final message = await _findMessage(info, target, action);
        if (action.type == ActionType.deleteMessage) {
          _record({'op': 'deleted', 'id': message.id, 'value': message.deleted});
          await services.messages.setDeleted(message.id, true);
        } else if (action.type == ActionType.editMessage) {
          final text = _text(action);
          if (text.isEmpty) throw StateError('новый текст пустой');
          _record({'op': 'text', 'id': message.id, 'text': message.text, 'edited': message.edited});
          await services.messages.updateText(message.id, text, edited: action.params['markEdited'] != false);
        } else {
          _record({'op': 'state', 'id': message.id, 'state': message.state.name});
          await services.messages.setState(message.id, _state(action, MessageState.read));
        }
        lastCreatedMessageId = message.id;

      case ActionType.showPhoto:
      case ActionType.showVideo:
      case ActionType.showVoice:
      case ActionType.showVideoNote:
        final target = await _target(info, action);
        final media = await _media(action);
        final type = switch (action.type) {
          ActionType.showPhoto => MessageType.photo,
          ActionType.showVideo => MessageType.video,
          ActionType.showVoice => MessageType.voice,
          _ => MessageType.videoNote,
        };
        if (action.params['direction'] == 'out') {
          await _insertOutgoing(info, target.chatId, action,
              type: type, text: _text(action, 'caption'), mediaId: media.id, fallback: MessageState.read);
        } else {
          await _incoming(info, target, action, cancelled,
              type: type, text: _text(action, 'caption'), mediaId: media.id);
        }

      case ActionType.playAudio:
        final media = await _media(action);
        _record({'op': 'audio'});
        if (!services.audio.isPlaying(media.id)) await services.audio.toggle(media);

      case ActionType.openChat:
        final target = await _target(info, action);
        if (!_chatOpen(target.chatId)) {
          _record({'op': 'navBack'});
          unawaited(AppNavigator.openChat(target.chatId));
        }

      case ActionType.openProfile:
        final target = await _target(info, action);
        _record({'op': 'navBack'});
        unawaited(AppNavigator.openProfile(deviceId: info.deviceId, characterId: target.peerId));

      case ActionType.navigateBack:
        AppNavigator.back();

      case ActionType.postNotification:
        final target = await _target(info, action);
        final id = chatNotificationId('scene-${action.id}');
        _lastEvent = _EventNotification(
          id: id,
          title: _text(action, 'title').isEmpty ? info.nameOf(target.peerId) : _text(action, 'title'),
          text: _text(action),
          time: services.engine.sceneNow() ?? DateTime.now(),
          chatId: target.chatId,
        );
        await _showEvent();
        _record({'op': 'notif', 'id': id});
      case ActionType.updateNotificationText:
        final last = _lastEvent;
        if (last == null) throw StateError('сначала нужно действие «Локальное уведомление»');
        _lastEvent = last.copyWith(text: _text(action));
        await _showEvent();
      case ActionType.updateNotificationTime:
        final last = _lastEvent;
        if (last == null) throw StateError('сначала нужно действие «Локальное уведомление»');
        final time = sceneClockStart(action.params['time'], DateTime.now());
        if (time == null) throw StateError('время должно быть в виде ЧЧ:ММ');
        _lastEvent = last.copyWith(time: time);
        await _showEvent();
      case ActionType.showEvent:
        final target = await _target(info, action);
        await _insert(info, target.chatId,
            senderId: null, type: MessageType.system, text: _text(action), state: MessageState.read);

      case ActionType.createGroup:
        final title = _text(action, 'title');
        if (title.isEmpty) throw StateError('нужно название группы');
        final members = [for (final m in (action.params['members'] as List?) ?? const []) if (m is String) m];
        final wanted = action.params['groupId'] as String?;
        if (wanted != null && await services.chats.header(wanted) != null) {
          throw StateError('группа с таким идентификатором уже есть');
        }
        final id = await services.chats.createGroup(
          deviceId: info.deviceId,
          title: title,
          memberIds: members,
          id: wanted,
        );
        _record({'op': 'deleteChat', 'id': id});
        info.chatIds.add(id);
        final creator = action.characterId;
        await _insert(info, id,
            senderId: null,
            type: MessageType.system,
            text: creator == null || creator == info.ownerId
                ? 'Вы создали группу «$title»'
                : '${await _contactName(info, creator)} создал(а) группу «$title»',
            state: MessageState.read);
        lastCreatedChatId = id;

      case ActionType.addGroupMember:
      case ActionType.removeGroupMember:
        final group = await _group(info, action.params['groupId'] as String? ?? '');
        final member = action.params['memberId'] as String?;
        if (member == null) throw StateError('не указан участник');
        final by = action.characterId ?? info.ownerId;
        final adding = action.type == ActionType.addGroupMember;
        final already = await services.chats.isMember(group, member);
        if (adding == already) {
          throw StateError(adding ? 'уже состоит в группе' : 'не состоит в группе');
        }
        await _touch(info, group);
        if (adding) {
          await services.chats.addMember(group, member);
          _record({'op': 'removeMember', 'chatId': group, 'characterId': member});
        } else {
          await services.chats.removeMember(group, member);
          _record({'op': 'addMember', 'chatId': group, 'characterId': member});
        }
        final who = await _contactName(info, by);
        final whom = member == info.ownerId ? 'вас' : await _contactName(info, member);
        final verb = adding ? 'добавил(а)' : 'удалил(а)';
        await _insert(info, group,
            senderId: null,
            type: MessageType.system,
            text: by == info.ownerId ? 'Вы ${adding ? 'добавили' : 'удалили'}: $whom' : '$who $verb $whom',
            state: MessageState.read);

      case ActionType.incomingAudioCall:
      case ActionType.incomingVideoCall:
      case ActionType.outgoingAudioCall:
      case ActionType.outgoingVideoCall:
        await _startCall(info, action);

      case ActionType.acceptCall:
        _checkCallOwner(info, action);
        services.callEngine.accept();
      case ActionType.declineCall:
        _checkCallOwner(info, action);
        services.callEngine.decline();
      case ActionType.endCall:
        _checkCallOwner(info, action);
        services.callEngine.hangUp();
      case ActionType.startConversation:
        _checkCallOwner(info, action);
        services.callEngine.activate();
      case ActionType.playCallSound:
        _checkCallOwner(info, action);
        final media = await _media(action);
        services.callEngine.setPeerMedia(audioPath: media.path);
      case ActionType.showCallVideo:
        _checkCallOwner(info, action);
        final media = await _media(action);
        services.callEngine.setPeerMedia(videoPath: media.path);

      default:
        throw UnsupportedError('недоступно в этой версии (${action.type?.group.label ?? ''})');
    }
  }

  // ---------- События на нескольких профилях ----------

  Future<String?> _deviceOf(String characterId) async =>
      (await services.devices.list()).where((d) => d.ownerCharacterId == characterId).firstOrNull?.id;

  static String _need(SceneAction a, String key) {
    final v = a.params[key];
    if (v is! String || v.isEmpty) throw StateError('не указано «$key»');
    return v;
  }

  /// «Алексей → Марина»: исходящее на телефоне Алексея, входящее — на
  /// телефоне Марины (если у персонажа есть профиль на этом устройстве).
  /// Недоставленное (отправляется / не доставлено) до Марины не доходит,
  /// пока событие статуса не сделает его доставленным.
  Future<void> _crossMessage(SceneRunInfo info, SceneAction action, bool Function() cancelled) async {
    final from = _need(action, 'from');
    final to = _need(action, 'to');
    if (from == to) throw StateError('отправитель и получатель совпадают');
    final text = _text(action);
    if (text.isEmpty) throw StateError('пустой текст');
    final state = _state(action, MessageState.delivered);
    final fromDev = await _deviceOf(from);
    final toDev = await _deviceOf(to);
    if (fromDev == null && toDev == null) {
      throw StateError('ни у отправителя, ни у получателя нет профиля на этом устройстве');
    }
    final delivered = state == MessageState.delivered || state == MessageState.read;
    final typingMs = _int(action, 'typingMs', 0);
    String? receiverChat;
    if (toDev != null && delivered && typingMs > 0) {
      receiverChat = await services.chats.openOrCreateDirect(deviceId: toDev, characterId: from);
      await _touch(info, receiverChat);
      _record({'op': 'typing', 'chatId': receiverChat});
      services.typing.start(receiverChat, duration: Duration(milliseconds: (typingMs / services.engine.speed).round() + 1500));
      await _wait(typingMs, cancelled);
      services.typing.stop(receiverChat);
      if (cancelled()) return;
    }
    final copies = <String>[];
    if (fromDev != null) {
      final chat = await services.chats.openOrCreateDirect(deviceId: fromDev, characterId: to);
      await _touch(info, chat);
      final id = await _insert(info, chat, senderId: from, type: MessageType.text, text: text, state: state);
      _eventOutgoing[action.id] = id;
      copies.add(id);
    }
    if (toDev != null) {
      if (delivered) {
        copies.add(await _deliver(info, toDev, from, to, text));
      } else {
        _eventPending[action.id] = (device: toDev, from: from, to: to, text: text);
        _record({'op': 'unpend', 'event': action.id});
      }
    }
    _eventMessages[action.id] = copies;
    _record({'op': 'forgetEvent', 'event': action.id});
    lastCreatedMessageId = copies.isEmpty ? null : copies.first;
  }

  /// Входящая копия на телефоне получателя.
  Future<String> _deliver(SceneRunInfo info, String device, String from, String to, String text) async {
    // Статусы в режиссёрских событиях задаёт оператор: ответ получателя
    // не делает его исходящие «прочитанными» сам.
    final chat = await services.chats.openOrCreateDirect(deviceId: device, characterId: from);
    await _touch(info, chat);
    final id = await _insert(info, chat, senderId: from, type: MessageType.text, text: text);
    final onScreen = services.currentDeviceId.value == device && _chatOpen(chat);
    if (!onScreen) {
      await services.chats.incrementUnread(chat);
      _record({'op': 'unreadDec', 'chatId': chat});
      if (services.currentDeviceId.value == device) {
        _record({'op': 'chatNotif', 'chatId': chat});
        unawaited(services.notifyIncoming(chat, text, time: services.engine.sceneNow()));
      }
    }
    return id;
  }

  /// Статус, удаление, правка сообщения конкретного события.
  Future<void> _messageByRef(SceneRunInfo info, SceneAction action) async {
    final ref = action.params['refActionId'] as String;
    final copies = _eventMessages[ref];
    if (copies == null) throw StateError('сообщение этого события ещё не отправлено в этом прогоне');
    switch (action.type) {
      case ActionType.setMessageState:
        final state = _state(action, MessageState.read);
        final out = _eventOutgoing[ref];
        if (out != null) {
          final m = await services.messages.byId(out);
          if (m != null) _record({'op': 'state', 'id': out, 'state': m.state.name});
          await services.messages.setState(out, state);
        }
        final pending = _eventPending[ref];
        if (pending != null && (state == MessageState.delivered || state == MessageState.read)) {
          // Доставка случилась сейчас: сообщение появляется у получателя.
          final id = await _deliver(info, pending.device, pending.from, pending.to, pending.text);
          copies.add(id);
          _eventPending.remove(ref);
          _record({'op': 'repend', 'event': ref, 'device': pending.device, 'from': pending.from, 'to': pending.to, 'text': pending.text, 'id': id});
        }
        lastCreatedMessageId = out;
      case ActionType.deleteMessage:
        for (final id in copies) {
          final m = await services.messages.byId(id);
          if (m == null) continue;
          _record({'op': 'deleted', 'id': id, 'value': m.deleted});
          await services.messages.setDeleted(id, true);
        }
        lastCreatedMessageId = copies.isEmpty ? null : copies.first;
      default: // editMessage
        final text = _text(action);
        if (text.isEmpty) throw StateError('новый текст пустой');
        for (final id in copies) {
          final m = await services.messages.byId(id);
          if (m == null) continue;
          _record({'op': 'text', 'id': id, 'text': m.text, 'edited': m.edited});
          await services.messages.updateText(id, text, edited: action.params['markEdited'] != false);
        }
    }
  }

  /// «Сергей → Алексей»: если на экране профиль одного из них — настоящий
  /// экран звонка (у второго — зеркальная запись в истории). Иначе звонок
  /// идёт «за кадром» и записывается в историю обоих профилей по окончании.
  Future<void> _crossCall(SceneRunInfo info, SceneAction action) async {
    final from = _need(action, 'from');
    final to = _need(action, 'to');
    if (from == to) throw StateError('звонящий и вызываемый совпадают');
    final video = action.params['video'] == true;
    final fromDev = await _deviceOf(from);
    final toDev = await _deviceOf(to);
    if (fromDev == null && toDev == null) {
      throw StateError('ни у звонящего, ни у вызываемого нет профиля на этом устройстве');
    }
    final current = services.currentDeviceId.value;
    if (current == toDev || current == fromDev) {
      final onCallee = current == toDev;
      final screenOwner = onCallee ? to : from;
      final peer = onCallee ? from : to;
      final chat = await services.chats.openOrCreateDirect(deviceId: current, characterId: peer);
      await _touch(info, chat);
      final contact = await services.contacts.view(current, peer);
      Future<String?> path(String? id) async =>
          id == null ? null : (await services.media.repository.byId(id))?.path;
      final started = services.callEngine.start(CallSession(
        deviceId: current,
        characterId: peer,
        direction: onCallee ? CallDirection.incoming : CallDirection.outgoing,
        kind: video ? CallKind.video : CallKind.audio,
        displayName: contact?.shownName ?? 'Неизвестный',
        chatId: chat,
        sceneId: info.sceneId,
        avatarTone: contact?.character.avatarTone,
        avatarPath: contact?.avatarPath,
        peerAudioPath: await path(contact?.character.callAudioMediaId),
        peerVideoPath: await path(contact?.character.callVideoMediaId),
        mirrorDeviceId: onCallee ? fromDev : toDev,
        mirrorCharacterId: screenOwner,
      ));
      if (!started) throw StateError('уже идёт другой звонок');
      _screenCalls[action.id] = (from: from, screenIsCaller: !onCallee);
      _record({'op': 'call'});
    } else {
      _virtualCalls[action.id] = _VirtualCall(
        fromDevice: fromDev,
        toDevice: toDev,
        from: from,
        to: to,
        video: video,
        startedAt: services.engine.sceneNow() ?? DateTime.now(),
      );
      _record({'op': 'vcall', 'event': action.id});
    }
  }

  /// Ответ, отклонение, завершение звонка «за кадром».
  Future<void> _virtualCallControl(SceneRunInfo info, SceneAction action) async {
    final ref = action.params['refActionId'] as String;
    final call = _virtualCalls[ref]!;
    if (action.type == ActionType.acceptCall) {
      if (call.acceptedAt != null) throw StateError('звонок уже принят');
      call.acceptedAt = services.engine.sceneNow() ?? DateTime.now();
      _record({'op': 'vunaccept', 'event': ref});
      return;
    }
    final CallOutcome outcome = action.type == ActionType.declineCall
        ? CallOutcome.declined
        : (call.acceptedAt != null ? CallOutcome.answered : CallOutcome.cancelled);
    final end = services.engine.sceneNow() ?? DateTime.now();
    final talked = call.acceptedAt == null ? Duration.zero : end.difference(call.acceptedAt!);
    final kind = call.video ? CallKind.video : CallKind.audio;
    Future<void> side(String device, String peer, CallDirection direction, CallOutcome o) async {
      final chat = await services.chats.openOrCreateDirect(deviceId: device, characterId: peer);
      await _touch(info, chat);
      final r = await writeCall(services,
          deviceId: device,
          peerId: peer,
          chatId: chat,
          direction: direction,
          kind: kind,
          outcome: o,
          startedAt: call.startedAt,
          talked: talked,
          sceneId: info.sceneId);
      _record({'op': 'deleteCall', 'id': r.callId});
      if (r.messageId.isNotEmpty) _record({'op': 'delete', 'id': r.messageId});
      if (r.unread) _record({'op': 'unreadDec', 'chatId': r.chatId});
    }

    if (call.fromDevice != null) await side(call.fromDevice!, call.to, CallDirection.outgoing, outcome);
    if (call.toDevice != null) {
      await side(call.toDevice!, call.from, CallDirection.incoming, mirrorOutcome(CallDirection.outgoing, outcome));
    }
    _virtualCalls.remove(ref);
    _finishedCalls[ref] = call;
    _record({'op': 'vreopen', 'event': ref});
  }

  _EventNotification? _lastEvent;

  Future<void> _showEvent() async {
    final event = _lastEvent;
    if (event == null) return;
    await services.notifications.showEvent(
      id: event.id,
      title: event.title,
      text: event.text,
      time: event.time,
      chatId: event.chatId,
    );
  }

  Future<void> _startCall(SceneRunInfo info, SceneAction action) async {
    final target = await _target(info, action);
    final contact = await services.contacts.view(info.deviceId, target.peerId);
    if (contact == null) throw StateError('участник не найден');
    final character = contact.character;
    Future<String?> path(String? id) async =>
        id == null ? null : (await services.media.repository.byId(id))?.path;
    final type = action.type;
    final started = services.callEngine.start(CallSession(
      deviceId: info.deviceId,
      characterId: target.peerId,
      direction: type == ActionType.incomingAudioCall || type == ActionType.incomingVideoCall
          ? CallDirection.incoming
          : CallDirection.outgoing,
      kind: type == ActionType.incomingVideoCall || type == ActionType.outgoingVideoCall
          ? CallKind.video
          : CallKind.audio,
      displayName: contact.shownName,
      chatId: target.chatId,
      sceneId: info.sceneId,
      avatarTone: character.avatarTone,
      avatarPath: contact.avatarPath,
      peerAudioPath: await path(character.callAudioMediaId),
      peerVideoPath: await path(character.callVideoMediaId),
    ));
    if (!started) throw StateError('уже идёт другой звонок');
    _record({'op': 'call'});
  }

  /// Исходящее «по-настоящему»: часы → галочка → две → прочитано.
  Future<bool> _isRead(String id) async => (await services.messages.byId(id))?.state == MessageState.read;

  /// Статусы отправки: отправлено → доставлено → (если разрешено) прочитано.
  /// [allowRead] false — «Прочитано: OFF»: дальше «доставлено» сообщение не
  /// идёт; а если ответ контакта уже прочитал его, статус не откатывается.
  Future<void> _trackMessageState(String id, SceneAction action, bool Function() cancelled, {bool allowRead = true}) async {
    try {
      await _wait(700, cancelled);
      if (cancelled() || await _isRead(id)) return;
      await services.messages.setState(id, MessageState.sent);
      await _wait(_int(action, 'deliverMs', 1200), cancelled);
      if (cancelled() || await _isRead(id)) return;
      await services.messages.setState(id, MessageState.delivered);
      final readMs = _int(action, 'readMs', 0);
      if (!allowRead || readMs <= 0) return;
      await _wait(readMs, cancelled);
      if (cancelled()) return;
      await services.messages.setState(id, MessageState.read);
    } catch (error) {
      debugPrint('Статус сообщения сцены не обновлён: $error');
    }
  }

  /// Применяет операции отмены в обратном порядке.
  /// [full] — сброс сцены: навигация не трогается, сообщения сцены
  /// удаляются одним запросом, счётчики берутся из снимков чатов.
  Future<void> _apply(List<Map<String, Object?>> ops, {required bool full}) async {
    for (final op in ops.reversed) {
      final id = op['id'] as String?;
      final kind = op['op'] as String? ?? (op.containsKey('deleted') ? 'deletedLegacy' : 'state');
      try {
        switch (kind) {
          case 'delete':
            if (!full && id != null) await services.messages.delete(id);
          case 'state':
            final state = MessageState.values.where((s) => s.name == op['state']);
            if (id != null && state.isNotEmpty) await services.messages.setState(id, state.first);
          case 'hold':
            if (id != null) await services.messages.setReadHold(id, op['value'] == true);
          case 'deleted':
            if (id != null) await services.messages.setDeleted(id, op['value'] == true);
          case 'text':
            if (id != null) {
              await services.messages.updateText(id, op['text'] as String? ?? '', edited: op['edited'] == true);
            }
          case 'deletedLegacy':
            if (id != null) await services.messages.setDeleted(id, op['deleted'] == true);
          case 'unreadDec':
            if (!full) await services.chats.decrementUnread(op['chatId'] as String);
          case 'typing':
            services.typing.stop(op['chatId'] as String);
          case 'audio':
            await services.audio.stop();
          case 'navBack':
            if (!full) AppNavigator.back();
          case 'call':
            services.callEngine.dismiss();
          case 'notif':
            await services.notifications.cancel((op['id'] as num).toInt());
          case 'chatNotif':
            await services.notifications.clearChat(op['chatId'] as String);
          case 'deleteChat':
            if (id != null) await services.chats.delete(id);
          case 'deleteCall':
            if (!full && id != null) await services.calls.deleteById(id);
          case 'forgetEvent':
            _eventMessages.remove(op['event']);
            _eventOutgoing.remove(op['event']);
          case 'unpend':
            _eventPending.remove(op['event']);
          case 'repend':
            final event = op['event'] as String;
            _eventPending[event] = (
              device: op['device'] as String,
              from: op['from'] as String,
              to: op['to'] as String,
              text: op['text'] as String,
            );
            _eventMessages[event]?.remove(op['id']);
          case 'vcall':
            _virtualCalls.remove(op['event']);
          case 'vunaccept':
            _virtualCalls[op['event']]?.acceptedAt = null;
          case 'vreopen':
            final call = _finishedCalls.remove(op['event']);
            if (call != null) _virtualCalls[op['event'] as String] = call;
          case 'removeMember':
            await services.chats.removeMember(op['chatId'] as String, op['characterId'] as String, forget: true);
          case 'addMember':
            await services.chats.addMember(op['chatId'] as String, op['characterId'] as String);
        }
      } catch (error) {
        debugPrint('Операция отмены не выполнена ($kind): $error');
      }
    }
  }

  @override
  Future<void> undoLast(SceneRunInfo info) async {
    if (_steps.isEmpty) return;
    final step = _steps.removeLast();
    await _apply(step, full: false);
    await _saveLog();
  }

  @override
  Future<void> endTake(SceneRunInfo info, {required bool completed}) async {
    final id = _takeId;
    if (id != null) {
      await _saveLog();
      await services.scenes.finishTake(id, completed ? TakeStatus.finished : TakeStatus.aborted);
    }
    await services.scenes.setStatus(info.sceneId, SceneStatus.finished);
  }

  @override
  Future<void> markTake(SceneRunInfo info, TakeStatus status) async {
    final take = await services.scenes.lastTake(info.sceneId);
    if (take != null) await services.scenes.finishTake(take.id, status);
  }

  @override
  Future<void> reset(SceneRunInfo info, {bool restoreScreen = false}) async {
    for (final chatId in info.chatIds) {
      services.typing.stop(chatId);
    }
    await services.audio.stop();
    if (services.callEngine.session?.sceneId == info.sceneId) services.callEngine.dismiss();
    await services.calls.deleteScene(info.sceneId);

    // Журнал: из памяти, а после перезапуска приложения — из базы.
    var snapshots = {for (final e in _snapshots.entries) e.key: Map<String, Object?>.from(e.value)};
    var steps = [for (final step in _steps) List<Map<String, Object?>>.from(step)];
    var openChat = _openChatAtStart;
    final last = await services.scenes.lastTake(info.sceneId);
    Map<String, Object?> storedLog = const {};
    if (last != null) storedLog = decodeJsonMap(last.logJson);
    final alreadyReset = storedLog['reset'] == true;

    if (_takeId == null && last != null && !alreadyReset) {
      List<Map<String, Object?>> ops(Object? list) => [
            for (final entry in (list as List?) ?? const [])
              if (entry is Map) Map<String, Object?>.from(entry),
          ];
      snapshots = {};
      final stored = storedLog['snapshots'];
      if (stored is Map) {
        for (final e in stored.entries) {
          if (e.value is Map) snapshots['${e.key}'] = Map<String, Object?>.from(e.value as Map);
        }
      }
      // Журнал сцены до многоконтактного режима: один снимок главного чата.
      final legacy = storedLog['snapshot'];
      if (legacy is Map && info.chatId != null) {
        snapshots[info.chatId!] = Map<String, Object?>.from(legacy);
      }
      steps = [
        for (final step in (storedLog['steps'] as List?) ?? const []) ops(step),
        if (storedLog['undo'] is List) ops(storedLog['undo']),
      ];
      openChat = storedLog['openChatAtStart'] as String? ??
          (storedLog['openAtStart'] == true ? info.chatId : null);
    }

    if (!alreadyReset || _takeId != null) {
      for (final step in steps.reversed) {
        await _apply(step, full: true);
      }
      for (final e in snapshots.entries) {
        await services.chats.restoreSnapshot(e.key, e.value);
        await services.notifications.clearChat(e.key);
      }
    }
    await services.messages.deleteSceneMessages(info.sceneId);

    if (last != null) {
      await services.scenes.saveTakeLog(last.id, {...storedLog, ..._takeId == null ? {} : _log, 'reset': true});
      if (last.status == TakeStatus.running) {
        await services.scenes.finishTake(last.id, TakeStatus.aborted);
      }
    }
    await services.scenes.setStatus(info.sceneId, SceneStatus.ready);
    _takeId = null;
    _progress = const {};
    _actionMessages.clear();
    _steps.clear();
    _snapshots.clear();
    _clearEvents();

    // Сброс «в кадре»: снова открыть чат, который был на экране в начале
    // дубля, с чистого листа (прокрутка, поле ввода, открытые сценой экраны).
    if (restoreScreen && openChat != null && info.chatIds.contains(openChat)) {
      AppNavigator.showInFrame(openChat);
    }
  }
}

/// «23:47» → сегодня в 23:47. Пустое или неверное значение — null.
DateTime? sceneClockStart(Object? value, DateTime today) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return DateTime(today.year, today.month, today.day, hour, minute);
}

/// Подпись вида сообщения для уведомления («Фото», «Голосовое сообщение»).
String messageTypeLabelFor(MessageType type) => messageTypeLabel(type);

/// Уведомление, показанное сценой (его можно изменить следующими действиями).
class _EventNotification {
  const _EventNotification({
    required this.id,
    required this.title,
    required this.text,
    required this.time,
    this.chatId,
  });

  final int id;
  final String title;
  final String text;
  final DateTime time;
  final String? chatId;

  _EventNotification copyWith({String? text, DateTime? time}) => _EventNotification(
        id: id,
        title: title,
        text: text ?? this.text,
        time: time ?? this.time,
        chatId: chatId,
      );
}

/// Звонок между профилями, которых нет на экране («за кадром»).
class _VirtualCall {
  _VirtualCall({
    required this.fromDevice,
    required this.toDevice,
    required this.from,
    required this.to,
    required this.video,
    required this.startedAt,
  });

  final String? fromDevice;
  final String? toDevice;
  final String from;
  final String to;
  final bool video;
  final DateTime startedAt;
  DateTime? acceptedAt;
}
