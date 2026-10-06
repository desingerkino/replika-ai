import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../data/models/media_item.dart';
import '../call/camera_cover.dart';
import '../media/media_kinds.dart';

/// Записать круглое видеосообщение фронтальной камерой.
/// Возвращает файл медиатеки или null.
Future<MediaItem?> recordVideoNote(BuildContext context) => Navigator.of(context).push<MediaItem>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _VideoNoteRecorder()),
    );

class _VideoNoteRecorder extends StatefulWidget {
  const _VideoNoteRecorder();

  @override
  State<_VideoNoteRecorder> createState() => _VideoNoteRecorderState();
}

class _VideoNoteRecorderState extends State<_VideoNoteRecorder> {
  static const Duration _maxLength = Duration(seconds: 60);

  CameraController? _controller;
  String? _problem;
  DateTime? _startedAt;
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    await Services.read(context).audio.stop();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('На телефоне нет камеры');
        return;
      }
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull ?? cameras.first;
      final controller = CameraController(front, ResolutionPreset.medium, enableAudio: true);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (error) {
      _fail(error.code.contains('ccess') || error.code.contains('ermission')
          ? 'Нет доступа к камере или микрофону. Разрешите их в настройках устройства.'
          : 'Камера недоступна');
    } catch (_) {
      _fail('Камера недоступна');
    }
  }

  void _fail(String text) {
    if (mounted) setState(() => _problem = text);
  }

  bool get _recording => _startedAt != null;

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    _busy = true;
    try {
      if (!_recording) {
        await controller.startVideoRecording();
        unawaited(HapticFeedback.lightImpact());
        _startedAt = DateTime.now();
        _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (!mounted) return;
          if (DateTime.now().difference(_startedAt!) >= _maxLength) {
            unawaited(_toggle());
          } else {
            setState(() {});
          }
        });
        setState(() {});
      } else {
        _ticker?.cancel();
        final file = await controller.stopVideoRecording();
        if (!mounted) return;
        final services = Services.read(context);
        final item = await services.media.registerVideoNote(file.path);
        if (mounted) Navigator.of(context).pop(item);
      }
    } catch (error) {
      debugPrint('Видеосообщение не записано: $error');
      _fail('Не удалось записать видео');
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final elapsed = _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1115),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Круг не больше 280 и не выше свободного места: в ландшафте
            // iPhone кнопка записи и подпись остаются на экране.
            final size = (constraints.maxHeight - 250).clamp(140.0, 280.0);
            return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Отмена',
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            const Spacer(),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(_problem!,
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
              )
            else
              ClipOval(
                child: SizedBox.square(
                  dimension: size,
                  child: ready
                      ? CameraCover(controller: controller)
                      : const ColoredBox(
                          color: Color(0xFF26313A),
                          child: Center(child: CircularProgressIndicator(color: Colors.white)),
                        ),
                ),
              ),
            const SizedBox(height: Space.l),
            Text(
              _recording ? formatDuration(elapsed) : 'Видеосообщение до 1 минуты',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_problem == null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xxl),
                child: Semantics(
                  button: true,
                  label: _recording ? 'Остановить и отправить' : 'Начать запись',
                  child: GestureDetector(
                    onTap: ready ? _toggle : null,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: Motion.fast,
                          width: _recording ? 28 : 58,
                          height: _recording ? 28 : 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5483E),
                            borderRadius: BorderRadius.circular(_recording ? 6 : 29),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
            );
          },
        ),
      ),
    );
  }
}
