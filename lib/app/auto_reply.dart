import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/models/message.dart';
import 'improv.dart';
import 'improv_sender.dart';
import 'services.dart';

/// Одна реплика переписки для ИИ.
@immutable
class AiTurn {
  const AiTurn({required this.fromOwner, required this.text});

  /// true — написал владелец телефона, false — собеседник (его играет ИИ).
  final bool fromOwner;
  final String text;
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

  /// Реплика собеседника. null — ответить нечем.
  Future<String?> reply({
    required String personaName,
    required String persona,
    required List<AiTurn> history,
  });

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
    enabled.value = value;
    await _services.settings.setValue(settingKey, value ? '1' : '0');
    if (!value) cancel();
  }

  void cancel() {
    _token++;
    engine?.cancel();
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
      if (header == null || header.chat.isGroup) return;
      // Идёт дубль сцены — собеседник говорит по сценарию, ИИ молчит.
      if (_services.engine.sceneIdForChat(chatId) != null) return;

      _services.typing.start(chatId, duration: const Duration(seconds: 90));
      if (!ai.ready) await ai.prepare();
      if (token != _token) return;

      final all = await _services.messages.forChat(chatId);
      final history = <AiTurn>[
        for (final m in all)
          if (m.type == MessageType.text && !m.deleted && m.text.trim().isNotEmpty)
            AiTurn(fromOwner: m.senderId == header.ownerCharacterId, text: m.text.trim()),
      ];
      final recent = history.length > 12 ? history.sublist(history.length - 12) : history;

      final peerId = header.chat.peerCharacterId;
      final contact = peerId == null
          ? null
          : await _services.contacts.view(_services.currentDeviceId.value, peerId);
      final reply = await ai.reply(
        personaName: header.peer.displayName,
        persona: contact?.character.description ?? '',
        history: recent,
      );
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
    } catch (error) {
      _error = error.toString();
      debugPrint('Автоответ ИИ не удался: $error');
      notifyListeners();
    } finally {
      if (token == _token) _services.typing.stop(chatId);
    }
  }
}
