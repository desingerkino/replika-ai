import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:replika/connect/protocol/protocol.dart';
import 'package:replika/connect/queue/command_queue.dart';

class FakeExecutor implements CommandExecutor {
  final List<String> started = [];
  final List<String> finished = [];
  Duration work = const Duration(milliseconds: 30);
  int stops = 0;

  @override
  Future<CommandResult> execute(CommandRequest request, CancelToken cancel) async {
    started.add(request.commandId);
    var left = request.actionType == 'PING' ? 0 : work.inMilliseconds;
    while (left > 0) {
      if (cancel.cancelled) return CommandResult.error(request.commandId, ConnectError.cancelled, 'stop');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      left -= 5;
    }
    finished.add(request.commandId);
    return CommandResult.ok(request.commandId);
  }

  @override
  Future<void> stopAll() async => stops++;
}

CommandRequest req(String id, [String type = 'MESSAGE', CommandPolicy policy = CommandPolicy.queue]) =>
    CommandRequest(commandId: id, actionType: type, payload: const {}, policy: policy);

void main() {
  test('команды выполняются строго по одной и по порядку', () async {
    final fx = FakeExecutor();
    final q = CommandQueue(fx);
    final statuses = <String>[];
    final results = await Future.wait([
      q.submit(req('001'), onStatus: (id, s) => statuses.add('$id:$s')),
      q.submit(req('002')),
      q.submit(req('003')),
    ]);
    expect(fx.started, ['001', '002', '003']);
    expect(fx.finished, ['001', '002', '003']);
    expect(results.every((r) => r.success), isTrue);
    expect(statuses, ['001:QUEUED', '001:EXECUTING']);
  });

  test('повтор во время выполнения не выполняет второй раз', () async {
    final fx = FakeExecutor();
    final q = CommandQueue(fx);
    final a = q.submit(req('c1'));
    final b = q.submit(req('c1'));
    final results = await Future.wait([a, b]);
    expect(fx.started, ['c1']);
    expect(results[1].status, CommandStatus.alreadyProcessed);
  });

  test('повтор после выполнения — прежний результат, ALREADY_PROCESSED', () async {
    final fx = FakeExecutor();
    final q = CommandQueue(fx);
    await q.submit(req('c1'));
    final again = await q.submit(req('c1'));
    expect(fx.started, ['c1']);
    expect(again.status, CommandStatus.alreadyProcessed);
    expect(again.result['originalStatus'], CommandStatus.executed);
  });

  test('защита от повтора переживает перезапуск (восстановленный кэш)', () async {
    Map<String, CommandResult>? saved;
    final q1 = CommandQueue(FakeExecutor(), onPersist: (m) => saved = Map.of(m));
    await q1.submit(req('c1'));
    final fx = FakeExecutor();
    final q2 = CommandQueue(fx, restored: saved);
    expect((await q2.submit(req('c1'))).status, CommandStatus.alreadyProcessed);
    expect(fx.started, isEmpty);
  });

  test('REJECT_IF_BUSY: занятый телефон отказывает, а не копит', () async {
    final fx = FakeExecutor();
    final q = CommandQueue(fx);
    final first = q.submit(req('a'));
    final second = await q.submit(req('b', 'MESSAGE', CommandPolicy.rejectIfBusy));
    expect(second.error, ConnectError.deviceNotReady);
    await first;
    expect(fx.started, ['a']);
  });

  test('STOP прерывает текущую и снимает ожидающие', () async {
    final fx = FakeExecutor()..work = const Duration(seconds: 2);
    final q = CommandQueue(fx);
    final a = q.submit(req('a'));
    final b = q.submit(req('b'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final stop = await q.submit(req('s', 'STOP'));
    expect(stop.success, isTrue);
    expect((await a).status, CommandStatus.cancelled);
    expect((await b).status, CommandStatus.cancelled);
    expect(fx.started, ['a']);
    expect(fx.stops, 1);
  });

  test('служебные команды не ждут очереди', () async {
    final fx = FakeExecutor()..work = const Duration(milliseconds: 300);
    final q = CommandQueue(fx);
    final long = q.submit(req('long'));
    final ping = await q.submit(req('p', 'PING'));
    expect(ping.success, isTrue);
    expect(fx.finished, ['p'], reason: 'PING выполнен раньше долгой команды');
    await long;
  });

  test('переполненная очередь отказывает', () async {
    final fx = FakeExecutor()..work = const Duration(milliseconds: 5);
    final q = CommandQueue(fx);
    final futures = [for (var i = 0; i <= ConnectLimits.queueLength + 1; i++) q.submit(req('c$i'))];
    final results = await Future.wait(futures);
    expect(results.where((r) => r.error == ConnectError.deviceNotReady), isNotEmpty);
  });
}
