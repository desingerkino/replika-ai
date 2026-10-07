import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/models/chat.dart';
import '../data/models/message.dart';
import 'improv.dart';
import 'improv_sender.dart';
import 'services.dart';

/// Одна реплика переписки для ИИ.
@immutable
class AiTurn {
  const AiTurn({required this.fromOwner, required this.text, this.speaker});

  /// true — написал владелец телефона, false — собеседник (его играет ИИ).
  final bool fromOwner;
  final String text;

  /// Имя автора. В личном чате не нужно (участников двое); задел для групп,
  /// где собеседников несколько.
  final String? speaker;
}

/// Кого играет ИИ. Привязано к персонажу, а не к экрану чата: те же данные
/// подойдут и участнику группы.
@immutable
class AiPersona {
  const AiPersona({
    required this.name,
    this.realName = '',
    this.description = '',
    this.ownerName = '',
  });

  /// Как персонаж записан в телефоне («Мама») — так его видит владелец.
  final String name;

  /// Настоящее имя из карточки, если отличается от записи в контактах.
  final String realName;

  /// Поле «описание» карточки: характер, манера речи, отношения — всё, что
  /// известно о персонаже. Отдельных полей под стиль и отношения в проекте нет.
  final String description;

  /// Имя владельца телефона — с кем персонаж переписывается.
  final String ownerName;
}

/// Параметры выборки. Значения — рекомендованные для Qwen3 без режима
/// размышлений; движок сам переводит их в параметры своей библиотеки.
@immutable
class AiSampling {
  const AiSampling({
    this.temperature = 0.7,
    this.topP = 0.8,
    this.topK = 20,
    this.minP = 0.0,
    this.repeatPenalty = 1.0,
    this.maxTokens = 96,
  });

  final double temperature;
  final double topP;
  final int topK;
  final double minP;

  /// 1.0 — штрафа нет. Штраф за повторы портит русские окончания слов.
  final double repeatPenalty;
  final int maxTokens;

  static const AiSampling chat = AiSampling();
}

/// Всё, что модель получает перед ответом. Шаблон чата (ChatML у Qwen)
/// накладывает сам движок из файла модели; здесь только содержание.
@immutable
class AiPrompt {
  const AiPrompt({
    required this.persona,
    required this.system,
    required this.turns,
    this.sampling = AiSampling.chat,
  });

  final AiPersona persona;
  final String system;
  final List<AiTurn> turns;
  final AiSampling sampling;

  /// Тот же запрос текстом — для экрана проверки и для тестов.
  String describe() {
    final out = StringBuffer()
      ..writeln('[system]')
      ..writeln(system)
      ..writeln();
    for (final t in turns) {
      final who = t.fromOwner ? 'user' : 'assistant';
      final name = t.speaker == null ? '' : ' (${t.speaker})';
      out
        ..writeln('[$who$name]')
        ..writeln(t.text)
        ..writeln();
    }
    out.write('[параметры] temperature=${sampling.temperature} top_p=${sampling.topP} '
        'top_k=${sampling.topK} min_p=${sampling.minP} repeat_penalty=${sampling.repeatPenalty} '
        'max_tokens=${sampling.maxTokens} thinking=off');
    return out.toString();
  }
}

/// Последний обмен с моделью — чтобы на устройстве было видно, что именно
/// она получила и что ответила (до и после очистки).
@immutable
class AiExchange {
  const AiExchange({required this.prompt, this.reply, this.error});

  final AiPrompt prompt;
  final String? reply;
  final String? error;
}

/// Может ли ИИ сейчас отвечать в этом чате.
///
/// Группы пока исключены: в группе ИИ должен отвечать от имени конкретного
/// участника, а отправка ответа и выбор «кто из участников — ИИ» рассчитаны
/// только на одного собеседника. Это единственное место, где стоит запрет.
bool aiCanReplyIn(Chat chat) => !chat.isGroup;

/// От чьего имени отвечает ИИ. В личном чате — собеседник; в группе пока
/// никто (нужен выбор участников).
String? aiResponderFor(Chat chat) => chat.isGroup ? null : chat.peerCharacterId;

/// Переписка для модели из сообщений чата.
///
/// Берутся только текстовые неудалённые сообщения. Сообщения одного автора
/// подряд склеиваются в одну реплику (шаблон чата ждёт чередования ролей).
/// Остаются последние [maxTurns] реплик, но не больше [maxChars] символов,
/// чтобы запрос помещался в окно контекста; последняя реплика остаётся всегда.
List<AiTurn> buildAiHistory(
  List<Message> messages, {
  required String ownerId,
  int maxTurns = 12,
  int maxChars = 2400,
  String? Function(String? senderId)? speakerName,
}) {
  final turns = <AiTurn>[];
  String? lastSender;
  for (final m in messages) {
    if (m.type != MessageType.text || m.deleted) continue;
    final text = m.text.trim();
    if (text.isEmpty) continue;
    if (turns.isNotEmpty && lastSender == m.senderId) {
      final prev = turns.removeLast();
      turns.add(AiTurn(fromOwner: prev.fromOwner, text: '${prev.text}\n$text', speaker: prev.speaker));
    } else {
      turns.add(AiTurn(
        fromOwner: m.senderId == ownerId,
        text: text,
        speaker: speakerName?.call(m.senderId),
      ));
    }
    lastSender = m.senderId;
  }
  var recent = turns.length > maxTurns ? turns.sublist(turns.length - maxTurns) : turns;
  var total = recent.fold<int>(0, (sum, t) => sum + t.text.length);
  while (recent.length > 1 && total > maxChars) {
    total -= recent.first.text.length;
    recent = recent.sublist(1);
  }
  if (recent.length == 1 && recent.first.text.length > maxChars) {
    final only = recent.first;
    recent = [
      AiTurn(
        fromOwner: only.fromOwner,
        text: only.text.substring(only.text.length - maxChars),
        speaker: only.speaker,
      ),
    ];
  }
  return recent;
}

/// Системная инструкция: кто персонаж, с кем говорит и как отвечать.
String buildAiSystemPrompt(AiPersona persona) {
  final name = persona.name.trim().isEmpty ? 'собеседник' : persona.name.trim();
  final real = persona.realName.trim();
  final owner = persona.ownerName.trim();
  final about = persona.description.trim();
  final lines = <String>[
    real.isNotEmpty && real.toLowerCase() != name.toLowerCase()
        ? 'Ты — $real. В телефоне собеседника ты записан(а) как «$name».'
        : 'Ты — $name.',
    owner.isEmpty
        ? 'Ты переписываешься в мессенджере с человеком, который записал тебя в контактах как «$name».'
        : 'Ты переписываешься в мессенджере с человеком по имени $owner; '
            'в его телефоне ты записан(а) как «$name».',
    if (about.isNotEmpty) 'О тебе: $about',
    'Выше в переписке — ваши прошлые сообщения: учитывай их и не противоречь тому, что уже сказано.',
    'Отвечай по-русски, от первого лица, как живой человек в личной переписке: '
        'одна короткая реплика (обычно 1–2 предложения), по смыслу последнего сообщения.',
    'Не повторяй слова собеседника и свои прошлые ответы. Без кавычек, без имени в начале, '
        'без пояснений и ремарок. Не говори, что ты ИИ, модель или ассистент.',
  ];
  return lines.join('\n');
}

/// Полный запрос к модели.
AiPrompt buildAiPrompt({
  required AiPersona persona,
  required List<AiTurn> history,
  AiSampling sampling = AiSampling.chat,
}) =>
    AiPrompt(
      persona: persona,
      system: buildAiSystemPrompt(persona),
      turns: List<AiTurn>.unmodifiable(history),
      sampling: sampling,
    );

/// Убирает из ответа то, что не должно попасть в чат: размышления модели
/// (в том числе незакрытые — когда ответ оборвался внутри них), служебные
/// метки, кавычки и «Имя:» в начале.
String cleanAiReply(String raw, String name) {
  var t = raw;
  t = t.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
  // «</think>» без начала: размышления шли с самого начала ответа.
  final close = t.lastIndexOf('</think>');
  if (close >= 0) t = t.substring(close + '</think>'.length);
  // «<think>» без конца: ответ оборвался внутри размышлений — это не реплика.
  final open = t.indexOf('<think>');
  if (open >= 0) t = t.substring(0, open);
  // Модель начала писать следующую реплику за собеседника.
  for (final marker in const ['<|im_end|>', '<|im_start|>', '<|endoftext|>']) {
    final at = t.indexOf(marker);
    if (at >= 0) t = t.substring(0, at);
  }
  t = t.trim();
  final who = name.trim();
  if (who.isNotEmpty) {
    final prefix = RegExp('^${RegExp.escape(who)}\\s*[:：]\\s*', caseSensitive: false);
    t = t.replaceFirst(prefix, '');
  }
  if (t.length >= 2 && '"«“'.contains(t[0]) && '"»”'.contains(t[t.length - 1])) {
    t = t.substring(1, t.length - 1);
  }
  return t.trim();
}

/// Движок автоответов. Приложение знает только этот интерфейс;
/// конкретная модель (Qwen и т.д.) подключается в сборке «Реплика AI».
abstract class AutoReplyEngine {
  /// Модель загружена и может отвечать.
  bool get ready;

  /// Короткое описание состояния для экрана настроек.
  String get statusText;

  /// Готовит движок к ответу (например, загружает модель с диска).
  /// Бросает исключение, если подготовить нельзя.
  Future<void> prepare();

  /// Реплика персонажа на [prompt]. Возвращает текст модели как есть —
  /// очистку делает приложение. null — ответить нечем.
  Future<String?> reply(AiPrompt prompt);

  void cancel();

  /// Страница настройки модели (выбор файла, замеры); null — нет.
  Widget? buildSetupPage();
}

/// Автоответы ИИ в обычных личных чатах.
///
/// Отвечает, только если: сборка с ИИ, переключатель включён, чат личный
/// (не группа), в чате не идёт дубль сцены. Ответ уходит тем же путём,
/// что и ответы импровизации («печатает…», непрочитанное, уведомление),
/// поэтому «Убрать импровизацию» стирает и его. Сценами и таймлайнами ИИ
/// не управляет и в их работу не вмешивается.
class AutoReplyController extends ChangeNotifier {
  AutoReplyController(this._services) {
    _loaded = _load();
  }

  /// Подключается только в сборке «Реплика AI» (lib/main_ai.dart).
  static AutoReplyEngine? engine;

  static const String settingKey = 'ai_autoreply';

  final AppServices _services;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  late final Future<void> _loaded;
  int _token = 0;
  String? _error;

  /// Последняя ошибка автоответа (для экрана настроек).
  String? get lastError => _error;

  AiExchange? _lastExchange;

  /// Последний запрос к модели и её ответ (для проверки на устройстве).
  AiExchange? get lastExchange => _lastExchange;

  /// Есть ли в этой сборке ИИ.
  bool get available => engine != null;

  Future<void> _load() async {
    try {
      enabled.value = await _services.settings.getValue(settingKey) == '1';
    } catch (error) {
      debugPrint('Настройка ИИ не прочитана: $error');
    }
  }

  Future<void> setEnabled(bool value) async {
    // Сначала дочитываем сохранённое значение: иначе запоздавшее чтение
    // перезапишет только что сделанный выбор.
    await _loaded;
    enabled.value = value;
    await _services.settings.setValue(settingKey, value ? '1' : '0');
    if (!value) cancel();
  }

  void cancel() {
    _token++;
    engine?.cancel();
  }

  /// Собирает запрос к модели для чата: персонаж, владелец, переписка.
  Future<AiPrompt> promptFor(ChatHeader header) async {
    final chatId = header.chat.id;
    final device = _services.currentDeviceId.value;
    final all = await _services.messages.forChat(chatId);
    final history = buildAiHistory(all, ownerId: header.ownerCharacterId);

    final responderId = aiResponderFor(header.chat);
    final contact = responderId == null ? null : await _services.contacts.view(device, responderId);
    final owner = await _services.contacts.view(device, header.ownerCharacterId);
    final ownerName = owner == null
        ? ''
        : (owner.character.firstName.trim().isNotEmpty
            ? owner.character.firstName.trim()
            : owner.character.fullName);
    return buildAiPrompt(
      persona: AiPersona(
        name: header.peer.displayName,
        realName: contact?.character.fullName ?? '',
        description: contact?.character.description ?? '',
        ownerName: ownerName,
      ),
      history: history,
    );
  }

  /// Вызывается после того, как владелец телефона отправил текст в чат.
  Future<void> onOwnerMessage(String chatId) async {
    final ai = engine;
    if (ai == null) return;
    await _loaded;
    if (!enabled.value) return;

    final token = ++_token;
    ai.cancel(); // новое сообщение отменяет ответ на предыдущее
    // Пауза: если человек шлёт несколько сообщений подряд, отвечаем на последнее.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (token != _token) return;

    try {
      final header = await _services.chats.header(chatId);
      if (header == null || !aiCanReplyIn(header.chat)) return;
      // Идёт дубль сцены — собеседник говорит по сценарию, ИИ молчит.
      if (_services.engine.sceneIdForChat(chatId) != null) return;

      _services.typing.start(chatId, duration: const Duration(seconds: 90));
      if (!ai.ready) await ai.prepare();
      if (token != _token) return;

      final prompt = await promptFor(header);
      String? raw;
      try {
        raw = await ai.reply(prompt);
      } catch (error) {
        _lastExchange = AiExchange(prompt: prompt, error: error.toString());
        rethrow;
      }
      final reply = raw == null ? null : cleanAiReply(raw, prompt.persona.name);
      _lastExchange = AiExchange(prompt: prompt, reply: raw);
      if (token != _token) return;
      _services.typing.stop(chatId);
      if (reply == null || reply.trim().isEmpty) return;

      // Пока ИИ думал, мог начаться дубль: тогда не вмешиваемся.
      if (_services.engine.sceneIdForChat(chatId) != null) return;

      await ServicesImprovSender(_services).send(
        chatId,
        QueuedReply(text: reply.trim(), typingMs: 0),
      );
      _error = null;
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      debugPrint('Автоответ ИИ не удался: $error');
      notifyListeners();
    } finally {
      if (token == _token) _services.typing.stop(chatId);
    }
  }
}
