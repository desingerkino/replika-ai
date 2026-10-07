import 'package:flutter/material.dart';

import '../../app/audio_playback.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/pressable.dart';
import '../../data/models/media_item.dart';
import '../media/media_content.dart';
import '../media/media_kinds.dart';

/// Компактный плеер над перепиской: пока играет или стоит на паузе голосовое
/// или аудио. Пауза/продолжение, перемотка касанием и протягиванием по
/// «волне», время «0:12 / 0:37» и закрытие. Один активный звук на всё
/// приложение — это состояние [AudioPlayback].
class VoiceMiniPlayer extends StatelessWidget {
  const VoiceMiniPlayer({super.key, required this.playback});

  final AudioPlayback playback;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final media = playback.currentMedia;
        if (media == null) return const SizedBox.shrink();
        return _PlayerBar(playback: playback, media: media);
      },
    );
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.playback, required this.media});

  final AudioPlayback playback;
  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final playing = playback.playing;
    final total = playback.duration ?? media.duration;
    final isVoice = media.kind == MediaKind.voice;
    final title = isVoice ? 'Голосовое' : (media.originalName ?? 'Аудио');
    final time = total == null
        ? formatDuration(playback.position)
        : '${formatDuration(playback.position)} / ${formatDuration(total)}';
    return Material(
      color: cs.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: rc.divider, width: Sizes.line)),
        ),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Pressable(
                tint: false,
                scale: 0.92,
                onTap: playback.togglePlayPause,
                semanticsLabel: playing ? 'Пауза' : 'Воспроизвести',
                child: SizedBox(
                  width: Sizes.minTouch,
                  height: 52,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                      child: Icon(playing ? AppIcons.pause : AppIcons.play, size: 22, color: cs.onPrimary),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.labelLarge,
                    ),
                    SizedBox(
                      height: 22,
                      child: _Scrubber(playback: playback, media: media, isVoice: isVoice),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              Text(
                time,
                style: context.tt.labelMedium?.copyWith(
                  color: rc.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Pressable(
                tint: false,
                onTap: playback.stop,
                semanticsLabel: 'Закрыть плеер',
                child: SizedBox(
                  width: Sizes.minTouch,
                  height: 52,
                  child: Icon(AppIcons.clear, size: 20, color: rc.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полоса перемотки: касание и протягивание меняют позицию.
/// Для голосового — его «волна», для аудио — тонкая линия прогресса.
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.playback, required this.media, required this.isVoice});

  final AudioPlayback playback;
  final MediaItem media;
  final bool isVoice;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final progress = playback.progressOf(media.id);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seek(double dx) {
          if (width <= 0) return;
          playback.seekFraction(dx / width);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seek(details.localPosition.dx),
          onHorizontalDragStart: (details) => seek(details.localPosition.dx),
          onHorizontalDragUpdate: (details) => seek(details.localPosition.dx),
          child: isVoice
              ? CustomPaint(
                  size: Size(width, 22),
                  painter: WaveformPainter(
                    values: media.waveform.isEmpty ? decorativeWaveform(media.id) : media.waveform,
                    progress: progress,
                    played: cs.primary,
                    idle: rc.textTertiary,
                  ),
                )
              : Align(
                  alignment: Alignment.center,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      color: cs.primary,
                      backgroundColor: rc.textTertiary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
