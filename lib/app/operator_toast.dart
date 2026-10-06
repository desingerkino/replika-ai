import 'package:flutter/material.dart';

import '../core/design/tokens.dart';
import 'navigator.dart';

/// Короткая плашка поверх любого экрана (например, «Сцена сброшена»).
/// Показывается только по настройке — между дублями, не во время съёмки.
void showOperatorToast(String text) {
  final overlay = AppNavigator.key.currentState?.overlay;
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(text: text, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({required this.text, required this.onDone});

  final String text;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: FadeTransition(
          opacity: TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 15),
            TweenSequenceItem(tween: ConstantTween(1), weight: 60),
            TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 25),
          ]).animate(_controller),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: Space.xxl),
            padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.l),
            decoration: BoxDecoration(
              color: OperatorPalette.background.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.restart_alt_rounded, color: OperatorPalette.standby),
                const SizedBox(width: Space.m),
                Flexible(
                  child: Text(
                    widget.text,
                    style: const TextStyle(
                      color: OperatorPalette.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
