import '../../core/util/db_values.dart';
import '../../core/util/json.dart';

enum ActionGroup {
  messages('Сообщения'),
  media('Медиа'),
  notifications('Уведомления'),
  navigation('Навигация'),
  calls('Звонки'),
  scene('Сцена');

  const ActionGroup(this.label);
  final String label;
}

/// Все типы действий таймлайна (ТЗ, п. 31).
///
/// Тип хранится в базе строкой. Новые типы добавляются сюда и в реестр
/// исполнителей Scene Engine (Этап 4); старые сцены при этом не ломаются,
/// а действие неизвестного типа сохраняется как есть и не теряется.
enum ActionType {
  showIncoming(ActionGroup.messages, 'Показать входящее'),
  showOutgoing(ActionGroup.messages, 'Показать исходящее'),
  startTyping(ActionGroup.messages, 'Начать печать'),
  sendMessage(ActionGroup.messages, 'Отправить'),
  deleteMessage(ActionGroup.messages, 'Удалить сообщение'),
  editMessage(ActionGroup.messages, 'Изменить сообщение'),
  message(ActionGroup.messages, 'Сообщение: кто → кому'),
  createGroup(ActionGroup.messages, 'Создать группу'),
  addGroupMember(ActionGroup.messages, 'Добавить в группу'),
  removeGroupMember(ActionGroup.messages, 'Удалить из группы'),
  setMessageState(ActionGroup.messages, 'Изменить состояние'),
  showPhoto(ActionGroup.media, 'Показать фото'),
  showVideo(ActionGroup.media, 'Показать видео'),
  playAudio(ActionGroup.media, 'Проиграть аудио'),
  showVoice(ActionGroup.media, 'Показать голосовое'),
  showVideoNote(ActionGroup.media, 'Показать видеосообщение'),
  postNotification(ActionGroup.notifications, 'Локальное уведомление'),
  updateNotificationText(ActionGroup.notifications, 'Изменить текст уведомления'),
  updateNotificationTime(ActionGroup.notifications, 'Изменить время уведомления'),
  showEvent(ActionGroup.notifications, 'Показать событие'),
  openChat(ActionGroup.navigation, 'Открыть чат'),
  openProfile(ActionGroup.navigation, 'Открыть профиль'),
  navigateBack(ActionGroup.navigation, 'Назад'),
  call(ActionGroup.calls, 'Звонок: кто → кому'),
  incomingAudioCall(ActionGroup.calls, 'Входящий аудиозвонок'),
  outgoingAudioCall(ActionGroup.calls, 'Исходящий аудиозвонок'),
  incomingVideoCall(ActionGroup.calls, 'Входящий видеозвонок'),
  outgoingVideoCall(ActionGroup.calls, 'Исходящий видеозвонок'),
  acceptCall(ActionGroup.calls, 'Принять звонок'),
  declineCall(ActionGroup.calls, 'Отклонить звонок'),
  endCall(ActionGroup.calls, 'Завершить звонок'),
  startConversation(ActionGroup.calls, 'Начать разговор'),
  playCallSound(ActionGroup.calls, 'Проиграть локальный звук'),
  showCallVideo(ActionGroup.calls, 'Показать локальное видео'),
  wait(ActionGroup.scene, 'Ожидание'),
  pause(ActionGroup.scene, 'Пауза'),
  resume(ActionGroup.scene, 'Продолжение'),
  finish(ActionGroup.scene, 'Завершение'),
  reset(ActionGroup.scene, 'Сброс');

  const ActionType(this.group, this.label);
  final ActionGroup group;
  final String label;

  static ActionType? byName(String name) {
    for (final type in values) {
      if (type.name == name) return type;
    }
    return null;
  }
}

class SceneAction {
  const SceneAction({
    required this.id,
    required this.sceneId,
    required this.position,
    required this.typeName,
    this.delayMs = 0,
    this.params = const {},
    this.note = '',
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String sceneId;
  final int position;

  /// Имя типа как в базе. Может быть неизвестным для этой версии приложения.
  final String typeName;

  /// Пауза перед действием в автоматическом режиме.
  final int delayMs;

  /// Параметры действия: текст, отправитель, медиа, статус и т.д.
  final Map<String, Object?> params;
  final String note;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  ActionType? get type => ActionType.byName(typeName);

  /// Участник сцены, от имени которого выполняется действие.
  String? get characterId => params['characterId'] as String?;

  SceneAction copyWithDelay(int delayMs) => SceneAction(
        id: id,
        sceneId: sceneId,
        position: position,
        typeName: typeName,
        delayMs: delayMs,
        params: params,
        note: note,
        enabled: enabled,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  bool get isSupported => type != null;

  String get label => type?.label ?? 'Действие не поддерживается этой версией';

  factory SceneAction.fromRow(Map<String, Object?> row) => SceneAction(
        id: row['id'] as String,
        sceneId: row['scene_id'] as String,
        position: readInt(row, 'position'),
        typeName: readString(row, 'type'),
        delayMs: readInt(row, 'delay_ms'),
        params: decodeJsonMap(readStringOrNull(row, 'params_json')),
        note: readString(row, 'note'),
        enabled: intToBool(row['enabled']),
        createdAt: intToDate(row['created_at']),
        updatedAt: intToDate(row['updated_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'scene_id': sceneId,
        'position': position,
        'type': typeName,
        'delay_ms': delayMs,
        'params_json': encodeJsonMap(params),
        'note': note,
        'enabled': boolToInt(enabled),
        'created_at': dateToInt(createdAt),
        'updated_at': dateToInt(updatedAt),
      };
}
