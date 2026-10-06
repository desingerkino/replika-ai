import 'package:flutter_test/flutter_test.dart';
import 'package:replika/data/models/media_item.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/features/media/media_kinds.dart';

void main() {
  group('Виды файлов', () {
    test('по расширению, с учётом назначения', () {
      expect(kindForFile('IMG_0042.JPG'), MediaKind.photo);
      expect(kindForFile('сцена12.mp4'), MediaKind.video);
      expect(kindForFile('сцена12.mp4', preferred: MediaKind.videoNote), MediaKind.videoNote);
      expect(kindForFile('мама.m4a'), MediaKind.audio);
      expect(kindForFile('мама.ogg', preferred: MediaKind.voice), MediaKind.voice);
      expect(kindForFile('договор.pdf'), MediaKind.file);
      expect(kindForFile('без_расширения'), MediaKind.file);
      expect(kindForFile('фото.jpg', preferred: MediaKind.voice), MediaKind.photo);
    });

    test('тип сообщения и MIME', () {
      expect(messageTypeFor(MediaKind.voice), MessageType.voice);
      expect(messageTypeFor(MediaKind.videoNote), MessageType.videoNote);
      expect(mimeForFile('a.jpeg'), 'image/jpeg');
      expect(mimeForFile('a.MOV'), 'video/quicktime');
      expect(mimeForFile('a.xyz'), 'application/octet-stream');
    });
  });

  group('Подписи', () {
    test('длительность', () {
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
      expect(formatDuration(const Duration(minutes: 12, seconds: 40)), '12:40');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('размер файла', () {
      expect(formatBytes(512), '512 Б');
      expect(formatBytes(820 * 1024), '820 КБ');
      expect(formatBytes((12.4 * 1024 * 1024).round()), '12 МБ');
      expect(formatBytes((1.5 * 1024 * 1024).round()), '1,5 МБ');
    });
  });

  test('«волна» голосового стабильна и в допустимых пределах', () {
    final a = decorativeWaveform('media-1');
    final b = decorativeWaveform('media-1');
    final c = decorativeWaveform('media-2');
    expect(a, b);
    expect(a, isNot(c));
    expect(a.length, 40);
    expect(a.every((v) => v >= 0.1 && v <= 1.0), isTrue);
  });

  test('сообщение читает файл из общего запроса ленты', () {
    final at = DateTime(2026, 9, 24, 12);
    final media = MediaItem(
      id: 'md1',
      kind: MediaKind.voice,
      path: '/data/media/md1.ogg',
      durationMs: 7000,
      waveform: const [0.2, 0.8],
      createdAt: at,
    );
    final row = {
      ...Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 's1',
        type: MessageType.voice,
        sentAt: at,
        mediaId: 'md1',
        createdAt: at,
      ).toRow(),
      for (final e in media.toRow().entries) 'md_${e.key}': e.value,
    };
    final message = Message.fromRow(row);
    expect(message.isMedia, isTrue);
    expect(message.media?.kind, MediaKind.voice);
    expect(message.media?.duration, const Duration(seconds: 7));
    expect(message.media?.waveform, [0.2, 0.8]);
  });

  test('неизвестные размеры — превью 4:3', () {
    final item = MediaItem(id: 'x', kind: MediaKind.photo, path: '/x.jpg', createdAt: DateTime(2026));
    expect(item.aspectRatio, closeTo(4 / 3, 0.001));
  });
}
