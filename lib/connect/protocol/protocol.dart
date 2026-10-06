/// Prop Control Protocol v1 — типизированные команды и ответы Connect.
///
/// Протокол не знает об экранах Messenger: команда говорит «что сделать»
/// (MESSAGE, CALL, OPEN_SCREEN…), а Messenger сам решает «как».
library;

/// Текущая версия протокола. Controller сверяет её в DEVICE_INFO.
const int protocolVersion = 1;

/// Версия реализации Connect на телефоне.
const String connectVersion = '1.3.0';

/// Порт по умолчанию.
const int defaultConnectPort = 47620;

/// Порт UDP для поиска телефонов в сети.
const int discoveryPort = 47621;

/// Метка протокола в UDP-пакетах поиска.
const String discoveryTag = 'replika-connect';

/// Путь WebSocket.
const String connectPath = '/connect';

/// Права доверенного устройства. В C1 выдаются все; архитектура позволяет
/// выдавать выборочно без изменения протокола.
enum ConnectScope { view, control, messages, calls, media, groups, screens, reset }

/// Разрешённые действия. Всё, чего нет в этом списке, — INVALID_COMMAND.
enum ConnectAction {
  // Служебные
  ping('PING', ConnectScope.view, immediate: true),
  deviceInfo('DEVICE_INFO', ConnectScope.view, immediate: true),
  listCharacters('LIST_CHARACTERS', ConnectScope.view, immediate: true),
  listMedia('LIST_MEDIA', ConnectScope.view, immediate: true),
  listGroups('LIST_GROUPS', ConnectScope.view, immediate: true),
  stop('STOP', ConnectScope.control, immediate: true),
  assignCharacter('ASSIGN_CHARACTER', ConnectScope.control),
  setContact('SET_CONTACT', ConnectScope.control),
  // Сцена
  message('MESSAGE', ConnectScope.messages),
  typing('TYPING', ConnectScope.messages),
  media('MEDIA', ConnectScope.media),
  deleteMessage('DELETE_MESSAGE', ConnectScope.messages),
  editMessage('EDIT_MESSAGE', ConnectScope.messages),
  messageStatus('MESSAGE_STATUS', ConnectScope.messages),
  call('CALL', ConnectScope.calls),
  videoCall('VIDEO_CALL', ConnectScope.calls),
  callAccept('CALL_ACCEPT', ConnectScope.calls),
  callDecline('CALL_DECLINE', ConnectScope.calls),
  endCall('END_CALL', ConnectScope.calls),
  notification('NOTIFICATION', ConnectScope.messages),
  openScreen('OPEN_SCREEN', ConnectScope.screens),
  delay('DELAY', ConnectScope.control),
  sequence('SEQUENCE', ConnectScope.control),
  resetScene('RESET_SCENE', ConnectScope.reset),
  // Управление ходом сцены с пульта (аддитивно: версия протокола прежняя).
  // Идут мимо очереди, как STOP, и выполняются через общий слой команд
  // оператора. Старое STOP по-прежнему прерывает только очередь Connect.
  sceneNext('SCENE_NEXT', ConnectScope.control, immediate: true),
  scenePrevious('SCENE_PREVIOUS', ConnectScope.control, immediate: true),
  sceneStop('SCENE_STOP', ConnectScope.control, immediate: true),
  // Группы (Connect 1.2)
  createChat('CREATE_CHAT', ConnectScope.groups),
  addParticipant('ADD_PARTICIPANT', ConnectScope.groups),
  removeParticipant('REMOVE_PARTICIPANT', ConnectScope.groups),
  // Подготовка телефона с пульта (Connect 1.3)
  upsertCharacter('UPSERT_CHARACTER', ConnectScope.control),
  // Передача файла кусками. Мимо очереди: загрузка не задерживает сцену
  // и не меняет её (в медиатеку файл попадает только на COMMIT).
  mediaUploadBegin('MEDIA_UPLOAD_BEGIN', ConnectScope.media, immediate: true),
  mediaUploadChunk('MEDIA_UPLOAD_CHUNK', ConnectScope.media, immediate: true),
  mediaUploadCommit('MEDIA_UPLOAD_COMMIT', ConnectScope.media, immediate: true);

  const ConnectAction(this.wire, this.scope, {this.immediate = false, this.supported = true});

  /// Имя в протоколе.
  final String wire;

  /// Право, нужное для выполнения.
  final ConnectScope scope;

  /// Выполняется сразу, минуя очередь (только чтение или экстренная остановка).
  final bool immediate;

  /// Реализовано ли в этой версии Messenger.
  final bool supported;

  static ConnectAction? parse(Object? wire) {
    for (final a in values) {
      if (a.wire == wire) return a;
    }
    return null;
  }
}

/// Статус команды.
abstract final class CommandStatus {
  static const received = 'RECEIVED';
  static const queued = 'QUEUED';
  static const executing = 'EXECUTING';
  static const executed = 'EXECUTED';
  static const failed = 'FAILED';
  static const cancelled = 'CANCELLED';
  static const alreadyProcessed = 'ALREADY_PROCESSED';
  static const unsupportedAction = 'UNSUPPORTED_ACTION';
  static const invalidRequest = 'INVALID_REQUEST';
  static const unauthorized = 'UNAUTHORIZED';
}

/// Коды ошибок (без трассировок и внутренних подробностей).
abstract final class ConnectError {
  static const unauthorized = 'UNAUTHORIZED';
  static const invalidRequest = 'INVALID_REQUEST';
  static const invalidCommand = 'INVALID_COMMAND';
  static const invalidTarget = 'INVALID_TARGET';
  static const unsupportedAction = 'UNSUPPORTED_ACTION';
  static const deviceNotReady = 'DEVICE_NOT_READY';
  static const sceneError = 'SCENE_ERROR';
  static const actionFailed = 'ACTION_FAILED';
  static const duplicateCommand = 'DUPLICATE_COMMAND';
  static const connectionError = 'CONNECTION_ERROR';
  static const sessionExpired = 'SESSION_EXPIRED';
  static const notFound = 'NOT_FOUND';
  static const cancelled = 'CANCELLED';
  static const internalError = 'INTERNAL_ERROR';
}

/// Ошибка выполнения с кодом протокола.
class ConnectException implements Exception {
  const ConnectException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Политика при занятом телефоне.
enum CommandPolicy {
  queue('QUEUE'),
  rejectIfBusy('REJECT_IF_BUSY');

  const CommandPolicy(this.wire);
  final String wire;

  static CommandPolicy parse(Object? v) => v == 'REJECT_IF_BUSY' ? rejectIfBusy : queue;
}

/// Ограничения на размер, чтобы команда не могла «завалить» телефон.
abstract final class ConnectLimits {
  static const commandIdLength = 64;
  static const textLength = 4000;
  static const sequenceSteps = 200;
  static const delayMs = 10 * 60 * 1000;
  static const frameBytes = 256 * 1024;
  static const queueLength = 50;

  /// executeAt не дальше этого срока от «сейчас».
  static const scheduleAheadMs = 10 * 60 * 1000;

  /// Кусок файла в MEDIA_UPLOAD_CHUNK (до base64). С запасом помещается
  /// в кадр [frameBytes] после base64 и шифрования.
  static const uploadChunkBytes = 96 * 1024;

  /// Самый большой файл, который можно передать с пульта.
  static const uploadBytes = 64 * 1024 * 1024;
}

/// Команда Controller → Messenger.
class CommandRequest {
  const CommandRequest({
    required this.commandId,
    required this.actionType,
    required this.payload,
    this.deviceId,
    this.timestamp,
    this.policy = CommandPolicy.queue,
    this.version = protocolVersion,
    this.executeAt,
  });

  final String commandId;

  /// Выполнить в этот момент по часам телефона (мс с 1970-01-01 UTC).
  /// Для синхронного запуска событий на нескольких телефонах.
  final int? executeAt;

  /// Имя действия как пришло (может быть неизвестным).
  final String actionType;
  final Map<String, Object?> payload;

  /// Какому телефону адресовано (null — этому).
  final String? deviceId;
  final int? timestamp;
  final CommandPolicy policy;
  final int version;

  ConnectAction? get action => ConnectAction.parse(actionType);

  /// Разбор с проверкой. Ошибка формата — [ConnectException].
  static CommandRequest fromJson(Object? json) {
    if (json is! Map) throw const ConnectException(ConnectError.invalidRequest, 'команда должна быть объектом');
    final id = json['commandId'];
    if (id is! String || id.trim().isEmpty || id.length > ConnectLimits.commandIdLength) {
      throw const ConnectException(ConnectError.invalidRequest, 'нужен commandId (строка до 64 символов)');
    }
    final version = json['protocolVersion'];
    if (version is! int) throw const ConnectException(ConnectError.invalidRequest, 'нужен protocolVersion');
    if (version > protocolVersion || version < 1) {
      throw const ConnectException(
          ConnectError.invalidRequest, 'телефон поддерживает протокол версии $protocolVersion');
    }
    final type = json['actionType'];
    if (type is! String || type.isEmpty) {
      throw const ConnectException(ConnectError.invalidRequest, 'нужен actionType');
    }
    final payload = json['payload'] ?? const <String, Object?>{};
    if (payload is! Map) throw const ConnectException(ConnectError.invalidRequest, 'payload должен быть объектом');
    final device = json['deviceId'] ?? json['targetDeviceId'];
    final executeAt = json['executeAt'];
    if (executeAt != null) {
      if (executeAt is! int) throw const ConnectException(ConnectError.invalidRequest, 'executeAt — число (мс)');
      if (executeAt - DateTime.now().millisecondsSinceEpoch > ConnectLimits.scheduleAheadMs) {
        throw const ConnectException(ConnectError.invalidRequest, 'executeAt дальше 10 минут');
      }
    }
    return CommandRequest(
      executeAt: executeAt as int?,
      commandId: id,
      actionType: type,
      payload: Map<String, Object?>.from(payload),
      deviceId: device is String ? device : null,
      timestamp: json['timestamp'] is int ? json['timestamp'] as int : null,
      policy: CommandPolicy.parse(json['policy']),
      version: version,
    );
  }

  Map<String, Object?> toJson() => {
        'type': 'command',
        'protocolVersion': version,
        'commandId': commandId,
        if (deviceId != null) 'deviceId': deviceId,
        'actionType': actionType,
        'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
        'policy': policy.wire,
        if (executeAt != null) 'executeAt': executeAt,
        'payload': payload,
      };
}

/// Ответ Messenger → Controller.
class CommandResult {
  const CommandResult({
    required this.commandId,
    required this.success,
    required this.status,
    this.error,
    this.message = '',
    this.result = const {},
    required this.timestamp,
  });

  final String commandId;
  final bool success;
  final String status;
  final String? error;
  final String message;
  final Map<String, Object?> result;
  final int timestamp;

  factory CommandResult.ok(String commandId, [Map<String, Object?> result = const {}]) => CommandResult(
        commandId: commandId,
        success: true,
        status: CommandStatus.executed,
        result: result,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

  factory CommandResult.error(String commandId, String error, String message) => CommandResult(
        commandId: commandId,
        success: false,
        status: switch (error) {
          ConnectError.unsupportedAction => CommandStatus.unsupportedAction,
          ConnectError.invalidRequest => CommandStatus.invalidRequest,
          ConnectError.unauthorized => CommandStatus.unauthorized,
          ConnectError.cancelled => CommandStatus.cancelled,
          _ => CommandStatus.failed,
        },
        error: error,
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

  /// Результат с отметкой, когда команда реально выполнена (для синхронизации).
  CommandResult withTiming({required int executedAt, int? lateMs}) => CommandResult(
        commandId: commandId,
        success: success,
        status: status,
        error: error,
        message: message,
        result: {...result, 'executedAt': executedAt, if (lateMs != null) 'lateMs': lateMs},
        timestamp: timestamp,
      );

  /// Повтор уже выполненной команды: прежний результат, действие не повторяется.
  CommandResult asAlreadyProcessed() => CommandResult(
        commandId: commandId,
        success: success,
        status: CommandStatus.alreadyProcessed,
        error: error,
        message: 'Команда уже выполнена, повтор не выполнялся',
        result: {...result, 'originalStatus': status},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, Object?> toJson() => {
        'type': 'result',
        'protocolVersion': protocolVersion,
        'commandId': commandId,
        'success': success,
        'status': status,
        if (error != null) 'error': error,
        'message': message,
        'timestamp': timestamp,
        if (result.isNotEmpty) 'result': result,
      };

  static CommandResult fromJson(Map<String, Object?> json) => CommandResult(
        commandId: json['commandId'] as String? ?? '',
        success: json['success'] == true,
        status: json['status'] as String? ?? CommandStatus.failed,
        error: json['error'] as String?,
        message: json['message'] as String? ?? '',
        result: json['result'] is Map ? Map<String, Object?>.from(json['result'] as Map) : const {},
        timestamp: json['timestamp'] is int ? json['timestamp'] as int : 0,
      );
}

/// Экраны, которые разрешено открыть командой OPEN_SCREEN.
enum ConnectScreen {
  chat('CHAT'),
  chatList('CHAT_LIST'),
  profile('PROFILE'),
  back('BACK'),
  // Connect 1.3: вкладки главного экрана.
  calls('CALLS'),
  contacts('CONTACTS');

  const ConnectScreen(this.wire);
  final String wire;

  static ConnectScreen? parse(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}
