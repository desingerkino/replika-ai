import '../../core/util/db_values.dart';
import '../../core/util/ids.dart';
import '../../core/util/media_paths.dart';
import '../db/tables.dart';
import '../models/story.dart';
import 'repository.dart';

/// Истории одного автора на телефоне: как он записан, аватар и сами истории
/// по времени публикации (старые сначала — так их и смотрят).
class StoryAuthor {
  const StoryAuthor({
    required this.characterId,
    required this.displayName,
    required this.stories,
    this.avatarTone,
    this.avatarPath,
    this.isOwner = false,
  });

  final String characterId;
  final String displayName;
  final int? avatarTone;
  final String? avatarPath;

  /// Владелец телефона («Моя история»).
  final bool isOwner;
  final List<Story> stories;

  /// Есть непросмотренные истории (кольцо — цветное).
  bool get hasUnseen => stories.any((s) => !s.seen);

  DateTime get latest => stories.last.postedAt;

  /// С какой истории начинать просмотр: с первой непросмотренной.
  int get startIndex {
    final i = stories.indexWhere((s) => !s.seen);
    return i < 0 ? 0 : i;
  }
}

class StoryRepository extends Repository {
  StoryRepository(super.database);

  static const String _select = '''
    SELECT s.*,
      md.id AS md_id, md.kind AS md_kind, md.path AS md_path,
      md.original_name AS md_original_name, md.mime AS md_mime,
      md.size_bytes AS md_size_bytes, md.duration_ms AS md_duration_ms,
      md.width AS md_width, md.height AS md_height,
      md.thumb_path AS md_thumb_path, md.waveform AS md_waveform,
      md.created_at AS md_created_at,
      COALESCE(dc.display_name, NULLIF(TRIM(c.first_name || ' ' || c.last_name), ''),
        NULLIF(c.phone, ''), 'Без имени') AS author_name,
      c.avatar_tone AS author_tone, am.path AS author_avatar,
      d.owner_character_id AS owner_id
    FROM stories s
    JOIN devices d ON d.id = s.device_id
    LEFT JOIN media md ON md.id = s.media_id
    LEFT JOIN characters c ON c.id = s.character_id
    LEFT JOIN device_contacts dc ON dc.device_id = s.device_id AND dc.character_id = s.character_id
    LEFT JOIN media am ON am.id = c.avatar_media_id
  ''';

  /// Активные (моложе суток) истории телефона, сгруппированные по авторам.
  /// Порядок: владелец, затем авторы с новыми историями, затем
  /// просмотренные; внутри групп — по свежести.
  Future<List<StoryAuthor>> authorsForDevice(String deviceId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final since = dateToInt(at.subtract(Story.lifetime));
    final rows = await db.rawQuery(
      '$_select WHERE s.device_id = ? AND s.posted_at > ? ORDER BY s.posted_at ASC, s.created_at ASC',
      [deviceId, since],
    );
    final byAuthor = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      byAuthor.putIfAbsent(row['character_id'] as String, () => []).add(row);
    }
    final authors = [
      for (final entry in byAuthor.entries)
        StoryAuthor(
          characterId: entry.key,
          displayName: readString(entry.value.first, 'author_name', 'Без имени'),
          avatarTone: readIntOrNull(entry.value.first, 'author_tone'),
          avatarPath: MediaPaths.resolveOrNull(readStringOrNull(entry.value.first, 'author_avatar')),
          isOwner: entry.value.first['owner_id'] == entry.key,
          stories: [for (final r in entry.value) Story.fromRow(r)],
        ),
    ];
    authors.sort((a, b) {
      if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
      if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
      return b.latest.compareTo(a.latest);
    });
    return authors;
  }

  /// Опубликовать историю от имени персонажа на этом телефоне.
  Future<Story> add({
    required String deviceId,
    required String characterId,
    required String mediaId,
    String caption = '',
    DateTime? postedAt,
    bool seen = false,
  }) async {
    final now = DateTime.now();
    final story = Story(
      id: newId(),
      deviceId: deviceId,
      characterId: characterId,
      mediaId: mediaId,
      caption: caption.trim(),
      postedAt: postedAt ?? now,
      seenAt: seen ? now : null,
      createdAt: now,
    );
    await db.insert(Tables.stories, story.toRow());
    notify({Tables.stories});
    return story;
  }

  Future<void> markSeen(String id) async {
    final changed = await db.rawUpdate(
      'UPDATE stories SET seen_at = ? WHERE id = ? AND seen_at IS NULL',
      [dateToInt(DateTime.now()), id],
    );
    if (changed > 0) notify({Tables.stories});
  }

  /// Снова «непросмотренные» — для повторного дубля.
  Future<void> markAllUnseen(String deviceId) async {
    await db.rawUpdate('UPDATE stories SET seen_at = NULL WHERE device_id = ?', [deviceId]);
    notify({Tables.stories});
  }

  Future<void> delete(String id) async {
    await db.delete(Tables.stories, where: 'id = ?', whereArgs: [id]);
    notify({Tables.stories});
  }
}
