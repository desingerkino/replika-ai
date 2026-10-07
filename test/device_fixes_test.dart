// Исправления после проверки на iPhone: просмотр фото/видео на весь экран
// и панель записи голосового, которая не «раздувается».
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/core/design/tokens.dart';
import 'package:replika/data/models/media_item.dart';
import 'package:replika/features/media/fitted_media.dart';
import 'package:replika/features/media/media_content.dart';
import 'package:replika/features/record/recording_bar.dart';
import 'package:replika/features/record/voice_recording.dart';

const _portraitPng =
    'iVBORw0KGgoAAAANSUhEUgAAABQAAAAeCAIAAACjcKk8AAAAHklEQVR4nGPQqDhBNmIY1TyqeVTzqOZRzaOah7NmAAAPS+7M0IGHAAAAAElFTkSuQmCC';

const _content = Key('content');
const _overlay = Key('overlay');

/// Кнопка «Закрыть» просмотра: обычный (не Positioned) ребёнок Stack.
const Widget _closeButton = Padding(
  padding: EdgeInsets.all(4),
  child: SizedBox(key: _overlay, width: 48, height: 48),
);

Size _shown(WidgetTester tester, Finder finder) => Size(
      tester.getBottomRight(finder).dx - tester.getTopLeft(finder).dx,
      tester.getBottomRight(finder).dy - tester.getTopLeft(finder).dy,
    );

class _Capture implements VoiceCapture {
  final StreamController<double> level = StreamController<double>.broadcast();

  @override
  Stream<double> get levels => level.stream;

  @override
  Future<bool> start() async => true;

  @override
  Future<String?> stop() async => '/tmp/voice.m4a';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async => level.close();
}

void main() {
  // Экран теста — 800×600.
  const screen = Size(800, 600);

  group('Просмотр на весь экран', () {
    testWidgets('причина бага: Stack в body Scaffold сжимается до кнопки «Закрыть»', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: ColoredBox(key: _content, color: Colors.red)),
              _closeButton,
            ],
          ),
        ),
      ));
      // Содержимое получает размер кнопки (56×56) в левом верхнем углу.
      expect(tester.getSize(find.byKey(_content)), const Size(56, 56));
      expect(tester.getTopLeft(find.byKey(_content)), Offset.zero);
    });

    testWidgets('сцена просмотра занимает экран, кнопка остаётся своего размера', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: FullscreenStage(
            content: ColoredBox(key: _content, color: Colors.red),
            overlays: [_closeButton],
          ),
        ),
      ));
      expect(tester.getSize(find.byKey(_content)), screen);
      expect(tester.getSize(find.byKey(_overlay)), const Size(48, 48));
      expect(tester.getTopLeft(find.byKey(_overlay)), const Offset(4, 4));
    });

    testWidgets('видео в сцене: на всю ширину и по центру, а не в углу', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: FullscreenStage(
            content: FittedContent(
              size: Size(160, 90),
              child: ColoredBox(key: _content, color: Colors.red),
            ),
            overlays: [_closeButton],
          ),
        ),
      ));
      final frame = find.byKey(_content);
      final size = _shown(tester, frame);
      expect(size.width, closeTo(800, 0.5));
      expect(size.height, closeTo(450, 0.5));
      expect(tester.getTopLeft(frame).dx, closeTo(0, 0.5));
      expect(tester.getTopLeft(frame).dy, closeTo(75, 0.5), reason: 'по центру по вертикали');
    });

    testWidgets('до и после инициализации плеера: 16:9, затем настоящий размер', (tester) async {
      Widget stage(Size videoSize) => MaterialApp(
            home: Scaffold(
              body: FullscreenStage(
                content: FittedContent(
                  size: videoSize,
                  child: const ColoredBox(key: _content, color: Colors.red),
                ),
                overlays: const [_closeButton],
              ),
            ),
          );
      await tester.pumpWidget(stage(Size.zero));
      var size = _shown(tester, find.byKey(_content));
      expect(size.width, closeTo(800, 0.5));
      expect(size.height, closeTo(450, 0.5));

      // Плеер сообщил настоящий размер: вертикальное видео.
      await tester.pumpWidget(stage(const Size(1080, 1920)));
      size = _shown(tester, find.byKey(_content));
      expect(size.height, closeTo(600, 0.5));
      expect(size.width, closeTo(337.5, 0.5));
      expect(size.width / size.height, closeTo(1080 / 1920, 0.01));
      final left = tester.getTopLeft(find.byKey(_content)).dx;
      expect(left, closeTo((800 - 337.5) / 2, 0.5), reason: 'по центру по горизонтали');
    });

    testWidgets('история: шапка во всю ширину не уменьшает содержимое', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: FullscreenStage(
            content: ColoredBox(key: _content, color: Colors.red),
            overlays: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 3),
                  Row(children: [Expanded(child: Text('Мама')), SizedBox(key: _overlay, width: 48, height: 48)]),
                ],
              ),
            ],
          ),
        ),
      ));
      expect(tester.getSize(find.byKey(_content)), screen);
      expect(tester.getTopLeft(find.byKey(_overlay)).dy, 3);
    });

    testWidgets('фото в сцене занимает экран и вписывается с пропорциями', (tester) async {
      final provider = MemoryImage(base64Decode(_portraitPng));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FullscreenStage(
            content: FittedPhoto(image: provider, zoomable: true),
            overlays: const [_closeButton],
          ),
        ),
      ));
      await tester.runAsync(() => precacheImage(provider, tester.element(find.byType(FittedPhoto))));
      await tester.pump();
      final render = tester.renderObject<RenderImage>(find.byType(RawImage));
      expect(render.size, screen);
      final image = render.image!;
      final painted = applyBoxFit(
        render.fit!,
        Size(image.width.toDouble(), image.height.toDouble()),
        render.size,
      ).destination;
      expect(painted.height, closeTo(600, 0.5));
      expect(painted.width, closeTo(400, 0.5));
    });
  });

  group('Панель записи голосового', () {
    test('столбик волны не толще предела при любом числе замеров', () {
      // Один замер на 180 px раньше давал столбик шириной 99 px.
      expect(WaveformPainter.barWidthFor(180, 1), WaveformPainter.maxBarWidth);
      expect(WaveformPainter.barWidthFor(180, 2), WaveformPainter.maxBarWidth);
      // Обычная волна из 40 столбиков не изменилась.
      expect(WaveformPainter.barWidthFor(150, 40), closeTo(150 / 40 * 0.55, 0.001));
      expect(WaveformPainter.barWidthFor(0, 40), 0);
      expect(WaveformPainter.barWidthFor(150, 0), 0);
    });

    test('столбик вместе со скруглением не выше отведённой высоты', () {
      const height = 28.0;
      const width = 4.0;
      for (final value in <double>[0, 0.05, 0.5, 1, 37, -3, double.nan, double.infinity]) {
        final h = WaveformPainter.barHeightFor(value, height, width);
        expect(h + width, lessThanOrEqualTo(height), reason: 'значение $value');
        expect(h, greaterThanOrEqualTo(0), reason: 'значение $value');
      }
      expect(WaveformPainter.barHeightFor(0.5, height, width), 14);
    });

    testWidgets('зафиксированная запись с одним замером: строка обычной высоты, 40 столбиков', (tester) async {
      final capture = _Capture();
      final controller = VoiceRecordingController(
        capture: capture,
        register: (path, duration, waveform) async => throw UnimplementedError(),
        onRecorded: (MediaItem item) async {},
        onProblem: (_) {},
      );
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: ColoredBox(key: _content, color: Colors.white)),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => RecordingBar(controller: controller),
              ),
            ],
          ),
        ),
      ));
      await controller.press(const Offset(300, 500));
      controller.drag(const Offset(300, 400)); // вверх на 100 — фиксация
      expect(controller.locked, isTrue);
      capture.level.add(1.0); // единственный замер
      // Панель перерисовывается по своему таймеру (раз в 200 мс).
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.getSize(find.byType(RecordingBar)).height, Sizes.minTouch);
      // Чат над панелью не потерял место.
      expect(tester.getSize(find.byKey(_content)).height, screen.height - Sizes.minTouch);

      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((c) => c.painter is WaveformPainter);
      final painter = paint.painter! as WaveformPainter;
      expect(painter.values, hasLength(VoiceRecordingController.liveBars));
      expect(painter.values.last, 1.0, reason: 'новый замер справа');
      expect(painter.values.first, 0.05);

      final wave = find.byWidget(paint);
      expect(tester.getSize(wave).height, RecordingBar.waveHeight);
      expect(find.ancestor(of: wave, matching: find.byType(ClipRect)), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await controller.cancel();
      controller.dispose();
    });

    test('волна записи всегда фиксированной длины', () async {
      final capture = _Capture();
      final controller = VoiceRecordingController(
        capture: capture,
        register: (path, duration, waveform) async => throw UnimplementedError(),
        onRecorded: (MediaItem item) async {},
        onProblem: (_) {},
      );
      expect(controller.liveWaveform, hasLength(VoiceRecordingController.liveBars));
      await controller.press(Offset.zero);
      for (var i = 0; i < 100; i++) {
        capture.level.add(0.5);
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.liveWaveform, hasLength(VoiceRecordingController.liveBars));
      expect(controller.liveWaveform.every((v) => v == 0.5), isTrue);
      await controller.cancel();
      controller.dispose();
    });
  });
}
