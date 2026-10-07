// Переписка с эталона экрана «Чат» (docs/brand/chat_reference.png) — для
// тестов и снимка экрана. В приложение эти данные не входят.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:replika/data/models/media_item.dart';
import 'package:replika/data/models/message.dart';

const String chatOwner = 'hero';
const String chatPeerId = 'peer-anna';

DateTime _at(int h, int m) => DateTime(2026, 10, 7, h, m);

/// Рисует картинку 1000×500: тёмная «кофейня» с тёплыми пятнами света.
Future<void> paintPhoto(String path, {bool sunset = false}) async {
  const w = 1000.0, h = 500.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(0, 0),
        const ui.Offset(w, h),
        sunset
            ? [const ui.Color(0xFF2A3548), const ui.Color(0xFFE8A06A), const ui.Color(0xFF1B1B26)]
            : [const ui.Color(0xFF2B221C), const ui.Color(0xFF6B4A34), const ui.Color(0xFF14110F)],
        const [0, 0.55, 1],
      ),
  );
  final rnd = math.Random(7);
  for (var i = 0; i < 9; i++) {
    canvas.drawCircle(
      ui.Offset(rnd.nextDouble() * w, rnd.nextDouble() * h * 0.6),
      30 + rnd.nextDouble() * 50,
      ui.Paint()..color = const ui.Color(0x33FFC88A),
    );
  }
  // «Человек»: тёмный силуэт и светлое лицо.
  canvas.drawOval(const ui.Rect.fromLTWH(330, 40, 250, 330), ui.Paint()..color = const ui.Color(0xFF3A2A22));
  canvas.drawOval(const ui.Rect.fromLTWH(390, 110, 150, 190), ui.Paint()..color = const ui.Color(0xFFC98F6B));
  canvas.drawRect(const ui.Rect.fromLTWH(250, 330, 420, 170), ui.Paint()..color = const ui.Color(0xFF15100E));
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
}

Message _m(
  String id,
  int h,
  int m, {
  required bool out,
  MessageType type = MessageType.text,
  String text = '',
  MediaItem? media,
  MessageState state = MessageState.read,
}) =>
    Message(
      id: id,
      chatId: 'chat-anna',
      senderId: out ? chatOwner : chatPeerId,
      type: type,
      text: text,
      state: state,
      media: media,
      sentAt: _at(h, m),
      createdAt: _at(h, m),
    );

/// Переписка эталона. Файлы-картинки должны уже лежать в [dir]
/// (см. [paintPhoto]); видео и PDF — пустые файлы-заглушки.
List<Message> referenceConversation(String dir) {
  MediaItem media(String id, MediaKind kind, String name, {int? ms, int? bytes, int w = 1000, int h = 500, List<double>? wave}) {
    final file = File('$dir/$name');
    if (!file.existsSync()) file.createSync(recursive: true);
    return MediaItem(
      id: id,
      kind: kind,
      path: file.path,
      originalName: name,
      durationMs: ms,
      sizeBytes: bytes,
      width: w,
      height: h,
      waveform: wave ?? const [],
      createdAt: _at(9, 0),
    );
  }

  final rnd = math.Random(3);
  final wave = [for (var i = 0; i < 44; i++) 0.15 + 0.85 * (0.5 + 0.5 * math.sin(i * 0.9)) * (0.4 + 0.6 * rnd.nextDouble())];

  return [
    _m('1', 9, 12, out: false, text: 'Привет! Как проходит твой день?\nТы уже на площадке?'),
    _m('2', 9, 14, out: true, text: 'Привет! Уже еду, буду через 20 минут.'),
    _m('3', 9, 15, out: false, type: MessageType.photo, media: media('p1', MediaKind.photo, 'cafe.png')),
    _m('4', 9, 15, out: false, text: 'Я уже в кафе, жду тебя 😊'),
    _m('5', 9, 16, out: true, type: MessageType.voice, media: media('v1', MediaKind.voice, 'voice.m4a', ms: 18000, wave: wave)),
    _m('6', 9, 18, out: false, type: MessageType.video, media: media('c1', MediaKind.video, 'frames.mp4', ms: 24000)),
    _m('7', 9, 18, out: false, text: 'Посмотри кадры, как тебе?\nНужно что-то поменять?'),
    _m('8', 9, 20, out: true, text: 'Выглядит отлично! Оставляем. Спасибо 🙏'),
    _m('9', 9, 21, out: false, type: MessageType.file, media: media('f1', MediaKind.file, 'Список реквизита.pdf', bytes: 2516582, w: 0, h: 0)),
    _m('10', 9, 22, out: true, text: 'Принял, посмотрю.'),
  ];
}
