import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Откуда брать время в нарисованной строке состояния.
enum KinoClock {
  scene('Время сцены (если задано), иначе реальное'),
  fixed('Своё время — идёт от заданного'),
  real('Реальное время телефона');

  const KinoClock(this.label);
  final String label;
}

/// Сеть в нарисованной строке состояния.
enum KinoNetwork {
  none(''),
  g4('4G'),
  lte('LTE'),
  g5('5G');

  const KinoNetwork(this.label);
  final String label;
}

/// Настройки КИНОРЕЖИМА. Хранятся одной строкой JSON в настройках.
@immutable
class KinoSettings {
  const KinoSettings({
    this.enabled = false,
    this.fakeStatusBar = true,
    this.clock = KinoClock.scene,
    this.fixedTime = '23:47',
    this.battery = 64,
    this.charging = false,
    this.signal = 3,
    this.network = KinoNetwork.lte,
    this.wifi = false,
  });

  final bool enabled;

  /// Скрыть системные панели и рисовать свою строку состояния.
  final bool fakeStatusBar;
  final KinoClock clock;

  /// «ЧЧ:ММ» для [KinoClock.fixed].
  final String fixedTime;

  /// Заряд батареи в процентах (0–100).
  final int battery;
  final bool charging;

  /// Уровень сигнала 0–3.
  final int signal;
  final KinoNetwork network;
  final bool wifi;

  KinoSettings copyWith({
    bool? enabled,
    bool? fakeStatusBar,
    KinoClock? clock,
    String? fixedTime,
    int? battery,
    bool? charging,
    int? signal,
    KinoNetwork? network,
    bool? wifi,
  }) =>
      KinoSettings(
        enabled: enabled ?? this.enabled,
        fakeStatusBar: fakeStatusBar ?? this.fakeStatusBar,
        clock: clock ?? this.clock,
        fixedTime: fixedTime ?? this.fixedTime,
        battery: (battery ?? this.battery).clamp(0, 100),
        charging: charging ?? this.charging,
        signal: (signal ?? this.signal).clamp(0, 3),
        network: network ?? this.network,
        wifi: wifi ?? this.wifi,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'fakeStatusBar': fakeStatusBar,
        'clock': clock.name,
        'fixedTime': fixedTime,
        'battery': battery,
        'charging': charging,
        'signal': signal,
        'network': network.name,
        'wifi': wifi,
      };

  static KinoSettings fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const KinoSettings();
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return const KinoSettings();
      T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
          values.where((v) => v.name == name).firstOrNull ?? fallback;
      return const KinoSettings().copyWith(
        enabled: map['enabled'] == true,
        fakeStatusBar: map['fakeStatusBar'] != false,
        clock: pick(KinoClock.values, map['clock'], KinoClock.scene),
        fixedTime: map['fixedTime'] is String ? map['fixedTime'] as String : null,
        battery: map['battery'] is num ? (map['battery'] as num).toInt() : null,
        charging: map['charging'] == true,
        signal: map['signal'] is num ? (map['signal'] as num).toInt() : null,
        network: pick(KinoNetwork.values, map['network'], KinoNetwork.lte),
        wifi: map['wifi'] == true,
      );
    } on FormatException {
      return const KinoSettings();
    }
  }
}

/// Время в нарисованной строке состояния.
DateTime kinoClockTime({
  required KinoSettings settings,
  required DateTime now,
  required DateTime? sceneNow,
  required DateTime? fixedSince,
}) {
  switch (settings.clock) {
    case KinoClock.real:
      return now;
    case KinoClock.scene:
      return sceneNow ?? now;
    case KinoClock.fixed:
      final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(settings.fixedTime.trim());
      if (match == null) return now;
      final start = DateTime(now.year, now.month, now.day,
          int.parse(match.group(1)!).clamp(0, 23), int.parse(match.group(2)!).clamp(0, 59));
      return start.add(now.difference(fixedSince ?? now));
  }
}

/// КИНОРЕЖИМ: телефон выглядит как обычный телефон персонажа, без следов
/// операторской и служебных пунктов.
class KinoController extends ValueNotifier<KinoSettings> {
  KinoController(super.value, {required this.persist}) {
    _lifecycle = AppLifecycleListener(onResume: apply);
  }

  final Future<void> Function(String json) persist;
  late final AppLifecycleListener _lifecycle;

  /// Когда отсчёт «своего времени» начался (включение режима или смена времени).
  DateTime _fixedSince = DateTime.now();
  DateTime get fixedSince => _fixedSince;

  bool get enabled => value.enabled;

  Future<void> update(KinoSettings settings) async {
    if (settings.fixedTime != value.fixedTime || (settings.enabled && !value.enabled)) {
      _fixedSince = DateTime.now();
    }
    value = settings;
    apply();
    await persist(jsonEncode(settings.toJson()));
  }

  /// Системные панели: в кинорежиме со своей строкой — скрыты
  /// (свайп от края временно показывает их), иначе — как обычно.
  void apply() {
    final hide = value.enabled && value.fakeStatusBar;
    unawaited(SystemChrome.setEnabledSystemUIMode(
      hide ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    ).catchError((Object error) => debugPrint('Системные панели не переключены: $error')));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }
}
