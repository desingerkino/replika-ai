import 'dart:async';
import 'dart:collection';

import '../protocol/protocol.dart';

/// Признак отмены для идущей команды (STOP, CANCEL последовательности).
class CancelToken {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Кто выполняет команды (Connect → сцена Connect → Scene Engine).
/// Отделено от очереди для автотестов.
abstract class CommandExecutor {
  Future<CommandResult> execute(CommandRequest request, CancelToken cancel);

  /// Экстренная остановка: прервать то, что идёт внутри Messenger.
  Future<void> stopAll();
}

typedef StatusSink = void Function(String commandId, String status);

class _Job {
  _Job(this.request, this.onStatus);

  final CommandRequest request;
  final StatusSink? onStatus;
  final Completer<CommandResult> completer = Completer<CommandResult>();
}

/// Единая очередь команд Messenger.
///
/// * Команды, меняющие состояние, выполняются строго по одной, в порядке
///   поступления — никакого параллельного изменения сцены.
/// * Повтор того же commandId не выполняет действие второй раз: пока
///   команда в очереди или выполняется — ждёт её результата, после —
///   сразу получает прежний результат со статусом ALREADY_PROCESSED.
/// * Служебные команды (PING, DEVICE_INFO, LIST_*) и STOP идут мимо
///   очереди: они только читают или останавливают.
class CommandQueue {
  CommandQueue(
    this.executor, {
    this.cacheSize = 500,
    this.onPersist,
    Map<String, CommandResult>? restored,
  }) {
    if (restored != null) _done.addAll(restored);
  }

  final CommandExecutor executor;
  final int cacheSize;

  /// Сохранить кэш выполненных команд (переживает перезапуск приложения).
  final void Function(Map<String, CommandResult> done)? onPersist;

  final LinkedHashMap<String, CommandResult> _done = LinkedHashMap();
  final Map<String, Future<CommandResult>> _inflight = {};
  final Queue<_Job> _jobs = Queue();
  CancelToken _current = CancelToken();
  bool _running = false;

  bool get busy => _running || _jobs.isNotEmpty;
  int get queued => _jobs.length;

  Future<CommandResult> submit(CommandRequest request, {StatusSink? onStatus}) {
    final id = request.commandId;
    final done = _done[id];
    if (done != null) return Future.value(done.asAlreadyProcessed());
    final inflight = _inflight[id];
    if (inflight != null) return inflight.then((r) => r.asAlreadyProcessed());

    final action = request.action;
    if (action != null && action.immediate) {
      final future = _runImmediate(request, action);
      _inflight[id] = future;
      return future;
    }
    if (request.policy == CommandPolicy.rejectIfBusy && busy) {
      return Future.value(CommandResult.error(
          id, ConnectError.deviceNotReady, 'Телефон занят другой командой (политика REJECT_IF_BUSY)'));
    }
    if (_jobs.length >= ConnectLimits.queueLength) {
      return Future.value(CommandResult.error(id, ConnectError.deviceNotReady, 'Очередь команд заполнена'));
    }
    final job = _Job(request, onStatus);
    _inflight[id] = job.completer.future;
    _jobs.add(job);
    onStatus?.call(id, CommandStatus.queued);
    unawaited(_pump());
    return job.completer.future;
  }

  Future<CommandResult> _runImmediate(CommandRequest request, ConnectAction action) async {
    if (action == ConnectAction.stop) {
      final cancelled = await cancelAll();
      final result = CommandResult.ok(request.commandId, {'cancelledCommands': cancelled});
      _remember(result);
      return result;
    }
    final result = await _execute(request, CancelToken());
    _remember(result);
    return result;
  }

  Future<CommandResult> _execute(CommandRequest request, CancelToken token) async {
    try {
      return await executor.execute(request, token);
    } on ConnectException catch (e) {
      return CommandResult.error(request.commandId, e.code, e.message);
    } catch (_) {
      // Подробности внутренней ошибки наружу не отдаются.
      return CommandResult.error(request.commandId, ConnectError.internalError, 'Внутренняя ошибка Messenger');
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_jobs.isNotEmpty) {
        final job = _jobs.removeFirst();
        _current = CancelToken();
        final token = _current;
        final at = job.request.executeAt;
        if (at != null && !await _waitUntil(at, token)) {
          final cancelled = CommandResult.error(job.request.commandId, ConnectError.cancelled, 'Команда отменена (STOP)');
          _remember(cancelled);
          job.completer.complete(cancelled);
          continue;
        }
        job.onStatus?.call(job.request.commandId, CommandStatus.executing);
        final started = DateTime.now().millisecondsSinceEpoch;
        var result = await _execute(job.request, token);
        result = result.withTiming(executedAt: started, lateMs: at == null ? null : started - at);
        _remember(result);
        job.completer.complete(result);
      }
    } finally {
      _running = false;
    }
  }

  /// Ждать момента executeAt. false — ожидание прервал STOP.
  static Future<bool> _waitUntil(int at, CancelToken token) async {
    while (true) {
      if (token.cancelled) return false;
      final left = at - DateTime.now().millisecondsSinceEpoch;
      if (left <= 0) return true;
      await Future<void>.delayed(Duration(milliseconds: left > 20 ? 20 : left));
    }
  }

  /// STOP: прервать текущую команду и снять все ожидающие (CANCELLED).
  Future<int> cancelAll() async {
    _current.cancel();
    var count = 0;
    while (_jobs.isNotEmpty) {
      final job = _jobs.removeFirst();
      final result = CommandResult.error(job.request.commandId, ConnectError.cancelled, 'Команда отменена (STOP)');
      _remember(result);
      job.completer.complete(result);
      count++;
    }
    await executor.stopAll();
    return count;
  }

  void _remember(CommandResult result) {
    _inflight.remove(result.commandId);
    _done.remove(result.commandId);
    _done[result.commandId] = result;
    while (_done.length > cacheSize) {
      _done.remove(_done.keys.first);
    }
    onPersist?.call(Map.unmodifiable(_done));
  }
}
