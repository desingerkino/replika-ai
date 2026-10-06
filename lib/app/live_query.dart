import 'dart:async';

import 'package:flutter/widgets.dart';

import 'services.dart';

/// Состояние живого запроса.
class LiveSnapshot<T> {
  const LiveSnapshot({
    required this.data,
    required this.error,
    required this.isLoading,
    required this.reload,
  });

  /// Последние загруженные данные (сохраняются во время перезагрузки).
  final T? data;
  final Object? error;

  /// true до завершения первой загрузки.
  final bool isLoading;
  final VoidCallback reload;
}

/// Виджет, который читает данные из базы и перечитывает их, когда
/// меняется любая из указанных таблиц — кем угодно: экраном, импортом
/// или (с Этапа 4) движком сцен.
class LiveQuery<T> extends StatefulWidget {
  const LiveQuery({
    super.key,
    required this.tables,
    required this.load,
    required this.builder,
    this.queryKey,
  });

  final Set<String> tables;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, LiveSnapshot<T> snapshot) builder;

  /// Смена ключа (например, другой чат) — загрузка с нуля.
  final Object? queryKey;

  @override
  State<LiveQuery<T>> createState() => _LiveQueryState<T>();
}

class _LiveQueryState<T> extends State<LiveQuery<T>> {
  StreamSubscription<Set<String>>? _subscription;
  T? _data;
  Object? _error;
  bool _loading = true;
  bool _running = false;
  bool _dirty = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _subscription =
        Services.read(context).database.changes.stream.listen(_onTablesChanged);
    _start();
  }

  @override
  void didUpdateWidget(covariant LiveQuery<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryKey != widget.queryKey) {
      _data = null;
      _error = null;
      _loading = true;
      _start();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onTablesChanged(Set<String> changed) {
    if (changed.any(widget.tables.contains)) _request();
  }

  /// Запрос перезагрузки; частые изменения схлопываются в одну загрузку.
  void _request() {
    if (_running) {
      _dirty = true;
      return;
    }
    _start();
  }

  void _start() {
    _generation++;
    _run(_generation);
  }

  Future<void> _run(int generation) async {
    _running = true;
    do {
      _dirty = false;
      try {
        final result = await widget.load();
        if (!mounted || generation != _generation) return;
        setState(() {
          _data = result;
          _error = null;
          _loading = false;
        });
      } catch (error, stack) {
        if (!mounted || generation != _generation) return;
        debugPrint('Ошибка загрузки данных: $error\n$stack');
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    } while (_dirty && mounted && generation == _generation);
    if (generation == _generation) _running = false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      LiveSnapshot<T>(
        data: _data,
        error: _error,
        isLoading: _loading,
        reload: _request,
      ),
    );
  }
}
