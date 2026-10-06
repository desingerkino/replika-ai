import 'dart:async';

/// Шина изменений базы: репозитории сообщают, какие таблицы изменились,
/// экраны (через LiveQuery) перечитывают только нужные данные.
/// Этим же механизмом будет пользоваться Scene Engine: он пишет в базу,
/// а интерфейс обновляется сам — без прямой связи движка с экранами.
class DbChanges {
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  Stream<Set<String>> get stream => _controller.stream;

  void notify(Iterable<String> tables) {
    if (_controller.isClosed) return;
    _controller.add(Set<String>.unmodifiable(tables));
  }

  Future<void> close() => _controller.close();
}
