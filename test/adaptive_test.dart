// Адаптивность по размеру окна: порог двухпанельной раскладки, ограничение
// ширины содержимого, выбор чата справа без отдельного окна.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/navigator.dart';
import 'package:replika/core/design/adaptive.dart';
import 'package:replika/features/kino/fake_status_bar.dart';

void main() {
  group('isWideWindow', () {
    test('iPhone в портрете и в ландшафте остаётся одноколоночным', () {
      expect(isWideWindow(const Size(393, 852)), isFalse);
      expect(isWideWindow(const Size(932, 430)), isFalse);
    });

    test('iPad mini в портрете — одна колонка, в ландшафте — две панели', () {
      expect(isWideWindow(const Size(744, 1133)), isFalse);
      expect(isWideWindow(const Size(1133, 744)), isTrue);
    });

    test('большой iPad и узкое окно Split View', () {
      expect(isWideWindow(const Size(1024, 1366)), isTrue);
      expect(isWideWindow(const Size(678, 1024)), isFalse);
      expect(isWideWindow(const Size(840, 480)), isTrue);
      expect(isWideWindow(const Size(839, 900)), isFalse);
    });
  });

  group('kinoStatusBand', () {
    test('iPhone с Dynamic Island: полоса на всю системную область сверху', () {
      const media = MediaQueryData(padding: EdgeInsets.only(top: 59), viewPadding: EdgeInsets.only(top: 59));
      final band = kinoStatusBand(media, ios: true);
      expect(band.top, 0);
      expect(band.height, 59);
    });

    test('iPad и iPhone без выреза: обычная полоса сверху', () {
      expect(kinoStatusBand(const MediaQueryData(), ios: true), (top: 0.0, height: kinoStatusBarHeight));
      const se = MediaQueryData(padding: EdgeInsets.only(top: 20), viewPadding: EdgeInsets.only(top: 20));
      expect(kinoStatusBand(se, ios: true).height, kinoStatusBarHeight);
    });

    test('Android: полоса под системным отступом, высота прежняя', () {
      const media = MediaQueryData(padding: EdgeInsets.only(top: 32), viewPadding: EdgeInsets.only(top: 32));
      final band = kinoStatusBand(media, ios: false);
      expect(band.top, 32);
      expect(band.height, kinoStatusBarHeight);
    });
  });

  group('ContentWidth', () {
    testWidgets('на широком экране ограничивает ширину и центрирует', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: ContentWidth(child: SizedBox.expand(key: Key('c'))),
      ));
      final size = tester.getSize(find.byKey(const Key('c')));
      expect(size.width, chatContentMaxWidth);
      expect(size.height, 800);
      expect(tester.getTopLeft(find.byKey(const Key('c'))).dx, (1200 - chatContentMaxWidth) / 2);
    });

    testWidgets('на узком экране ширина равна доступной', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: ContentWidth(child: SizedBox.expand(key: Key('c'))),
      ));
      expect(tester.getSize(find.byKey(const Key('c'))).width, 400);
    });
  });

  group('AppNavigator в двухпанельной раскладке', () {
    tearDown(() {
      AppNavigator.twoPane.value = false;
      AppNavigator.detailChat.value = null;
      AppNavigator.detailScreen.value = null;
      AppNavigator.homeTab.value = 0;
    });

    testWidgets('openChat выбирает чат справа и не открывает новый экран', (tester) async {
      await tester.pumpWidget(MaterialApp(navigatorKey: AppNavigator.key, home: const SizedBox()));
      AppNavigator.twoPane.value = true;
      await AppNavigator.openChat('c1', revealMessageId: 'm1');
      expect(AppNavigator.detailChat.value, const ChatTarget('c1', revealMessageId: 'm1'));
      expect(AppNavigator.key.currentState!.canPop(), isFalse);
    });

    testWidgets('«Назад» сначала закрывает чат справа, toRoot тоже', (tester) async {
      await tester.pumpWidget(MaterialApp(navigatorKey: AppNavigator.key, home: const SizedBox()));
      AppNavigator.twoPane.value = true;
      AppNavigator.detailChat.value = const ChatTarget('c1');
      AppNavigator.back();
      expect(AppNavigator.detailChat.value, isNull);

      AppNavigator.detailChat.value = const ChatTarget('c2');
      AppNavigator.toRoot();
      expect(AppNavigator.detailChat.value, isNull);
    });

    testWidgets('в «Настройках» экраны открываются справа и закрываются «Назад»', (tester) async {
      await tester.pumpWidget(MaterialApp(navigatorKey: AppNavigator.key, home: const SizedBox()));
      AppNavigator.twoPane.value = true;
      AppNavigator.homeTab.value = 3;
      await AppNavigator.openAddons();
      expect(AppNavigator.detailScreen.value?.name, '/addons');
      expect(AppNavigator.key.currentState!.canPop(), isFalse);
      AppNavigator.back();
      expect(AppNavigator.detailScreen.value, isNull);
    });

    testWidgets('вне «Настроек» экран открывается отдельным окном', (tester) async {
      await tester.pumpWidget(MaterialApp(navigatorKey: AppNavigator.key, home: const SizedBox()));
      AppNavigator.twoPane.value = true;
      AppNavigator.homeTab.value = 0;
      // Маршрут добавляется сразу; кадр не строим: экран требует служб приложения.
      unawaited(AppNavigator.openAddons());
      expect(AppNavigator.detailScreen.value, isNull);
      expect(AppNavigator.key.currentState!.canPop(), isTrue);
    });
  });
}
