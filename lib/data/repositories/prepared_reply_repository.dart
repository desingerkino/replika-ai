import '../../core/util/ids.dart';
import '../db/tables.dart';
import '../models/prepared_reply.dart';
import 'repository.dart';

/// Заготовки ответов для импровизации.
class PreparedReplyRepository extends Repository {
  PreparedReplyRepository(super.database);

  Future<List<PreparedReply>> list({ReplyCategory? category}) async {
    final rows = await db.query(
      Tables.preparedReplies,
      where: category == null ? null : 'category = ?',
      whereArgs: category == null ? null : [category.name],
      orderBy: 'category, sort_order, created_at',
    );
    return rows.map(PreparedReply.fromRow).toList();
  }

  Future<void> save({String? id, required ReplyCategory category, required String text}) async {
    final value = text.trim();
    if (value.isEmpty) return;
    if (id == null) {
      final reply = PreparedReply(
        id: newId(),
        category: category,
        text: value,
        sortOrder: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        createdAt: DateTime.now(),
      );
      await db.insert(Tables.preparedReplies, reply.toRow());
    } else {
      await db.update(
        Tables.preparedReplies,
        {'category': category.name, 'text': value},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    notify({Tables.preparedReplies});
  }

  Future<void> delete(String id) async {
    await db.delete(Tables.preparedReplies, where: 'id = ?', whereArgs: [id]);
    notify({Tables.preparedReplies});
  }
}
