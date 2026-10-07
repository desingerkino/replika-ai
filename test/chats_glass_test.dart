// Главный экран «Чаты» (светлое стекло): фильтры и архив, карточка чата,
// шапка, плавающая панель вкладок, анимация открытия, «потянуть — обновить».
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/chat_archive.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/core/design/icons.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/core/design/widgets/avatar.dart';
import 'package:replika/core/util/time_format.dart';
import 'package:replika/data/models/chat.dart';
import 'package:replika/design_system/glass_surface.dart';
import 'package:replika/design_system/glass_tab_bar.dart';
import 'package:replika/design_system/glass_theme.dart';
import 'package:replika/design_system/orb_refresh.dart';
import 'package:replika/design_system/replika_logo.dart';
import 'package:replika/features/chat/message_ticks.dart';
import 'package:replika/features/chats/chat_filter.dart';
import 'package:replika/features/chats/chat_tile.dart';
import 'package:replika/features/chats/chats_screen.dart';
import 'package:replika/features/shell/home_shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/reference_chats.dart';

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

Widget tile(ChatListItem item, {bool typing = false, StoryRing ring = StoryRing.none, VoidCallback? onAvatarTap}) =>
    SizedBox(
      width: 393,
      child: ChatTile(
        key: ValueKey(item.chat.id),
        item: item,
        now: refNow,
        typing: typing,
        ring: ring,
        onAvatarTap: onAvatarTap,
        onTap: () {},
        onLongPress: () {},
      ),
    );

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

void main() {
  final chats = referenceChats();
  ChatListItem chat(String id) => chats.firstWhere((c) => c.chat.id == id);

  group('Фильтры и архив', () {
    test('«Все», «Личные», «Группы» показывают только то, что не в архиве', () {
      List<String> ids(ChatFilter f, Set<String> archived) =>
          applyChatFilter(chats, f, archived).map((c) => c.chat.id).toList();

      expect(ids(ChatFilter.all, {}), hasLength(7));
      expect(ids(ChatFilter.personal, {}), ['anna', 'alex', 'victoria', 'dmitry', 'maria']);
      expect(ids(ChatFilter.groups, {}), ['scene7', 'team']);
      expect(ids(ChatFilter.archive, {}), isEmpty);

      const archived = {'anna', 'team'};
      expect(ids(ChatFilter.all, archived), ['alex', 'scene7', 'victoria', 'dmitry', 'maria']);
      expect(ids(ChatFilter.personal, archived), ['alex', 'victoria', 'dmitry', 'maria']);
      expect(ids(ChatFilter.groups, archived), ['scene7']);
      expect(ids(ChatFilter.archive, archived), ['anna', 'team']);
      expect(ChatFilter.values.map((f) => f.label), ['Все', 'Личные', 'Группы', 'Архив']);
    });

    test('сохранённый архив читается, повреждённая запись даёт пустой', () {
      expect(ChatArchive.parse('["a","b"]'), {'a', 'b'});
      expect(ChatArchive.parse('["a",5,null]'), {'a'});
      expect(ChatArchive.parse(null), isEmpty);
      expect(ChatArchive.parse('{"a":1}'), isEmpty);
      expect(ChatArchive.parse('не json'), isEmpty);
    });

    test('архив хранится в настройках и переживает перезапуск', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppServices.testCallSounds = _Silent.new;
      AppServices.testSecretStore = MemorySecretStore.new;
      final dir = Directory.systemTemp.createTempSync('replika_archive_');
      final s = await AppServices.open(databasePath: p.join(dir.path, 'replika.db'));
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await s.close();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      expect(s.archive.ids, isEmpty);
      var notified = 0;
      s.archive.addListener(() => notified++);
      await s.archive.setArchived('chat-mama', true);
      await s.archive.setArchived('chat-mama', true);
      expect(s.archive.contains('chat-mama'), isTrue);
      expect(notified, 1, reason: 'повторное действие ничего не меняет');

      final reopened = ChatArchive(s.settings);
      await reopened.load();
      expect(reopened.ids, {'chat-mama'});

      // Сам чат и его сообщения на месте: архив — только фильтр.
      final list = await s.chats.listForDevice('device-maxim');
      expect(list.any((c) => c.chat.id == 'chat-mama'), isTrue);
      expect(applyChatFilter(list, ChatFilter.all, s.archive.ids).any((c) => c.chat.id == 'chat-mama'), isFalse);
      expect(applyChatFilter(list, ChatFilter.archive, s.archive.ids).single.chat.id, 'chat-mama');

      await s.archive.setArchived('chat-mama', false);
      expect(s.archive.ids, isEmpty);
    });
  });

  group('Время на карточке', () {
    test('сегодня — часы, вчера — «Вчера», на неделе — день недели', () {
      expect(formatChatCardTime(DateTime(2026, 10, 7, 9, 41), refNow), '09:41');
      expect(formatChatCardTime(DateTime(2026, 10, 6, 23, 59), refNow), 'Вчера');
      expect(formatChatCardTime(DateTime(2026, 10, 5, 10), refNow), 'Понедельник');
      expect(formatChatCardTime(DateTime(2026, 10, 1, 10), refNow), 'Четверг');
      expect(formatChatCardTime(DateTime(2026, 9, 10, 10), refNow), '10 сент.');
      expect(formatChatCardTime(DateTime(2025, 12, 31, 10), refNow), '31.12.25');
    });
  });

  group('Карточка чата', () {
    testWidgets('размеры по эталону: карточка 72, аватар 58, поля 20, зазор 2', (tester) async {
      await tester.pumpWidget(host(tile(chat('anna'))));
      expect(tester.getSize(find.byType(ChatTile)), const Size(393, 72 + 2));
      expect(tester.getSize(find.byType(GlassSurface)), const Size(353, 72));
      expect(tester.getSize(find.byType(Avatar)), const Size(58, 58));
      expect(ChatTile.margin.left, 20);
    });

    testWidgets('имя, превью, время и счётчик непрочитанных', (tester) async {
      await tester.pumpWidget(host(tile(chat('anna'))));
      expect(find.text('Анна Смирнова'), findsOneWidget);
      expect(find.text('Я уже в кафе, ты где?'), findsOneWidget);
      expect(find.text('09:41'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(AppIcons.muted), findsNothing);
      expect(find.byIcon(AppIcons.pin), findsNothing);
    });

    testWidgets('группа: значок на аватаре, автор в превью, «без звука» рядом со счётчиком', (tester) async {
      await tester.pumpWidget(host(tile(chat('scene7'))));
      expect(find.byIcon(AppIcons.group), findsOneWidget);
      expect(find.textContaining('Игорь: Скинул новые кадры', findRichText: true), findsOneWidget);
      expect(find.byIcon(AppIcons.muted), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('08:54'), findsOneWidget);
    });

    testWidgets('голосовое: значок волны и длительность', (tester) async {
      await tester.pumpWidget(host(tile(chat('victoria'))));
      expect(find.byIcon(AppIcons.waveform), findsOneWidget);
      expect(find.text('Голосовое сообщение'), findsOneWidget);
      expect(find.text('0:24'), findsOneWidget);
      expect(find.text('Вчера'), findsOneWidget);
    });

    testWidgets('файл: имя файла в превью; закреплённый чат — значок', (tester) async {
      await tester.pumpWidget(host(tile(chat('dmitry'))));
      expect(find.byIcon(AppIcons.file), findsOneWidget);
      expect(find.text('Файл: Список реквизита.pdf'), findsOneWidget);
      expect(find.byIcon(AppIcons.pin), findsOneWidget);
    });

    testWidgets('своё прочитанное сообщение: галочки перед текстом', (tester) async {
      await tester.pumpWidget(host(tile(chat('maria'))));
      expect(find.byType(MessageTicks), findsOneWidget);
      final ticks = tester.widget<Icon>(find.byIcon(AppIcons.tickDouble));
      expect(ticks.color, GlassTheme.accentBlue);
      expect(find.text('Хорошо, вижу'), findsOneWidget);
      expect(find.text('Понедельник'), findsOneWidget);
    });

    testWidgets('«печатает…» заменяет превью', (tester) async {
      await tester.pumpWidget(host(tile(chat('alex'), typing: true)));
      expect(find.text('печатает…'), findsOneWidget);
      expect(find.text('Буду через 10 минут'), findsNothing);
    });

    testWidgets('нажатие на аватар с историей и на карточку — разные действия', (tester) async {
      var story = 0;
      var open = 0;
      await tester.pumpWidget(host(SizedBox(
        width: 393,
        child: ChatTile(
          item: chat('anna'),
          now: refNow,
          ring: StoryRing.unviewed,
          onAvatarTap: () => story++,
          onTap: () => open++,
          onLongPress: () {},
        ),
      )));
      await tester.tap(find.byType(Avatar));
      expect((story, open), (1, 0));
      await tester.tap(find.text('Анна Смирнова'));
      expect((story, open), (1, 1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('новое входящее: карточка вспыхивает и гаснет', (tester) async {
      ChatListItem alex(int unread) => refChat('alex', 'Алекс', at: refNow, text: 'Привет', unread: unread);
      GlassSurface surface() => tester.widget<GlassSurface>(find.byType(GlassSurface));

      await tester.pumpWidget(host(tile(alex(0))));
      expect(surface().glow, isNull);

      await tester.pumpWidget(host(tile(alex(1))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(surface().glow, isNotNull);
      await tester.pump(ChatTile.pulseDuration);
      await tester.pump();
      expect(surface().glow, isNull);

      // Прочитали (счётчик уменьшился) — вспышки нет.
      await tester.pumpWidget(host(tile(alex(0))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(surface().glow, isNull);
    });

    testWidgets('тёмная тема: карточка читается на тёмном стекле', (tester) async {
      await tester.pumpWidget(host(tile(chat('anna')), theme: AppTheme.dark));
      final name = tester.widget<Text>(find.text('Анна Смирнова'));
      expect(name.style?.color, GlassTheme.night.textPrimary);
    });
  });

  group('Шапка и фильтры', () {
    testWidgets('заголовок 36, кнопки «Меню» и «Новый чат», скрытое удержание', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(host(ChatsHeader(
        onMenu: () => log.add('menu'),
        onNewChat: () => log.add('new'),
        onTitleHold: () => log.add('hold'),
      )));
      final title = tester.widget<Text>(find.text('Чаты'));
      expect(title.style?.fontSize, 36);
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(title.style?.color, const Color(0xFF111827));

      await tester.tap(find.byTooltip('Меню'));
      await tester.tap(find.byTooltip('Новый чат'));
      expect(log, ['menu', 'new']);
      expect(tester.getSize(find.byTooltip('Меню')), const Size(44, 44));

      // Короткое нажатие на заголовок ничего не делает; удержание 2 с — делает.
      await tester.tap(find.text('Чаты'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(log, ['menu', 'new']);
      final gesture = await tester.startGesture(tester.getCenter(find.text('Чаты')));
      await tester.pump(const Duration(milliseconds: 2100));
      await gesture.up();
      expect(log, ['menu', 'new', 'hold']);
    });

    testWidgets('четыре капсулы, выбранная отмечена, нажатие сообщает выбор', (tester) async {
      var selected = ChatFilter.all;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => ChatFilterBar(
          selected: selected,
          onSelect: (f) => setState(() => selected = f),
        ),
      )));
      for (final label in ['Все', 'Личные', 'Группы', 'Архив']) {
        expect(find.text(label), findsOneWidget);
      }
      GlassSurface chip(String name) => tester.widget<GlassSurface>(
            find.descendant(of: find.byKey(ValueKey('filter-$name')), matching: find.byType(GlassSurface)),
          );
      expect(chip('all').gradient, isNotNull);
      expect(chip('groups').gradient, isNull);

      await tester.tap(find.text('Группы'));
      await tester.pump();
      expect(selected, ChatFilter.groups);
      expect(chip('groups').gradient, isNotNull);
      expect(chip('all').gradient, isNull);
    });
  });

  group('Анимация открытия', () {
    test('карточки идут по очереди с шагом 50 мс', () {
      const total = 900;
      expect(ChatsIntro.duration.inMilliseconds, total);
      final first = ChatsIntro.intervalFor(0);
      final second = ChatsIntro.intervalFor(1);
      expect((second.begin - first.begin) * total, closeTo(50, 0.001));
      expect((first.end - first.begin) * total, closeTo(320, 0.001));
      expect(ChatsIntro.intervalFor(40).begin, ChatsIntro.intervalFor(ChatsIntro.staggered).begin);
      expect(ChatsIntro.intervalFor(40).end, lessThanOrEqualTo(1));
    });

    testWidgets('карточка проявляется в свой отрезок времени', (tester) async {
      final controller = AnimationController(vsync: tester, duration: ChatsIntro.duration);
      addTearDown(controller.dispose);
      await tester.pumpWidget(host(KeyedSubtree(
        key: const Key('slot'),
        child: ChatsIntro.card(
          animation: controller,
          index: 2,
          child: const SizedBox(width: 100, height: 40),
        ),
      )));
      double opacity() => tester
          .widget<FadeTransition>(
            find.descendant(of: find.byKey(const Key('slot')), matching: find.byType(FadeTransition)),
          )
          .opacity
          .value;
      expect(opacity(), 0);
      controller.value = 0.2; // 180 мс: карточка №2 начинает на 220 мс
      await tester.pump();
      expect(opacity(), 0);
      controller.value = 1;
      await tester.pump();
      expect(opacity(), 1);
    });
  });

  group('Панель вкладок', () {
    Widget bar({required int index, required ValueChanged<int> onSelect, int unread = 0, double systemBottom = 0}) =>
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(viewPadding: EdgeInsets.only(bottom: systemBottom)),
            child: child!,
          ),
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: HomeNavBar(index: index, unread: unread, onSelect: onSelect),
          ),
        );

    testWidgets('порядок как на эталоне, номера разделов прежние', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(bar(index: 0, onSelect: picked.add));
      final xs = [
        for (final label in ['Звонки', 'Контакты', 'Чаты', 'Настройки']) tester.getCenter(find.text(label)).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()), reason: 'слева направо: Звонки, Контакты, Чаты, Настройки');

      await tester.tap(find.text('Звонки'));
      await tester.tap(find.text('Контакты'));
      await tester.tap(find.text('Чаты'));
      await tester.tap(find.text('Настройки'));
      expect(picked, [1, 2, 0, 3]);
    });

    testWidgets('капсула 76 высотой, поля 20, над полоской «домой»', (tester) async {
      await tester.pumpWidget(bar(index: 0, onSelect: (_) {}));
      var rect = tester.getRect(find.descendant(of: find.byType(GlassTabBar), matching: find.byType(GlassSurface)));
      expect(rect.height, 76);
      expect(rect.left, 20);
      expect(rect.right, 800 - 20);
      expect(600 - rect.bottom, 20);

      await tester.pumpWidget(bar(index: 0, onSelect: (_) {}, systemBottom: 34));
      rect = tester.getRect(find.descendant(of: find.byType(GlassTabBar), matching: find.byType(GlassSurface)));
      expect(600 - rect.bottom, 40);
      expect(GlassTabBar.extentFor(34), 116);
      expect(GlassTabBar.extentFor(0), 96);
    });

    testWidgets('счётчик на «Чатах» виден только с других вкладок', (tester) async {
      await tester.pumpWidget(bar(index: 0, unread: 5, onSelect: (_) {}));
      expect(find.text('5'), findsNothing);
      await tester.pumpWidget(bar(index: 2, unread: 5, onSelect: (_) {}));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('Потянуть, чтобы обновить', () {
    testWidgets('сфера Replika вместо обычного кольца', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OrbRefresh(
            onRefresh: () async => refreshed++,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              itemCount: 30,
              itemBuilder: (context, i) => SizedBox(height: 60, child: Text('строка $i')),
            ),
          ),
        ),
      ));
      expect(find.byType(ReplikaOrb), findsNothing);

      final gesture = await tester.startGesture(const Offset(400, 150));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 320));
      await tester.pump();
      expect(find.byType(ReplikaOrb), findsOneWidget, reason: 'сфера видна, пока тянут');
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(refreshed, 0);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(refreshed, 1);
      expect(find.byType(ReplikaOrb), findsOneWidget);

      await tester.pump(OrbRefresh.minSpin);
      await tester.pumpAndSettle();
      expect(find.byType(ReplikaOrb), findsNothing);
      expect(refreshed, 1);
    });

    testWidgets('короткое движение ничего не обновляет', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OrbRefresh(
            onRefresh: () async => refreshed++,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              itemCount: 30,
              itemBuilder: (context, i) => SizedBox(height: 60, child: Text('строка $i')),
            ),
          ),
        ),
      ));
      await tester.drag(find.byType(ListView), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(refreshed, 0);
      expect(find.byType(ReplikaOrb), findsNothing);
    });
  });
}
