/// Слой локальной нейросети («Реплика AI»).
///
/// Отвечает только за: загрузку модели, выгрузку, генерацию текста,
/// состояние и ошибки. Ничего не знает о Chat / Message / Event / сценах.
/// Конкретная модель и движок скрыты за этим интерфейсом: чтобы заменить
/// Qwen на другую локальную модель, достаточно другого файла .gguf или
/// другой реализации [LocalLlmProvider] — остальное приложение не меняется.
library;

import 'dart:async';

enum LocalLlmStatus { unloaded, loading, ready, generating, error }

/// Любая ошибка слоя ИИ. [message] — по-русски, для показа человеку.
class LocalLlmException implements Exception {
  const LocalLlmException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message ($cause)';
}

/// Замеры одной генерации. Всё, что движок не сообщил, остаётся null.
class LocalLlmMetrics {
  const LocalLlmMetrics({
    this.timeToFirstToken,
    this.totalTime,
    this.promptTokens,
    this.completionTokens,
    this.residentMemoryBytes,
  });

  final Duration? timeToFirstToken;
  final Duration? totalTime;
  final int? promptTokens;
  final int? completionTokens;

  /// Память процесса (RSS) сразу после генерации.
  final int? residentMemoryBytes;

  /// Скорость набора токенов после первого токена.
  double? get tokensPerSecond {
    final total = totalTime;
    final first = timeToFirstToken;
    final tokens = completionTokens;
    if (total == null || first == null || tokens == null || tokens < 2) {
      return null;
    }
    final seconds = (total - first).inMicroseconds / 1e6;
    if (seconds <= 0) return null;
    return (tokens - 1) / seconds;
  }
}

class LocalLlmResult {
  const LocalLlmResult(this.text, this.metrics);
  final String text;
  final LocalLlmMetrics metrics;
}

/// Сведения о загруженной модели (для экрана замеров).
class LocalLlmModelInfo {
  const LocalLlmModelInfo({
    required this.path,
    required this.fileBytes,
    required this.loadTime,
    required this.backend,
    required this.residentMemoryBytes,
  });

  final String path;
  final int fileBytes;
  final Duration loadTime;

  /// Название вычислительного бэкенда, как его сообщил движок (Metal / CPU …).
  final String backend;
  final int residentMemoryBytes;
}

/// Реплика для модели: либо человек ([fromUser] = true), либо сама модель.
class LocalLlmMessage {
  const LocalLlmMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

abstract class LocalLlmProvider {
  LocalLlmStatus get status;
  Stream<LocalLlmStatus> get statusChanges;

  /// Сведения о загруженной модели; null, пока модель не загружена.
  LocalLlmModelInfo? get modelInfo;

  /// Загружает GGUF-файл с диска. Только локальный путь, интернет не нужен.
  Future<void> load(String modelPath);

  /// Выгружает модель и освобождает память.
  Future<void> unload();

  /// Генерирует короткий ответ. [onToken] получает текст по мере появления.
  Future<LocalLlmResult> generate(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 64,
    double temperature = 0.7,
    void Function(String piece)? onToken,
  });

  /// Ответ с учётом переписки: [history] по порядку, последняя — от человека.
  ///
  /// Параметры выборки по умолчанию — рекомендованные для Qwen3 без
  /// размышлений. [repeatPenalty] 1.0 — штрафа за повторы нет.
  Future<LocalLlmResult> chat(
    List<LocalLlmMessage> history, {
    String? systemPrompt,
    int maxTokens = 64,
    double temperature = 0.7,
    double topP = 0.8,
    int topK = 20,
    double minP = 0.0,
    double repeatPenalty = 1.0,
    void Function(String piece)? onToken,
  });

  /// Прерывает идущую генерацию.
  void cancel();

  Future<void> dispose();
}
