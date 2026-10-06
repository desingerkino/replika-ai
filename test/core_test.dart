import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/core/design/tokens.dart';
import 'package:replika/core/design/widgets/avatar.dart';
import 'package:replika/core/util/ids.dart';
import 'package:replika/core/util/json.dart';
import 'package:replika/core/util/time_format.dart';
import 'package:replika/data/models/chat.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/data/models/origin.dart';
import 'package:replika/data/models/scene_action.dart';
import 'package:replika/features/chat/chat_rows.dart';
import 'package:replika/features/chat/message_bubble.dart';
import 'package:replika/features/chats/chat_filter.dart';
import 'package:replika/features/contacts/contact_filter.dart';

Message msg(
  String id,
  String? sender,
  DateTime at, {
  String text = 'текст',
  bool deleted = false,
}) =>
    Message(
      id: id,
      chatId: 'c1',
      senderId: sender,
      text: text,
      sentAt: at,
      createdAt: at,
      deleted: deleted,
    );

ChatListItem chatItem(String id, String name, Message? last) {
  final t = DateTime(2026, 9, 24, 12);
  return ChatListItem(
    chat: Chat(id: id, deviceId: 'd1', createdAt: t, updatedAt: t),
    peer: ChatPeer(displayName: name),
    ownerCharacterId: 'hero',
    lastMessage: last,
  );
}

void main() {
  // «Сегодня» для тестов — четверг, 24 сентября 2026, 15:00.
  final now = DateTime(2026, 9, 24, 15, 0);

  group('Форматы дат', () {
    test('время в списке чатов', () {
      expect(formatChatListTime(DateTime(2026, 9, 24, 9, 5), now), '09:05');
      expect(formatChatListTime(DateTime(2026, 9, 23, 23, 59), now), 'вчера');
      expect(formatChatListTime(DateTime(2026, 9, 21, 10, 0), now), 'пн');
      expect(formatChatListTime(DateTime(2026, 9, 10, 10, 0), now), '10 сент.');
      expect(formatChatListTime(DateTime(2025, 12, 31, 10, 0), now), '31.12.25');
    });

    test('разделитель дней', () {
      expect(formatDaySeparator(DateTime(2026, 9, 24, 1), now), 'Сегодня');
      expect(formatDaySeparator(DateTime(2026, 9, 23, 22), now), 'Вчера');
      expect(formatDaySeparator(DateTime(2026, 9, 10, 8), now), '10 сентября');
      expect(formatDaySeparator(DateTime(2025, 12, 31, 8), now), '31 декабря 2025');
    });

    test('календарные дни, а не 24 часа', () {
      expect(daysBetween(DateTime(2026, 9, 23, 23, 59), DateTime(2026, 9, 24, 0, 1)), 1);
      expect(daysBetween(DateTime(2026, 9, 24, 0, 1), DateTime(2026, 9, 24, 23, 59)), 0);
    });
  });

  group('Лента чата', () {
    test('разделители дней и группировка по отправителю', () {
      final rows = buildChatRows([
        msg('m0', 'a', DateTime(2026, 9, 23, 20, 0)),
        msg('m1', 'a', DateTime(2026, 9, 24, 10, 0)),
        msg('m2', 'a', DateTime(2026, 9, 24, 10, 3)),
        msg('m3', 'a', DateTime(2026, 9, 24, 10, 20)),
        msg('m4', 'hero', DateTime(2026, 9, 24, 10, 21)),
      ], ownerId: 'hero', now: now);

      expect(rows.length, 7);
      expect(rows[0], isA<DaySeparatorRow>());
      expect((rows[0] as DaySeparatorRow).label, 'Вчера');
      expect(rows[2], isA<DaySeparatorRow>());
      expect((rows[2] as DaySeparatorRow).label, 'Сегодня');

      final m1 = rows[3] as MessageRow;
      final m2 = rows[4] as MessageRow;
      final m3 = rows[5] as MessageRow;
      final m4 = rows[6] as MessageRow;
      expect(m1.joinsPrevious, isFalse);
      expect(m1.joinsNext, isTrue);
      expect(m2.joinsPrevious, isTrue);
      expect(m2.joinsNext, isFalse, reason: 'разрыв 17 минут');
      expect(m3.joinsPrevious, isFalse);
      expect(m3.joinsNext, isFalse, reason: 'другой отправитель');
      expect(m4.outgoing, isTrue);
      expect(m1.outgoing, isFalse);
    });

    test('скругления пузыря', () {
      final single = bubbleRadius(outgoing: true, joinsPrevious: false, joinsNext: false);
      expect(single.topRight, const Radius.circular(Radii.bubble));
      expect(single.bottomRight, const Radius.circular(Radii.tail));
      expect(single.topLeft, const Radius.circular(Radii.bubble));

      final middle = bubbleRadius(outgoing: true, joinsPrevious: true, joinsNext: true);
      expect(middle.topRight, const Radius.circular(Radii.joined));
      expect(middle.bottomRight, const Radius.circular(Radii.joined));

      final incoming = bubbleRadius(outgoing: false, joinsPrevious: false, joinsNext: false);
      expect(incoming.bottomLeft, const Radius.circular(Radii.tail));
      expect(incoming.bottomRight, const Radius.circular(Radii.bubble));
    });
  });

  group('Утилиты', () {
    test('инициалы', () {
      expect(initialsOf('Алексей Громов'), 'АГ');
      expect(initialsOf('мама'), 'М');
      expect(initialsOf('   '), '?');
    });

    test('идентификаторы UUID v4', () {
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      final ids = List.generate(200, (_) => newId());
      expect(ids.every(pattern.hasMatch), isTrue);
      expect(ids.toSet().length, ids.length);
    });

    test('повреждённый JSON не роняет приложение', () {
      expect(decodeJsonMap('{не json'), isEmpty);
      expect(decodeJsonMap(null), isEmpty);
      expect(decodeJsonMap('{"a": 1}')['a'], 1);
    });

    test('тона аватаров стабильны', () {
      expect(AvatarTones.indexForKey('Мама'), AvatarTones.indexForKey('Мама'));
      expect(AvatarTones.at(-3), AvatarTones.all[3]);
    });
  });

  group('Модели', () {
    test('сообщение сохраняется и читается без потерь', () {
      final original = Message(
        id: 'x1',
        chatId: 'c1',
        senderId: 's1',
        type: MessageType.videoNote,
        text: 'Привет',
        sentAt: DateTime(2026, 9, 24, 10, 30),
        state: MessageState.read,
        favorite: true,
        deleted: true,
        edited: true,
        origin: DataOrigin.scene,
        sceneId: 'scene-1',
        createdAt: DateTime(2026, 9, 24, 10, 30, 1),
      );
      final copy = Message.fromRow(original.toRow());
      expect(copy.type, MessageType.videoNote);
      expect(copy.state, MessageState.read);
      expect(copy.sentAt, original.sentAt);
      expect(copy.favorite && copy.deleted && copy.edited, isTrue);
      expect(copy.origin, DataOrigin.scene);
      expect(copy.sceneId, 'scene-1');
    });

    test('неизвестные значения в базе не ломают чтение', () {
      final row = msg('x2', 's', now).toRow()
        ..['type'] = 'hologram'
        ..['state'] = 'teleported';
      final message = Message.fromRow(row);
      expect(message.type, MessageType.text);
      expect(message.state, MessageState.sent);
    });

    test('действие таймлайна неизвестного типа сохраняется как есть', () {
      final unknown = SceneAction(
        id: 'a1',
        sceneId: 's1',
        position: 0,
        typeName: 'futureAction',
        params: const {'x': 1},
        createdAt: now,
        updatedAt: now,
      );
      expect(unknown.type, isNull);
      expect(unknown.isSupported, isFalse);
      final restored = SceneAction.fromRow(unknown.toRow());
      expect(restored.typeName, 'futureAction');
      expect(restored.params['x'], 1);

      final known = SceneAction.fromRow(
        unknown.toRow()..['type'] = ActionType.openChat.name,
      );
      expect(known.type, ActionType.openChat);
      expect(known.label, 'Открыть чат');
      expect(known.type!.group, ActionGroup.navigation);
    });

    test('в таймлайне есть все группы действий из ТЗ', () {
      final groups = ActionType.values.map((t) => t.group).toSet();
      expect(groups, ActionGroup.values.toSet());
    });
  });

  group('Поиск', () {
    test('чаты: по имени, по тексту, без учёта регистра и «ё»', () {
      final items = [
        chatItem('1', 'Мама', msg('a', 'n', now, text: 'Я волнуюсь')),
        chatItem('2', 'Алексей', msg('b', 'a', now, text: 'Срочно ПЕРЕЗВОНИ')),
        chatItem('3', 'Работа', msg('c', 'i', now, text: 'Ещё отчёт')),
      ];
      expect(filterChats(items, 'мам').map((i) => i.chat.id), ['1']);
      expect(filterChats(items, 'перезвони').map((i) => i.chat.id), ['2']);
      expect(filterChats(items, 'еще').map((i) => i.chat.id), ['3']);
      expect(filterChats(items, '').length, 3);
    });

    test('превью удалённого сообщения', () {
      expect(messagePreview(msg('d', 's', now, deleted: true)), 'Сообщение удалено');
      expect(messagePreview(null), isNull);
    });

    test('буквы разделов контактов', () {
      expect(sectionLetter('ёжик'), 'Е');
      expect(sectionLetter('Мама'), 'М');
      expect(sectionLetter('+7 900'), '#');
    });
  });
}
