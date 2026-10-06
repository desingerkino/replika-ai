import 'dart:async';

import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/util/ids.dart';
import '../../data/models/media_item.dart';
import '../../data/models/message.dart';
import '../../data/models/scene_action.dart';
import '../../data/repositories/contact_repository.dart';
import '../protocol/protocol.dart';
import '../queue/command_queue.dart';
import '../scene/connect_scene.dart';
import 'media_upload.dart';

typedef _Handler = Future<Map<String, Object?>> Function(Map<String, Object?> payload, CancelToken cancel);

/// Неудача последовательности: ответ содержит результаты всех шагов.
class SequenceFailure implements Exception {
  const SequenceFailure(this.code, this.message, this.steps);

  final String code;
  final String message;
  final List<Map<String, Object?>> steps;
}

/// Команды Connect → действия существующего Messenger.
///
/// Каждый ActionType — отдельный обработчик в таблице (не цепочка if/else).
/// Персонаж и физический телефон — разные сущности: телефон показывает мир
/// глазами владельца своего текущего виртуального телефона. Кто владелец,
/// Controller назначает командой ASSIGN_CHARACTER.
class ConnectActions implements CommandExecutor {
  ConnectActions(this.services, {required this.deviceInfo}) : scene = ConnectScene(services) {
    _handlers = {
      ConnectAction.ping: _ping,
      ConnectAction.deviceInfo: (_, __) => deviceInfo(),
      ConnectAction.listCharacters: _listCharacters,
      ConnectAction.listMedia: _listMedia,
      ConnectAction.listGroups: _listGroups,
      ConnectAction.createChat: _createGroup,
      ConnectAction.addParticipant: (p, c) => _groupMember(p, c, add: true),
      ConnectAction.removeParticipant: (p, c) => _groupMember(p, c, add: false),
      ConnectAction.assignCharacter: _assignCharacter,
      ConnectAction.setContact: _setContact,
      ConnectAction.message: (p, c) => _withTime(p, c, _message),
      ConnectAction.typing: _typing,
      ConnectAction.media: (p, c) => _withTime(p, c, _media),
      ConnectAction.deleteMessage: (p, c) => _messageEdit(p, c, ActionType.deleteMessage),
      ConnectAction.editMessage: (p, c) => _messageEdit(p, c, ActionType.editMessage),
      ConnectAction.messageStatus: (p, c) => _messageEdit(p, c, ActionType.setMessageState),
      ConnectAction.call: (p, c) => _call(p, c, video: false),
      ConnectAction.videoCall: (p, c) => _call(p, c, video: true),
      ConnectAction.callAccept: (p, c) => _callControl(p, c, ActionType.acceptCall),
      ConnectAction.callDecline: (p, c) => _callControl(p, c, ActionType.declineCall),
      ConnectAction.endCall: (p, c) => _callControl(p, c, ActionType.endCall),
      ConnectAction.notification: _notification,
      ConnectAction.openScreen: _openScreen,
      ConnectAction.delay: _delay,
      ConnectAction.sequence: _sequence,
      ConnectAction.resetScene: _reset,
      // Управление ходом сцены: Connect → PropControllerInput → слой команд.
      ConnectAction.sceneNext: (p, c) => services.propInput.handle(ConnectAction.sceneNext),
      ConnectAction.scenePrevious: (p, c) => services.propInput.handle(ConnectAction.scenePrevious),
      ConnectAction.sceneStop: (p, c) => services.propInput.handle(ConnectAction.sceneStop),
      // Подготовка с пульта (Connect 1.3)
      ConnectAction.upsertCharacter: _upsertCharacter,
      ConnectAction.mediaUploadBegin: (p, c) => _uploads.begin(p),
      ConnectAction.mediaUploadChunk: (p, c) => _uploads.chunk(p),
      ConnectAction.mediaUploadCommit: (p, c) => _uploads.commit(p),
    };
  }

  final AppServices services;
  final ConnectScene scene;

  /// Сведения о телефоне (их собирает ConnectService).
  final Future<Map<String, Object?>> Function() deviceInfo;

  late final Map<ConnectAction, _Handler> _handlers;

  /// Приём файлов с пульта (MEDIA_UPLOAD_*).
  late final MediaUploads _uploads = MediaUploads(services);

  @override
  Future<CommandResult> execute(CommandRequest request, CancelToken cancel) async {
    final action = request.action;
    if (action == null) {
      return CommandResult.error(
          request.commandId, ConnectError.invalidCommand, 'Неизвестный actionType «${request.actionType}»');
    }
    if (!action.supported) {
      return CommandResult.error(
        request.commandId,
        ConnectError.unsupportedAction,
        action.scope == ConnectScope.groups
            ? 'Group actions are not implemented yet'
            : 'Действие не поддерживается этой версией Messenger',
      );
    }
    final handler = _handlers[action];
    if (handler == null) {
      return CommandResult.error(request.commandId, ConnectError.unsupportedAction, 'Нет обработчика');
    }
    try {
      return CommandResult.ok(request.commandId, await handler(request.payload, cancel));
    } on SequenceFailure catch (f) {
      return CommandResult(
        commandId: request.commandId,
        success: false,
        status: f.code == ConnectError.cancelled ? CommandStatus.cancelled : CommandStatus.failed,
        error: f.code,
        message: f.message,
        result: {'steps': f.steps},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  @override
  Future<void> stopAll() async {
    services.typing.stopAll();
    await services.audio.stop();
  }

  // ---------- Проверка параметров ----------

  static String _str(Map<String, Object?> p, String key, {bool required = true, int max = ConnectLimits.textLength}) {
    final v = p[key];
    if (v == null && !required) return '';
    if (v is! String || (required && v.trim().isEmpty)) {
      throw ConnectException(ConnectError.invalidRequest, 'нужен параметр «$key» (непустая строка)');
    }
    if (v.length > max) throw ConnectException(ConnectError.invalidRequest, '«$key» длиннее $max символов');
    return v.trim();
  }

  static int _int(Map<String, Object?> p, String key, int fallback, {int min = 0, int max = ConnectLimits.delayMs}) {
    final v = p[key];
    if (v == null) return fallback;
    if (v is! num) throw ConnectException(ConnectError.invalidRequest, '«$key» должен быть числом');
    final n = v.toInt();
    if (n < min || n > max) throw ConnectException(ConnectError.invalidRequest, '«$key» вне диапазона $min…$max');
    return n;
  }

  static String? _optId(Map<String, Object?> p, String key) {
    final v = p[key];
    if (v == null) return null;
    if (v is! String || v.isEmpty || v.length > 128) {
      throw ConnectException(ConnectError.invalidRequest, '«$key» должен быть идентификатором');
    }
    return v;
  }

  Future<String> _owner() async {
    final device = await services.devices.byId(services.currentDeviceId.value);
    if (device == null) throw const ConnectException(ConnectError.deviceNotReady, 'Телефон не настроен');
    return device.ownerCharacterId;
  }

  /// Персонаж должен существовать в проекте Messenger.
  Future<void> _requireCharacter(String id) async {
    final all = await services.contacts.allCharacters();
    if (!all.any((c) => c.id == id)) {
      throw ConnectException(ConnectError.invalidTarget, 'Персонаж «$id» не найден (см. LIST_CHARACTERS)');
    }
  }

  /// «Кто кому» → участник сцены и направление глазами владельца телефона.
  Future<({String participant, bool incoming})> _direction(Map<String, Object?> p) async {
    final from = _str(p, 'fromCharacterId', max: 128);
    final to = _str(p, 'toCharacterId', max: 128);
    await _requireCharacter(from);
    await _requireCharacter(to);
    final owner = await _owner();
    if (from == to) throw const ConnectException(ConnectError.invalidTarget, 'Отправитель и получатель совпадают');
    if (to == owner) return (participant: from, incoming: true);
    if (from == owner) return (participant: to, incoming: false);
    throw const ConnectException(
      ConnectError.invalidTarget,
      'Ни отправитель, ни получатель не владелец этого телефона. '
      'Назначьте персонажа телефону командой ASSIGN_CHARACTER (переписка третьих лиц — только в группах, их пока нет)',
    );
  }

  SceneAction _action(ActionType type, String? characterId, Map<String, Object?> params) {
    final now = DateTime.now();
    return SceneAction(
      id: newId(),
      sceneId: scene.sceneId,
      position: 0,
      typeName: type.name,
      params: {if (characterId != null) 'characterId': characterId, ...params},
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Map<String, Object?>> _run(SceneAction action, CancelToken cancel, {Iterable<String> extra = const []}) async {
    final messageId = await scene.run(action, cancel: cancel, extra: extra);
    return {'sceneId': scene.sceneId, if (messageId != null) 'messageId': messageId};
  }

  // ---------- Группы ----------

  static final RegExp _groupKey = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

  /// Ключ группы от Controller («crew») → id чата на этом телефоне.
  /// Один и тот же ключ работает на всех телефонах. Группы, созданные
  /// вручную на телефоне, доступны по их id из LIST_GROUPS.
  Future<String> _groupChat(String key) async {
    final deviceId = services.currentDeviceId.value;
    final header = await services.chats.header(key);
    if (header != null && header.chat.isGroup && header.chat.deviceId == deviceId) return key;
    if (!_groupKey.hasMatch(key)) {
      throw const ConnectException(ConnectError.invalidRequest, 'groupId: латиница, цифры, «_» или «-», до 64 символов');
    }
    return 'grp:$deviceId:$key';
  }

  Future<String> _existingGroup(Map<String, Object?> p) async {
    final id = await _groupChat(_str(p, 'groupId', max: 128));
    final header = await services.chats.header(id);
    if (header == null || !header.chat.isGroup) {
      throw const ConnectException(ConnectError.invalidTarget, 'Группа не найдена на этом телефоне (см. LIST_GROUPS)');
    }
    return id;
  }

  Future<void> _requireMember(String chatId, String characterId) async {
    if (!await services.chats.isMember(chatId, characterId)) {
      throw ConnectException(ConnectError.invalidTarget, '«$characterId» не состоит в группе');
    }
  }

  Future<Map<String, Object?>> _listGroups(Map<String, Object?> p, CancelToken c) async {
    final deviceId = services.currentDeviceId.value;
    final prefix = 'grp:$deviceId:';
    return {
      'groups': [
        for (final g in await services.chats.groupsForDevice(deviceId))
          {
            'groupId': g.id.startsWith(prefix) ? g.id.substring(prefix.length) : g.id,
            'title': g.title,
            'members': [for (final m in await services.chats.members(g.id)) m.characterId],
          },
      ],
    };
  }

  Future<Map<String, Object?>> _createGroup(Map<String, Object?> p, CancelToken c) async {
    final key = _str(p, 'groupId', max: 64);
    final title = _str(p, 'title', max: 80);
    final raw = p['memberIds'];
    if (raw is! List || raw.isEmpty || raw.any((m) => m is! String)) {
      throw const ConnectException(ConnectError.invalidRequest, 'memberIds: непустой список characterId');
    }
    final members = raw.cast<String>().toSet();
    for (final m in members) {
      await _requireCharacter(m);
    }
    final creator = _optId(p, 'fromCharacterId');
    if (creator != null) await _requireCharacter(creator);
    final chatId = await _groupChat(key);
    if (await services.chats.header(chatId) != null) {
      throw const ConnectException(ConnectError.invalidTarget, 'Группа с таким groupId уже есть на этом телефоне');
    }
    final result = await _run(
      _action(ActionType.createGroup, creator, {'groupId': chatId, 'title': title, 'members': members.toList()}),
      c,
      extra: members,
    );
    return {...result, 'groupId': key, 'chatId': chatId};
  }

  Future<Map<String, Object?>> _groupMember(Map<String, Object?> p, CancelToken c, {required bool add}) async {
    final chatId = await _existingGroup(p);
    final member = _str(p, 'characterId', max: 128);
    await _requireCharacter(member);
    final by = _optId(p, 'byCharacterId');
    if (by != null) {
      await _requireCharacter(by);
      await _requireMember(chatId, by);
    }
    final isMember = await services.chats.isMember(chatId, member);
    if (add && isMember) throw const ConnectException(ConnectError.invalidTarget, 'Уже состоит в группе');
    if (!add && !isMember) throw const ConnectException(ConnectError.invalidTarget, 'Не состоит в группе');
    return _run(
      _action(add ? ActionType.addGroupMember : ActionType.removeGroupMember, by, {'groupId': chatId, 'memberId': member}),
      c,
      extra: [member],
    );
  }

  /// Сообщение в группу: от участника — входящее, от владельца — исходящее.
  Future<({String chatId, String sender, bool incoming})> _groupDirection(Map<String, Object?> p) async {
    final chatId = await _existingGroup(p);
    final from = _str(p, 'fromCharacterId', max: 128);
    await _requireCharacter(from);
    await _requireMember(chatId, from);
    return (chatId: chatId, sender: from, incoming: from != await _owner());
  }

  // ---------- Служебные ----------

  Future<Map<String, Object?>> _ping(Map<String, Object?> p, CancelToken c) async => {
        'pong': true,
        'deviceTime': DateTime.now().millisecondsSinceEpoch,
        if (p['sentAt'] is int) 'sentAt': p['sentAt'],
      };

  Future<Map<String, Object?>> _listCharacters(Map<String, Object?> p, CancelToken c) async {
    final deviceId = services.currentDeviceId.value;
    final owner = await _owner();
    final contacts = {for (final c in await services.contacts.forDevice(deviceId)) c.id: c.displayName};
    return {
      'characters': [
        for (final ch in await services.contacts.allCharacters())
          {
            'characterId': ch.id,
            'firstName': ch.firstName,
            'lastName': ch.lastName,
            'phone': ch.phone,
            'contactName': contacts[ch.id],
            'isOwner': ch.id == owner,
          },
      ],
    };
  }

  Future<Map<String, Object?>> _listMedia(Map<String, Object?> p, CancelToken c) async => {
        'media': [
          for (final m in await services.media.repository.list())
            {
              'mediaId': m.id,
              'kind': m.kind.name,
              'name': m.originalName ?? m.kind.label,
              if (m.durationMs != null) 'durationMs': m.durationMs,
            },
        ],
      };

  /// Назначить телефону персонажа: телефон показывает мир его глазами.
  /// Виртуальный телефон персонажа создаётся при необходимости.
  Future<Map<String, Object?>> _assignCharacter(Map<String, Object?> p, CancelToken c) async {
    final id = _str(p, 'characterId', max: 128);
    await _requireCharacter(id);
    if (services.engine.hasTake && services.engine.info?.sceneId != scene.sceneId) {
      throw const ConnectException(ConnectError.deviceNotReady, 'Идёт дубль сцены в операторской');
    }
    // У Connect своя сцена на каждый профиль: дубль прежнего профиля
    // завершается (его данные остаются и сбрасываются на том профиле).
    if (services.engine.info?.sceneId == scene.sceneId) await services.engine.stop();
    final devices = await services.devices.list();
    var target = devices.where((d) => d.ownerCharacterId == id).firstOrNull?.id;
    if (target == null) {
      final character = (await services.contacts.allCharacters()).firstWhere((ch) => ch.id == id);
      final name = character.firstName.isEmpty ? character.fullName : character.firstName;
      target = await services.devices.create(name: 'Телефон: $name', ownerCharacterId: id);
    }
    await services.setCurrentDevice(target);
    return deviceInfo();
  }

  /// Как персонаж записан в контактах этого телефона («Мама», «Красотка»).
  Future<Map<String, Object?>> _setContact(Map<String, Object?> p, CancelToken c) async {
    final id = _str(p, 'characterId', max: 128);
    final name = _str(p, 'displayName', max: 100);
    final deviceId = services.currentDeviceId.value;
    final view = await services.contacts.view(deviceId, id);
    if (view == null) throw ConnectException(ConnectError.invalidTarget, 'Персонаж «$id» не найден');
    final ch = view.character;
    await services.contacts.save(
      deviceId: deviceId,
      characterId: id,
      displayName: name,
      draft: CharacterDraft(
        firstName: ch.firstName,
        lastName: ch.lastName,
        phone: ch.phone,
        statusText: ch.statusText,
        tone: ch.avatarTone,
        description: ch.description,
        avatarMediaId: ch.avatarMediaId,
        callAudioMediaId: ch.callAudioMediaId,
        callVideoMediaId: ch.callVideoMediaId,
      ),
    );
    return {'characterId': id, 'contactName': name};
  }

  // ---------- Подготовка с пульта (Connect 1.3) ----------

  static final RegExp _characterKey = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

  /// Создать или обновить персонажа по ключу пульта («masha»). Меняются
  /// только переданные поля. Ключ одинаков на всех телефонах, поэтому
  /// «Маша» везде — один и тот же characterId.
  ///
  /// Персонаж — подготовка, а не событие сцены: RESET_SCENE его не удаляет.
  /// Контакты — на текущем профиле телефона: `contactName` — как записан
  /// («Мама»); без него новый контакт записывается по имени;
  /// `addToContacts: false` — не в контактах (в чате виден номер).
  Future<Map<String, Object?>> _upsertCharacter(Map<String, Object?> p, CancelToken c) async {
    final id = _str(p, 'characterId', max: 64);
    if (!_characterKey.hasMatch(id)) {
      throw const ConnectException(
          ConnectError.invalidRequest, 'characterId: латиница, цифры, «_» или «-», до 64 символов');
    }
    String field(String key, String current, int max) =>
        p.containsKey(key) ? _str(p, key, required: false, max: max) : current;

    final existing = (await services.contacts.allCharacters()).where((ch) => ch.id == id).firstOrNull;
    final firstName = field('firstName', existing?.firstName ?? '', 80);
    final lastName = field('lastName', existing?.lastName ?? '', 80);
    if (firstName.isEmpty && lastName.isEmpty) {
      throw const ConnectException(ConnectError.invalidRequest, 'нужно имя персонажа (firstName)');
    }
    var avatar = existing?.avatarMediaId;
    if (p.containsKey('avatarMediaId')) {
      if (p['avatarMediaId'] == null) {
        avatar = null;
      } else {
        final mediaId = _str(p, 'avatarMediaId', max: 128);
        final media = await services.media.repository.byId(mediaId);
        if (media == null || media.kind != MediaKind.photo) {
          throw ConnectException(ConnectError.invalidTarget, 'Фото «$mediaId» не найдено на телефоне (MEDIA_UPLOAD_*)');
        }
        avatar = mediaId;
      }
    }

    final deviceId = services.currentDeviceId.value;
    final isOwner = (await services.devices.byId(deviceId))?.ownerCharacterId == id;
    final hideContact = p['addToContacts'] == false;
    String? contactName;
    if (!isOwner && !hideContact) {
      final given = p.containsKey('contactName') ? _str(p, 'contactName', required: false, max: 100) : '';
      final listed = (await services.contacts.forDevice(deviceId)).any((ct) => ct.id == id);
      if (given.isNotEmpty) {
        contactName = given;
      } else if (!listed) {
        contactName = '$firstName $lastName'.trim();
      }
    }

    final created = await services.contacts.ensureCharacter(id);
    await services.contacts.save(
      deviceId: deviceId,
      characterId: id,
      displayName: contactName,
      draft: CharacterDraft(
        firstName: firstName,
        lastName: lastName,
        phone: field('phone', existing?.phone ?? '', 40),
        statusText: field('statusText', existing?.statusText ?? '', 140),
        tone: existing?.avatarTone,
        description: field('description', existing?.description ?? '', 1000),
        avatarMediaId: avatar,
        callAudioMediaId: existing?.callAudioMediaId,
        callVideoMediaId: existing?.callVideoMediaId,
      ),
    );
    if (hideContact && !isOwner) await services.contacts.removeFromDevice(deviceId, id);
    return {
      'characterId': id,
      'created': created,
      'isOwner': isOwner,
      if (contactName != null) 'contactName': contactName,
    };
  }

  /// Connect 1.3: `messageTime` — какое время показать у сообщения
  /// (мс с 1970-01-01 UTC, например «23:47» в кадре). Без него — время
  /// по часам телефона (или «время в кадре» сцены).
  Future<Map<String, Object?>> _withTime(Map<String, Object?> p, CancelToken c, _Handler handler) async {
    final raw = p['messageTime'];
    DateTime? at;
    if (raw != null) {
      if (raw is! int || raw <= 0) {
        throw const ConnectException(ConnectError.invalidRequest, 'messageTime — число (мс с 1970-01-01 UTC)');
      }
      at = DateTime.fromMillisecondsSinceEpoch(raw);
    }
    final result = await handler(p, c);
    final messageId = result['messageId'];
    if (at != null && messageId is String) await services.messages.setSentAt(messageId, at);
    return result;
  }

  // ---------- Сообщения ----------

  Future<Map<String, Object?>> _message(Map<String, Object?> p, CancelToken c) async {
    final text = _str(p, 'text');
    if (p['groupId'] != null) {
      final g = await _groupDirection(p);
      return _run(
        _action(g.incoming ? ActionType.showIncoming : ActionType.showOutgoing, g.sender, {
          'groupId': g.chatId,
          'text': text,
          if (g.incoming) 'typingMs': _int(p, 'typingMs', 0, max: 60000),
          if (!g.incoming) 'state': _state(p['state']) ?? MessageState.read.name,
        }),
        c,
      );
    }
    final d = await _direction(p);
    final typingMs = _int(p, 'typingMs', 0, max: 60000);
    final ActionType type;
    if (d.incoming) {
      type = ActionType.showIncoming;
    } else {
      type = p['delivery'] == true ? ActionType.sendMessage : ActionType.showOutgoing;
    }
    return _run(
      _action(type, d.participant, {
        'text': text,
        if (d.incoming) 'typingMs': typingMs,
        if (!d.incoming) 'state': _state(p['state']) ?? MessageState.read.name,
      }),
      c,
    );
  }

  static String? _state(Object? v) {
    if (v == null) return null;
    for (final s in MessageState.values) {
      if (s.name == v || s.name.toUpperCase() == v) return s.name;
    }
    throw const ConnectException(ConnectError.invalidRequest, 'state: SENDING, SENT, DELIVERED, READ или FAILED');
  }

  Future<Map<String, Object?>> _typing(Map<String, Object?> p, CancelToken c) async {
    final from = _str(p, 'fromCharacterId', max: 128);
    await _requireCharacter(from);
    if (p['groupId'] != null) {
      final g = await _groupDirection(p);
      return _run(
        _action(ActionType.startTyping, g.sender,
            {'groupId': g.chatId, 'durationMs': _int(p, 'durationMs', 4000, min: 500, max: 120000)}),
        c,
      );
    }
    if (from == await _owner()) {
      throw const ConnectException(ConnectError.invalidTarget, '«Печатает…» показывается для собеседника, не для владельца');
    }
    final ms = _int(p, 'durationMs', 4000, min: 500, max: 120000);
    return _run(_action(ActionType.startTyping, from, {'durationMs': ms}), c);
  }

  Future<Map<String, Object?>> _media(Map<String, Object?> p, CancelToken c) async {
    final mediaId = _str(p, 'mediaId', max: 128);
    final media = await services.media.repository.byId(mediaId);
    if (media == null) throw ConnectException(ConnectError.invalidTarget, 'Медиа «$mediaId» не найдено (см. LIST_MEDIA)');
    final type = switch (media.kind) {
      MediaKind.photo => ActionType.showPhoto,
      MediaKind.video => ActionType.showVideo,
      MediaKind.voice || MediaKind.audio => ActionType.showVoice,
      MediaKind.videoNote => ActionType.showVideoNote,
      MediaKind.file => null,
    };
    if (type == null) {
      throw const ConnectException(ConnectError.unsupportedAction, 'Файлы как сообщения пока не поддерживаются');
    }
    if (p['groupId'] != null) {
      final g = await _groupDirection(p);
      return _run(
        _action(type, g.sender, {
          'groupId': g.chatId,
          'mediaId': media.id,
          'mediaName': media.originalName ?? media.kind.label,
          'direction': g.incoming ? 'in' : 'out',
          'caption': _str(p, 'caption', required: false),
          if (g.incoming) 'typingMs': _int(p, 'typingMs', 0, max: 60000),
        }),
        c,
      );
    }
    final d = await _direction(p);
    return _run(
      _action(type, d.participant, {
        'mediaId': media.id,
        'mediaName': media.originalName ?? media.kind.label,
        'direction': d.incoming ? 'in' : 'out',
        'caption': _str(p, 'caption', required: false),
        if (d.incoming) 'typingMs': _int(p, 'typingMs', 0, max: 60000),
      }),
      c,
    );
  }

  /// Удалить / изменить / сменить статус: по messageId или последнее
  /// сообщение в чате с участником.
  Future<Map<String, Object?>> _messageEdit(Map<String, Object?> p, CancelToken c, ActionType type) async {
    final messageId = _optId(p, 'messageId');
    var participant = _optId(p, 'characterId');
    if (messageId != null) {
      final message = await services.messages.byId(messageId);
      if (message == null) throw ConnectException(ConnectError.invalidTarget, 'Сообщение «$messageId» не найдено');
      final header = await services.chats.header(message.chatId);
      if (header == null || header.chat.deviceId != services.currentDeviceId.value) {
        throw const ConnectException(ConnectError.invalidTarget, 'Сообщение не на этом телефоне');
      }
      if (header.chat.isGroup) {
        return _run(
          _action(type, message.senderId ?? await _owner(), {
            'groupId': header.chat.id,
            'messageId': messageId,
            if (type == ActionType.editMessage) 'text': _str(p, 'text'),
            if (type == ActionType.setMessageState) 'state': _state(p['state']) ?? MessageState.read.name,
          }),
          c,
        );
      }
      participant ??= header.chat.peerCharacterId;
    }
    if (participant == null) {
      throw const ConnectException(ConnectError.invalidRequest, 'нужен characterId (участник чата) или messageId');
    }
    await _requireCharacter(participant);
    final target = p['target'];
    if (target != null && target != 'lastIncoming' && target != 'lastOutgoing' && target != 'last') {
      throw const ConnectException(ConnectError.invalidRequest, 'target: lastIncoming, lastOutgoing или last');
    }
    return _run(
      _action(type, participant, {
        if (messageId != null) 'messageId': messageId,
        if (target != null) 'target': target,
        if (type == ActionType.editMessage) 'text': _str(p, 'text'),
        if (type == ActionType.setMessageState) 'state': _state(p['state']) ?? MessageState.read.name,
      }),
      c,
    );
  }

  // ---------- Звонки ----------

  Future<Map<String, Object?>> _call(Map<String, Object?> p, CancelToken c, {required bool video}) async {
    final d = await _direction(p);
    final type = switch ((d.incoming, video)) {
      (true, false) => ActionType.incomingAudioCall,
      (true, true) => ActionType.incomingVideoCall,
      (false, false) => ActionType.outgoingAudioCall,
      (false, true) => ActionType.outgoingVideoCall,
    };
    return _run(_action(type, d.participant, const {}), c);
  }

  Future<Map<String, Object?>> _callControl(Map<String, Object?> p, CancelToken c, ActionType type) async {
    final session = services.callEngine.session;
    if (session == null || !services.callEngine.inCall) {
      throw const ConnectException(ConnectError.invalidTarget, 'Сейчас нет звонка');
    }
    final who = _optId(p, 'characterId');
    if (who != null && who != session.characterId) {
      throw const ConnectException(ConnectError.invalidTarget, 'Звонок идёт с другим персонажем');
    }
    return _run(_action(type, session.characterId, const {}), c);
  }

  // ---------- Уведомления и экраны ----------

  Future<Map<String, Object?>> _notification(Map<String, Object?> p, CancelToken c) async {
    final from = _str(p, 'fromCharacterId', max: 128);
    await _requireCharacter(from);
    return _run(
      _action(ActionType.postNotification, from, {
        'text': _str(p, 'text'),
        'title': _str(p, 'title', required: false, max: 100),
      }),
      c,
    );
  }

  Future<Map<String, Object?>> _openScreen(Map<String, Object?> p, CancelToken c) async {
    final screen = ConnectScreen.parse(p['screen']);
    if (screen == null) {
      throw const ConnectException(
          ConnectError.invalidRequest, 'screen: CHAT, CHAT_LIST, PROFILE, BACK, CALLS или CONTACTS');
    }
    switch (screen) {
      case ConnectScreen.chatList:
      case ConnectScreen.calls:
      case ConnectScreen.contacts:
        AppNavigator.toRoot();
        AppNavigator.homeTab.value = switch (screen) {
          ConnectScreen.calls => 1,
          ConnectScreen.contacts => 2,
          _ => 0,
        };
        return {'screen': screen.wire};
      case ConnectScreen.back:
        return _run(_action(ActionType.navigateBack, null, const {}), c);
      case ConnectScreen.chat when p['groupId'] != null:
        // Connect 1.3: групповой чат по groupId.
        final chatId = await _existingGroup(p);
        return {
          ...await _run(_action(ActionType.openChat, null, {'groupId': chatId}), c),
          'screen': screen.wire,
          'groupId': p['groupId'],
        };
      case ConnectScreen.chat:
      case ConnectScreen.profile:
        final who = _str(p, 'characterId', max: 128);
        await _requireCharacter(who);
        if (who == await _owner()) {
          throw const ConnectException(ConnectError.invalidTarget, 'Это владелец телефона — у него нет чата с самим собой');
        }
        return _run(
          _action(screen == ConnectScreen.chat ? ActionType.openChat : ActionType.openProfile, who, const {}),
          c,
        );
    }
  }

  // ---------- Время и последовательности ----------

  Future<Map<String, Object?>> _delay(Map<String, Object?> p, CancelToken c) async {
    final ms = _int(p, 'ms', 0, max: ConnectLimits.delayMs);
    var left = ms;
    while (left > 0) {
      if (c.cancelled) throw const ConnectException(ConnectError.cancelled, 'Пауза прервана (STOP)');
      final step = left < 50 ? left : 50;
      await Future<void>.delayed(Duration(milliseconds: step));
      left -= step;
    }
    return {'waitedMs': ms};
  }

  /// SEQUENCE: шаги выполняются по порядку тем же исполнителем.
  /// stopOnError (по умолчанию true) — остановиться на первой ошибке.
  Future<Map<String, Object?>> _sequence(Map<String, Object?> p, CancelToken c) async {
    final steps = sequenceSteps(p);
    final stopOnError = p['stopOnError'] != false;
    final results = <Map<String, Object?>>[];
    String? firstError;
    for (var i = 0; i < steps.length; i++) {
      if (c.cancelled) {
        throw SequenceFailure(ConnectError.cancelled, 'Последовательность остановлена (STOP) на шаге ${i + 1}', results);
      }
      final step = steps[i];
      final action = ConnectAction.parse(step['actionType']);
      final payload = step['payload'] is Map ? Map<String, Object?>.from(step['payload'] as Map) : <String, Object?>{};
      Map<String, Object?> entry;
      try {
        if (action == null) throw const ConnectException(ConnectError.invalidCommand, 'неизвестный actionType');
        if (!action.supported) {
          throw const ConnectException(ConnectError.unsupportedAction, 'Действие не поддерживается этой версией');
        }
        final handler = _handlers[action]!;
        final result = await handler(payload, c);
        entry = {'index': i, 'actionType': step['actionType'], 'success': true, 'result': result};
      } on ConnectException catch (e) {
        entry = {'index': i, 'actionType': step['actionType'], 'success': false, 'error': e.code, 'message': e.message};
        firstError ??= 'шаг ${i + 1}: ${e.message}';
        results.add(entry);
        if (e.code == ConnectError.cancelled) {
          throw SequenceFailure(ConnectError.cancelled, 'Последовательность остановлена (STOP)', results);
        }
        if (stopOnError) throw SequenceFailure(ConnectError.actionFailed, firstError, results);
        continue;
      }
      results.add(entry);
    }
    if (firstError != null) throw SequenceFailure(ConnectError.actionFailed, firstError, results);
    return {'steps': results};
  }

  Future<Map<String, Object?>> _reset(Map<String, Object?> p, CancelToken c) async {
    final done = await scene.reset();
    return {'sceneId': scene.sceneId, 'reset': done};
  }
}

/// Шаги SEQUENCE с проверкой формы (используется и сервером — для проверки
/// прав на каждый шаг до постановки в очередь).
List<Map<String, Object?>> sequenceSteps(Map<String, Object?> payload) {
  final raw = payload['steps'];
  if (raw is! List || raw.isEmpty) {
    throw const ConnectException(ConnectError.invalidRequest, 'steps: непустой список шагов');
  }
  if (raw.length > ConnectLimits.sequenceSteps) {
    throw const ConnectException(ConnectError.invalidRequest, 'Слишком много шагов (до ${ConnectLimits.sequenceSteps})');
  }
  final steps = <Map<String, Object?>>[];
  for (final s in raw) {
    if (s is! Map) throw const ConnectException(ConnectError.invalidRequest, 'шаг должен быть объектом');
    final action = ConnectAction.parse(s['actionType']);
    if (action == ConnectAction.sequence ||
        action == ConnectAction.stop ||
        action == ConnectAction.sceneNext ||
        action == ConnectAction.scenePrevious ||
        action == ConnectAction.sceneStop) {
      throw const ConnectException(
          ConnectError.invalidRequest, 'SEQUENCE, STOP и SCENE_NEXT/SCENE_PREVIOUS/SCENE_STOP нельзя вкладывать в SEQUENCE');
    }
    steps.add(Map<String, Object?>.from(s));
  }
  return steps;
}
