import '../db/tables.dart';
import '../models/media_item.dart';
import 'repository.dart';

/// Записи медиатеки. Сами файлы копирует и удаляет MediaStore.
class MediaRepository extends Repository {
  MediaRepository(super.database);

  Future<List<MediaItem>> list({MediaKind? kind}) async {
    final rows = await db.query(
      Tables.media,
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : [kind.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(MediaItem.fromRow).toList();
  }

  Future<MediaItem?> byId(String id) async {
    final rows = await db.query(Tables.media, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : MediaItem.fromRow(rows.first);
  }

  Future<void> insert(MediaItem item) async {
    await db.insert(Tables.media, item.toRow());
    notify({Tables.media});
  }

  /// Сколько сообщений и аватаров ссылается на файл.
  Future<int> usageCount(String id) async {
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM messages WHERE media_id = ?) +
        (SELECT COUNT(*) FROM characters WHERE avatar_media_id = ?) AS n
    ''', [id, id]);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Удаляет запись. Сообщения остаются с пометкой «Файл удалён»,
  /// аватары возвращаются к инициалам (ON DELETE SET NULL).
  Future<void> delete(String id) async {
    await db.delete(Tables.media, where: 'id = ?', whereArgs: [id]);
    notify({Tables.media, Tables.messages, Tables.characters});
  }
}
