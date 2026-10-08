// Снимки ключевых экранов в обеих темах (только по запросу:
// REPLIKA_SCREENSHOTS=1 flutter test test/screenshots_test.dart --update-goldens).
// Нужны для визуальной проверки редизайна в CI; в обычном прогоне пропускаются.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/app.dart';
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/navigator.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/core/theme/app_theme_id.dart';
import 'package:replika/data/models/media_item.dart';
import 'package:replika/data/repositories/settings_repository.dart';
import 'package:replika/data/seed/demo_seed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

final bool enabled = Platform.environment.containsKey('REPLIKA_SCREENSHOTS');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts');
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final file = File(p.join(dir, f));
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Light.ttf']);
  await family('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// Картинка-градиент для историй и фото (без файлов в репозитории).
Future<String> _picture(String path, List<Color> colors) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(720, 1280);
  canvas.drawRect(
    Offset.zero & size,
    Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), colors),
  );
  canvas.drawCircle(const Offset(360, 560), 180, Paint()..color = const Color(0x55FFFFFF));
  final image = await recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppServices s;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  Future<void> settle(WidgetTester tester, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    await expectLater(find.byType(ReplikaApp), matchesGoldenFile('shots/$name.png'));
  }

  testWidgets('экраны в темах Telegram и Replika', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('replika_shots_');
      s = await AppServices.open(databasePath: p.join(dir.path, 'replika.db'));
      await s.settings.setValue(SettingKeys.welcomeSeen, '1');
      // Истории: своя и двух контактов, одна просмотрена.
      const device = DemoSeed.deviceId;
      final owner = (await s.devices.byId(device))!.ownerCharacterId;
      final contacts = (await s.contacts.forDevice(device)).where((c) => c.id != owner).toList();
      Future<MediaItem> media(String id, List<Color> colors) async {
        final path = await _picture(p.join(dir.path, '$id.png'), colors);
        final item = MediaItem(id: id, kind: MediaKind.photo, path: path, width: 720, height: 1280, createdAt: DateTime.now());
        await s.media.repository.insert(item);
        return item;
      }

      final now = DateTime.now();
      await s.stories.add(
        deviceId: device,
        characterId: contacts[0].id,
        mediaId: (await media('st1', const [Color(0xFF6FB1FF), Color(0xFFCB30E0)])).id,
        postedAt: now.subtract(const Duration(minutes: 15)),
      );
      if (contacts.length > 1) {
        await s.stories.add(
          deviceId: device,
          characterId: contacts[1].id,
          mediaId: (await media('st2', const [Color(0xFFFFD27F), Color(0xFFFF7AD9)])).id,
          postedAt: now.subtract(const Duration(hours: 2)),
          seen: true,
        );
      }
      final first = (await s.messages.forChat('chat-veronika')).first;
      await s.messages.setReaction(first.id, '❤️');
    });

    for (final theme in [AppThemeId.telegram, AppThemeId.replika]) {
      await tester.runAsync(() => s.setTheme(theme));
      await tester.pumpWidget(ReplikaApp(services: s));
      AppNavigator.homeTab.value = 0;
      await shot(tester, '${theme.name}_1_chats');

      AppNavigator.openChat('chat-veronika');
      await shot(tester, '${theme.name}_2_chat');
      AppNavigator.toRoot();

      AppNavigator.openProfile(deviceId: DemoSeed.deviceId, characterId: 'char-veronika');
      await shot(tester, '${theme.name}_3_profile');
      AppNavigator.toRoot();

      AppNavigator.homeTab.value = 3;
      await shot(tester, '${theme.name}_4_stories');

      AppNavigator.homeTab.value = 4;
      await shot(tester, '${theme.name}_5_settings');

      AppNavigator.homeTab.value = 1;
      await shot(tester, '${theme.name}_6_contacts');

      AppNavigator.openThemes();
      await shot(tester, '${theme.name}_7_themes');
      AppNavigator.toRoot();
      AppNavigator.homeTab.value = 0;
      await settle(tester, 3);
    }

    // Отпустить таймеры и базу до конца теста.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await s.close();
    });
  }, skip: !enabled);
}
