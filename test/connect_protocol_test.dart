import 'package:flutter_test/flutter_test.dart';
import 'package:replika/connect/protocol/protocol.dart';

Map<String, Object?> cmd([Map<String, Object?> extra = const {}]) => {
      'type': 'command',
      'protocolVersion': 1,
      'commandId': 'cmd-001',
      'actionType': 'MESSAGE',
      'payload': {'text': 'Ты где?'},
      ...extra,
    };

void main() {
  group('Команда: разбор', () {
    test('корректная команда: сериализация и разбор без потерь', () {
      final r = CommandRequest.fromJson(cmd({'deviceId': 'MESSENGER-7F32A1', 'policy': 'REJECT_IF_BUSY'}));
      expect(r.commandId, 'cmd-001');
      expect(r.action, ConnectAction.message);
      expect(r.deviceId, 'MESSENGER-7F32A1');
      expect(r.policy, CommandPolicy.rejectIfBusy);
      final again = CommandRequest.fromJson(r.toJson());
      expect(again.toJson()..remove('timestamp'), r.toJson()..remove('timestamp'));
    });

    void invalid(Object? json, String reason) {
      expect(
        () => CommandRequest.fromJson(json),
        throwsA(isA<ConnectException>().having((e) => e.code, 'code', ConnectError.invalidRequest)),
        reason: reason,
      );
    }

    test('повреждённые пакеты — INVALID_REQUEST', () {
      invalid('текст', 'не объект');
      invalid(cmd({'commandId': ''}), 'пустой commandId');
      invalid(cmd({'commandId': 'x' * 65}), 'длинный commandId');
      invalid(cmd({'protocolVersion': null}), 'нет версии');
      invalid(cmd({'actionType': null}), 'нет actionType');
      invalid(cmd({'payload': 'строка'}), 'payload не объект');
    });

    test('версия протокола новее поддерживаемой — отказ', () {
      invalid(cmd({'protocolVersion': 2}), 'версия 2');
      invalid(cmd({'protocolVersion': 0}), 'версия 0');
    });

    test('неизвестный actionType разбирается, но не распознаётся', () {
      final r = CommandRequest.fromJson(cmd({'actionType': 'LAUNCH_ROCKET'}));
      expect(r.action, isNull);
    });
  });

  group('Действия', () {
    test('группы поддерживаются и требуют права GROUPS', () {
      for (final a in [ConnectAction.createChat, ConnectAction.addParticipant, ConnectAction.removeParticipant]) {
        expect(a.supported, isTrue);
        expect(a.scope, ConnectScope.groups);
      }
    });

    test('служебные команды идут мимо очереди, сценарные — через неё', () {
      expect(ConnectAction.ping.immediate, isTrue);
      expect(ConnectAction.stop.immediate, isTrue);
      expect(ConnectAction.message.immediate, isFalse);
      expect(ConnectAction.sequence.immediate, isFalse);
    });

    test('имена в протоколе уникальны', () {
      final names = ConnectAction.values.map((a) => a.wire).toList();
      expect(names.toSet().length, names.length);
    });
  });

  group('Ответ', () {
    test('успех, ошибка, повтор', () {
      final ok = CommandResult.ok('c1', {'messageId': 'm1'});
      expect(ok.toJson()['status'], CommandStatus.executed);
      final err = CommandResult.error('c2', ConnectError.unsupportedAction, 'нет');
      expect(err.status, CommandStatus.unsupportedAction);
      expect(err.success, isFalse);
      final again = ok.asAlreadyProcessed();
      expect(again.status, CommandStatus.alreadyProcessed);
      expect(again.result['messageId'], 'm1');
      expect(CommandResult.fromJson(err.toJson()).error, ConnectError.unsupportedAction);
    });

    test('ответ не содержит трассировок', () {
      final err = CommandResult.error('c', ConnectError.internalError, 'Внутренняя ошибка Messenger');
      expect(err.toJson().toString(), isNot(contains('#0')));
    });
  });
}
