/// Автоответы на локальной модели: связывает общий слой автоответов
/// приложения (AutoReplyEngine) с LocalLlmProvider. Чтобы сменить модель,
/// достаточно положить другой .gguf или подставить другой провайдер.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app/auto_reply.dart';
import 'local_ai_test_screen.dart';
import 'local_llm_provider.dart';

class LocalAutoReplyEngine implements AutoReplyEngine {
  LocalAutoReplyEngine(this.provider);

  final LocalLlmProvider provider;

  @override
  bool get ready => provider.status == LocalLlmStatus.ready;

  @override
  String get statusText => switch (provider.status) {
        LocalLlmStatus.unloaded => 'модель не загружена',
        LocalLlmStatus.loading => 'загружается…',
        LocalLlmStatus.ready => 'готова',
        LocalLlmStatus.generating => 'отвечает…',
        LocalLlmStatus.error => 'ошибка',
      };

  /// Модель лежит в папке приложения models/ (туда её кладёт экран
  /// «Модель и проверка»). Берём первый .gguf.
  Future<String?> _findModel() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'models'));
    if (!await dir.exists()) return null;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) return entity.path;
    }
    return null;
  }

  @override
  Future<void> prepare() async {
    if (ready) return;
    final path = await _findModel();
    if (path == null) {
      throw const LocalLlmException(
          'Файл модели не найден. Откройте Настройки → Дополнения → Модель и проверка.');
    }
    await provider.load(path);
  }

  static String systemPrompt(String name, String persona) {
    final who = persona.trim().isEmpty ? '' : ' Твой характер и обстоятельства: ${persona.trim()}.';
    return 'Ты — $name, живой человек, переписываешься в мессенджере с близким знакомым.'
        '$who Отвечай по-русски, как в обычной переписке: одной короткой репликой '
        '(обычно 1–2 предложения), без пояснений, без кавычек, без имени в начале, '
        'без оформления. Не говори, что ты ИИ или модель.';
  }

  /// Убирает то, что модель иногда добавляет: остатки размышлений,
  /// кавычки, «Имя:» в начале.
  static String clean(String raw, String name) {
    var t = raw;
    t = t.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    t = t.replaceAll(RegExp(r'</?think>'), '');
    t = t.trim();
    final prefix = RegExp('^${RegExp.escape(name)}\\s*[:：]\\s*', caseSensitive: false);
    t = t.replaceFirst(prefix, '');
    if (t.length >= 2 && '"«“'.contains(t[0]) && '"»”'.contains(t[t.length - 1])) {
      t = t.substring(1, t.length - 1);
    }
    return t.trim();
  }

  @override
  Future<String?> reply({
    required String personaName,
    required String persona,
    required List<AiTurn> history,
  }) async {
    final name = personaName.trim().isEmpty ? 'собеседник' : personaName.trim();
    final result = await provider.chat(
      [
        for (final t in history) LocalLlmMessage(fromUser: t.fromOwner, text: t.text),
      ],
      systemPrompt: systemPrompt(name, persona),
      maxTokens: 80,
      temperature: 0.8,
    );
    final text = clean(result.text, name);
    return text.isEmpty ? null : text;
  }

  @override
  void cancel() => provider.cancel();

  @override
  Widget? buildSetupPage() => LocalAiTestScreen(provider: provider);
}
