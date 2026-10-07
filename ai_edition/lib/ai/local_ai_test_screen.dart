/// Технический экран «Local AI Test»: проверка, что локальная модель
/// отвечает на iPhone без интернета. К чатам и сценам не подключён.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'llamadart_provider.dart';
import 'local_llm_provider.dart';

class LocalAiTestScreen extends StatefulWidget {
  /// [provider] — общий провайдер приложения: модель загружается один раз
  /// и для этого экрана, и для автоответов. Без него экран работает сам по себе.
  const LocalAiTestScreen({super.key, this.provider});

  final LocalLlmProvider? provider;

  @override
  State<LocalAiTestScreen> createState() => _LocalAiTestScreenState();
}

class _LocalAiTestScreenState extends State<LocalAiTestScreen> {
  // Экран работает только с интерфейсом: движок можно заменить в одной строке.
  late final LocalLlmProvider _llm = widget.provider ?? LlamadartLocalLlmProvider();
  final _prompt = TextEditingController(text: 'Ты дома?');
  final _answer = StringBuffer();

  StreamSubscription<LocalLlmStatus>? _sub;
  String? _modelPath;
  String? _error;
  /// Сколько байт модели скопировано; null — копирования нет.
  int? _copiedBytes;
  LocalLlmMetrics? _metrics;

  static const _systemPrompt =
      'Ты отвечаешь в мессенджере как обычный человек. Пиши по-русски, '
      'одной короткой репликой, без пояснений и без оформления.';

  @override
  void initState() {
    super.initState();
    _sub = _llm.statusChanges.listen((_) => setState(() {}));
    _findSavedModel();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _prompt.dispose();
    // Общий провайдер живёт вместе с приложением и здесь не выгружается.
    if (widget.provider == null) _llm.dispose();
    super.dispose();
  }

  Future<Directory> _modelsDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _findSavedModel() async {
    final dir = await _modelsDir();
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
    if (newest == null || !mounted) return;
    setState(() => _modelPath = newest!.path);
  }

  static String _mb(num bytes) => '${(bytes / 1048576).toStringAsFixed(0)} МБ';

  /// Файл GGUF начинается с четырёх байт «GGUF».
  Future<bool> _looksLikeGguf(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(4);
      return head.length == 4 && String.fromCharCodes(head) == 'GGUF';
    } finally {
      await raf.close();
    }
  }

  /// Сколько всего байт копируется (для строки прогресса); null — неизвестно.
  int? _totalBytes;

  /// Переносит выбранный файл в папку моделей.
  ///
  /// Почему раньше вылетало на 2,5 ГБ: `sink.add` не ждёт записи на диск, а
  /// чтение источника быстрее записи, поэтому данные копились в ОЗУ, пока iOS
  /// не завершал приложение. Теперь:
  ///  * файл из временной папки выбора просто переименовывается (без второй
  ///    копии и без записи 2,5 ГБ ещё раз);
  ///  * иначе копируется кусками с ожиданием каждой записи;
  ///  * копия идёт в «.part» и становится моделью только после проверки;
  ///    оборванное копирование того же файла продолжается с места обрыва.
  Future<void> _pickModel() async {
    setState(() {
      _error = null;
      _copiedBytes = 0;
      _totalBytes = null;
    });
    try {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      if (picked.isEmpty) {
        setState(() => _copiedBytes = null);
        return;
      }
      final file = picked.first;
      if (!file.name.toLowerCase().endsWith('.gguf')) {
        throw const LocalLlmException('Нужен файл с расширением .gguf');
      }
      final dir = await _modelsDir();
      final target = File(p.join(dir.path, file.name));
      final part = File('${target.path}.part');
      final src = file.path;
      final temp = (await getTemporaryDirectory()).path;
      // Размер берём у самого файла на диске (dart:io), не у объекта выбора.
      if (src != null) {
        final length = await File(src).length();
        _totalBytes = length > 0 ? length : null;
      }

      var moved = false;
      if (src != null && p.isWithin(temp, src)) {
        try {
          if (await target.exists()) await target.delete();
          if (await part.exists()) await part.delete();
          await File(src).rename(target.path);
          moved = true;
        } on FileSystemException {
          // Другой раздел — копируем.
        }
      }
      if (!moved) {
        await _copyWithResume(file, part);
        if (await target.exists()) await target.delete();
        await part.rename(target.path);
        if (src != null && p.isWithin(temp, src)) {
          try {
            await File(src).delete();
          } catch (_) {}
        }
      }

      if (!await _looksLikeGguf(target)) {
        await target.delete();
        throw const LocalLlmException('Это не GGUF-файл (нет заголовка GGUF).');
      }
      if (!mounted) return;
      setState(() {
        _modelPath = target.path;
        _copiedBytes = null;
        _totalBytes = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _copiedBytes = null;
        _totalBytes = null;
      });
    }
  }

  /// Копирует кусками; каждая запись ожидается, поэтому память не растёт.
  /// Если «.part» от прерванного копирования этого же файла короче источника,
  /// копирование продолжается с его конца.
  Future<void> _copyWithResume(PlatformFile file, File part) async {
    final src = file.path;
    var offset = 0;
    if (src != null && await part.exists()) {
      final have = await part.length();
      final total = await File(src).length();
      if (have > 0 && have < total) offset = have;
    }
    if (offset == 0 && await part.exists()) await part.delete();
    final Stream<List<int>> source =
        src != null ? File(src).openRead(offset) : file.readAsByteStream();
    final raf = await part.open(mode: offset > 0 ? FileMode.append : FileMode.write);
    var done = offset;
    var lastUi = DateTime.now();
    try {
      await for (final chunk in source) {
        await raf.writeFrom(chunk);
        done += chunk.length;
        final now = DateTime.now();
        if (mounted && now.difference(lastUi) > const Duration(milliseconds: 250)) {
          lastUi = now;
          setState(() => _copiedBytes = done);
        }
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
    if (mounted) setState(() => _copiedBytes = done);
  }

  Future<void> _load() async {
    final path = _modelPath;
    if (path == null) return;
    setState(() => _error = null);
    try {
      await _llm.load(path);
    } on LocalLlmException catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _unload() async {
    await _llm.unload();
    setState(() => _metrics = null);
  }

  Future<void> _generate() async {
    setState(() {
      _error = null;
      _answer.clear();
      _metrics = null;
    });
    try {
      final result = await _llm.generate(
        _prompt.text,
        systemPrompt: _systemPrompt,
        maxTokens: 48,
        temperature: 0.7,
        onToken: (piece) => setState(() => _answer.write(piece)),
      );
      setState(() {
        _answer
          ..clear()
          ..write(result.text);
        _metrics = result.metrics;
      });
    } on LocalLlmException catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _metricsText() {
    final info = _llm.modelInfo;
    final m = _metrics;
    final lines = <String>[];
    if (info != null) {
      lines
        ..add('Файл модели: ${_mb(info.fileBytes)}')
        ..add('Загрузка модели: ${(info.loadTime.inMilliseconds / 1000).toStringAsFixed(1)} с')
        ..add('Вычисления: ${info.backend}')
        ..add('ОЗУ после загрузки: ${_mb(info.residentMemoryBytes)}');
    }
    if (m != null) {
      final ttft = m.timeToFirstToken;
      final total = m.totalTime;
      final tps = m.tokensPerSecond;
      lines
        ..add('До первого токена: ${ttft == null ? '—' : '${ttft.inMilliseconds} мс'}')
        ..add('Скорость: ${tps == null ? '—' : '${tps.toStringAsFixed(1)} ток/с'}')
        ..add('Вся генерация: ${total == null ? '—' : '${(total.inMilliseconds / 1000).toStringAsFixed(2)} с'}')
        ..add('Токенов: запрос ${m.promptTokens ?? '—'}, ответ ${m.completionTokens ?? '—'}')
        ..add('ОЗУ после генерации: ${m.residentMemoryBytes == null ? '—' : _mb(m.residentMemoryBytes!)}');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final status = _llm.status;
    final busy = status == LocalLlmStatus.loading || status == LocalLlmStatus.generating;
    final ready = status == LocalLlmStatus.ready;
    final statusText = switch (status) {
      LocalLlmStatus.unloaded => 'модель не загружена',
      LocalLlmStatus.loading => 'загружается…',
      LocalLlmStatus.ready => 'готова',
      LocalLlmStatus.generating => 'генерирует…',
      LocalLlmStatus.error => 'ошибка',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Local AI Test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Состояние: $statusText'),
            const SizedBox(height: 8),
            Text(
              _modelPath == null ? 'Файл модели не выбран' : 'Модель: ${p.basename(_modelPath!)}',
            ),
            const SizedBox(height: 8),
            if (_copiedBytes != null) ...[
              LinearProgressIndicator(
                value: _totalBytes == null || _totalBytes == 0
                    ? null
                    : (_copiedBytes! / _totalBytes!).clamp(0.0, 1.0).toDouble(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_totalBytes == null
                    ? 'Копирование модели: ${_mb(_copiedBytes!)}'
                    : 'Копирование модели: ${_mb(_copiedBytes!)} из ${_mb(_totalBytes!)}'),
              ),
            ],
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy || _copiedBytes != null ? null : _pickModel,
                  child: const Text('Выбрать .gguf'),
                ),
                FilledButton(
                  onPressed: busy || ready || _modelPath == null ? null : _load,
                  child: const Text('Загрузить'),
                ),
                OutlinedButton(
                  onPressed: busy || !ready ? null : _unload,
                  child: const Text('Выгрузить'),
                ),
              ],
            ),
            const Divider(height: 32),
            TextField(
              controller: _prompt,
              decoration: const InputDecoration(labelText: 'Сообщение', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: ready ? _generate : null,
              child: const Text('Сгенерировать'),
            ),
            const SizedBox(height: 16),
            if (_answer.isNotEmpty) SelectableText(_answer.toString(), style: const TextStyle(fontSize: 20)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            SelectableText(_metricsText(), style: const TextStyle(fontFamily: 'Menlo', fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
