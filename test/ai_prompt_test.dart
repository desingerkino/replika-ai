// ИИ-собеседник: что именно получает модель (персонаж, история, параметры),
// очистка ответа и маршрутизация личный чат / группа.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/auto_reply.dart';
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/data/models/chat.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/features/settings/addons_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const device = 'device-maxim';
const maxim = 'char-maxim';
const nina = 'char-nina';
const veronika = 'char-veronika';
const mamaChat = 'chat-mama';

final DateTime _t = DateTime(2026, 10, 7, 12);
var _n = 0;

Message msg(String? sender, String text, {MessageType type = MessageType.text, bool deleted = false}) {
  _n++;
  return Message(
    id: 'm$_n',
    chatId: 'c',
    senderId: sender,
    type: type,
    text: text,
    deleted: deleted,
    sentAt: _t.add(Duration(minutes: _n)),
    createdAt: _t.add(Duration(minutes: _n)),
  );
}

class _Silent implements CallSounds {
  @override
  void ringtone() {}
  @override
  void ringback() {}
  @override
  void hangup() {}
  @override
  void stop() {}
}

/// Модель-заглушка: запоминает, что её спросили.
class _FakeEngine implements AutoReplyEngine {
  final List<AiPrompt> prompts = [];
  String? answer = 'Хорошо, жду';

  @override
  bool get ready => true;

  @override
  String get statusText => 'готова';

  @override
  Future<void> prepare() async {}

  @override
  Future<String?> reply(AiPrompt prompt) async {
    prompts.add(prompt);
    return answer;
  }

  @override
  void cancel() {}

  @override
  Widget? buildSetupPage() => null;
}

void main() {
  group('История для модели', () {
    test('роли, порядок и прошлый ответ персонажа сохраняются', () {
      final turns = buildAiHistory([
        msg(nina, 'Ты шапку купил?'),
        msg(maxim, 'Ещё тепло'),
        msg(nina, 'Всё равно купи'),
        msg(maxim, 'Ладно'),
      ], ownerId: maxim);
      expect(turns.map((t) => t.fromOwner), [false, true, false, true]);
      expect(turns.map((t) => t.text), ['Ты шапку купил?', 'Ещё тепло', 'Всё равно купи', 'Ладно']);
      expect(turns.last.fromOwner, isTrue, reason: 'последним идёт сообщение, на которое отвечаем');
    });

    test('в историю идут только текстовые, не удалённые и не пустые сообщения', () {
      final turns = buildAiHistory([
        msg(nina, 'Привет'),
        msg(maxim, '', type: MessageType.photo),
        msg(maxim, 'Исходящий звонок', type: MessageType.call),
        msg(maxim, 'стёрто', deleted: true),
        msg(maxim, '   '),
        msg(maxim, 'Привет, мам'),
      ], ownerId: maxim);
      expect(turns.map((t) => t.text), ['Привет', 'Привет, мам']);
    });

    test('сообщения одного автора подряд — одна реплика', () {
      final turns = buildAiHistory([
        msg(nina, 'Ты так и не позвонил'),
        msg(nina, 'Я волнуюсь'),
        msg(maxim, 'Прости'),
        msg(maxim, 'Замотался'),
      ], ownerId: maxim);
      expect(turns, hasLength(2));
      expect(turns.first.text, 'Ты так и не позвонил\nЯ волнуюсь');
      expect(turns.first.fromOwner, isFalse);
      expect(turns.last.text, 'Прости\nЗамотался');
    });

    test('остаются последние реплики: по числу и по объёму, последняя — всегда', () {
      final many = [
        for (var i = 0; i < 40; i++) msg(i.isEven ? nina : maxim, 'реплика $i'),
      ];
      final turns = buildAiHistory(many, ownerId: maxim);
      expect(turns, hasLength(12));
      expect(turns.last.text, 'реплика 39');
      expect(turns.first.text, 'реплика 28');

      final long = [
        msg(nina, 'а' * 1000),
        msg(maxim, 'б' * 1000),
        msg(nina, 'в' * 1000),
        msg(maxim, 'г' * 100),
      ];
      final fit = buildAiHistory(long, ownerId: maxim, maxChars: 1500);
      expect(fit.map((t) => t.text.length), [1000, 100], reason: 'старые реплики отброшены');

      final huge = buildAiHistory([msg(maxim, 'д' * 5000)], ownerId: maxim, maxChars: 1500);
      expect(huge.single.text.length, 1500);
    });

    test('задел для групп: у реплики есть имя автора', () {
      final names = {nina: 'Мама', veronika: 'Красотка'};
      final turns = buildAiHistory([
        msg(nina, 'Кто дома?'),
        msg(veronika, 'Я'),
        msg(maxim, 'Буду через час'),
      ], ownerId: maxim, speakerName: (id) => names[id]);
      expect(turns.map((t) => t.speaker), ['Мама', 'Красотка', null]);
      expect(turns.map((t) => t.fromOwner), [false, false, true]);
    });
  });

  group('Запрос к модели', () {
    const persona = AiPersona(
      name: 'Мама',
      realName: 'Нина Ветрова',
      description: 'Мама героя. Говорит заботливо, коротко.',
      ownerName: 'Максим',
    );

    test('системная инструкция содержит персонажа, владельца и описание', () {
      final system = buildAiSystemPrompt(persona);
      expect(system, contains('Нина Ветрова'));
      expect(system, contains('«Мама»'));
      expect(system, contains('Максим'));
      expect(system, contains('Мама героя. Говорит заботливо, коротко.'));
      expect(system, contains('по-русски'));
    });

    test('без описания и без имени владельца инструкция остаётся осмысленной', () {
      final system = buildAiSystemPrompt(const AiPersona(name: 'Алексей'));
      expect(system, startsWith('Ты — Алексей.'));
      expect(system, isNot(contains('О тебе:')));
      expect(system, isNot(contains('null')));
      expect(buildAiSystemPrompt(const AiPersona(name: '  ')), startsWith('Ты — собеседник.'));
    });

    test('в запрос попадают инструкция, вся переданная история и параметры Qwen3', () {
      final history = buildAiHistory([
        msg(nina, 'Ты шапку купил?'),
        msg(maxim, 'Купил'),
        msg(nina, 'Какую?'),
        msg(maxim, 'Серую'),
      ], ownerId: maxim);
      final prompt = buildAiPrompt(persona: persona, history: history);
      expect(prompt.system, buildAiSystemPrompt(persona));
      expect(prompt.turns, hasLength(4));

      final text = prompt.describe();
      expect(text, contains('[system]'));
      expect(text, contains('Нина Ветрова'));
      // Порядок реплик и роли: прошлый ответ персонажа — assistant.
      final order = ['Ты шапку купил?', 'Купил', 'Какую?', 'Серую'].map(text.indexOf).toList();
      expect(order.every((i) => i >= 0), isTrue);
      expect(order, orderedEquals([...order]..sort()));
      expect(text, contains('[assistant]\nКакую?'));
      expect(text, contains('[user]\nСерую'));
      expect(
        text,
        contains('temperature=0.7 top_p=0.8 top_k=20 min_p=0.0 repeat_penalty=1.0 max_tokens=96 thinking=off'),
      );
    });

    test('параметры выборки: не жадный режим, значения Qwen3 без размышлений', () {
      const s = AiSampling.chat;
      expect(s.temperature, 0.7);
      expect(s.topP, 0.8);
      expect(s.topK, 20);
      expect(s.minP, 0.0);
      expect(s.repeatPenalty, 1.0);
      expect(s.temperature, greaterThan(0), reason: 'жадная выборка не используется');
    });
  });

  group('Очистка ответа', () {
    test('размышления, служебные метки, имя и кавычки убираются', () {
      expect(cleanAiReply('<think>надо ответить тепло</think>Хорошо, сынок', 'Мама'), 'Хорошо, сынок');
      expect(cleanAiReply('<think>\n\n</think>\n\nХорошо', 'Мама'), 'Хорошо');
      expect(cleanAiReply('рассуждаю...</think>\nХорошо', 'Мама'), 'Хорошо');
      expect(cleanAiReply('Мама: Хорошо', 'Мама'), 'Хорошо');
      expect(cleanAiReply('«Хорошо»', 'Мама'), 'Хорошо');
      expect(cleanAiReply('Хорошо<|im_end|>\n<|im_start|>user\nА когда?', 'Мама'), 'Хорошо');
      expect(cleanAiReply('  Хорошо, жду  ', 'Мама'), 'Хорошо, жду');
    });

    test('ответ, оборвавшийся внутри размышлений, не уходит в чат', () {
      expect(cleanAiReply('<think>Okay, the user says he bought a hat, so I', 'Мама'), isEmpty);
    });
  });

  group('Маршрутизация', () {
    test('личный чат: отвечает собеседник; группа: пока никто', () {
      final personal = Chat(id: 'c1', deviceId: device, peerCharacterId: nina, createdAt: _t, updatedAt: _t);
      final group = Chat(id: 'g1', deviceId: device, isGroup: true, title: 'Семья', createdAt: _t, updatedAt: _t);
      expect(aiCanReplyIn(personal), isTrue);
      expect(aiResponderFor(personal), nina);
      expect(aiCanReplyIn(group), isFalse);
      expect(aiResponderFor(group), isNull);
    });
  });

  group('На настоящей базе', () {
    late Directory tempDir;
    late AppServices s;
    late _FakeEngine engine;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppServices.testCallSounds = _Silent.new;
      AppServices.testSecretStore = MemorySecretStore.new;
    });

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('replika_ai_');
      s = await AppServices.open(databasePath: p.join(tempDir.path, 'replika.db'));
      engine = _FakeEngine();
      AutoReplyController.engine = engine;
      await s.autoReply.setEnabled(true);
      expect(s.autoReply.enabled.value, isTrue);
      expect(s.autoReply.available, isTrue);
    });

    tearDown(() async {
      AutoReplyController.engine = null;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await s.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('личный чат: модель получает персонажа и переписку, ответ уходит от собеседника', () async {
      expect(s.currentDeviceId.value, device);
      s.openChatId.value = mamaChat;
      await s.messages.sendText(chatId: mamaChat, senderId: maxim, text: 'Мам, я купил шапку');
      await s.autoReply.onOwnerMessage(mamaChat);

      final first = engine.prompts.single;
      expect(first.persona.name, 'Мама');
      expect(first.persona.realName, 'Нина Ветрова');
      expect(first.persona.ownerName, 'Максим');
      expect(first.persona.description, 'Мама героя.');
      expect(first.system, contains('Нина Ветрова'));
      expect(first.system, contains('Максим'));
      expect(first.system, contains('Мама героя.'));
      // История из базы: прошлые сообщения мамы и владельца, последним — новое.
      expect(first.turns.first.text, contains('шапку купил'));
      expect(first.turns.first.fromOwner, isFalse);
      expect(first.turns.any((t) => t.fromOwner && t.text.contains('Вечером наберу')), isTrue);
      expect(first.turns.last.fromOwner, isTrue);
      expect(first.turns.last.text, 'Мам, я купил шапку');
      expect(first.turns[first.turns.length - 2].text, 'Ты так и не позвонил\nЯ волнуюсь');

      final saved = await s.messages.forChat(mamaChat);
      expect(saved.any((m) => m.text == 'Хорошо, жду' && m.senderId == nina), isTrue);

      // Второй ход: прошлый ответ модели есть в запросе — это один разговор.
      engine.answer = '<think>подумаю</think>Молодец';
      await s.messages.sendText(chatId: mamaChat, senderId: maxim, text: 'Тёплая, серая');
      await s.autoReply.onOwnerMessage(mamaChat);
      final second = engine.prompts.last;
      expect(engine.prompts, hasLength(2));
      expect(second.turns.last.text, 'Тёплая, серая');
      expect(second.turns[second.turns.length - 2].text, 'Хорошо, жду');
      expect(second.turns[second.turns.length - 2].fromOwner, isFalse);
      expect(second.turns[second.turns.length - 3].text, 'Мам, я купил шапку');

      final after = await s.messages.forChat(mamaChat);
      expect(after.any((m) => m.text == 'Молодец' && m.senderId == nina), isTrue,
          reason: 'в чат уходит очищенный ответ');
      expect(after.any((m) => m.text.contains('think')), isFalse);

      // Экран проверки показывает запрос и ответ модели как есть.
      final exchange = s.autoReply.lastExchange!;
      expect(exchange.reply, '<think>подумаю</think>Молодец');
      final page = AiExchangeScreen.textOf(exchange);
      expect(page, contains('Тёплая, серая'));
      expect(page, contains('[ответ модели как есть]\n<think>подумаю</think>Молодец'));
      expect(page, contains('[в чат ушло]\nМолодец'));
    });

    test('пустой ответ модели в чат не уходит', () async {
      s.openChatId.value = mamaChat;
      engine.answer = '<think>так и не ответила';
      final before = (await s.messages.forChat(mamaChat)).length;
      await s.messages.sendText(chatId: mamaChat, senderId: maxim, text: 'Привет');
      await s.autoReply.onOwnerMessage(mamaChat);
      expect(engine.prompts, hasLength(1));
      expect((await s.messages.forChat(mamaChat)).length, before + 1);
    });

    test('группа: модель не вызывается, сообщение владельца остаётся единственным', () async {
      final id = await s.chats.createGroup(deviceId: device, title: 'Семья', memberIds: [nina, veronika]);
      s.openChatId.value = id;
      final header = (await s.chats.header(id))!;
      expect(header.chat.isGroup, isTrue);
      expect(aiCanReplyIn(header.chat), isFalse);

      await s.messages.sendText(chatId: id, senderId: maxim, text: 'Всем привет');
      await s.autoReply.onOwnerMessage(id);
      expect(engine.prompts, isEmpty);
      expect(s.autoReply.lastError, isNull, reason: 'это решение маршрутизации, а не сбой');

      // Тот же движок в личном чате отвечает: запрет именно на группу.
      s.openChatId.value = mamaChat;
      await s.messages.sendText(chatId: mamaChat, senderId: maxim, text: 'Мам, привет');
      await s.autoReply.onOwnerMessage(mamaChat);
      expect(engine.prompts, hasLength(1));
      final texts = (await s.messages.forChat(id)).where((m) => m.type == MessageType.text);
      expect(texts.map((m) => m.text), ['Всем привет']);
    });

    test('выключенный переключатель: модель не вызывается', () async {
      await s.autoReply.setEnabled(false);
      await s.messages.sendText(chatId: mamaChat, senderId: maxim, text: 'Привет');
      await s.autoReply.onOwnerMessage(mamaChat);
      expect(engine.prompts, isEmpty);
    });
  });
}
