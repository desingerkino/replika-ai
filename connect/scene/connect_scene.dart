import '../../app/scene_effects.dart';
import '../../app/services.dart';
import '../../data/models/scene_action.dart';
import '../protocol/protocol.dart';
import '../queue/command_queue.dart';

/// Служебная сцена «Connect» текущего виртуального телефона.
///
/// Всё, что делает Controller, выполняется внутри неё существующим
/// Scene Engine. Поэтому:
/// * сообщения, звонки, уведомления — настоящие данные Messenger;
/// * RESET_SCENE убирает только то, что добавил Connect, — обычные
///   переписки, другие сцены и настройки не трогаются;
/// * журнал отмены переживает перезапуск приложения.
///
/// Connect не пишет в SQLite напрямую — только через Scene Engine.
class ConnectScene {
  ConnectScene(this.services);

  final AppServices services;

  static String idFor(String virtualDeviceId) => 'connect-$virtualDeviceId';

  String get sceneId => idFor(services.currentDeviceId.value);

  /// Создать сцену при необходимости, добавить участников, загрузить в движок.
  Future<void> prepare(Iterable<String> characterIds) async {
    final deviceId = services.currentDeviceId.value;
    final id = idFor(deviceId);
    if (await services.scenes.byId(id) == null) {
      await services.scenes.create(id: id, deviceId: deviceId, number: 'C', name: 'Connect');
    }
    final ids = {for (final c in characterIds) if (c.isNotEmpty) c};
    if (ids.isNotEmpty) await services.scenes.addParticipants(id, ids);

    final engine = services.engine;
    if (engine.info?.sceneId == id) return;
    if (engine.hasTake) {
      throw const ConnectException(
        ConnectError.deviceNotReady,
        'На телефоне идёт дубль другой сцены — завершите или сбросьте его в операторской',
      );
    }
    try {
      await engine.load(id);
    } on StateError catch (e) {
      throw ConnectException(ConnectError.sceneError, e.message);
    }
  }

  /// Выполнить действие сцены. Возвращает id созданного или изменённого
  /// сообщения (если есть).
  Future<String?> run(SceneAction action, {CancelToken? cancel, Iterable<String> extra = const []}) async {
    await prepare([if (action.characterId != null) action.characterId!, ...extra]);
    final effects = services.engine.effects;
    if (effects is SceneDataEffects) effects.lastCreatedMessageId = null;
    try {
      await services.engine.performCommand(action, cancelled: () => cancel?.cancelled ?? false);
    } on UnsupportedError {
      throw const ConnectException(ConnectError.unsupportedAction, 'Действие не поддерживается этой версией');
    } on StateError catch (e) {
      throw ConnectException(ConnectError.actionFailed, e.message);
    } on ConnectException {
      rethrow;
    } catch (_) {
      throw const ConnectException(ConnectError.actionFailed, 'Действие не выполнено');
    }
    return effects is SceneDataEffects ? effects.lastCreatedMessageId : null;
  }

  /// Сброс сцены Connect: только то, что добавили команды Connect.
  Future<bool> reset() async {
    final id = sceneId;
    if (await services.scenes.byId(id) == null) return false;
    final engine = services.engine;
    if (engine.info?.sceneId != id) {
      if (engine.hasTake) {
        throw const ConnectException(
          ConnectError.deviceNotReady,
          'Идёт дубль другой сцены — сбросьте его в операторской',
        );
      }
      try {
        await engine.load(id);
      } on StateError {
        return false; // участников нет — Connect ещё ничего не добавлял
      }
    }
    await engine.reset();
    return true;
  }
}
