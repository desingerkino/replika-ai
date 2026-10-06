import '../../core/util/db_values.dart';
import '../../core/util/json.dart';
import '../../core/util/media_paths.dart';

enum MediaKind {
  photo('Фото'),
  video('Видео'),
  audio('Аудио'),
  voice('Голосовое'),
  videoNote('Видеосообщение'),
  file('Файл');

  const MediaKind(this.label);
  final String label;
}

/// Файл медиатеки. Сам файл лежит во внутренней папке приложения,
/// в базе — путь и сведения о нём.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    required this.path,
    this.originalName,
    this.mime,
    this.sizeBytes,
    this.durationMs,
    this.width,
    this.height,
    this.thumbPath,
    this.waveform = const [],
    required this.createdAt,
  });

  final String id;
  final MediaKind kind;
  final String path;
  final String? originalName;
  final String? mime;
  final int? sizeBytes;
  final int? durationMs;
  final int? width;
  final int? height;
  final String? thumbPath;

  /// Огибающая звука 0..1 для голосовых сообщений.
  final List<double> waveform;
  final DateTime createdAt;

  factory MediaItem.fromRow(Map<String, Object?> row) => MediaItem(
        id: row['id'] as String,
        kind: enumByName(MediaKind.values, row['kind'], MediaKind.file),
        path: MediaPaths.resolve(readString(row, 'path')),
        originalName: readStringOrNull(row, 'original_name'),
        mime: readStringOrNull(row, 'mime'),
        sizeBytes: readIntOrNull(row, 'size_bytes'),
        durationMs: readIntOrNull(row, 'duration_ms'),
        width: readIntOrNull(row, 'width'),
        height: readIntOrNull(row, 'height'),
        thumbPath: MediaPaths.resolveOrNull(readStringOrNull(row, 'thumb_path')),
        waveform: decodeDoubleList(readStringOrNull(row, 'waveform')),
        createdAt: intToDate(row['created_at']),
      );

  /// Файл из строки с префиксом полей (например, «md_»); null — файла нет.
  static MediaItem? fromPrefixedRow(Map<String, Object?> row, String prefix) {
    if (row['${prefix}id'] == null) return null;
    return MediaItem.fromRow({
      for (final entry in row.entries)
        if (entry.key.startsWith(prefix)) entry.key.substring(prefix.length): entry.value,
    });
  }

  Duration? get duration => durationMs == null ? null : Duration(milliseconds: durationMs!);

  /// Соотношение сторон для превью; неизвестное — 4:3.
  double get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 4 / 3;
    return w / h;
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'kind': kind.name,
        'path': path,
        'original_name': originalName,
        'mime': mime,
        'size_bytes': sizeBytes,
        'duration_ms': durationMs,
        'width': width,
        'height': height,
        'thumb_path': thumbPath,
        'waveform': encodeDoubleList(waveform),
        'created_at': dateToInt(createdAt),
      };
}
