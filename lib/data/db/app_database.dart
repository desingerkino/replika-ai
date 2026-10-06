import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db_changes.dart';
import 'schema.dart';

/// Локальная база SQLite во внутреннем хранилище приложения.
/// Данные переживают закрытие приложения и перезагрузку телефона;
/// удаляются только вместе с приложением или его данными.
class AppDatabase {
  AppDatabase._(this.db, this.changes);

  final Database db;
  final DbChanges changes;

  static const String fileName = 'replika.db';

  static Future<AppDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), fileName);
    final db = await openDatabase(
      dbPath,
      version: Schema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) => Schema.migrate(db, 0, version),
      onUpgrade: (db, from, to) => Schema.migrate(db, from, to),
      // onDowngrade намеренно не задан: при установке более старой версии
      // поверх новой данные не удаляются автоматически.
    );
    return AppDatabase._(db, DbChanges());
  }

  Future<void> close() async {
    await changes.close();
    await db.close();
  }
}
