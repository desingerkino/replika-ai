// P1.14: простые виджет-тесты, которые защищают готовый UI от случайных
// поломок: состояния сообщений, значки навигации, кнопки звонка, действия
// профиля. Без снимков экрана и сторонних инструментов.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/call_engine.dart';
import 'package:replika/core/design/icons.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/data/models/call_record.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/features/call/call_screen.dart';
import 'package:replika/features/chat/message_labels.dart';
import 'package:replika/features/chat/message_ticks.dart';
import 'package:replika/features/profile/contact_profile_screen.dart';
import 'package:replika/features/shell/home_shell.dart';

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

class _Recorder implements CallRecorder {
  @override
  Future<void> record(CallSession session, CallOutcome outcome, DateTime startedAt, Duration talked) async {}
}

class _Sounds implements CallSounds {
  @override
  void ringtone() {}
  @override
  void ringback() {}
  @override
  void hangup() {}
  @override
  void stop() {}
}

const _ownFont = 'ReplikaIcons';

/// Значок из собственного шрифта: семейство верное, код не нулевой.
void expectOwnGlyph(IconData icon, String name) {
  expect(icon.fontFamily, _ownFont, reason: '$name должен быть из ReplikaIcons');
  expect(icon.codePoint, greaterThan(0xE000), reason: '$name: пустой код символа');
}

void main() {
  group('Состояния сообщения', () {
    const quiet = Color(0xFF111111);
    const read = Color(0xFF22AA22);
    const failed = Color(0xFFCC2222);

    Future<Icon> iconFor(WidgetTester tester, MessageState state) async {
      await tester.pumpWidget(host(MessageTicks(
        state: state,
        color: quiet,
        readColor: read,
        failedColor: failed,
      )));
      // Внутри один значок состояния.
      return tester.widget<Icon>(find.descendant(of: find.byType(MessageTicks), matching: find.byType(Icon)));
    }

    testWidgets('sent, delivered, read и failed выглядят по-разному', (tester) async {
      final sent = await iconFor(tester, MessageState.sent);
      expect(sent.icon, AppIcons.tickSent);
      expect(sent.color, quiet);

      final delivered = await iconFor(tester, MessageState.delivered);
      expect(delivered.icon, AppIcons.tickDouble);
      expect(delivered.color, quiet);

      final readIcon = await iconFor(tester, MessageState.read);
      expect(readIcon.icon, AppIcons.tickDouble);
      expect(readIcon.color, read);

      final failedIcon = await iconFor(tester, MessageState.failed);
      expect(failedIcon.icon, AppIcons.error);
      expect(failedIcon.color, failed);

      // Пары (значок, цвет) попарно различаются: состояния не слиплись.
      final looks = {
        for (final i in [sent, delivered, readIcon, failedIcon]) '${i.icon!.codePoint}/${i.icon!.fontFamily}/${i.color}',
      };
      expect(looks.length, 4);
    });

    testWidgets('у каждого состояния своя подпись для скринридера', (tester) async {
      final labels = <String>{};
      for (final state in [MessageState.sent, MessageState.delivered, MessageState.read, MessageState.failed]) {
        await iconFor(tester, state);
        final label = messageStateLabel(state);
        expect(
          find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label),
          findsOneWidget,
          reason: 'нет подписи «$label»',
        );
        labels.add(label);
      }
      expect(labels.length, 4);
    });
  });

  group('Значки навигации', () {
    test('Чаты, Контакты, Настройки, Звонки — собственные значки, обычный и активный различаются', () {
      final pairs = <String, (IconData, IconData)>{
        'Чаты': (AppIcons.chats, AppIcons.chatsActive),
        'Контакты': (AppIcons.contacts, AppIcons.contactsActive),
        'Настройки': (AppIcons.settings, AppIcons.settingsActive),
        'Звонки': (AppIcons.callOutlined, AppIcons.call),
      };
      pairs.forEach((name, pair) {
        expectOwnGlyph(pair.$1, '$name (обычный)');
        expectOwnGlyph(pair.$2, '$name (активный)');
        expect(pair.$1.codePoint, isNot(pair.$2.codePoint), reason: '$name: активный совпал с обычным');
      });
    });

    testWidgets('нижняя панель показывает значки AppIcons и подписи', (tester) async {
      var index = 0;
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: StatefulBuilder(builder: (context, setState) {
            set = setState;
            return HomeNavBar(index: index, unread: 0, onSelect: (i) => setState(() => index = i));
          }),
        ),
      ));
      for (final label in ['Чаты', 'Звонки', 'Контакты', 'Настройки']) {
        expect(find.text(label), findsOneWidget, reason: 'нет вкладки «$label»');
      }
      // Выбрана первая вкладка: её активный значок и обычные значки остальных.
      expect(find.byIcon(AppIcons.chatsActive), findsWidgets);
      expect(find.byIcon(AppIcons.callOutlined), findsWidgets);
      expect(find.byIcon(AppIcons.contacts), findsWidgets);
      expect(find.byIcon(AppIcons.settings), findsWidgets);

      // Переключение на «Контакты» и «Настройки» меняет значок на активный.
      set(() => index = 2);
      await tester.pumpAndSettle();
      expect(find.byIcon(AppIcons.contactsActive), findsWidgets);
      set(() => index = 3);
      await tester.pumpAndSettle();
      expect(find.byIcon(AppIcons.settingsActive), findsWidgets);
      set(() => index = 1);
      await tester.pumpAndSettle();
      expect(find.byIcon(AppIcons.call), findsWidgets);
    });
  });

  group('Кнопки звонка', () {
    const video = CallSession(
      deviceId: 'dev',
      characterId: 'char',
      direction: CallDirection.outgoing,
      kind: CallKind.video,
      displayName: 'Тест',
    );

    Widget controls(CallEngine engine, {required bool isVideo}) => host(
          ListenableBuilder(
            listenable: engine,
            builder: (context, _) => CallControls(engine: engine, video: isVideo),
          ),
          theme: AppTheme.dark,
        );

    testWidgets('микрофон и камера меняют значок при переключении', (tester) async {
      final engine = CallEngine(recorder: _Recorder(), sounds: _Sounds());
      addTearDown(engine.dispose);
      expect(engine.start(video), isTrue);
      engine.activate();

      await tester.pumpWidget(controls(engine, isVideo: true));
      expect(find.byIcon(AppIcons.microphone), findsOneWidget);
      expect(find.byIcon(AppIcons.microphoneOff), findsNothing);
      expect(find.byIcon(AppIcons.video), findsOneWidget);
      expect(find.byIcon(AppIcons.videoOff), findsNothing);
      expect(find.byIcon(AppIcons.callEnd), findsOneWidget);

      await tester.tap(find.text('Микрофон'));
      await tester.pump();
      expect(engine.muted, isTrue);
      expect(find.byIcon(AppIcons.microphoneOff), findsOneWidget);
      expect(find.byIcon(AppIcons.microphone), findsNothing);

      await tester.tap(find.text('Включить'));
      await tester.pump();
      expect(find.byIcon(AppIcons.microphone), findsOneWidget);

      await tester.tap(find.text('Камера'));
      await tester.pump();
      expect(engine.cameraOff, isTrue);
      expect(find.byIcon(AppIcons.videoOff), findsOneWidget);
      expect(find.byIcon(AppIcons.video), findsNothing);

      await tester.tap(find.text('Камера'));
      await tester.pump();
      expect(find.byIcon(AppIcons.video), findsOneWidget);

      // «Завершить» кладёт трубку; таймеры движка гасим до конца теста.
      await tester.tap(find.text('Завершить'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.phase, CallPhase.ended);
      // Движок сам уходит в idle после паузы «Звонок завершён».
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('в аудиозвонке нет кнопки камеры, а значки завершения на месте', (tester) async {
      final engine = CallEngine(recorder: _Recorder(), sounds: _Sounds());
      addTearDown(engine.dispose);
      engine.start(const CallSession(
        deviceId: 'dev',
        characterId: 'char',
        direction: CallDirection.outgoing,
        kind: CallKind.audio,
        displayName: 'Тест',
      ));
      engine.activate();

      await tester.pumpWidget(controls(engine, isVideo: false));
      expect(find.byIcon(AppIcons.microphone), findsOneWidget);
      expect(find.byIcon(AppIcons.video), findsNothing);
      expect(find.byIcon(AppIcons.videoOff), findsNothing);
      expect(find.byIcon(AppIcons.callEnd), findsOneWidget);

      engine.hangUp();
      await tester.pump(const Duration(seconds: 3));
    });

    test('значки звонка — собственные и все разные', () {
      final icons = {
        'microphone': AppIcons.microphone,
        'microphoneOff': AppIcons.microphoneOff,
        'video': AppIcons.video,
        'videoOff': AppIcons.videoOff,
        'callEnd': AppIcons.callEnd,
      };
      icons.forEach((name, icon) => expectOwnGlyph(icon, name));
      expect(icons.values.map((i) => i.codePoint).toSet().length, icons.length);
    });
  });

  group('Действия профиля', () {
    testWidgets('«Написать», «Позвонить», «Видео» на месте и срабатывают', (tester) async {
      var wrote = 0;
      final calls = <CallKind>[];
      await tester.pumpWidget(host(ProfileActions(
        onWrite: () => wrote++,
        onCall: calls.add,
      )));

      for (final label in ['Написать', 'Позвонить', 'Видео']) {
        expect(find.text(label), findsOneWidget, reason: 'нет кнопки «$label»');
        expect(
          find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label && w.properties.button == true),
          findsOneWidget,
          reason: 'у «$label» нет подписи кнопки для скринридера',
        );
      }
      expect(find.byIcon(AppIcons.message), findsOneWidget);
      expect(find.byIcon(AppIcons.call), findsOneWidget);
      expect(find.byIcon(AppIcons.video), findsOneWidget);

      await tester.tap(find.text('Написать'));
      await tester.tap(find.text('Позвонить'));
      await tester.tap(find.text('Видео'));
      await tester.pump();
      expect(wrote, 1);
      expect(calls, [CallKind.audio, CallKind.video]);
    });
  });
}
