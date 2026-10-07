// Снимок главного экрана «Чаты» для сверки с эталоном
// docs/brand/chats_reference.png: build/chats_shot_a.png (светлая тема) и
// build/chats_shot_b.png (тёмная). Данные — чаты с эталона (test/fixtures).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/core/design/icons.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/design_system/glass_controls.dart';
import 'package:replika/design_system/glass_wallpaper.dart';
import 'package:replika/features/chats/chat_filter.dart';
import 'package:replika/features/chats/chat_tile.dart';
import 'package:replika/features/chats/chats_screen.dart';
import 'package:replika/features/shell/home_shell.dart';

import 'fixtures/fonts.dart';
import 'fixtures/reference_chats.dart';

/// Тот же состав экрана, что собирает ChatsScreen, но без базы данных.
class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) {
    final chats = referenceChats();
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: HomeNavBar(index: 0, unread: 16, onSelect: (_) {}),
      body: GlassWallpaper(
        child: SafeArea(
          bottom: false,
          child: Builder(
            builder: (context) => Column(
              children: [
                ChatsHeader(onMenu: () {}, onNewChat: () {}),
                Padding(
                  padding: const EdgeInsets.fromLTRB(ChatsScreen.sideMargin, 6, ChatsScreen.sideMargin, 0),
                  child: GlassSearchBar(
                    controller: TextEditingController(),
                    hint: 'Поиск',
                    searchIcon: AppIcons.search,
                    clearIcon: AppIcons.clear,
                    onChanged: (_) {},
                  ),
                ),
                ChatFilterBar(selected: ChatFilter.all, onSelect: (_) {}),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
                    children: [
                      for (final chat in chats)
                        ChatTile(item: chat, now: refNow, onTap: () {}, onLongPress: () {}),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('снимок экрана 393×852, светлая и тёмная тема', (tester) async {
    const screen = Size(393, 852);
    const ratio = 2.0;
    tester.view.physicalSize = screen * ratio;
    tester.view.devicePixelRatio = ratio;
    // Вырезы iPhone: строка состояния и полоска «домой».
    tester.view.padding = const FakeViewPadding(top: 59 * ratio, bottom: 34 * ratio);
    tester.view.viewPadding = const FakeViewPadding(top: 59 * ratio, bottom: 34 * ratio);
    addTearDown(tester.view.reset);
    // В тестах размытые тени по умолчанию отключены; для снимка включаем и
    // возвращаем до конца теста.
    debugDisableShadows = false;

    await tester.runAsync(loadAppFonts);

    const key = Key('shot');
    Future<void> shoot(ThemeData theme, String name) async {
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: const _Screen()),
      ));
      await tester.pump(const Duration(milliseconds: 400));
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

    await shoot(AppTheme.light, 'chats_shot_a.png');
    await shoot(AppTheme.dark, 'chats_shot_b.png');

    debugDisableShadows = true;
    expect(File('build/chats_shot_a.png').lengthSync(), greaterThan(10000));
    expect(tester.takeException(), isNull);
  });
}
