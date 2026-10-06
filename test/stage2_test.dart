import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/typing.dart';
import 'package:replika/core/util/text.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/features/chat/chat_rows.dart';
import 'package:replika/features/profile/contact_edit_screen.dart';
import 'package:replika/features/settings/settings_screen.dart';

Message incoming(String id, DateTime at) =>
    Message(id: id, chatId: 'c', senderId: 'peer', sentAt: at, createdAt: at);

Message outgoing(String id, DateTime at) =>
    Message(id: id, chatId: 'c', senderId: 'hero', sentAt: at, createdAt: at);

void main() {
  final now = DateTime(2026, 9, 24, 15, 0);

  group('Поиск и подсветка', () {
    test('совпадение без учёта регистра и «ё»', () {
      final match = findMatch('Ещё отчёт готов', 'ОТЧЕТ');
      expect(match, isNotNull);
      expect(match!.start, 4);
      expect(match.end, 9);
      expect(findMatch('Привет', 'пока'), isNull);
      expect(findMatch('Привет', '  '), isNull);
    });

    test('фрагмент длинного текста начинается рядом с совпадением', () {
      const text = 'Сначала очень длинное вступление о погоде и делах, а потом главное: '
          'перезвони срочно';
      final cut = excerpt(text, 'перезвони');
      expect(cut.startsWith('…'), isTrue);
      expect(cut.contains('перезвони'), isTrue);
      expect(excerpt('Коротко: перезвони', 'перезвони'), 'Коротко: перезвони');
    });
  });

  group('Плашка непрочитанных', () {
    final messages = [
      incoming('a', DateTime(2026, 9, 24, 10, 0)),
      outgoing('b', DateTime(2026, 9, 24, 10, 1)),
      incoming('c', DateTime(2026, 9, 24, 10, 2)),
      incoming('d', DateTime(2026, 9, 24, 10, 3)),
    ];

    int separatorBefore(List<ChatRow> rows) {
      final i = rows.indexWhere((r) => r is UnreadSeparatorRow);
      return i < 0 ? -1 : i;
    }

    test('стоит перед первым из непрочитанных входящих', () {
      final rows = buildChatRows(messages, ownerId: 'hero', now: now, unreadCount: 2);
      final i = separatorBefore(rows);
      expect(i, greaterThan(0));
      expect((rows[i + 1] as MessageRow).message.id, 'c');
    });

    test('нет непрочитанных — нет плашки', () {
      final rows = buildChatRows(messages, ownerId: 'hero', now: now);
      expect(separatorBefore(rows), -1);
    });

    test('счётчик больше числа входящих — перед первым входящим', () {
      final rows = buildChatRows(messages, ownerId: 'hero', now: now, unreadCount: 9);
      final i = separatorBefore(rows);
      expect((rows[i + 1] as MessageRow).message.id, 'a');
    });
  });

  group('«Печатает…»', () {
    test('включается, выключается и оповещает интерфейс', () {
      final typing = TypingRegistry();
      var notified = 0;
      typing.addListener(() => notified++);
      typing.start('chat-1');
      expect(typing.isTyping('chat-1'), isTrue);
      expect(typing.isTyping('chat-2'), isFalse);
      typing.stop('chat-1');
      expect(typing.isTyping('chat-1'), isFalse);
      typing.start('chat-2');
      typing.stopAll();
      expect(typing.isTyping('chat-2'), isFalse);
      expect(notified, 4);
      typing.dispose();
    });
  });

  group('Форма контакта', () {
    test('имя в контактах подставляется из настоящего имени', () {
      const check = ContactFormCheck(
        displayName: ' ',
        firstName: 'Вероника',
        lastName: 'Лебедева',
        ownerMode: false,
      );
      expect(check.resolvedDisplayName, 'Вероника Лебедева');
      expect(check.error, isNull);
    });

    test('пустой контакт не сохраняется', () {
      const check = ContactFormCheck(displayName: '', firstName: '', lastName: '', ownerMode: false);
      expect(check.error, isNotNull);
    });

    test('владельцу телефона нужно имя', () {
      const check = ContactFormCheck(displayName: '', firstName: '', lastName: 'Ветров', ownerMode: true);
      expect(check.error, isNotNull);
    });
  });

  test('подписи темы на русском', () {
    expect(themeModeLabel(ThemeMode.system), 'Как в системе');
    expect(themeModeLabel(ThemeMode.dark), 'Тёмная');
  });
}
