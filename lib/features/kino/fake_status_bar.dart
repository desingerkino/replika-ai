import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/kino.dart';
import '../../app/services.dart';
import '../../core/design/colors.dart';
import '../../core/design/tokens.dart';
import '../../core/util/time_format.dart';
import '../../core/util/platform_info.dart';

/// Высота нарисованной строки состояния (как у Android) и минимальная
/// высота полосы на iOS.
const double kinoStatusBarHeight = 26;

/// Где рисуется строка состояния кинорежима: отступ сверху и высота полосы.
///
/// Android: полоса под системным отступом, высота фиксирована.
/// iOS: полоса занимает всю системную область сверху. На iPhone с вырезом или
/// Dynamic Island это высота выреза (время слева от него, значки справа, как у
/// настоящей строки), без выреза (iPad, старые iPhone) — обычная полоса сверху.
/// Размеры берутся из системных отступов, а не из модели устройства.
({double top, double height}) kinoStatusBand(MediaQueryData media, {required bool ios}) {
  if (!ios) return (top: media.padding.top, height: kinoStatusBarHeight);
  final inset = media.viewPadding.top;
  return (top: 0.0, height: inset > kinoStatusBarHeight ? inset : kinoStatusBarHeight);
}

/// Сколько из четырёх полос сигнала закрашено. Уровень оператора — 0…3:
/// 0 — нет сигнала, 3 — полный.
int signalBars(int level) => level <= 0 ? 0 : (level + 1).clamp(0, 4);

/// Доля заполнения батареи (0…1) по проценту заряда.
double batteryFill(int level) => level.clamp(0, 100) / 100;

/// Строка состояния, которую рисует приложение в КИНОРЕЖИМЕ: время,
/// сеть, сигнал, заряд — всё задаёт оператор.
class FakeStatusBar extends StatefulWidget {
  const FakeStatusBar({
    super.key,
    required this.settings,
    required this.lightIcons,
    this.height = kinoStatusBarHeight,
  });

  final KinoSettings settings;

  /// Высота полосы: на iPhone с вырезом больше обычной, строка по центру.
  final double height;

  /// Светлые значки — над тёмным экраном (звонок, просмотр фото).
  final bool lightIcons;

  @override
  State<FakeStatusBar> createState() => _FakeStatusBarState();
}

class _FakeStatusBarState extends State<FakeStatusBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final s = widget.settings;
    final time = kinoClockTime(
      settings: s,
      now: DateTime.now(),
      sceneNow: services.engine.sceneNow(),
      fixedSince: services.kino.fixedSince,
    );
    final light = widget.lightIcons || Theme.of(context).brightness == Brightness.dark;
    final color = light ? Colors.white : Palette.ink;
    // Полоса у выреза (iPhone с Dynamic Island) выше обычной: там и время, и
    // значки крупнее, как у настоящей строки.
    final tall = widget.height > 40;
    final k = tall ? 1.0 : 0.88;
    // inherit: false — строка состояния остаётся системным шрифтом телефона
    // (на iPhone SF, на Android Roboto), а не Inter интерфейса мессенджера:
    // в кадре она должна выглядеть как настоящая системная.
    final text = TextStyle(
      inherit: false,
      color: color,
      fontSize: tall ? 16 : 13.5,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      decoration: TextDecoration.none,
    );
    final small = text.copyWith(fontSize: tall ? 12.5 : 11);

    // Значки нарисованы самим приложением (не Material): четыре полосы
    // сигнала, веер Wi-Fi, батарея с контуром и «носиком».
    final signal = CustomPaint(
      size: Size(17 * k, 11.5 * k),
      painter: _SignalPainter(color: color, filled: signalBars(s.signal)),
    );
    final wifi = CustomPaint(size: Size(16 * k, 11.5 * k), painter: _WifiPainter(color: color));
    final network = Text(s.network.label, style: small);
    final hasNetwork = s.network != KinoNetwork.none;
    final battery = CustomPaint(
      size: Size(25 * k, 12 * k),
      painter: _BatteryPainter(
        color: color,
        fill: batteryFill(s.battery),
        charging: s.charging,
        chargeColor: light ? ReplikaColors.dark.success : ReplikaColors.light.success,
      ),
    );
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: MediaQuery.withNoTextScaling(
          child: SizedBox(
            height: widget.height,
            child: Padding(
              // У выреза время и значки отодвигаются от края, как у настоящей строки.
              padding: EdgeInsets.symmetric(horizontal: tall ? 30 : 18),
              child: Row(
                children: [
                  Text(formatClock(time), style: text),
                  const Spacer(),
                  if (isIOS) ...[
                    // iPhone: полосы, затем Wi-Fi либо тип сети (при Wi-Fi
                    // тип сотовой сети настоящий iPhone не показывает).
                    signal,
                    if (s.wifi) ...[const SizedBox(width: 5), wifi] else if (hasNetwork) ...[
                      const SizedBox(width: 4),
                      network,
                    ],
                  ] else ...[
                    if (s.wifi) ...[wifi, const SizedBox(width: 4)],
                    if (hasNetwork) ...[network, const SizedBox(width: 3)],
                    signal,
                  ],
                  const SizedBox(width: 6),
                  Text('${s.battery}%', style: text.copyWith(fontSize: tall ? 13 : 12.5)),
                  const SizedBox(width: 3),
                  battery,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Сотовый сигнал: четыре полосы по возрастанию; незакрашенные — бледные.
class _SignalPainter extends CustomPainter {
  const _SignalPainter({required this.color, required this.filled});

  final Color color;
  final int filled;

  static const List<double> _heights = [0.40, 0.58, 0.78, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width * 0.09;
    final bar = (size.width - gap * 3) / 4;
    final radius = Radius.circular(bar * 0.3);
    for (var i = 0; i < 4; i++) {
      final height = size.height * _heights[i];
      final left = i * (bar + gap);
      final paint = Paint()
        ..isAntiAlias = true
        ..color = i < filled ? color : color.withValues(alpha: 0.3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left, size.height - height, bar, height), radius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SignalPainter old) => old.color != color || old.filled != filled;
}

/// Wi-Fi: веер из точки и двух дуг, раскрытый на четверть круга.
class _WifiPainter extends CustomPainter {
  const _WifiPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final outer = size.height;
    final stroke = outer * 0.2;
    const start = -math.pi * 3 / 4;
    const sweep = math.pi / 2;
    final arc = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final radius in [outer - stroke / 2, outer * 0.56]) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, arc);
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outer * 0.3),
      start,
      sweep,
      true,
      Paint()
        ..isAntiAlias = true
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_WifiPainter old) => old.color != color;
}

/// Батарея: контур, «носик» справа и заполнение по уровню заряда.
/// На зарядке заполнение зелёное и поверх рисуется молния.
class _BatteryPainter extends CustomPainter {
  const _BatteryPainter({
    required this.color,
    required this.fill,
    required this.charging,
    required this.chargeColor,
  });

  final Color color;
  final double fill;
  final bool charging;
  final Color chargeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final cap = size.width * 0.06;
    final gap = size.width * 0.04;
    final bodyWidth = size.width - cap - gap;
    final outline = color.withValues(alpha: 0.45);
    final line = h * 0.1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(line / 2, line / 2, bodyWidth - line, h - line),
        Radius.circular(h * 0.28),
      ),
      Paint()
        ..isAntiAlias = true
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = line,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bodyWidth + gap, h * 0.32, cap, h * 0.36),
        Radius.circular(cap / 2),
      ),
      Paint()
        ..isAntiAlias = true
        ..color = outline,
    );

    final inset = line * 2;
    final innerWidth = bodyWidth - inset * 2;
    if (fill > 0) {
      final width = math.max(innerWidth * fill, h * 0.14);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, inset, width, h - inset * 2),
          Radius.circular(h * 0.14),
        ),
        Paint()
          ..isAntiAlias = true
          ..color = charging ? chargeColor : color,
      );
    }

    if (charging) {
      // Молния по центру корпуса, 70 % его высоты.
      final bh = h * 0.7;
      final bw = bh * 0.6;
      final ox = (bodyWidth - bw) / 2;
      final oy = (h - bh) / 2;
      Offset at(double x, double y) => Offset(ox + bw * x, oy + bh * y);
      final bolt = Path()
        ..moveTo(at(0.62, 0).dx, at(0.62, 0).dy)
        ..lineTo(at(0.05, 0.58).dx, at(0.05, 0.58).dy)
        ..lineTo(at(0.45, 0.58).dx, at(0.45, 0.58).dy)
        ..lineTo(at(0.38, 1).dx, at(0.38, 1).dy)
        ..lineTo(at(0.95, 0.42).dx, at(0.95, 0.42).dy)
        ..lineTo(at(0.55, 0.42).dx, at(0.55, 0.42).dy)
        ..close();
      canvas.drawPath(
        bolt,
        Paint()
          ..isAntiAlias = true
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.color != color || old.fill != fill || old.charging != charging || old.chargeColor != chargeColor;
}

/// Рамка приложения в КИНОРЕЖИМЕ: своя строка состояния поверх экранов,
/// а экраны получают отступ сверху, как под настоящей строкой.
class KinoFrame extends StatelessWidget {
  const KinoFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ValueListenableBuilder<KinoSettings>(
      valueListenable: services.kino,
      builder: (context, settings, _) {
        if (!settings.enabled || !settings.fakeStatusBar) return child;
        final mq = MediaQuery.of(context);
        final band = kinoStatusBand(mq, ios: isIOS);
        return MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(top: band.top + band.height),
            viewPadding: mq.viewPadding.copyWith(
              top: isIOS ? band.height : mq.viewPadding.top + kinoStatusBarHeight,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: child),
              Positioned(
                top: band.top,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<int>(
                  valueListenable: services.darkScreens,
                  builder: (context, dark, _) =>
                      FakeStatusBar(settings: settings, lightIcons: dark > 0, height: band.height),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
