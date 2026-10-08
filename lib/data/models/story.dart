import '../../core/util/db_values.dart';
import 'media_item.dart';

/// История: фото или видео персонажа, видимое на телефоне 24 часа.
class Story {
  const Story({
    required this.id,
    required this.deviceId,
    required this.characterId,
    required this.mediaId,
    this.caption = '',
    required this.postedAt,
    this.seenAt,
    required this.createdAt,
    this.media,
  });

  /// Сколько история видна после публикации.
  static const Duration lifetime = Duration(hours: 24);

  final String id;
  final String deviceId;
  final String characterId;
  final String mediaId;
  final String caption;

  /// Время публикации, которое видно в кадре («15 минут назад»).
  final DateTime postedAt;

  /// Когда владелец телефона её посмотрел (null — не смотрел).
  final DateTime? seenAt;
  final DateTime createdAt;

  /// Файл истории (подгружается запросом, в базу не пишется).
  final MediaItem? media;

  bool get seen => seenAt != null;

  bool isActive(DateTime now) => now.difference(postedAt) < lifetime;

  factory Story.fromRow(Map<String, Object?> row) => Story(
        id: row['id'] as String,
        deviceId: row['device_id'] as String,
        characterId: row['character_id'] as String,
        mediaId: row['media_id'] as String,
        caption: readString(row, 'caption'),
        postedAt: intToDate(row['posted_at']),
        seenAt: intToDateOrNull(row['seen_at']),
        createdAt: intToDate(row['created_at']),
        media: MediaItem.fromPrefixedRow(row, 'md_'),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'device_id': deviceId,
        'character_id': characterId,
        'media_id': mediaId,
        'caption': caption,
        'posted_at': dateToInt(postedAt),
        'seen_at': seenAt == null ? null : dateToInt(seenAt!),
        'created_at': dateToInt(createdAt),
      };
}
