import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../data/models/media_item.dart';
import '../media/media_content.dart';
import '../media/media_kinds.dart';

/// Записать голосовое прямо в чате. Возвращает готовый файл медиатеки
/// или null (отмена, нет разрешения, ошибка).
Future<MediaItem?> recordVoice(BuildContext context) {
  return showModalBottomSheet<MediaItem>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: context.cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
    ),
    builder: (_) => const _VoiceRecorder(),
  );
}

class _VoiceRecorder extends StatefulWidget {
  const _VoiceRecorder();

  @override
  State<_VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<_VoiceRecorder> {
  static const Duration _maxLength = Duration(minutes: 10);

  final AudioRecorder _recorder = AudioRecorder();
  final List<double> _levels = [];
  StreamSubscription<Amplitude>? _amplitude;
  Timer? _ticker;
  DateTime? _startedAt;
  String? _path;
  String? _problem;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final services = Services.read(context);
    await services.audio.stop();
    try {
      if (!await _recorder.hasPermission()) {
        _fail('Нет доступа к микрофону. Разрешите его в настройках устройства и попробуйте снова.');
        return;
      }
      final path = await services.media.newRecordingPath('.m4a');
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      _path = path;
      _startedAt = DateTime.now();
      unawaited(HapticFeedback.lightImpact());
      _amplitude = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
        _levels.add(levelFromDb(a.current));
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        if (_elapsed >= _maxLength) {
          unawaited(_send());
        } else {
          setState(() {});
        }
      });
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Запись не началась: $error');
      _fail('Не удалось начать запись');
    }
  }

  void _fail(String text) {
    if (mounted) setState(() => _problem = text);
  }

  Duration get _elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  Future<void> _stopStreams() async {
    _ticker?.cancel();
    await _amplitude?.cancel();
  }

  Future<void> _cancel() async {
    if (_finishing) return;
    _finishing = true;
    await _stopStreams();
    try {
      await _recorder.cancel();
    } catch (_) {
      final path = _path;
      if (path != null && File(path).existsSync()) File(path).deleteSync();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _send() async {
    if (_finishing || _path == null) return;
    _finishing = true;
    final services = Services.read(context);
    final duration = _elapsed;
    await _stopStreams();
    try {
      final path = await _recorder.stop() ?? _path!;
      if (duration < const Duration(milliseconds: 700)) {
        if (File(path).existsSync()) File(path).deleteSync();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final item = await services.media.registerVoice(
        path,
        duration: duration,
        waveform: downsampleWaveform(_levels),
      );
      if (mounted) Navigator.of(context).pop(item);
    } catch (error) {
      debugPrint('Голосовое не сохранено: $error');
      _finishing = false;
      _fail('Не удалось сохранить запись');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_amplitude?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final recent = _levels.length > 40 ? _levels.sublist(_levels.length - 40) : _levels;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_problem != null) ...[
              Text(_problem!, textAlign: TextAlign.center, style: context.tt.bodyLarge),
              const SizedBox(height: Space.l),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть')),
            ] else ...[
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: rc.danger, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: Space.s),
                  Text(
                    formatDuration(_elapsed),
                    style: context.tt.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: CustomPaint(
                        painter: WaveformPainter(
                          values: recent.isEmpty ? const [0.05] : recent,
                          progress: 1,
                          played: cs.primary,
                          idle: rc.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _cancel,
                      style: TextButton.styleFrom(foregroundColor: rc.danger),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _path == null ? null : _send,
                      icon: const Icon(AppIcons.send),
                      label: const Text('Отправить'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
