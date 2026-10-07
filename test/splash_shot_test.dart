// Снимок стартового экрана для сверки с эталоном docs/brand/splash_reference.png.
// Пишет build/splash_shot_a.png (полоса ~2/3, как на эталоне) и
// build/splash_shot_b.png (пик свечения). В CI снимок выводится шагом
// «Снимок стартового экрана» (tool/ci_emit_image.py).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/design_system/glass_background.dart';
import 'package:replika/design_system/replika_logo.dart';
import 'package:replika/features/splash/splash_screen.dart';

void main() {
  testWidgets('снимок экрана 393×852', (tester) async {
    const screen = Size(393, 852);
    const ratio = 2.0;
    tester.view.physicalSize = screen * ratio;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);

    // Настоящий шрифт приложения вместо тестового.
    await tester.runAsync(() async {
      final loader = FontLoader('Inter');
      for (final name in ['Regular', 'Medium']) {
        final bytes = File('assets/fonts/Inter-$name.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    });

    const key = Key('shot');
    await tester.pumpWidget(const RepaintBoundary(
      key: key,
      child: MaterialApp(debugShowCheckedModeBanner: false, home: SplashScreen()),
    ));
    await tester.runAsync(() async {
      final context = tester.element(find.byType(SplashScreen));
      await precacheImage(const AssetImage(GlassBackground.asset), context);
      await precacheImage(const AssetImage(ReplikaOrb.asset), context);
    });

    Future<void> save(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/$name')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pump(const Duration(milliseconds: 1500));
    await save('splash_shot_a.png');
    await tester.pump(const Duration(milliseconds: 1500));
    await save('splash_shot_b.png');

    expect(File('build/splash_shot_a.png').lengthSync(), greaterThan(10000));
    expect(tester.takeException(), isNull);
  });
}
