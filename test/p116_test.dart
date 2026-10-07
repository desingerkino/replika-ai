// P1.16: удалённое превью, запись голоса (жест), кольцо Story, истории,
// свайпы списка, громкая связь. Без снимков экрана: только состояния и поведение.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/audio_playback.dart';
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/story_store.dart';
import 'package:replika/core/design/icons.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/core/design/widgets/avatar.dart';
import 'package:replika/core/design/widgets/story_ring.dart';
import 'package:replika/data/models/call_record.dart';
import 'package:replika/data/models/chat.dart';
import 'package:replika/data/models/media_item.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/features/call/call_screen.dart';
import 'package:replika/features/call/two_finger_tap.dart';
import 'package:replika/features/chat/voice_mini_player.dart';
import 'package:replika/features/chats/chat_tile.dart';
import 'package:replika/features/chats/swipe_actions.dart';
import 'package:replika/features/record/voice_recording.dart';
import 'package:replika_recorder/replika_recorder.dart';

Widget host(Widget child, {ThemeData? theme, bool disableAnimations = false}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      builder: (context, home) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
        child: home!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

final DateTime _t = DateTime(2026, 10, 7, 12);

ChatListItem chatItem({bool deleted = false}) => ChatListItem(
      chat: Chat(id: 'c1', deviceId: 'd1', peerCharacterId: 'p1', createdAt: _t, updatedAt: _t),
      peer: const ChatPeer(displayName: 'Мама'),
      ownerCharacterId: 'hero',
      lastMessage: Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'p1',
        text: deleted ? '' : 'Привет',
        sentAt: _t,
        createdAt: _t,
        deleted: deleted,
      ),
    );

class _FakeCapture implements VoiceCapture {
  final StreamController<double> _levels = StreamController<double>.broadcast();
  bool permission = true;
  int started = 0;
  int stopped = 0;
  int cancelled = 0;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> start() async {
    if (!permission) return false;
    started++;
    return true;
  }

  @override
  Future<String?> stop() async {
    stopped++;
    return '/tmp/voice.m4a';
  }

  @override
  Future<void> cancel() async => cancelled++;

  @override
  Future<void> dispose() async => _levels.close();
}

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

const _voiceSession = CallSession(
  deviceId: 'd',
  characterId: 'c',
  direction: CallDirection.outgoing,
  kind: CallKind.audio,
  displayName: 'Тест',
);

void main() {
  group('Удалённое сообщение в списке чатов', () {
    testWidgets('выглядит как системное состояние: значок и приглушённый тон', (tester) async {
      await tester.pumpWidget(host(
        SizedBox(width: 400, child: ChatTile(item: chatItem(deleted: true), now: _t, onTap: () {}, onLongPress: () {})),
      ));
      expect(find.byKey(const ValueKey('deleted-preview')), findsOneWidget);
      expect(find.byIcon(AppIcons.markDeleted), findsOneWidget);
      final text = tester.widget<Text>(find.text('Сообщение удалено'));
      expect(text.style?.color, isNot(AppTheme.light.colorScheme.error), reason: 'без красного');
    });

    testWidgets('обычное сообщение показывается как раньше', (tester) async {
      await tester.pumpWidget(host(
        SizedBox(width: 400, child: ChatTile(item: chatItem(), now: _t, onTap: () {}, onLongPress: () {})),
      ));
      expect(find.byKey(const ValueKey('deleted-preview')), findsNothing);
      expect(find.text('Привет'), findsOneWidget);
    });
  });

  group('Запись голосового', () {
    late _FakeCapture capture;
    late DateTime now;
    late List<String> sent;
    late List<String> problems;
    late VoiceRecordingController voice;

    setUp(() {
      capture = _FakeCapture();
      now = DateTime(2026, 10, 7, 12);
      sent = [];
      problems = [];
      voice = VoiceRecordingController(
        capture: capture,
        clock: () => now,
        register: (path, duration, waveform) async => MediaItem(
          id: 'v${sent.length}',
          kind: MediaKind.voice,
          path: path,
          durationMs: duration.inMilliseconds,
          createdAt: now,
        ),
        onRecorded: (item) async => sent.add(item.id),
        onProblem: problems.add,
      );
    });

    tearDown(() => voice.dispose());

    test('удержал и отпустил — запись отправляется', () async {
      await voice.press(const Offset(100, 500));
      expect(voice.state, VoiceRecState.holding);
      expect(voice.recording, isTrue);
      now = now.add(const Duration(seconds: 3));
      await voice.release();
      expect(voice.state, VoiceRecState.idle);
      expect(sent, ['v0']);
      expect(capture.stopped, 1);
    });

    test('короткое касание не отправляет, а подсказывает «удерживайте»', () async {
      await voice.press(const Offset(100, 500));
      now = now.add(const Duration(milliseconds: 200));
      await voice.release();
      expect(sent, isEmpty);
      expect(capture.cancelled, 1);
      expect(problems, [voiceHoldHint]);
    });

    test('свайп вверх фиксирует запись; отпускание уже не отправляет', () async {
      await voice.press(const Offset(100, 500));
      voice.drag(const Offset(100, 480));
      expect(voice.state, VoiceRecState.holding);
      expect(voice.lockProgress, greaterThan(0));
      voice.drag(Offset(100, 500 - VoiceRecordingController.lockDistance - 1));
      expect(voice.state, VoiceRecState.locked);
      now = now.add(const Duration(seconds: 2));
      await voice.release();
      expect(voice.state, VoiceRecState.locked, reason: 'палец поднят, запись идёт');
      expect(sent, isEmpty);
      await voice.sendLocked();
      expect(voice.state, VoiceRecState.idle);
      expect(sent, ['v0']);
    });

    test('зафиксированную запись можно отменить', () async {
      await voice.press(const Offset(100, 500));
      voice.drag(Offset(100, 500 - VoiceRecordingController.lockDistance - 1));
      await voice.cancel();
      expect(voice.state, VoiceRecState.idle);
      expect(sent, isEmpty);
      expect(capture.cancelled, 1);
    });

    test('свайп влево отменяет запись', () async {
      await voice.press(const Offset(300, 500));
      voice.drag(const Offset(250, 500));
      expect(voice.cancelProgress, greaterThan(0));
      expect(voice.state, VoiceRecState.holding);
      voice.drag(Offset(300 - VoiceRecordingController.cancelDistance - 1, 500));
      await Future<void>.delayed(Duration.zero);
      expect(voice.state, VoiceRecState.idle);
      expect(sent, isEmpty);
      expect(capture.cancelled, 1);
    });

    test('нет доступа к микрофону — сообщение, запись не начинается', () async {
      capture.permission = false;
      await voice.press(const Offset(100, 500));
      expect(voice.state, VoiceRecState.idle);
      expect(problems.single, contains('микрофон'));
    });
  });

  group('Кольцо Story', () {
    testWidgets('новая история: градиент живёт; без анимаций — стоит на месте', (tester) async {
      const ring = Avatar(name: 'Мама', ring: StoryRing.unviewed);
      await tester.pumpWidget(host(const Padding(padding: EdgeInsets.all(20), child: ring)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'градиент переливается');

      await tester.pumpWidget(host(const Padding(padding: EdgeInsets.all(20), child: ring), disableAnimations: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'reduced motion: статичный градиент');
      expect(find.byType(StoryRingView), findsOneWidget, reason: 'кольцо остаётся');
    });

    testWidgets('просмотренная — спокойное кольцо без движения; без истории — кольца нет', (tester) async {
      await tester.pumpWidget(host(const Padding(
        padding: EdgeInsets.all(20),
        child: Avatar(name: 'Мама', ring: StoryRing.viewed),
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.byType(StoryRingView), findsOneWidget);

      await tester.pumpWidget(host(const Padding(
        padding: EdgeInsets.all(20),
        child: Avatar(name: 'Мама'),
      )));
      expect(find.byType(StoryRingView), findsNothing);
    });

    test('цвета кольца замкнуты: синий → фиолетовый → розово-фиолетовый → зелёный → синий', () {
      expect(storyRingColors.length, 5);
      expect(storyRingColors.first, storyRingColors.last);
    });
  });

  group('Истории', () {
    test('JSON истории читается и повреждённое пропускается', () {
      final story = Story(mediaId: 'm1', kind: MediaKind.photo, addedAt: DateTime(2026, 10, 7));
      final parsed = StoryStore.parse(
        '{"p1":[{"mediaId":"m1","kind":"photo","addedAt":${story.addedAt.millisecondsSinceEpoch},"viewed":false},'
        '{"broken":true},{"mediaId":"m2","kind":"audio","addedAt":1}],"p2":"мусор"}',
      );
      expect(parsed.keys, ['p1']);
      expect(parsed['p1']!.single.mediaId, 'm1');
      expect(parsed['p1']!.single.viewed, isFalse);
      expect(StoryStore.parse('не json'), isEmpty);
      expect(StoryStore.parse(null), isEmpty);
    });

    test('просмотр меняет состояние на «просмотрено»', () {
      final fresh = Story(mediaId: 'm1', kind: MediaKind.video, addedAt: DateTime(2026, 10, 7));
      final seen = fresh.copyWith(viewed: true);
      expect(fresh.viewed, isFalse);
      expect(seen.viewed, isTrue);
      expect(Story.fromJson(seen.toJson())!.viewed, isTrue);
      expect(Story.fromJson(seen.toJson())!.kind, MediaKind.video);
    });
  });

  group('Воспроизведение голосового', () {
    test('без активного звука плеер пуст, перемотка ничего не ломает', () async {
      final playback = AudioPlayback();
      expect(playback.currentMedia, isNull);
      expect(playback.progressOf('x'), 0);
      await playback.seekFraction(0.5);
      await playback.togglePlayPause();
      expect(playback.currentMedia, isNull);
      playback.dispose();
    });

    testWidgets('верхний плеер скрыт, пока ничего не играет', (tester) async {
      final playback = AudioPlayback();
      await tester.pumpWidget(host(VoiceMiniPlayer(playback: playback)));
      expect(find.byIcon(AppIcons.play), findsNothing);
      expect(find.byIcon(AppIcons.pause), findsNothing);
      await tester.pumpWidget(const SizedBox());
      playback.dispose();
    });
  });

  group('Свайп чата', () {
    Widget tile(ValueNotifier<String?> open, List<String> log) => host(
          SizedBox(
            width: 400,
            height: 72,
            child: SwipeActionTile(
              id: 'a',
              open: open,
              leading: [
                SwipeAction(icon: AppIcons.pin, label: 'Закрепить', color: Colors.green, onTap: () => log.add('pin')),
              ],
              trailing: [
                SwipeAction(icon: AppIcons.delete, label: 'Удалить', color: Colors.red, onTap: () => log.add('delete')),
              ],
              child: GestureDetector(
                onTap: () => log.add('tap'),
                child: const SizedBox.expand(child: Center(child: Text('Строка'))),
              ),
            ),
          ),
        );

    testWidgets('влево открывает действия справа, нажатие выполняет и закрывает', (tester) async {
      final open = ValueNotifier<String?>(null);
      final log = <String>[];
      await tester.pumpWidget(tile(open, log));
      await tester.drag(find.text('Строка'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(open.value, 'a');
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(log, ['delete']);
      expect(open.value, isNull);
    });

    testWidgets('вправо открывает другие действия слева', (tester) async {
      final open = ValueNotifier<String?>(null);
      final log = <String>[];
      await tester.pumpWidget(tile(open, log));
      await tester.drag(find.text('Строка'), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(find.text('Закрепить'), findsOneWidget);
      expect(find.text('Удалить'), findsNothing);
      await tester.tap(find.text('Закрепить'));
      await tester.pumpAndSettle();
      expect(log, ['pin']);
    });

    testWidgets('недостаточный свайп возвращается, нажатие на открытую строку только закрывает', (tester) async {
      final open = ValueNotifier<String?>(null);
      final log = <String>[];
      await tester.pumpWidget(tile(open, log));
      await tester.drag(find.text('Строка'), const Offset(-20, 0));
      await tester.pumpAndSettle();
      expect(open.value, isNull);

      await tester.drag(find.text('Строка'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(open.value, 'a');
      final origin = tester.getTopLeft(find.byType(SwipeActionTile));
      await tester.tapAt(origin + const Offset(60, 36));
      await tester.pumpAndSettle();
      expect(log, isEmpty, reason: 'открытая строка не открывает чат');
      expect(open.value, isNull);

      await tester.tap(find.text('Строка'));
      expect(log, ['tap']);
    });
  });

  group('Громкая связь', () {
    test('по умолчанию выключена, переключается и сбрасывается новым звонком', () {
      final engine = CallEngine(recorder: _Recorder(), sounds: _Sounds());
      addTearDown(engine.dispose);
      engine.toggleSpeaker();
      expect(engine.speakerOn, isFalse, reason: 'вне звонка переключать нечего');
      engine.start(_voiceSession);
      expect(engine.speakerOn, isFalse);
      engine.toggleSpeaker();
      expect(engine.speakerOn, isTrue);
      engine.toggleSpeaker();
      expect(engine.speakerOn, isFalse);
      engine.toggleSpeaker();
      engine.hangUp();
      engine.start(_voiceSession);
      expect(engine.speakerOn, isFalse, reason: 'новый звонок снова через разговорный динамик');
      engine.hangUp();
    });

    testWidgets('кнопка «Динамик» меняет состояние; ход звонка не меняется', (tester) async {
      final engine = CallEngine(recorder: _Recorder(), sounds: _Sounds());
      addTearDown(engine.dispose);
      engine.start(_voiceSession);
      engine.activate();
      await tester.pumpWidget(host(
        ListenableBuilder(
          listenable: engine,
          builder: (context, _) => CallControls(engine: engine, video: false),
        ),
        theme: AppTheme.dark,
      ));
      expect(find.text('Динамик'), findsOneWidget);
      await tester.tap(find.text('Динамик'));
      await tester.pump();
      expect(engine.speakerOn, isTrue);
      expect(engine.phase, CallPhase.active);
      engine.hangUp();
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('Маршрут звука звонка', () {
    test('какой маршрут нужен в каждой фазе', () {
      bool? route(CallPhase p, {bool speaker = false}) => callAudioRoute(p, speakerOn: speaker);
      expect(route(CallPhase.incoming), isNull, reason: 'рингтон звучит обычно');
      expect(route(CallPhase.idle), isNull);
      expect(route(CallPhase.ended), isNull);
      expect(route(CallPhase.outgoing), isFalse, reason: 'гудки у уха');
      expect(route(CallPhase.connecting), isFalse);
      expect(route(CallPhase.active), isFalse, reason: 'по умолчанию разговорный динамик');
      expect(route(CallPhase.active, speaker: true), isTrue);
    });

    testWidgets('нативный маршрут получает выбранное значение', (tester) async {
      final calls = <MethodCall>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('ru.kinoprop.replika/recorder');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await ReplikaRecorder.setSpeaker(false);
      await ReplikaRecorder.setSpeaker(true);
      await ReplikaRecorder.releaseAudioRoute();
      expect(calls.map((c) => c.method), ['setSpeaker', 'setSpeaker', 'releaseAudioRoute']);
      expect(calls[0].arguments, {'on': false});
      expect(calls[1].arguments, {'on': true});
    });
  });

  group('Касание двумя пальцами', () {
    Future<int> run(WidgetTester tester, Future<void> Function(Offset center) gesture) async {
      var count = 0;
      await tester.pumpWidget(host(TwoFingerTap(
        onTap: () => count++,
        child: const SizedBox(width: 300, height: 300),
      )));
      await gesture(tester.getCenter(find.byType(TwoFingerTap)));
      return count;
    }

    testWidgets('два пальца быстро — срабатывает', (tester) async {
      final count = await run(tester, (c) async {
        final a = await tester.startGesture(c - const Offset(40, 0));
        final b = await tester.startGesture(c + const Offset(40, 0));
        await a.up();
        await b.up();
      });
      expect(count, 1);
    });

    testWidgets('один палец не срабатывает', (tester) async {
      final count = await run(tester, (c) async {
        final a = await tester.startGesture(c);
        await a.up();
      });
      expect(count, 0);
    });

    testWidgets('палец уехал далеко (прокрутка) — не срабатывает', (tester) async {
      final count = await run(tester, (c) async {
        final a = await tester.startGesture(c - const Offset(40, 0));
        final b = await tester.startGesture(c + const Offset(40, 0));
        await a.moveBy(const Offset(0, 80));
        await a.up();
        await b.up();
      });
      expect(count, 0);
    });

    testWidgets('три пальца — не срабатывает', (tester) async {
      final count = await run(tester, (c) async {
        final a = await tester.startGesture(c - const Offset(70, 0));
        final b = await tester.startGesture(c);
        final d = await tester.startGesture(c + const Offset(70, 0));
        await a.up();
        await b.up();
        await d.up();
      });
      expect(count, 0);
    });
  });
}
