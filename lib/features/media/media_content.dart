import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../data/models/media_item.dart';
import 'media_kinds.dart';
import 'media_viewer.dart';

/// Файл отсутствует: удалён из медиатеки или с телефона.
class MissingMedia extends StatelessWidget {
  const MissingMedia({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hide_image_outlined, size: 20, color: color),
          const SizedBox(width: Space.s),
          Text('Файл удалён', style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

bool mediaFileExists(MediaItem? media) => media != null && File(media.path).existsSync();

/// Фото в пузыре. Нажатие — полноэкранный просмотр.
class PhotoContent extends StatelessWidget {
  const PhotoContent({super.key, required this.media, required this.width});

  final MediaItem media;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width / media.aspectRatio.clamp(0.62, 1.8);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return GestureDetector(
      onTap: () => openPhotoViewer(context, media),
      child: Image.file(
        File(media.path),
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: (width * dpr).round(),
        errorBuilder: (context, error, stack) => SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: MediaPalette.scrimLight,
            child: Icon(Icons.broken_image_outlined, color: context.rc.textTertiary),
          ),
        ),
      ),
    );
  }
}

/// Первый кадр видео (плеер создаётся, только пока пузырь на экране).
class VideoFrame extends StatefulWidget {
  const VideoFrame({super.key, required this.media, required this.width, required this.height});

  final MediaItem media;
  final double width;
  final double height;

  @override
  State<VideoFrame> createState() => _VideoFrameState();
}

class _VideoFrameState extends State<VideoFrame> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.file(File(widget.media.path));
    _controller = controller;
    controller.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object error) {
      debugPrint('Превью видео недоступно: $error');
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final size = ready ? controller.value.size : Size.zero;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ColoredBox(
        color: MediaPalette.background,
        child: ready && size.width > 0
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(controller)),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

/// Видео в пузыре: кадр, кнопка воспроизведения и длительность.
class VideoContent extends StatelessWidget {
  const VideoContent({super.key, required this.media, required this.width});

  final MediaItem media;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width / media.aspectRatio.clamp(0.62, 1.8);
    final duration = media.duration;
    return GestureDetector(
      onTap: () => openVideoViewer(context, media),
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoFrame(media: media, width: width, height: height),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0x8C000000),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x66FFFFFF), width: 1.5),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: MediaPalette.onMedia, size: 38),
          ),
          if (duration != null)
            Positioned(
              left: Space.s,
              top: Space.s,
              child: _Pill(text: formatDuration(duration)),
            ),
        ],
      ),
    );
  }
}

/// Круглое видеосообщение: нажатие — воспроизведение со звуком.
class VideoNoteContent extends StatefulWidget {
  const VideoNoteContent({super.key, required this.media, this.size = 220});

  final MediaItem media;
  final double size;

  @override
  State<VideoNoteContent> createState() => _VideoNoteContentState();
}

class _VideoNoteContentState extends State<VideoNoteContent> {
  late final VideoPlayerController _controller =
      VideoPlayerController.file(File(widget.media.path));
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
    _controller.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object error) {
      debugPrint('Видеосообщение недоступно: $error');
    });
  }

  void _onTick() {
    final value = _controller.value;
    if (value.isInitialized && !value.isPlaying && value.position >= value.duration && value.duration > Duration.zero) {
      _controller.seekTo(Duration.zero);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await Services.read(context).audio.stop();
      await _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    final total = value.duration.inMilliseconds;
    final progress = total > 0 ? value.position.inMilliseconds / total : 0.0;
    final size = value.size;
    final remaining = _ready ? value.duration - value.position : widget.media.duration;
    return GestureDetector(
      onTap: _toggle,
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          children: [
            ClipOval(
              child: ColoredBox(
                color: MediaPalette.background,
                child: SizedBox.expand(
                  child: _ready && size.width > 0
                      ? FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(_controller)),
                        )
                      : null,
                ),
              ),
            ),
            if (value.isPlaying || value.position > Duration.zero)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RingPainter(progress: progress, color: MediaPalette.onMedia),
                ),
              ),
            if (remaining != null)
              Positioned(
                left: Space.m,
                bottom: Space.m,
                child: _Pill(text: formatDuration(remaining)),
              ),
            if (!value.isPlaying)
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
                  child: const Icon(Icons.volume_up_rounded, color: MediaPalette.onMedia, size: 24),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    canvas.drawArc(rect.deflate(3), -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.progress != progress;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x80000000),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: MediaPalette.onMedia,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Голосовое или аудио: кнопка, волна (или дорожка) с перемоткой касанием
/// и перетаскиванием, текущая позиция и длительность. [messageId] связывает
/// воспроизведение с сообщением (плеер над чатом, «прослушано»).
class AudioContent extends StatelessWidget {
  const AudioContent({
    super.key,
    required this.media,
    required this.voice,
    required this.foreground,
    required this.accent,
    required this.onAccent,
    required this.muted,
    this.messageId,
    this.unplayed = false,
  });

  final MediaItem media;
  final bool voice;
  final Color foreground;
  final Color accent;
  final Color onAccent;
  final Color muted;
  final String? messageId;

  /// Входящее голосовое ещё не дослушано — точка рядом со временем.
  final bool unplayed;

  void _failed(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось воспроизвести файл')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = Services.of(context).audio;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final playing = playback.isPlaying(media.id);
        final current = playback.isCurrent(media.id);
        final progress = playback.progressOf(media.id);
        final total = media.duration ?? (current ? playback.duration : null);
        final time = current
            ? '${formatDuration(playback.position)}${total == null ? '' : ' / ${formatDuration(total)}'}'
            : (total == null ? '' : formatDuration(total));
        Future<void> seek(double f) async {
          try {
            await playback.seekFraction(media, f, messageId: messageId);
          } catch (_) {
            if (context.mounted) _failed(context);
          }
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: playing ? 'Пауза' : 'Воспроизвести',
              child: GestureDetector(
                onTap: () async {
                  try {
                    await playback.toggle(media, messageId: messageId);
                  } catch (_) {
                    if (context.mounted) _failed(context);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: onAccent,
                    size: 28,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.m - 2),
            // Ширина сжимается при крупном шрифте, чтобы время и галочки
            // оставались внутри пузыря.
            Flexible(
              child: SizedBox(
                width: 176,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!voice)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          media.originalName ?? 'Аудио',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: foreground, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    SeekableWaveform(
                      // Волна — только настоящая (записанная в приложении);
                      // у файлов без замеров — ровная дорожка с бегунком.
                      values: voice ? media.waveform : const [],
                      progress: progress,
                      played: accent,
                      idle: muted,
                      onSeek: seek,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          time,
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (unplayed) ...[
                          const SizedBox(width: 5),
                          Semantics(
                            label: 'Не прослушано',
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Волна (или дорожка, если замеров нет) с перемоткой: касание или
/// перетаскивание по ней переставляет воспроизведение.
class SeekableWaveform extends StatefulWidget {
  const SeekableWaveform({
    super.key,
    required this.values,
    required this.progress,
    required this.played,
    required this.idle,
    required this.onSeek,
    this.height = 28,
  });

  final List<double> values;
  final double progress;
  final Color played;
  final Color idle;
  final ValueChanged<double> onSeek;
  final double height;

  @override
  State<SeekableWaveform> createState() => _SeekableWaveformState();
}

class _SeekableWaveformState extends State<SeekableWaveform> {
  double? _dragging;

  double _fraction(Offset local, double width) => width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final shown = _dragging ?? widget.progress;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 176.0;
        return Semantics(
          slider: true,
          value: '${(shown * 100).round()}%',
          label: 'Перемотка',
          onIncrease: () => widget.onSeek((widget.progress + 0.1).clamp(0.0, 1.0)),
          onDecrease: () => widget.onSeek((widget.progress - 0.1).clamp(0.0, 1.0)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onSeek(_fraction(d.localPosition, width)),
            onHorizontalDragStart: (d) => setState(() => _dragging = _fraction(d.localPosition, width)),
            onHorizontalDragUpdate: (d) => setState(() => _dragging = _fraction(d.localPosition, width)),
            onHorizontalDragEnd: (_) {
              final f = _dragging;
              setState(() => _dragging = null);
              if (f != null) widget.onSeek(f);
            },
            onHorizontalDragCancel: () => setState(() => _dragging = null),
            child: SizedBox(
              height: widget.height,
              width: width,
              child: CustomPaint(
                painter: widget.values.isEmpty
                    ? _TrackPainter(progress: shown, played: widget.played, idle: widget.idle)
                    : WaveformPainter(
                        values: widget.values,
                        progress: shown,
                        played: widget.played,
                        idle: widget.idle,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Дорожка с бегунком для аудио без замеров громкости.
class _TrackPainter extends CustomPainter {
  const _TrackPainter({required this.progress, required this.played, required this.idle});

  final double progress;
  final Color played;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x = size.width * progress;
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint..color = idle);
    canvas.drawLine(Offset(0, y), Offset(x, y), paint..color = played);
    canvas.drawCircle(Offset(x.clamp(5.0, size.width - 5), y), 5, Paint()..color = played);
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) => oldDelegate.progress != progress;
}

/// Столбики «волны» голосового; проигранная часть — цветом акцента.
class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.values,
    required this.progress,
    required this.played,
    required this.idle,
  });

  final List<double> values;
  final double progress;
  final Color played;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final step = size.width / values.length;
    final barWidth = math.max(2.0, step * 0.6);
    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = barWidth;
    for (var i = 0; i < values.length; i++) {
      final x = step * i + step / 2;
      final h = math.max(barWidth, values[i] * size.height);
      paint.color = (i + 0.5) / values.length <= progress ? played : idle;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.values != values;
}

/// Прочий файл: значок, имя, размер.
class FileContent extends StatelessWidget {
  const FileContent({super.key, required this.media, required this.foreground, required this.muted});

  final MediaItem media;
  final Color foreground;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_rounded, size: 36, color: muted),
        const SizedBox(width: Space.s),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                media.originalName ?? 'Файл',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (media.sizeBytes != null)
                Text(formatBytes(media.sizeBytes!), style: TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
