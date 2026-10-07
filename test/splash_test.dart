// Стартовый экран REPLIKA MESSENGER: состав, раскладка по эталону, анимации
// (появление сферы, «дыхание», полоса загрузки) и завершение.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/design_system/glass_background.dart';
import 'package:replika/design_system/glow_effect.dart';
import 'package:replika/design_system/loading_indicator.dart';
import 'package:replika/design_system/replika_logo.dart';
import 'package:replika/features/splash/splash_screen.dart';

Widget splash({bool reduceMotion = false, VoidCallback? onFinished}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: SplashScreen(onFinished: onFinished),
    );

void phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

ReplikaOrb orbOf(WidgetTester tester) => tester.widget<ReplikaOrb>(find.byType(ReplikaOrb));
double progressOf(WidgetTester tester) =>
    tester.widget<GlassLoadingBar>(find.byType(GlassLoadingBar)).progress;

void main() {
  const design = SplashScreen.design;

  group('Состав и раскладка', () {
    testWidgets('на холсте эталона элементы стоят на своих местах', (tester) async {
      phone(tester, design);
      await tester.pumpWidget(splash());
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(GlassBackground), findsOneWidget);
      expect(find.byType(ReplikaOrb), findsOneWidget);
      expect(find.byType(GlassLoadingBar), findsOneWidget);
      expect(find.byType(GlowEffect), findsOneWidget);
      expect(find.text('REPLIKA'), findsNWidgets(2), reason: 'буквы и слой свечения');
      expect(find.text('MESSENGER'), findsOneWidget);
      expect(find.text('Загрузка...'), findsOneWidget);

      // Сфера: центр и размер как в эталоне (246 из 393 пунктов ширины).
      final orb = tester.getRect(find.byType(ReplikaOrb));
      expect(orb.center.dx, closeTo(195.4, 0.5));
      expect(orb.center.dy, closeTo(291.0, 0.5));
      expect(orb.width, closeTo(246.3 * 496 / 430, 0.5), reason: 'сфера 246.3 плюс поле под ореол');

      // Строки: середина заглавных букв на отметках эталона.
      double capCenter(Finder f, double size) => tester.getTopLeft(f).dy + size * 0.4365;
      expect(capCenter(find.byType(SplashLogotype), 32.3), closeTo(441.4, 0.6));
      expect(capCenter(find.byType(SplashSubtitle), 17.3), closeTo(477.2, 0.6));
      expect(capCenter(find.byType(SplashStatusText), 12.6), closeTo(558.6, 0.6));

      // Полоса: по центру, 206×5.2.
      final bar = tester.getRect(find.byType(GlassLoadingBar));
      expect(bar.center.dx, closeTo(design.width / 2, 0.5));
      expect(bar.center.dy, closeTo(528.2, 0.5));
      expect(bar.width, closeTo(206 + GlassLoadingBar.glowPad * 2, 0.5));

      // Надписи и полоса по центру экрана.
      for (final f in [find.byType(SplashLogotype), find.byType(SplashSubtitle), find.byType(SplashStatusText)]) {
        expect(tester.getCenter(f).dx, closeTo(design.width / 2, 0.6));
      }
    });

    testWidgets('iPhone 393×852: всё масштабируется вместе и остаётся по центру', (tester) async {
      const screen = Size(393, 852);
      phone(tester, screen);
      await tester.pumpWidget(splash());
      await tester.pump(const Duration(seconds: 3));

      final scale = screen.height / design.height; // выше эталона → по высоте
      final shiftX = (screen.width - design.width * scale) / 2;
      final orb = tester.getRect(find.byType(ReplikaOrb));
      expect(orb.center.dx, closeTo(195.4 * scale + shiftX, 0.6));
      expect(orb.center.dy, closeTo(291.0 * scale, 0.6));
      expect(orb.width / orb.height, closeTo(1, 0.001), reason: 'сфера не искажена');

      // Порядок сверху вниз, как на эталоне.
      final ys = [
        orb.center.dy,
        tester.getCenter(find.byType(SplashLogotype)).dy,
        tester.getCenter(find.byType(SplashSubtitle)).dy,
        tester.getCenter(find.byType(GlassLoadingBar)).dy,
        tester.getCenter(find.byType(SplashStatusText)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(tester.getRect(find.byType(GlassLoadingBar)).right, lessThan(screen.width));
      expect(tester.takeException(), isNull);
    });

    testWidgets('невысокий экран 360×640: ничего не ломается, сфера целиком на экране', (tester) async {
      const screen = Size(360, 640);
      phone(tester, screen);
      await tester.pumpWidget(splash());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      final orb = tester.getRect(find.byType(ReplikaOrb));
      expect(orb.left, greaterThanOrEqualTo(0));
      expect(orb.right, lessThanOrEqualTo(screen.width));
      expect(orb.top, greaterThanOrEqualTo(0));
      final status = tester.getRect(find.byType(SplashStatusText));
      expect(status.bottom, lessThan(screen.height));
    });
  });

  group('Анимации', () {
    test('сфера: масштаб 0.95 → 1, яркость 70 % → 100 %', () {
      expect(ReplikaOrb.scaleFor(0), 0.95);
      expect(ReplikaOrb.scaleFor(1), 1);
      expect(ReplikaOrb.opacityFor(0, 1), 0);
      expect(ReplikaOrb.opacityFor(1, 0), closeTo(0.7, 1e-9));
      expect(ReplikaOrb.opacityFor(1, 1), 1);
      expect(SplashScreen.appearDuration, const Duration(milliseconds: 1200));
      expect(SplashScreen.glowDuration, const Duration(seconds: 3));
      expect(SplashScreen.loadingDuration, const Duration(milliseconds: 2500));
    });

    testWidgets('появление за 1200 мс, «дыхание» по кругу, полоса за 2,5 с', (tester) async {
      phone(tester, design);
      var finished = 0;
      await tester.pumpWidget(splash(onFinished: () => finished++));
      expect(orbOf(tester).appear, 0);
      expect(progressOf(tester), 0);

      await tester.pump(const Duration(milliseconds: 600));
      expect(orbOf(tester).appear, greaterThan(0.8), reason: 'easeOutCubic: быстро в начале');
      expect(orbOf(tester).appear, lessThan(1));

      await tester.pump(const Duration(milliseconds: 600)); // 1200
      expect(orbOf(tester).appear, 1);
      expect(progressOf(tester), inExclusiveRange(0.3, 0.6));

      await tester.pump(const Duration(milliseconds: 50)); // 1250 — середина полосы
      expect(progressOf(tester), closeTo(0.5, 0.02));

      await tester.pump(const Duration(milliseconds: 1150)); // 2400
      expect(finished, 0);
      expect(progressOf(tester), lessThan(1));

      await tester.pump(const Duration(milliseconds: 100)); // 2500
      expect(progressOf(tester), 1);
      expect(finished, 1);

      await tester.pump(const Duration(milliseconds: 500)); // 3000 — пик яркости
      expect(orbOf(tester).glow, closeTo(1, 0.001));
      await tester.pump(const Duration(milliseconds: 1500)); // 4500 — гаснет
      expect(orbOf(tester).glow, closeTo(0.5, 0.02));
      await tester.pump(const Duration(milliseconds: 1500)); // 6000 — минимум
      expect(orbOf(tester).glow, closeTo(0, 0.001));
      await tester.pump(const Duration(milliseconds: 1500)); // 7500 — снова растёт
      expect(orbOf(tester).glow, closeTo(0.5, 0.02));

      expect(finished, 1, reason: 'завершение сообщается один раз');
      expect(progressOf(tester), 1, reason: 'полоса остаётся заполненной, пока идёт запуск');
    });

    testWidgets('без анимаций: статичный экран и короткая задержка', (tester) async {
      phone(tester, design);
      var finished = 0;
      await tester.pumpWidget(splash(reduceMotion: true, onFinished: () => finished++));
      expect(orbOf(tester).appear, 1);
      expect(orbOf(tester).glow, 1);
      expect(progressOf(tester), 1);

      await tester.pump(const Duration(milliseconds: 500));
      expect(finished, 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(finished, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(orbOf(tester).glow, 1, reason: 'свечение не мигает');
    });
  });

  group('Полоса загрузки', () {
    testWidgets('значение ограничено 0…1, размер капсулы 206×5.2', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: GlassLoadingBar(progress: 3)),
      ));
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(GlassLoadingBar));
      expect(size.width, 206 + GlassLoadingBar.glowPad * 2);
      expect(size.height, closeTo(5.2 + GlassLoadingBar.glowPad * 2, 0.001));
      expect(find.byType(BackdropFilter), findsOneWidget, reason: 'дорожка — стекло');
      expect(GlassLoadingBar.fillColors.length, GlassLoadingBar.fillStops.length);
    });
  });
}
