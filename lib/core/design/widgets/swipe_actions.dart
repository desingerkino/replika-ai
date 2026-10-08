import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../context.dart';
import '../tokens.dart';

/// Кнопка, открывающаяся под строкой при свайпе.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// Строка со свайп-действиями, как в iOS-мессенджерах: свайп вправо
/// открывает [leading], влево — [trailing]. Открыта всегда только одна
/// строка; прокрутка списка или касание по строке её закрывают.
class SwipeActionTile extends StatefulWidget {
  const SwipeActionTile({
    super.key,
    required this.child,
    this.leading = const [],
    this.trailing = const [],
  });

  final Widget child;
  final List<SwipeAction> leading;
  final List<SwipeAction> trailing;

  /// Какая строка сейчас открыта (одна на всё приложение).
  static final ValueNotifier<Object?> open = ValueNotifier<Object?>(null);

  static void closeAll() => open.value = null;

  @override
  State<SwipeActionTile> createState() => _SwipeActionTileState();
}

class _SwipeActionTileState extends State<SwipeActionTile> with SingleTickerProviderStateMixin {
  static const double actionWidth = 76;

  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  final Object _token = Object();
  ScrollPosition? _scroll;
  bool _armedHaptic = false;

  double get _leadingMax => widget.leading.length * actionWidth + Space.s;
  double get _trailingMax => widget.trailing.length * actionWidth + Space.s;

  @override
  void initState() {
    super.initState();
    SwipeActionTile.open.addListener(_onOtherOpened);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scroll) {
      _scroll?.isScrollingNotifier.removeListener(_onScroll);
      _scroll = position;
      _scroll?.isScrollingNotifier.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    SwipeActionTile.open.removeListener(_onOtherOpened);
    _scroll?.isScrollingNotifier.removeListener(_onScroll);
    if (SwipeActionTile.open.value == _token) SwipeActionTile.open.value = null;
    _c.dispose();
    super.dispose();
  }

  void _onOtherOpened() {
    if (SwipeActionTile.open.value != _token && _c.value != 0) _animateTo(0);
  }

  void _onScroll() {
    if ((_scroll?.isScrollingNotifier.value ?? false) && _c.value != 0) _close();
  }

  void _animateTo(double target) {
    _c.animateTo(target, duration: Motion.normal, curve: Curves.easeOutCubic);
  }

  void _close() {
    _animateTo(0);
    if (SwipeActionTile.open.value == _token) SwipeActionTile.open.value = null;
  }

  void _update(DragUpdateDetails d) {
    var next = _c.value + d.delta.dx;
    final maxRight = widget.leading.isEmpty ? 0.0 : _leadingMax * 1.25;
    final maxLeft = widget.trailing.isEmpty ? 0.0 : -_trailingMax * 1.25;
    next = next.clamp(maxLeft, maxRight);
    _c.value = next;
    final threshold = next > 0 ? _leadingMax * 0.5 : _trailingMax * 0.5;
    final armed = next.abs() > threshold && next != 0;
    if (armed && !_armedHaptic) HapticFeedback.selectionClick();
    _armedHaptic = armed;
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final x = _c.value;
    double target = 0;
    if (x > 0 && (x > _leadingMax * 0.45 || v > 600)) target = _leadingMax;
    if (x < 0 && (-x > _trailingMax * 0.45 || v < -600)) target = -_trailingMax;
    if (v.abs() > 600 && (v > 0) != (x > 0)) target = 0;
    _animateTo(target);
    if (target != 0) {
      SwipeActionTile.open.value = _token;
    } else if (SwipeActionTile.open.value == _token) {
      SwipeActionTile.open.value = null;
    }
  }

  void _run(SwipeAction action) {
    HapticFeedback.lightImpact();
    _close();
    action.onTap();
  }

  Widget _buttons(List<SwipeAction> actions, {required bool left}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in actions)
          SizedBox(
            width: actionWidth,
            child: Semantics(
              button: true,
              label: a.label,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _run(a),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 62,
                      height: 44,
                      decoration: BoxDecoration(color: a.color, borderRadius: BorderRadius.circular(22)),
                      child: Icon(a.icon, color: MediaPalette.onMedia, size: 24),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.labelSmall?.copyWith(color: context.rc.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.leading.isEmpty && widget.trailing.isEmpty) return widget.child;
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _end(DragEndDetails()),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final x = _c.value;
          return Stack(
            children: [
              if (x > 0)
                Positioned(
                  left: Space.xs,
                  top: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: (x / _leadingMax).clamp(0.0, 1.0),
                    child: _buttons(widget.leading, left: true),
                  ),
                ),
              if (x < 0)
                Positioned(
                  right: Space.xs,
                  top: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: (-x / _trailingMax).clamp(0.0, 1.0),
                    child: _buttons(widget.trailing, left: false),
                  ),
                ),
              Transform.translate(
                offset: Offset(x, 0),
                child: GestureDetector(
                  // Касание по открытой строке закрывает её, а не открывает чат.
                  behavior: HitTestBehavior.translucent,
                  onTap: x != 0 ? _close : null,
                  child: AbsorbPointer(absorbing: x != 0, child: child),
                ),
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}
