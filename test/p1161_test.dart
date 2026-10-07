// P1.16.1: фото и видео занимают область просмотра, а не размер файла/превью.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/features/media/fitted_media.dart';

const _portrait =
    'iVBORw0KGgoAAAANSUhEUgAAABQAAAAeCAIAAACjcKk8AAAAHklEQVR4nGPQqDhBNmIY1TyqeVTzqOZRzaOah7NmAAAPS+7M0IGHAAAAAElFTkSuQmCC';
const _landscape =
    'iVBORw0KGgoAAAANSUhEUgAAAB4AAAAUCAIAAAAVyRqTAAAAH0lEQVR4nGPQqDhBI8QwavSo0aPGjxo9avSo0UPRaACERkvulyYRrAAAAABJRU5ErkJggg==';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: SizedBox(width: 400, height: 800, child: child)),
      ),
    );

Future<RenderImage> _pumpPhoto(WidgetTester tester, String base64Png, {bool zoomable = false}) async {
  final provider = MemoryImage(base64Decode(base64Png));
  await tester.pumpWidget(_host(FittedPhoto(image: provider, zoomable: zoomable)));
  await tester.runAsync(() => precacheImage(provider, tester.element(find.byType(FittedPhoto))));
  await tester.pump();
  return tester.renderObject<RenderImage>(find.byType(RawImage));
}

Size _painted(RenderImage render) {
  final image = render.image!;
  return applyBoxFit(render.fit!, Size(image.width.toDouble(), image.height.toDouble()), render.size)
      .destination;
}

void main() {
  group('Фото в просмотре', () {
    testWidgets('книжное маленькое фото растягивается на область, а не остаётся 20×30', (tester) async {
      final render = await _pumpPhoto(tester, _portrait);
      expect(render.image!.width, 20);
      expect(render.image!.height, 30);
      expect(render.size, const Size(400, 800), reason: 'область = ограничения экрана');
      final painted = _painted(render);
      expect(painted.width, closeTo(400, 0.5));
      expect(painted.height, closeTo(600, 0.5));
      expect(painted.width / painted.height, closeTo(20 / 30, 0.01), reason: 'пропорции сохранены');
    });

    testWidgets('альбомное маленькое фото вписывается по ширине', (tester) async {
      final render = await _pumpPhoto(tester, _landscape);
      expect(render.size, const Size(400, 800));
      final painted = _painted(render);
      expect(painted.width, closeTo(400, 0.5));
      expect(painted.height, closeTo(400 * 20 / 30, 0.5));
    });

    testWidgets('с увеличением (просмотр сообщений) раскладка та же', (tester) async {
      final render = await _pumpPhoto(tester, _portrait, zoomable: true);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(render.size, const Size(400, 800));
      expect(_painted(render).width, closeTo(400, 0.5));
    });

    testWidgets('в историях без увеличения: тот же размер', (tester) async {
      final render = await _pumpPhoto(tester, _landscape);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(_painted(render).width, closeTo(400, 0.5));
    });
  });

  group('Видео в просмотре', () {
    Size shown(WidgetTester tester, Finder finder) =>
        Size(
          tester.getBottomRight(finder).dx - tester.getTopLeft(finder).dx,
          tester.getBottomRight(finder).dy - tester.getTopLeft(finder).dy,
        );

    testWidgets('маленький кадр 160×90 увеличивается до ширины экрана', (tester) async {
      await tester.pumpWidget(_host(
        const FittedContent(size: Size(160, 90), child: ColoredBox(key: Key('frame'), color: Colors.red)),
      ));
      final size = shown(tester, find.byKey(const Key('frame')));
      expect(size.width, closeTo(400, 0.5));
      expect(size.height, closeTo(225, 0.5));
    });

    testWidgets('вертикальное видео вписывается без искажений', (tester) async {
      await tester.pumpWidget(_host(
        const FittedContent(size: Size(1080, 1920), child: ColoredBox(key: Key('frame'), color: Colors.red)),
      ));
      final size = shown(tester, find.byKey(const Key('frame')));
      expect(size.width / size.height, closeTo(1080 / 1920, 0.01));
      expect(size.width, closeTo(400, 0.5));
      expect(size.height, lessThanOrEqualTo(800.5));
    });

    testWidgets('неизвестный размер (до инициализации) — 16:9 на всю ширину', (tester) async {
      await tester.pumpWidget(_host(
        const FittedContent(size: Size.zero, child: ColoredBox(key: Key('frame'), color: Colors.red)),
      ));
      final size = shown(tester, find.byKey(const Key('frame')));
      expect(size.width, closeTo(400, 0.5));
      expect(size.height, closeTo(225, 0.5));
    });
  });

  testWidgets('без ограничений по высоте берётся экран, а не размер файла', (tester) async {
    final provider = MemoryImage(base64Decode(_portrait));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: FittedPhoto(image: provider)),
      ),
    ));
    await tester.runAsync(() => precacheImage(provider, tester.element(find.byType(FittedPhoto))));
    await tester.pump();
    final render = tester.renderObject<RenderImage>(find.byType(RawImage));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(render.size.height, screen.height);
    expect(render.size.width, screen.width);
  });
}
