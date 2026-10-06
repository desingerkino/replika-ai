import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

/// База репозиториев: доступ к базе и оповещение об изменениях таблиц.
abstract class Repository {
  Repository(this.database);

  final AppDatabase database;

  Database get db => database.db;

  void notify(Set<String> tables) => database.changes.notify(tables);
}
