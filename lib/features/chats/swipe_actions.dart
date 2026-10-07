import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/tokens.dart';

/// Одно действие, которое открывает свайп строки.
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

/// Строка со свайпами в стиле мессенджеров: вправо — [leading] слева,
/// влево — [trailing] справа. Недотянул — строка возвращается, дотянул —
/// остаётся открытой, пока не нажмут на неё, на действие или не откроют
/// другую (общий [open]). Жест не мешает вертикальной прокрутке и нажатию:
/// на открытой строке нажатие только закрывает её.
class SwipeActionTile extends StatefulWidget {
  const SwipeActionTile({
    super.key,
    required this.id,
    required this.open,
    required this.child,
    this.leading = const [],
    this.trailing = const [],
  });

  /// Ширина одного действия.
  static const double actionWidth = 76;

  /// Доля раскрытия, после которой строка остаётся открытой.
  static const double openThreshold = 0.4;

  final String id;

  /// Какая строка открыта сейчас (id) — общий для всего списка.
  final ValueNotifier<String?> open;
  final Widget child;
  final List<SwipeAction> leading;
  final List<SwipeAction> trailing;

  @override
  State<SwipeActionTile> createState() => _SwipeActionTileState();
}

class _SwipeActionTileState extends State<SwipeActionTile> with SingleTickerProviderStateMixin {
  late final AnimationController _offset;

  double get _leadingWidth => widget.leading.length * SwipeActionTile.actionWidth;
  double get _trailingWidth => widget.trailing.length * SwipeActionTile.actionWidth;

  bool get _isOpen => _offset.value.abs() > 1;

  @override
  void initState() {
    super.initState();
    _offset = AnimationController(
      vsync: this,
      lowerBound: -_trailingWidth,
      upperBound: _leadingWidth,
      value: 0,
    );
    widget.open.addListener(_onGroupChanged);
  }

  @override
  void dispose() {
    widget.open.removeListener(_onGroupChanged);
    _offset.dispose();
    super.dispose();
  }

  void _onGroupChanged() {
    if (widget.open.value != widget.id && _offset.value != 0) _settle(0);
  }

  Duration get _duration =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200);

  void _settle(double target) {
    _offset.animateTo(target, duration: _duration, curve: Curves.easeOutCubic);
    if (target != 0) {
      widget.open.value = widget.id;
    } else if (widget.open.value == widget.id) {
      widget.open.value = null;
    }
  }

  void _onDragStart(DragStartDetails details) {
    // Начали тянуть эту строку — остальные закрываются.
    if (widget.open.value != widget.id) widget.open.value = null;
    _offset.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _offset.value = (_offset.value + details.delta.dx).clamp(-_trailingWidth, _leadingWidth);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final value = _offset.value;
    if (_leadingWidth > 0 && (value > _leadingWidth * SwipeActionTile.openThreshold || velocity > 700) && value > 0) {
      _settle(_leadingWidth);
    } else if (_trailingWidth > 0 &&
        (value < -_trailingWidth * SwipeActionTile.openThreshold || velocity < -700) &&
        value < 0) {
      _settle(-_trailingWidth);
    } else {
      _settle(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.leading.isEmpty && widget.trailing.isEmpty) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _offset,
          builder: (context, _) {
            final dx = _offset.value;
            return Stack(
              children: [
                if (dx > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _ActionRow(actions: widget.leading, onDone: () => _settle(0)),
                    ),
                  ),
                if (dx < 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _ActionRow(actions: widget.trailing, onDone: () => _settle(0)),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(dx, 0),
                  child: Stack(
                    children: [
                      ColoredBox(color: context.cs.surface, child: widget.child),
                      if (_isOpen)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _settle(0),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.actions, required this.onDone});

  final List<SwipeAction> actions;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              onDone();
              action.onTap();
            },
            child: Semantics(
              button: true,
              label: action.label,
              excludeSemantics: true,
              child: SizedBox(
                width: SwipeActionTile.actionWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 40,
                      decoration: BoxDecoration(
                        color: action.color,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Icon(action.icon, size: 22, color: Colors.white),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1),
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
}
