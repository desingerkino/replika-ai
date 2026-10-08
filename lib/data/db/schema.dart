import 'package:sqflite/sqflite.dart';

/// Схема локальной базы и её миграции.
///
/// Правило: опубликованную миграцию не редактируем. Любое изменение схемы —
/// новая версия со своим списком команд, чтобы данные на телефонах
/// пользователей переживали обновление приложения.
abstract final class Schema {
  static const int version = 6;

  static Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    for (var target = from + 1; target <= to; target++) {
      final steps = _migrations[target];
      if (steps == null) {
        throw StateError('Нет миграции базы данных до версии $target');
      }
      for (final sql in steps) {
        await db.execute(sql);
      }
    }
  }

  static const Map<int, List<String>> _migrations = {1: _v1, 2: _v2, 3: _v3, 4: _v4, 5: _v5, 6: _v6};

  /// v6: архив чатов, свой фон у каждого чата (NULL — «Стандартный») и
  /// момент, когда голосовое прослушали до конца (отдельно от статуса доставки).
  static const List<String> _v6 = [
    'ALTER TABLE chats ADD COLUMN archived_at INTEGER',
    'ALTER TABLE chats ADD COLUMN background TEXT',
    'ALTER TABLE messages ADD COLUMN played_at INTEGER',
  ];

  /// v5: реакция на сообщение (эмодзи под пузырём) и истории — фото или
  /// видео персонажа на 24 часа, которые видны на этом телефоне.
  static const List<String> _v5 = [
    'ALTER TABLE messages ADD COLUMN reaction TEXT',
    '''
    CREATE TABLE stories (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
      character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
      media_id TEXT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      caption TEXT NOT NULL DEFAULT '',
      posted_at INTEGER NOT NULL,
      seen_at INTEGER,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_stories_device ON stories(device_id, posted_at)',
  ];

  /// v4: «Прочитано: OFF» у исходящего сообщения сцены. Пока флаг стоит,
  /// сообщение остаётся непрочитанным: его читает только ответ контакта
  /// на это конкретное сообщение (reply_to_id), а не любое следующее.
  static const List<String> _v4 = [
    'ALTER TABLE messages ADD COLUMN read_hold INTEGER NOT NULL DEFAULT 0',
  ];

  /// v3: цвет участника внутри группы и «мягкое» удаление из состава.
  /// Цвет принадлежит участнику группы и не меняется при переименовании
  /// контакта; NULL — прежнее поведение (цвет по имени). Удалённый участник
  /// остаётся строкой с removed_at, чтобы его старые сообщения сохранили
  /// имя и цвет.
  static const List<String> _v3 = [
    'ALTER TABLE chat_members ADD COLUMN color_tone INTEGER',
    'ALTER TABLE chat_members ADD COLUMN removed_at INTEGER',
  ];

  /// v2: моменты жизненного цикла сообщения — реальные данные, а не только
  /// текущее состояние. У существующих сообщений моменты берутся из времени
  /// отправки, чтобы история оставалась согласованной.
  static const List<String> _v2 = [
    'ALTER TABLE messages ADD COLUMN delivered_at INTEGER',
    'ALTER TABLE messages ADD COLUMN read_at INTEGER',
    'ALTER TABLE messages ADD COLUMN deleted_at INTEGER',
    "UPDATE messages SET delivered_at = sent_at WHERE state IN ('delivered', 'read')",
    "UPDATE messages SET read_at = sent_at WHERE state = 'read'",
    'UPDATE messages SET deleted_at = sent_at WHERE deleted = 1',
  ];

  static const List<String> _v1 = [
    '''
    CREATE TABLE media (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      path TEXT NOT NULL,
      original_name TEXT,
      mime TEXT,
      size_bytes INTEGER,
      duration_ms INTEGER,
      width INTEGER,
      height INTEGER,
      thumb_path TEXT,
      waveform TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE characters (
      id TEXT PRIMARY KEY,
      first_name TEXT NOT NULL DEFAULT '',
      last_name TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '',
      avatar_media_id TEXT REFERENCES media(id) ON DELETE SET NULL,
      avatar_tone INTEGER,
      status_text TEXT NOT NULL DEFAULT '',
      extra_json TEXT,
      behavior_json TEXT,
      call_audio_media_id TEXT REFERENCES media(id) ON DELETE SET NULL,
      call_video_media_id TEXT REFERENCES media(id) ON DELETE SET NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE devices (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      owner_character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE device_contacts (
      device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
      character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
      display_name TEXT NOT NULL,
      favorite INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (device_id, character_id)
    )
    ''',
    '''
    CREATE TABLE chats (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
      peer_character_id TEXT REFERENCES characters(id) ON DELETE SET NULL,
      title TEXT,
      is_group INTEGER NOT NULL DEFAULT 0,
      pinned_at INTEGER,
      unread_count INTEGER NOT NULL DEFAULT 0,
      muted INTEGER NOT NULL DEFAULT 0,
      draft TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_chats_device ON chats(device_id)',
    '''
    CREATE TABLE chat_members (
      chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
      character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
      PRIMARY KEY (chat_id, character_id)
    )
    ''',
    '''
    CREATE TABLE scenes (
      id TEXT PRIMARY KEY,
      number TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      device_id TEXT REFERENCES devices(id) ON DELETE SET NULL,
      chat_id TEXT REFERENCES chats(id) ON DELETE SET NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      duration_ms INTEGER NOT NULL DEFAULT 0,
      current_position INTEGER NOT NULL DEFAULT 0,
      take_number INTEGER NOT NULL DEFAULT 0,
      initial_state_json TEXT,
      copied_from_id TEXT REFERENCES scenes(id) ON DELETE SET NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE scene_characters (
      scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
      character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
      role TEXT NOT NULL DEFAULT '',
      PRIMARY KEY (scene_id, character_id)
    )
    ''',
    '''
    CREATE TABLE scene_actions (
      id TEXT PRIMARY KEY,
      scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      type TEXT NOT NULL,
      delay_ms INTEGER NOT NULL DEFAULT 0,
      params_json TEXT,
      note TEXT NOT NULL DEFAULT '',
      enabled INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_scene_actions_scene ON scene_actions(scene_id, position)',
    '''
    CREATE TABLE takes (
      id TEXT PRIMARY KEY,
      scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
      number INTEGER NOT NULL,
      started_at INTEGER NOT NULL,
      finished_at INTEGER,
      status TEXT NOT NULL DEFAULT 'running',
      result TEXT NOT NULL DEFAULT '',
      comment TEXT NOT NULL DEFAULT '',
      log_json TEXT
    )
    ''',
    'CREATE INDEX idx_takes_scene ON takes(scene_id, number)',
    '''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
      sender_id TEXT REFERENCES characters(id) ON DELETE SET NULL,
      type TEXT NOT NULL DEFAULT 'text',
      text TEXT NOT NULL DEFAULT '',
      sent_at INTEGER NOT NULL,
      state TEXT NOT NULL DEFAULT 'sent',
      media_id TEXT REFERENCES media(id) ON DELETE SET NULL,
      reply_to_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
      favorite INTEGER NOT NULL DEFAULT 0,
      deleted INTEGER NOT NULL DEFAULT 0,
      edited INTEGER NOT NULL DEFAULT 0,
      origin TEXT NOT NULL DEFAULT 'base',
      scene_id TEXT REFERENCES scenes(id) ON DELETE SET NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_messages_chat_time ON messages(chat_id, sent_at)',
    '''
    CREATE TABLE calls (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
      character_id TEXT REFERENCES characters(id) ON DELETE SET NULL,
      direction TEXT NOT NULL,
      kind TEXT NOT NULL,
      outcome TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      origin TEXT NOT NULL DEFAULT 'base',
      scene_id TEXT REFERENCES scenes(id) ON DELETE SET NULL
    )
    ''',
    'CREATE INDEX idx_calls_device_time ON calls(device_id, started_at)',
    '''
    CREATE TABLE prepared_replies (
      id TEXT PRIMARY KEY,
      category TEXT NOT NULL,
      text TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''',
  ];
}
