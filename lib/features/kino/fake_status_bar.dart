import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/kino.dart';
import '../../app/services.dart';
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

IconData batteryIcon(int level, {bool charging = false}) {
  if (charging) return Icons.battery_charging_full;
  if (level >= 95) return Icons.battery_full;
  if (level >= 80) return Icons.battery_6_bar;
  if (level >= 65) return Icons.battery_5_bar;
  if (level >= 50) return Icons.battery_4_bar;
  if (level >= 35) return Icons.battery_3_bar;
  if (level >= 20) return Icons.battery_2_bar;
  if (level >= 8) return Icons.battery_1_bar;
  return Icons.battery_0_bar;
}

IconData signalIcon(int level) => switch (level) {
      0 => Icons.signal_cellular_0_bar,
      1 => Icons.signal_cellular_alt_1_bar,
      2 => Icons.signal_cellular_alt_2_bar,
      _ => Icons.signal_cellular_alt,
    };

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
    final color = widget.lightIcons || Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF15202B);
    // inherit: false — строка состояния остаётся системным шрифтом телефона
    // (на iPhone SF, на Android Roboto), а не Inter интерфейса мессенджера:
    // в кадре она должна выглядеть как настоящая системная.
    final text = TextStyle(
      inherit: false,
      color: color,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      decoration: TextDecoration.none,
    );
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: MediaQuery.withNoTextScaling(
          child: SizedBox(
            height: widget.height,
            child: Padding(
              // У выреза время и значки отодвигаются от края, как у настоящей строки.
              padding: EdgeInsets.symmetric(horizontal: widget.height > 40 ? 30 : 18),
              child: Row(
                children: [
                  Text(formatClock(time), style: text),
                  const Spacer(),
                  if (s.wifi) ...[Icon(Icons.wifi, size: 15, color: color), const SizedBox(width: 4)],
                  if (s.network != KinoNetwork.none) ...[
                    Text(s.network.label, style: text.copyWith(fontSize: 11)),
                    const SizedBox(width: 2),
                  ],
                  Icon(signalIcon(s.signal), size: 15, color: color),
                  const SizedBox(width: 6),
                  Text('${s.battery}%', style: text.copyWith(fontSize: 12.5)),
                  const SizedBox(width: 2),
                  Icon(batteryIcon(s.battery, charging: s.charging), size: 16, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
