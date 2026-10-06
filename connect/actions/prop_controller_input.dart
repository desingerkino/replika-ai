import '../../app/operator/operator_commands.dart';
import '../protocol/protocol.dart';

/// Источник команд оператора «Prop Controller»: превращает сетевые
/// SCENE_NEXT, SCENE_PREVIOUS и SCENE_STOP в [OperatorCommand] и отдаёт
/// их общему слою. Права (`control`) проверяет сервер Connect до этого
/// места; своей авторизации здесь нет.
class PropControllerInput implements OperatorInput {
  PropControllerInput(this.layer);

  final OperatorCommandLayer layer;

  @override
  OperatorInputSource get source => OperatorInputSource.propController;

  @override
  void attach() {}

  @override
  void detach() {}

  /// Команда оператора для действия протокола; для остальных — null.
  static OperatorCommand? commandFor(ConnectAction action) => switch (action) {
        ConnectAction.sceneNext => OperatorCommand.next,
        ConnectAction.scenePrevious => OperatorCommand.previous,
        ConnectAction.sceneStop => OperatorCommand.stop,
        _ => null,
      };

  /// Выполнить действие протокола и вернуть подтверждение для пульта:
  /// `handled` — у команды был адресат (сцена, звонок, импровизация),
  /// `target` — какой именно. Если адресата нет, это не ошибка:
  /// пульт видит `handled: false`.
  Future<Map<String, Object?>> handle(ConnectAction action) async {
    final command = commandFor(action);
    if (command == null) {
      throw ConnectException(ConnectError.invalidCommand, '${action.wire} не операторская команда');
    }
    final outcome = await layer.dispatch(command, source);
    return {
      'command': command.name,
      'handled': outcome.handled,
      'target': outcome.target.name,
    };
  }
}
