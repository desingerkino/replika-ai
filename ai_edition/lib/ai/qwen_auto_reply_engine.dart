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
    // Если моделей несколько, берём ту, что добавлена последней.
    File? newest;
    DateTime? newestTime;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
        final time = (await entity.stat()).modified;
        if (newestTime == null || time.isAfter(newestTime)) {
          newest = entity;
          newestTime = time;
        }
      }
    }
    return newest?.path;
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

  /// Запрос собирает приложение (lib/app/auto_reply.dart): системная
  /// инструкция с персонажем и переписка. Здесь он только передаётся модели;
  /// шаблон чата Qwen3 (ChatML) накладывает движок из самого файла .gguf.
  @override
  Future<String?> reply(AiPrompt prompt) async {
    final sampling = prompt.sampling;
    final result = await provider.chat(
      [
        for (final t in prompt.turns) LocalLlmMessage(fromUser: t.fromOwner, text: t.text),
      ],
      systemPrompt: prompt.system,
      maxTokens: sampling.maxTokens,
      temperature: sampling.temperature,
      topP: sampling.topP,
      topK: sampling.topK,
      minP: sampling.minP,
      repeatPenalty: sampling.repeatPenalty,
    );
    final text = result.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  void cancel() => provider.cancel();

  @override
  Widget? buildSetupPage() => LocalAiTestScreen(provider: provider);
}
