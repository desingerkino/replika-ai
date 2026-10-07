import 'package:flutter/material.dart';

import 'replika_logo.dart';

/// «Потянуть, чтобы обновить» с маленькой светящейся сферой Replika вместо
/// обычного кольца. Список внутри должен «пружинить» у верхнего края
/// (BouncingScrollPhysics) — сфера появляется в освободившемся месте.
class OrbRefresh extends StatefulWidget {
  const OrbRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Насколько нужно оттянуть список, чтобы обновление началось.
  static const double threshold = 72;

  /// Сколько сфера остаётся на экране, даже если данные пришли мгновенно.
  static const Duration minSpin = Duration(milliseconds: 700);

  @override
  State<OrbRefresh> createState() => _OrbRefreshState();
}

class _OrbRefreshState extends State<OrbRefresh> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  double _pull = 0;
  bool _refreshing = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification note) {
    if (note.depth != 0 || _refreshing) return false;
    if (note is ScrollUpdateNotification) {
      final over = -note.metrics.pixels;
      final pull = (over / OrbRefresh.threshold).clamp(0.0, 1.0);
      final released = note.dragDetails == null;
      if (released && _pull >= 1) {
        _start();
      } else if (!released || pull < _pull) {
        if ((pull - _pull).abs() > 0.01) setState(() => _pull = pull);
      }
    } else if (note is ScrollEndNotification && _pull != 0) {
      setState(() => _pull = 0);
    }
    return false;
  }

  Future<void> _start() async {
    setState(() {
      _refreshing = true;
      _pull = 1;
    });
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion) _pulse.repeat(reverse: true);
    try {
      await Future.wait([
        widget.onRefresh(),
        Future<void>.delayed(OrbRefresh.minSpin),
      ]);
    } finally {
      if (mounted) {
        _pulse
          ..stop()
          ..value = 0;
        setState(() {
          _refreshing = false;
          _pull = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          if (_pull > 0)
            Positioned(
              top: 6 + 14 * _pull,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => ReplikaOrb(
                      diameter: 30,
                      appear: _pull,
                      glow: _refreshing ? _pulse.value : _pull,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
