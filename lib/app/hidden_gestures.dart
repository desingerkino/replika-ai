import 'dart:async';

import 'package:flutter/widgets.dart';

/// Скрытые жесты оператора — работают на любом экране и ничего
/// не показывают в кадре:
/// * касание двумя пальцами — «Далее» (только когда дубль идёт);
/// * два пальца вместе вверх (свайп) — «Назад», предыдущее событие;
/// * три пальца, удерживать 1 секунду — открыть операторскую.
///
/// Жест «два пальца вверх» не срабатывает, пока открыта клавиатура или
/// фокус в текстовом поле: там он нужен для обычной работы с текстом. Сами
/// касания жест не перехватывает — прокрутка и нажатия под ним работают.
const double kTwoFingerSwipeDistance = 72;

/// Свайп засчитывается, если сделан быстро: медленное перетаскивание — нет.
const Duration kTwoFingerSwipeWindow = Duration(milliseconds: 1500);
class HiddenGestures extends StatefulWidget {
  const HiddenGestures({
    super.key,
    required this.child,
    required this.onNext,
    required this.onOperator,
    this.onPrevious,
  });

  final Widget child;
  final VoidCallback onNext;
  final VoidCallback onOperator;

  /// Два пальца вверх. null — жест выключен.
  final VoidCallback? onPrevious;

  @override
  State<HiddenGestures> createState() => _HiddenGesturesState();
}

class _HiddenGesturesState extends State<HiddenGestures> {
  final Map<int, Offset> _start = {};
  final Map<int, Offset> _current = {};
  final Set<int> _down = {};
  bool _swiped = false;
  DateTime? _firstDown;
  int _maxPointers = 0;
  bool _moved = false;
  bool _consumed = false;
  Timer? _hold;

  void _reset() {
    _start.clear();
    _current.clear();
    _swiped = false;
    _firstDown = null;
    _maxPointers = 0;
    _moved = false;
    _consumed = false;
    _hold?.cancel();
  }

  void _onDown(PointerDownEvent event) {
    if (_down.isEmpty) _reset();
    _down.add(event.pointer);
    _start[event.pointer] = event.position;
    _current[event.pointer] = event.position;
    _firstDown ??= DateTime.now();
    if (_down.length > _maxPointers) _maxPointers = _down.length;
    if (_down.length == 3) {
      _hold?.cancel();
      _hold = Timer(const Duration(seconds: 1), () {
        if (_down.length >= 3 && !_moved) {
          _consumed = true;
          widget.onOperator();
        }
      });
    }
  }

  void _onMove(PointerMoveEvent event) {
    final start = _start[event.pointer];
    if (start != null && (event.position - start).distance > 24) _moved = true;
    _current[event.pointer] = event.position;
    _checkSwipeUp();
  }

  /// Ровно два пальца, оба ушли вверх и движение в основном вертикальное.
  void _checkSwipeUp() {
    final callback = widget.onPrevious;
    final first = _firstDown;
    if (callback == null || _swiped || _consumed || first == null) return;
    if (_down.length != 2 || _maxPointers != 2) return;
    if (DateTime.now().difference(first) > kTwoFingerSwipeWindow) return;
    for (final id in _down) {
      final from = _start[id];
      final to = _current[id];
      if (from == null || to == null) return;
      final delta = to - from;
      if (delta.dy > -kTwoFingerSwipeDistance || delta.dy.abs() < delta.dx.abs() * 1.5) return;
    }
    if (_textInputActive()) return;
    _swiped = true;
    _consumed = true;
    callback();
  }

  /// Открыта клавиатура или фокус в текстовом поле — жест остаётся полю.
  bool _textInputActive() {
    if (MediaQuery.maybeViewInsetsOf(context)?.bottom case final inset? when inset > 0) return true;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText || focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _onUp(PointerEvent event) {
    _down.remove(event.pointer);
    if (_down.isNotEmpty) return;
    _hold?.cancel();
    final first = _firstDown;
    final quick = first != null && DateTime.now().difference(first) < const Duration(milliseconds: 400);
    if (!_consumed && !_moved && quick && _maxPointers == 2) widget.onNext();
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: widget.child,
    );
  }
}
