import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../brand/logo.dart';

/// «Потяните, чтобы обновить» со знаком «Реплики» вместо стандартного
/// кружка: маленькая сфера проявляется и растёт вместе с жестом,
/// поворачивается, а во время обновления вращается и переливается.
///
/// Работает с пружинящей прокруткой (ReplikaScrollBehavior): жест читается
/// по уходу списка за верхний край.
class ReplikaRefreshIndicator extends StatefulWidget {
  const ReplikaRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.triggerDistance = 84,
    this.logoSize = 34,
    this.minDuration = const Duration(milliseconds: 900),
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Насколько потянуть, чтобы обновить.
  final double triggerDistance;
  final double logoSize;

  /// Анимация видна не меньше этого времени, даже если данные уже готовы.
  final Duration minDuration;

  @override
  State<ReplikaRefreshIndicator> createState() => _ReplikaRefreshIndicatorState();
}

class _ReplikaRefreshIndicatorState extends State<ReplikaRefreshIndicator> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _hide = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  double _pull = 0;
  bool _armed = false;
  bool _refreshing = false;
  bool _dragging = false;

  @override
  void dispose() {
    _spin.dispose();
    _hide.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) {
      _dragging = n.dragDetails != null;
    } else if (n is ScrollUpdateNotification) {
      _dragging = n.dragDetails != null;
    } else if (n is ScrollEndNotification) {
      _dragging = false;
    }
    if (_refreshing) return false;

    // Край списка — minScrollExtent: всё, что «над» ним, — оттяжка.
    final over = n.metrics.minScrollExtent - n.metrics.pixels;
    final pull = over > 0 ? over : 0.0;

    // Палец отпущен за порогом — обновляем.
    if (_armed && !_dragging) {
      _start();
      return false;
    }
    var armed = _armed;
    if (_dragging) {
      armed = pull >= widget.triggerDistance;
      if (armed && !_armed) HapticFeedback.mediumImpact();
    }
    if (pull != _pull || armed != _armed) {
      setState(() {
        _pull = pull;
        _armed = armed;
      });
    }
    return false;
  }

  Future<void> _start() async {
    setState(() {
      _refreshing = true;
      _armed = false;
    });
    _hide.value = 0;
    unawaited(_spin.repeat());
    final started = DateTime.now();
    try {
      await widget.onRefresh();
    } catch (error) {
      debugPrint('Обновление не удалось: $error');
    }
    final left = widget.minDuration - DateTime.now().difference(started);
    if (left > Duration.zero) await Future<void>.delayed(left);
    if (!mounted) return;
    await _hide.forward();
    if (!mounted) return;
    _spin.stop();
    setState(() {
      _refreshing = false;
      _pull = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final progress = (_pull / widget.triggerDistance).clamp(0.0, 1.0);
    final visible = _refreshing || _pull > 4;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          if (visible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_spin, _hide]),
                  builder: (context, _) {
                    final shown = _refreshing ? 1.0 - _hide.value : Curves.easeOut.transform(progress);
                    final scale = _refreshing ? 1.0 - 0.4 * _hide.value : 0.5 + 0.5 * progress;
                    final turn = _refreshing ? _spin.value : progress * 0.6;
                    final top = _refreshing ? 14.0 : math.max(4.0, _pull / 2 - widget.logoSize / 2);
                    return Padding(
                      padding: EdgeInsets.only(top: top),
                      child: Center(
                        child: Opacity(
                          opacity: shown,
                          child: Transform.scale(
                            scale: scale,
                            child: Transform.rotate(
                              angle: reduce ? 0 : turn * 2 * math.pi,
                              child: _RefreshOrb(
                                size: widget.logoSize,
                                shine: reduce ? 0 : turn,
                                glow: _refreshing || _armed ? 1 : progress * 0.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RefreshOrb extends StatelessWidget {
  const _RefreshOrb({required this.size, required this.shine, required this.glow});

  final double size;
  final double shine;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Обновление',
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: logoGlow(size, glow)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ReplikaLogo(size: size),
              ClipOval(child: CustomPaint(painter: GlassShinePainter(turn: shine, strength: 1.4))),
            ],
          ),
        ),
      ),
    );
  }
}
