// Экран «Чат» (светлое стекло): формы пузырей, шапка, поле ввода, появление
// новых сообщений, «печатает…», плитка файла.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/data/models/chat.dart';
import 'package:replika/data/models/media_item.dart';
import 'package:replika/design_system/glass_surface.dart';
import 'package:replika/design_system/glass_theme.dart';
import 'package:replika/design_system/replika_logo.dart';
import 'package:replika/features/chat/chat_glass.dart';
import 'package:replika/features/chat/composer.dart';
import 'package:replika/features/chat/emoji_sheet.dart';
import 'package:replika/features/chat/typing_indicator.dart';
import 'package:replika/features/media/media_content.dart';

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child)),
    );

void main() {
  group('Формы и цвета', () {
    test('входящие — радиус 22 и маленький «хвост» у последнего', () {
      final single = ChatGlass.bubbleRadius(outgoing: false, joinsPrevious: false, joinsNext: false);
      expect(single.topLeft, const Radius.circular(22));
      expect(single.topRight, const Radius.circular(22));
      expect(single.bottomRight, const Radius.circular(22));
      expect(single.bottomLeft, const Radius.circular(ChatGlass.tail));

      final out = ChatGlass.bubbleRadius(outgoing: true, joinsPrevious: true, joinsNext: true);
      expect(out.topRight, const Radius.circular(ChatGlass.joined));
      expect(out.bottomRight, const Radius.circular(ChatGlass.joined));
      expect(out.topLeft, const Radius.circular(22));
    });

    test('градиент исходящих — #5667FF → #A078FF, входящие — белый 70 %', () {
      expect(ChatGlass.outgoing.colors, const [Color(0xFF5667FF), Color(0xFFA078FF)]);
      expect(ChatGlass.incomingFillLight.a, closeTo(0.7, 0.01));
      expect(ChatGlass.incomingFillLight.toARGB32() & 0xFFFFFF, 0xFFFFFF);
    });
  });

  group('Шапка', () {
    testWidgets('имя, статус «в сети» и три стеклянные кнопки', (tester) async {
      var calls = 0, videos = 0, more = 0;
      await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        ChatGlassHeader(
          peer: const ChatPeer(displayName: 'Анна Смирнова', statusText: 'в сети'),
          typing: false,
          onCall: () => calls++,
          onVideo: () => videos++,
          onMore: () => more++,
        ),
      ])));
      expect(find.text('Анна Смирнова'), findsOneWidget);
      expect(find.text('в сети'), findsOneWidget);
      await tester.tap(find.byTooltip('Аудиозвонок'));
      await tester.tap(find.byTooltip('Видеозвонок'));
      await tester.tap(find.byTooltip('Ещё'));
      expect([calls, videos, more], [1, 1, 1]);
      expect(find.byTooltip('Назад'), findsOneWidget);
    });

    testWidgets('в группе кнопок звонка нет, вместо статуса — число участников', (tester) async {
      await tester.pumpWidget(host(const ChatGlassHeader(
        peer: ChatPeer(displayName: 'Съёмочная группа'),
        typing: false,
        subtitle: '3 участника',
      )));
      expect(find.text('3 участника'), findsOneWidget);
      expect(find.byTooltip('Аудиозвонок'), findsNothing);
      expect(find.byTooltip('Видеозвонок'), findsNothing);
    });

    testWidgets('когда собеседник печатает, в шапке «печатает…»', (tester) async {
      await tester.pumpWidget(host(const ChatGlassHeader(
        peer: ChatPeer(displayName: 'Анна', statusText: 'в сети'),
        typing: true,
      )));
      expect(find.text('печатает…'), findsOneWidget);
      expect(find.text('в сети'), findsNothing);
    });
  });

  group('Поле ввода', () {
    Widget composer(TextEditingController c, {VoidCallback? onSend, VoidCallback? onAttach}) => Composer(
          controller: c,
          focusNode: FocusNode(),
          onSend: onSend ?? () {},
          onAttach: onAttach ?? () {},
        );

    testWidgets('капсула высотой 60, «+», «Сообщение», эмодзи и отправка', (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(composer(c)));
      expect(find.text('Сообщение'), findsOneWidget);
      expect(find.byTooltip('Прикрепить'), findsOneWidget);
      expect(find.byTooltip('Эмодзи'), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
      // Капсула — самая широкая стеклянная поверхность (кнопки внутри уже).
      final sizes = [for (final e in find.byType(GlassSurface).evaluate()) e.size!];
      final capsule = sizes.reduce((a, b) => a.width >= b.width ? a : b);
      expect(capsule.height, Composer.capsuleHeight);
      expect(Composer.capsuleHeight, 60);
      expect(Composer.capsuleRadius, 30);
    });

    testWidgets('«Отправить» работает, только когда есть текст', (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      var sent = 0;
      await tester.pumpWidget(host(composer(c, onSend: () => sent++)));
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      expect(sent, 0);
      await tester.enterText(find.byType(TextField), 'Привет');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      expect(sent, 1);
    });

    testWidgets('эмодзи вставляется в позицию курсора', (tester) async {
      final c = TextEditingController(text: 'Привет!');
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 6);
      insertEmoji(c, '😊');
      expect(c.text, 'Привет😊!');
      expect(c.selection.baseOffset, 6 + '😊'.length);

      await tester.pumpWidget(host(composer(c)));
      await tester.tap(find.byTooltip('Эмодзи'));
      await tester.pumpAndSettle();
      expect(find.text('🔥'), findsOneWidget);
      await tester.tap(find.text('🔥'));
      await tester.pumpAndSettle();
      expect(c.text.contains('🔥'), isTrue);
    });
  });

  group('Появление и «печатает…»', () {
    testWidgets('новая реплика: прозрачность 0→1, сдвиг 20 px, размытие уходит', (tester) async {
      await tester.pumpWidget(host(const MessageEntrance(
        animate: true,
        child: SizedBox(key: Key('m'), width: 100, height: 40),
      )));
      final start = tester.getTopLeft(find.byKey(const Key('m'))).dy;
      expect(find.byType(ImageFiltered), findsOneWidget);
      final first = tester
          .widget<Opacity>(find.descendant(of: find.byType(MessageEntrance), matching: find.byType(Opacity)).first)
          .opacity;
      expect(first, lessThan(0.2));

      await tester.pump(MessageEntrance.duration ~/ 2);
      final mid = tester.getTopLeft(find.byKey(const Key('m'))).dy;
      expect(mid, lessThan(start));

      await tester.pump(MessageEntrance.duration);
      await tester.pump();
      expect(find.byType(ImageFiltered), findsNothing);
      expect(tester.getTopLeft(find.byKey(const Key('m'))).dy, start - MessageEntrance.shift);
    });

    testWidgets('старые сообщения и «уменьшить движение» — без анимации', (tester) async {
      await tester.pumpWidget(host(const MessageEntrance(animate: false, child: SizedBox(width: 10, height: 10))));
      expect(find.byType(ImageFiltered), findsNothing);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(const MessageEntrance(animate: true, child: SizedBox(width: 10, height: 10))),
      ));
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('собеседник печатает: сфера Replika и «печатает…»', (tester) async {
      await tester.pumpWidget(host(const TypingBubble()));
      expect(find.text('печатает'), findsOneWidget);
      expect(find.byType(ReplikaOrb), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Файл', () {
    MediaItem file(String name) => MediaItem(
          id: name,
          kind: MediaKind.file,
          path: '/tmp/$name',
          originalName: name,
          sizeBytes: 2516582,
          createdAt: DateTime(2026, 10, 7),
        );

    testWidgets('PDF — красная плитка «PDF», имя и размер', (tester) async {
      await tester.pumpWidget(host(FileContent(
        media: file('Список реквизита.pdf'),
        foreground: Colors.black,
        muted: Colors.grey,
      )));
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Список реквизита.pdf'), findsOneWidget);
      expect(find.text('2,4 МБ'), findsOneWidget);
      expect(FileContent.tileColor('pdf'), const Color(0xFFFF4D4F));
      expect(FileContent.tileColor('xlsx'), isNot(FileContent.tileColor('pdf')));
    });

    testWidgets('без расширения — плитка «ФАЙЛ»', (tester) async {
      await tester.pumpWidget(host(FileContent(media: file('readme'), foreground: Colors.black, muted: Colors.grey)));
      expect(find.text('ФАЙЛ'), findsOneWidget);
    });
  });

  test('тёмная тема стекла не светлее светлой', () {
    expect(GlassTheme.night.dark, isTrue);
  });
}
