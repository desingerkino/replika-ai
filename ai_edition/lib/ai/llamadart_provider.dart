/// Реализация [LocalLlmProvider] на llama.cpp через пакет llamadart.
/// Единственное место проекта, которое знает про llamadart.
library;

import 'dart:async';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

import 'local_llm_provider.dart';

class LlamadartLocalLlmProvider implements LocalLlmProvider {
  LlamadartLocalLlmProvider({this.contextSize = 2048});

  /// Окно контекста. Для коротких реплик хватает 2048; меньше окно —
  /// меньше памяти под KV-кэш.
  final int contextSize;

  LlamaEngine? _engine;
  LocalLlmStatus _status = LocalLlmStatus.unloaded;
  LocalLlmModelInfo? _info;
  final _changes = StreamController<LocalLlmStatus>.broadcast();

  @override
  LocalLlmStatus get status => _status;

  @override
  Stream<LocalLlmStatus> get statusChanges => _changes.stream;

  @override
  LocalLlmModelInfo? get modelInfo => _info;

  void _set(LocalLlmStatus value) {
    _status = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  @override
  Future<void> load(String modelPath) async {
    if (_status == LocalLlmStatus.loading || _status == LocalLlmStatus.generating) {
      throw const LocalLlmException('Модель занята, подождите.');
    }
    await unload();

    final file = File(modelPath);
    if (!await file.exists()) {
      _set(LocalLlmStatus.error);
      throw LocalLlmException('Файл модели не найден: $modelPath');
    }
    final bytes = await file.length();

    _set(LocalLlmStatus.loading);
    final watch = Stopwatch()..start();
    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.loadModel(
        modelPath,
        modelParams: ModelParams(
          contextSize: contextSize,
          // Все слои на GPU: на iPhone это Metal. Если бэкенд недоступен,
          // движок сам вернётся на CPU — какой выбран, видно в modelInfo.backend.
          gpuLayers: ModelParams.maxGpuLayers,
        ),
      );
      watch.stop();
      final backend = '${await engine.getBackendName()}';
      _engine = engine;
      _info = LocalLlmModelInfo(
        path: modelPath,
        fileBytes: bytes,
        loadTime: watch.elapsed,
        backend: backend,
        residentMemoryBytes: ProcessInfo.currentRss,
      );
      _set(LocalLlmStatus.ready);
    } catch (e) {
      try {
        await engine.dispose();
      } catch (_) {}
      _engine = null;
      _info = null;
      _set(LocalLlmStatus.error);
      throw LocalLlmException('Не удалось загрузить модель', e);
    }
  }

  @override
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _info = null;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (_) {
        // Выгрузка не должна падать: память освобождается при закрытии процесса.
      }
    }
    _set(LocalLlmStatus.unloaded);
  }

  @override
  Future<LocalLlmResult> generate(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 64,
    double temperature = 0.7,
    void Function(String piece)? onToken,
  }) =>
      chat(
        [LocalLlmMessage(fromUser: true, text: prompt)],
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        onToken: onToken,
      );

  @override
  Future<LocalLlmResult> chat(
    List<LocalLlmMessage> history, {
    String? systemPrompt,
    int maxTokens = 64,
    double temperature = 0.7,
    void Function(String piece)? onToken,
  }) async {
    final engine = _engine;
    if (engine == null || _status != LocalLlmStatus.ready) {
      throw const LocalLlmException('Модель не загружена.');
    }
    _set(LocalLlmStatus.generating);

    final messages = <LlamaChatMessage>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        LlamaChatMessage.fromText(role: LlamaChatRole.system, text: systemPrompt),
      for (final m in history)
        LlamaChatMessage.fromText(
          role: m.fromUser ? LlamaChatRole.user : LlamaChatRole.assistant,
          text: m.text,
        ),
    ];

    final text = StringBuffer();
    final watch = Stopwatch()..start();
    Duration? firstToken;
    Duration? engineFirstToken;
    Duration? engineTotal;
    int? promptTokens;
    int? completionTokens;

    try {
      await for (final chunk in engine.create(
        messages,
        // У Qwen3 по умолчанию есть режим «размышлений»: для короткой
        // реплики он не нужен и только тратит время.
        enableThinking: false,
        params: GenerationParams(maxTokens: maxTokens, temp: temperature),
      )) {
        if (chunk.choices.isNotEmpty) {
          final piece = chunk.choices.first.delta.content;
          if (piece != null && piece.isNotEmpty) {
            firstToken ??= watch.elapsed;
            text.write(piece);
            onToken?.call(piece);
          }
        }
        final usage = chunk.usage;
        if (usage != null) {
          promptTokens = usage.promptTokens;
          completionTokens = usage.completionTokens;
          engineFirstToken = usage.timeToFirstToken;
          engineTotal = usage.duration;
        }
      }
      watch.stop();
    } catch (e) {
      _set(_engine == null ? LocalLlmStatus.unloaded : LocalLlmStatus.ready);
      throw LocalLlmException('Ошибка генерации', e);
    }
    _set(LocalLlmStatus.ready);

    return LocalLlmResult(
      text.toString().trim(),
      LocalLlmMetrics(
        // Предпочитаем время самого движка (без очереди и отрисовки), иначе — свои часы.
        timeToFirstToken: engineFirstToken ?? firstToken,
        totalTime: engineTotal ?? watch.elapsed,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        residentMemoryBytes: ProcessInfo.currentRss,
      ),
    );
  }

  @override
  void cancel() => _engine?.cancelGeneration();

  @override
  Future<void> dispose() async {
    await unload();
    await _changes.close();
  }
}
