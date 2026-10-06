import 'package:sqflite/sqflite.dart';

import '../../core/util/db_values.dart';
import '../db/app_database.dart';
import '../db/tables.dart';
import '../models/message.dart';
import '../repositories/settings_repository.dart';

/// Демонстрационные данные: телефон героя, персонажи из ТЗ и переписки.
///
/// Записываются один раз, при первом запуске, одной транзакцией.
/// Потом это обычные данные: их можно менять и удалять, повторно
/// они не появятся. Номера телефонов вымышленные — перед съёмкой
/// заменить на согласованные с площадкой.
class DemoSeed {
  DemoSeed(this.database);

  final AppDatabase database;

  /// 1 — персонажи и переписки, 2 — демонстрационная сцена,
  /// 3 — заготовки ответов для импровизации.
  static const int version = 3;

  static const String heroId = 'char-maxim';
  static const String veronikaId = 'char-veronika';
  static const String ninaId = 'char-nina';
  static const String alekseyId = 'char-aleksey';
  static const String igorId = 'char-igor';
  static const String deviceId = 'device-maxim';

  /// Возвращает true, если данные были записаны сейчас.
  /// Уже установленное приложение получает только недостающие части
  /// (например, демо-сцену), существующие данные не трогаются.
  Future<bool> ensure({DateTime? now}) async {
    final db = database.db;
    final done = await db.query(
      Tables.settings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [SettingKeys.seedVersion],
      limit: 1,
    );
    final current = done.isEmpty ? 0 : int.tryParse(done.first['value'] as String? ?? '') ?? 0;
    if (current >= version) return false;

    final moment = now ?? DateTime.now();
    await db.transaction((txn) async {
      if (current < 1) {
        await _write(txn, moment);
        await txn.insert(
          Tables.settings,
          {'key': SettingKeys.currentDeviceId, 'value': deviceId},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (current < 2) await _writeScene(txn, moment);
      if (current < 3) await _writeReplies(txn, moment);
      await txn.insert(
        Tables.settings,
        {'key': SettingKeys.seedVersion, 'value': '$version'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    database.changes.notify(Tables.all);
    return true;
  }

  /// Заготовки ответов по категориям ТЗ. Их можно менять и удалять.
  Future<void> _writeReplies(Transaction txn, DateTime now) async {
    const replies = <String, List<String>>{
      'short': ['Ок', 'Да', 'Нет', 'Понял', 'Ага', 'Хорошо'],
      'neutral': ['Посмотрим', 'Ладно, потом обсудим', 'Я на месте', 'Напиши, когда освободишься'],
      'emotional': ['Ты серьёзно?!', 'Мне очень обидно', 'Я так скучаю', 'Не могу больше это терпеть', '😢'],
      'question': ['Ты где?', 'Почему не отвечаешь?', 'Что случилось?', 'Ты один?', 'Когда будешь?'],
      'agree': ['Договорились', 'Давай', 'Конечно', 'Без проблем'],
      'refuse': ['Нет, не сегодня', 'Не могу', 'Даже не проси', 'Я против'],
      'explain': ['Я всё объясню при встрече', 'Это не то, что ты думаешь', 'Телефон сел, прости', 'Задержали на работе'],
      'action': ['Выхожу', 'Уже еду', 'Буду через 10 минут', 'Открой дверь', 'Перезвони мне'],
    };
    final ms = dateToInt(now);
    var order = 0;
    for (final entry in replies.entries) {
      for (final text in entry.value) {
        order++;
        await txn.insert(
          Tables.preparedReplies,
          {
            'id': 'reply-default-$order',
            'category': entry.key,
            'text': text,
            'sort_order': order,
            'created_at': ms,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  /// Демо-сцена «12. Вероника у офиса» — чтобы сразу попробовать панель.
  Future<void> _writeScene(Transaction txn, DateTime now) async {
    final chat = await txn.query(Tables.chats, columns: ['id'], where: 'id = ?', whereArgs: ['chat-veronika']);
    if (chat.isEmpty) return;
    final ms = dateToInt(now);
    await txn.insert(
      Tables.scenes,
      {
        'id': 'scene-demo-12',
        'number': '12',
        'name': 'Вероника у офиса',
        'description': 'Демо: входящие с «печатает…», исходящее с галочками, пауза, удаление.',
        'device_id': deviceId,
        'chat_id': 'chat-veronika',
        'status': 'ready',
        'created_at': ms,
        'updated_at': ms,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    const actions = <(String, int, String)>[
      ('showIncoming', 1000, '{"text":"Ты где сейчас?","typingMs":2500}'),
      ('showIncoming', 1500, '{"text":"Я у твоего офиса. Света в окнах нет","typingMs":3500}'),
      ('sendMessage', 2500, '{"text":"Задержался на встрече, скоро буду","deliverMs":1200,"readMs":2500}'),
      ('pause', 0, '{}'),
      ('showIncoming', 800, '{"text":"Не ври мне.","typingMs":2000}'),
      ('deleteMessage', 2500, '{"target":"lastIncoming"}'),
    ];
    for (var i = 0; i < actions.length; i++) {
      final (type, delay, params) = actions[i];
      await txn.insert(
        Tables.sceneActions,
        {
          'id': 'scene-demo-12-a${i + 1}',
          'scene_id': 'scene-demo-12',
          'position': i,
          'type': type,
          'delay_ms': delay,
          'params_json': params,
          'note': '',
          'enabled': 1,
          'created_at': ms,
          'updated_at': ms,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _write(Transaction txn, DateTime now) async {
    final nowMs = dateToInt(now);

    DateTime day(int daysAgo, int hour, int minute) =>
        DateTime(now.year, now.month, now.day - daysAgo, hour, minute);
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

    // Персонажи.
    final characters = <Map<String, Object?>>[
      _character(heroId, 'Максим', 'Ветров', '+7 915 318-42-07', 'Главный герой. Владелец телефона в кадре.', 6, 'в сети'),
      _character(veronikaId, 'Вероника', 'Лебедева', '+7 926 571-08-33', 'Девушка героя.', 4, 'в сети'),
      _character(ninaId, 'Нина', 'Ветрова', '+7 903 744-19-62', 'Мама героя.', 1, 'была недавно'),
      _character(alekseyId, 'Алексей', 'Громов', '+7 985 260-51-14', 'Друг героя со школы.', 3, 'был недавно'),
      _character(igorId, 'Игорь', 'Панин', '+7 495 781-36-20', 'Начальник героя, руководитель отдела.', 0, 'был недавно'),
    ];
    for (final row in characters) {
      await txn.insert(Tables.characters, {...row, 'created_at': nowMs, 'updated_at': nowMs});
    }

    // Телефон героя.
    await txn.insert(Tables.devices, {
      'id': deviceId,
      'name': 'Телефон Максима',
      'owner_character_id': heroId,
      'sort_order': 0,
      'created_at': nowMs,
    });

    // Как персонажи записаны в контактах этого телефона.
    const contacts = {
      veronikaId: 'Красотка',
      ninaId: 'Мама',
      alekseyId: 'Алексей',
      igorId: 'Работа',
    };
    for (final entry in contacts.entries) {
      await txn.insert(Tables.deviceContacts, {
        'device_id': deviceId,
        'character_id': entry.key,
        'display_name': entry.value,
        'favorite': entry.key == ninaId ? 1 : 0,
        'created_at': nowMs,
      });
    }

    // Переписки. Последние входящие без ответа — непрочитанные.
    final chats = <_SeedChat>[
      _SeedChat('chat-veronika', veronikaId, unread: 2, messages: [
        _SeedMessage(veronikaId, 'Ты сегодня опять допоздна?', day(1, 21, 14)),
        _SeedMessage(heroId, 'Да, сдаём проект. Прости', day(1, 21, 31)),
        _SeedMessage(heroId, 'Завтра точно освобожусь', day(1, 21, 31)),
        _SeedMessage(veronikaId, 'Ладно', day(1, 21, 40)),
        _SeedMessage(veronikaId, 'Я купила билеты на пятницу, не забудь', day(1, 21, 40)),
        _SeedMessage(heroId, 'Не забуду. Что за фильм?', day(1, 22, 5)),
        _SeedMessage(veronikaId, 'Сюрприз 🙂', day(1, 22, 7)),
        _SeedMessage(heroId, 'Доброе утро', ago(134)),
        _SeedMessage(veronikaId, 'Доброе. Ты где вчера был в час ночи?', ago(130)),
        _SeedMessage(veronikaId, 'Я звонила', ago(129)),
        _SeedMessage(heroId, 'Телефон сел. В офисе был, честно', ago(118), MessageState.read, 10),
        _SeedMessage(veronikaId, 'Нам надо поговорить', ago(12), MessageState.delivered),
        _SeedMessage(veronikaId, 'Сегодня. Без отговорок', ago(11), MessageState.delivered),
      ]),
      _SeedChat('chat-mama', ninaId, unread: 2, pinned: true, messages: [
        _SeedMessage(ninaId, 'Максим, ты шапку купил? Холодно же', day(3, 19, 20)),
        _SeedMessage(heroId, 'Мам, ещё тепло 🙂', day(3, 20, 2)),
        _SeedMessage(ninaId, 'Всё равно', day(3, 20, 3)),
        _SeedMessage(ninaId, 'Позвони, когда сможешь', day(1, 12, 47)),
        _SeedMessage(heroId, 'Вечером наберу', day(1, 18, 10)),
        _SeedMessage(ninaId, 'Ты так и не позвонил', ago(47), MessageState.delivered),
        _SeedMessage(ninaId, 'Я волнуюсь', ago(46), MessageState.delivered),
      ]),
      _SeedChat('chat-aleksey', alekseyId, unread: 1, messages: [
        _SeedMessage(heroId, 'Ну что, в пятницу в силе?', day(6, 22, 15)),
        _SeedMessage(alekseyId, 'Конечно. В восемь у Лёвы', day(6, 22, 40)),
        _SeedMessage(alekseyId, 'Возьми гитару', day(6, 22, 41)),
        _SeedMessage(alekseyId, 'Ты видел, что Панин разослал?', day(2, 14, 3)),
        _SeedMessage(heroId, 'Видел. Потом обсудим', day(2, 14, 30)),
        _SeedMessage(alekseyId, 'Слушай, срочно перезвони. Это не про пятницу', ago(25), MessageState.delivered),
      ]),
      _SeedChat('chat-work', igorId, unread: 0, messages: [
        _SeedMessage(igorId, 'Максим, отчёт к 18:00 жду', day(1, 9, 12)),
        _SeedMessage(heroId, 'Отправил на почту', day(1, 17, 55)),
        _SeedMessage(heroId, 'Там две таблицы, вторая по регионам', day(1, 17, 56)),
        _SeedMessage(igorId, 'Получил. Завтра в 10 планёрка, не опаздывай', day(1, 18, 20)),
        _SeedMessage(igorId, 'Планёрку перенесли на 11', ago(190)),
      ]),
    ];

    var pinOffset = 0;
    for (final chat in chats) {
      // Устойчивая сортировка: при одинаковом времени сохраняется порядок реплик.
      final indexed = [for (var i = 0; i < chat.messages.length; i++) (i, chat.messages[i])];
      indexed.sort((a, b) {
        final byTime = a.$2.at.compareTo(b.$2.at);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
      final sorted = [for (final entry in indexed) entry.$2];
      final lastAt = sorted.isEmpty ? now : sorted.last.at;
      await txn.insert(Tables.chats, {
        'id': chat.id,
        'device_id': deviceId,
        'peer_character_id': chat.peerId,
        'is_group': 0,
        'pinned_at': chat.pinned ? nowMs - pinOffset++ : null,
        'unread_count': chat.unread,
        'muted': 0,
        'created_at': dateToInt(sorted.isEmpty ? now : sorted.first.at),
        'updated_at': dateToInt(lastAt),
      });
      for (final member in [heroId, chat.peerId]) {
        await txn.insert(Tables.chatMembers, {'chat_id': chat.id, 'character_id': member});
      }
      var index = 0;
      for (final message in sorted) {
        index++;
        await txn.insert(Tables.messages, {
          'id': '${chat.id}-m$index',
          'chat_id': chat.id,
          'sender_id': message.from,
          'type': MessageType.text.name,
          'text': message.text,
          'sent_at': dateToInt(message.at),
          'state': message.state.name,
          'favorite': 0,
          'deleted': 0,
          'edited': 0,
          'origin': 'base',
          // Ответ ссылается только на уже записанное сообщение этого чата.
          'reply_to_id': message.replyTo != null && message.replyTo! < index
              ? '${chat.id}-m${message.replyTo}'
              : null,
          // Порядок записи = порядок в переписке, даже при одинаковом времени.
          'created_at': dateToInt(message.at) + index,
        });
      }
    }
  }

  static Map<String, Object?> _character(
    String id,
    String firstName,
    String lastName,
    String phone,
    String description,
    int tone,
    String status,
  ) =>
      {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'description': description,
        'avatar_tone': tone,
        'status_text': status,
      };
}

class _SeedChat {
  _SeedChat(
    this.id,
    this.peerId, {
    required this.unread,
    this.pinned = false,
    required this.messages,
  });

  final String id;
  final String peerId;
  final int unread;
  final bool pinned;
  final List<_SeedMessage> messages;
}

class _SeedMessage {
  _SeedMessage(this.from, this.text, this.at, [this.state = MessageState.read, this.replyTo]);

  final String from;
  final String text;
  final DateTime at;
  final MessageState state;

  /// Номер (с 1, в хронологическом порядке) сообщения, на которое это ответ.
  final int? replyTo;
}
