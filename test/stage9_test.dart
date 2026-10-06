import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/kino.dart';
import 'package:replika/features/kino/fake_status_bar.dart';

void main() {
  test('настройки кинорежима сохраняются и читаются без потерь', () {
    const s = KinoSettings(
      enabled: true,
      clock: KinoClock.fixed,
      fixedTime: '02:15',
      battery: 12,
      charging: true,
      signal: 1,
      network: KinoNetwork.g5,
      wifi: true,
    );
    final copy = KinoSettings.fromJson(
      '{"enabled":true,"fakeStatusBar":true,"clock":"fixed","fixedTime":"02:15",'
      '"battery":12,"charging":true,"signal":1,"network":"g5","wifi":true}',
    );
    expect(copy.toJson(), s.toJson());
  });

  test('повреждённые настройки — значения по умолчанию', () {
    expect(KinoSettings.fromJson('{не json').enabled, isFalse);
    expect(KinoSettings.fromJson(null).battery, 64);
    expect(const KinoSettings().copyWith(battery: 150, signal: 9).battery, 100);
    expect(const KinoSettings().copyWith(signal: -1).signal, 0);
  });

  test('время в строке состояния', () {
    final now = DateTime(2026, 9, 25, 14, 0, 30);
    final since = DateTime(2026, 9, 25, 14, 0, 0);
    final scene = DateTime(2026, 9, 25, 23, 48);
    DateTime at(KinoClock clock) => kinoClockTime(
          settings: KinoSettings(clock: clock, fixedTime: '23:47'),
          now: now,
          sceneNow: scene,
          fixedSince: since,
        );
    expect(at(KinoClock.real), now);
    expect(at(KinoClock.scene), scene);
    expect(at(KinoClock.fixed), DateTime(2026, 9, 25, 23, 47, 30));
    expect(
      kinoClockTime(settings: const KinoSettings(), now: now, sceneNow: null, fixedSince: since),
      now,
      reason: 'без сцены — реальное время',
    );
  });

  test('значки заряда и сигнала', () {
    expect(batteryIcon(100), Icons.battery_full);
    expect(batteryIcon(3), Icons.battery_0_bar);
    expect(batteryIcon(50, charging: true), Icons.battery_charging_full);
    expect(signalIcon(3), Icons.signal_cellular_alt);
    expect(signalIcon(0), Icons.signal_cellular_0_bar);
  });
}
