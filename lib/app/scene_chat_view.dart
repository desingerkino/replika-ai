import '../data/models/scene_action.dart';

/// Личные таймлайны чатов сцены.
///
/// Событие существует один раз (SceneAction). «Личный таймлайн» чата — это
/// не копия, а представление: события самого чата плюс те чужие события,
/// которые оператор сам привязал к этому чату («показывать также в чате»,
/// параметр `alsoIn`). Общий таймлайн — все события сцены.

/// Ключ чата сцены: личный чат с контактом.
String directChatKey(String characterId) => 'c:$characterId';

/// Ключ чата сцены: групповая беседа (id чата на телефоне сцены).
String groupChatKey(String chatId) => 'g:$chatId';

bool isGroupKey(String key) => key.startsWith('g:');

/// Идентификатор после префикса: id контакта или id группового чата.
String chatKeyId(String key) => key.length > 2 ? key.substring(2) : '';

/// Типы, которыми управляет сам движок: у них нет чата.
const Set<ActionType> _controlTypes = {
  ActionType.wait,
  ActionType.pause,
  ActionType.resume,
  ActionType.finish,
  ActionType.reset,
};

/// Чат, которому принадлежит действие на телефоне сцены.
///
/// * с `groupId` — групповая беседа;
/// * «кто → кому» — собеседник владельца телефона (если владелец не
///   участвует, у действия нет чата на этом телефоне);
/// * со ссылкой `refActionId` (статус, удаление, ответ на звонок) — чат
///   того события, на которое оно ссылается;
/// * иначе — участник действия (или участник по умолчанию).
///
/// null — действие принадлежит только общему таймлайну.
String? sceneChatKeyOf(
  SceneAction action, {
  required String ownerId,
  String? defaultPeerId,
  Map<String, SceneAction> byId = const {},
  int depth = 0,
}) {
  final type = action.type;
  if (type != null && _controlTypes.contains(type)) return null;
  final groupId = action.params['groupId'] as String?;
  if (groupId != null) return groupChatKey(groupId);

  final ref = action.params['refActionId'] as String?;
  if (ref != null && depth < 5) {
    final target = byId[ref];
    if (target != null) {
      return sceneChatKeyOf(target, ownerId: ownerId, defaultPeerId: defaultPeerId, byId: byId, depth: depth + 1);
    }
  }

  if (type == ActionType.message || type == ActionType.call) {
    final from = action.params['from'] as String?;
    final to = action.params['to'] as String?;
    if (from == ownerId && to != null) return directChatKey(to);
    if (to == ownerId && from != null) return directChatKey(from);
    return null;
  }

  final who = action.characterId ?? defaultPeerId;
  if (who == null || who == ownerId) return null;
  return directChatKey(who);
}

/// Чаты, в личных таймлайнах которых оператор попросил показывать событие.
List<String> sceneAlsoIn(SceneAction action) {
  final raw = action.params['alsoIn'];
  if (raw is! List) return const [];
  return [for (final key in raw) if (key is String && key.length > 2) key];
}

/// Индексы действий в личном таймлайне чата [chatKey]: свои и привязанные.
List<int> sceneChatView(
  List<SceneAction> actions,
  String chatKey, {
  required String ownerId,
  String? defaultPeerId,
}) {
  final byId = {for (final a in actions) a.id: a};
  final result = <int>[];
  for (var i = 0; i < actions.length; i++) {
    final action = actions[i];
    final own = sceneChatKeyOf(action, ownerId: ownerId, defaultPeerId: defaultPeerId, byId: byId) == chatKey;
    if (own || sceneAlsoIn(action).contains(chatKey)) result.add(i);
  }
  return result;
}

/// Чужое для этого чата событие, показанное в его таймлайне по привязке.
bool isCrossChatEvent(
  SceneAction action,
  String chatKey, {
  required String ownerId,
  String? defaultPeerId,
  Map<String, SceneAction> byId = const {},
}) =>
    sceneChatKeyOf(action, ownerId: ownerId, defaultPeerId: defaultPeerId, byId: byId) != chatKey;
