import 'package:flutter/widgets.dart';

/// Касание двумя пальцами: оба пальца ложатся почти одновременно, почти не
/// двигаются и поднимаются быстро. Обычное касание одним пальцем, прокрутка
/// и касание тремя пальцами не срабатывают. Вложенные кнопки продолжают
/// получать свои касания: виджет только слушает события.
class TwoFingerTap extends StatefulWidget {
  const TwoFingerTap({super.key, required this.onTap, required this.child});

  /// Максимальное смещение пальца, при котором касание ещё считается касанием.
  static const double slop = 24;

  /// Максимальная длительность жеста от второго пальца до подъёма последнего.
  static const Duration maxDuration = Duration(milliseconds: 700);

  final VoidCallback onTap;
  final Widget child;

  @override
  State<TwoFingerTap> createState() => _TwoFingerTapState();
}

class _TwoFingerTapState extends State<TwoFingerTap> {
  final Map<int, Offset> _start = {};
  DateTime? _armedAt;
  bool _valid = true;

  void _reset() {
    _start.clear();
    _armedAt = null;
    _valid = true;
  }

  void _down(PointerDownEvent event) {
    if (_start.isEmpty) {
      _valid = true;
      _armedAt = null;
    }
    _start[event.pointer] = event.position;
    if (_start.length == 2) {
      _armedAt = DateTime.now();
    } else if (_start.length > 2) {
      _valid = false;
    }
  }

  void _move(PointerMoveEvent event) {
    final origin = _start[event.pointer];
    if (origin != null && (event.position - origin).distance > TwoFingerTap.slop) _valid = false;
  }

  void _up(PointerEvent event) {
    _start.remove(event.pointer);
    if (event is PointerCancelEvent) _valid = false;
    if (_start.isNotEmpty) return;
    final armed = _armedAt;
    final ok = _valid && armed != null && DateTime.now().difference(armed) <= TwoFingerTap.maxDuration;
    _reset();
    if (ok) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: widget.child,
    );
  }
}
