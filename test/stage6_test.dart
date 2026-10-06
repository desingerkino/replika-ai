import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/improv.dart';
import 'package:replika/data/models/prepared_reply.dart';

class FakeSender implements ImprovSender {
  final List<String> chat = [];
  var _next = 0;

  @override
  Future<String> send(String chatId, QueuedReply reply) async {
    chat.add(reply.text);
    return 'm${_next++}:${reply.text}';
  }

  @override
  Future<void> delete(String messageId) async => chat.remove(messageId.split(':').last);
}

void main() {
  group('Очередь импровизации', () {
    test('взведённая очередь отправляет ответы по одному', () async {
      final sender = FakeSender();
      final improv = ImprovController(sender)
        ..setChat('c1')
        ..enqueue(const QueuedReply(text: 'Ты где?'))
        ..enqueue(const QueuedReply(text: 'Ответь'));
      await improv.sendNext();
      expect(sender.chat, isEmpty, reason: 'пока очередь не взведена, ничего не уходит');
      improv.arm(true);
      await improv.sendNext();
      expect(sender.chat, ['Ты где?']);
      await improv.sendNext();
      await improv.sendNext();
      expect(sender.chat, ['Ты где?', 'Ответь']);
      expect(improv.queue.isEmpty, isTrue);
    });

    test('отмена убирает сообщение и возвращает реплику в начало очереди', () async {
      final sender = FakeSender();
      final improv = ImprovController(sender)
        ..setChat('c1')
        ..enqueue(const QueuedReply(text: 'Первый'))
        ..enqueue(const QueuedReply(text: 'Второй'))
        ..arm(true);
      await improv.sendNext();
      await improv.undoLast();
      expect(sender.chat, isEmpty);
      expect(improv.queue.items.map((r) => r.text), ['Первый', 'Второй']);
      await improv.sendNext();
      expect(sender.chat, ['Первый']);
    });

    test('пустой текст в очередь не попадает, без чата очередь не взводится', () {
      final improv = ImprovController(FakeSender())..enqueue(const QueuedReply(text: '  '));
      expect(improv.queue.isEmpty, isTrue);
      improv.arm(true);
      expect(improv.armed, isFalse);
    });
  });

  group('Подсказка категорий (ключевые слова, не ИИ)', () {
    test('вопрос героя — объяснение', () {
      expect(suggestReplyCategories('Ты где сейчас').first, ReplyCategory.explain);
      expect(suggestReplyCategories('Всё нормально?').first, ReplyCategory.explain);
    });

    test('извинение — эмоции, просьба — согласие', () {
      expect(suggestReplyCategories('Прости меня, пожалуйста').first, ReplyCategory.emotional);
      expect(suggestReplyCategories('Давай встретимся вечером').first, ReplyCategory.agree);
    });

    test('приветствие и пустая реплика', () {
      expect(suggestReplyCategories('Привет').first, ReplyCategory.short);
      expect(suggestReplyCategories('').first, ReplyCategory.neutral);
    });
  });
}
