import 'package:flutter/material.dart';

import '../context.dart';
import '../tokens.dart';

/// Касание без тяжёлой Material-волны: короткая мягкая подсветка фона
/// (и, если нужно, лёгкое уменьшение) за [Motion.fast].
///
/// Один виджет на строки списка и элементы ленты контактов.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.tint = true,
    this.scale = 1,
    this.borderRadius,
    this.semanticsLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Подсвечивать фон под содержимым.
  final bool tint;

  /// Масштаб при нажатии (1 — без изменения).
  final double scale;

  /// Скругление подсветки (для небольших элементов вроде заголовка чата).
  final BorderRadius? borderRadius;
  final String? semanticsLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final duration =
        MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.fast;
    final tint = widget.tint && _pressed ? context.rc.selection : Colors.transparent;
    Widget content = AnimatedContainer(
      duration: duration,
      curve: Motion.curve,
      decoration: BoxDecoration(color: tint, borderRadius: widget.borderRadius),
      child: widget.scale == 1
          ? widget.child
          : AnimatedScale(
              scale: _pressed ? widget.scale : 1,
              duration: duration,
              curve: Motion.curve,
              child: widget.child,
            ),
    );
    if (widget.semanticsLabel != null) {
      content = Semantics(
        button: true,
        label: widget.semanticsLabel,
        excludeSemantics: true,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: content,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: content,
    );
  }
}
