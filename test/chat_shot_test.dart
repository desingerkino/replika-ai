// Снимок экрана «Чат» для сверки с эталоном docs/brand/chat_reference.png:
// build/chat_shot_a.png (светлая тема) и build/chat_shot_b.png (тёмная).
// Состав экрана тот же, что собирает ChatScreen, но без базы сообщений.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/core/design/widgets/avatar.dart';
import 'package:replika/data/models/chat.dart';
import 'package:replika/design_system/glass_wallpaper.dart';
import 'package:replika/features/chat/chat_glass.dart';
import 'package:replika/features/chat/chat_rows.dart';
import 'package:replika/features/chat/composer.dart';
import 'package:replika/features/chat/message_bubble.dart';
import 'package:replika/features/record/voice_recording.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/fonts.dart';
import 'fixtures/reference_chat.dart';

class _Silent implements CallSounds {
  @override
  void ringtone() {}
  @override
  void ringback() {}
  @override
  void hangup() {}
  @override
  void stop() {}
}

class _Capture implements VoiceCapture {
  @override
  Stream<double> get levels => const Stream<double>.empty();
  @override
  Future<bool> start() async => true;
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class _Screen extends StatelessWidget {
  const _Screen({required this.rows, required this.voice});

  final List<MessageRow> rows;
  final VoiceRecordingController voice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassWallpaper(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const ChatGlassHeader(
                peer: ChatPeer(displayName: 'Анна Смирнова', statusText: 'в сети'),
                typing: false,
                onCall: _noop,
                onVideo: _noop,
                onMore: _noop,
              ),
              Expanded(
                child: ListView(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final row in rows.reversed)
                      MessageBubble(
                        key: ValueKey(row.message.id),
                        row: row,
                        onLongPress: () {},
                        avatar: row.outgoing ? null : const Avatar(name: 'Анна Смирнова', size: 30, tone: 3),
                      ),
                  ],
                ),
              ),
              Composer(
                controller: TextEditingController(),
                focusNode: FocusNode(),
                onSend: () {},
                onAttach: () {},
                voice: voice,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _noop() {}

void main() {
  testWidgets('снимок экрана 393×852, светлая и тёмная тема', (tester) async {
    const screen = Size(393, 852);
    const ratio = 2.0;
    tester.view.physicalSize = screen * ratio;
    tester.view.devicePixelRatio = ratio;
    tester.view.padding = const FakeViewPadding(top: 59 * ratio, bottom: 34 * ratio);
    tester.view.viewPadding = const FakeViewPadding(top: 59 * ratio, bottom: 34 * ratio);
    addTearDown(tester.view.reset);
    debugDisableShadows = false;

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
    final dir = Directory.systemTemp.createTempSync('replika_chat_shot_');
    late AppServices services;
    await tester.runAsync(() async {
      await loadAppFonts();
      services = await AppServices.open(databasePath: p.join(dir.path, 'replika.db'));
      await paintPhoto('${dir.path}/cafe.png');
    });
    final messages = referenceConversation(dir.path);
    final rows = buildChatRows(messages, ownerId: chatOwner, now: DateTime(2026, 10, 7, 9, 45))
        .whereType<MessageRow>()
        .toList();
    final voice = VoiceRecordingController(
      capture: _Capture(),
      register: (path, duration, waveform) async => throw UnimplementedError(),
      onRecorded: (item) async {},
      onProblem: (_) {},
    );

    const key = Key('shot');
    Future<void> shoot(ThemeData theme, String name) async {
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: Services(
          services: services,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: _Screen(rows: rows, voice: voice),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 100));
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

    await shoot(AppTheme.light, 'chat_shot_a.png');
    await shoot(AppTheme.dark, 'chat_shot_b.png');

    debugDisableShadows = true;
    expect(File('build/chat_shot_a.png').lengthSync(), greaterThan(10000));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    voice.dispose();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await services.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });
}
