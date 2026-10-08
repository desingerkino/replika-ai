import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../data/models/media_item.dart';
import '../media/media_content.dart';
import '../media/media_kinds.dart';
import '../record/voice_recording.dart';

/// Насколько сдвинуть палец вверх, чтобы поставить запись «на замок»,
/// и влево — чтобы отменить.
const double voiceLockDistance = 72;
const double voiceCancelDistance = 120;

/// Кнопка микрофона: удерживать — запись, отпустить — отправить, вверх —
/// замок, влево — отмена. Короткое касание — запись «на замке» сразу
/// (можно говорить, не держа палец).
class MicButton extends StatefulWidget {
  const MicButton({super.key, required this.voice, required this.onSend, this.size = 46, this.enabled = true});

  final VoiceRecorderController voice;
  final Future<void> Function(MediaItem item) onSend;
  final double size;
  final bool enabled;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  Offset _drag = Offset.zero;
  bool _cancelled = false;

  VoiceRecorderController get _v => widget.voice;

  void _start(LongPressStartDetails _) {
    _drag = Offset.zero;
    _cancelled = false;
    _v.pressed = true;
    unawaited(_v.start());
  }

  /// Жест прервала система (звонок, окно разрешения): палец «потерян» —
  /// запись не отправляется сама, а встаёт на замок.
  void _lost() {
    _v.pressed = false;
    if (_v.state == VoiceRecState.holding) _v.lock();
    if (mounted) setState(() => _drag = Offset.zero);
  }

  void _move(LongPressMoveUpdateDetails d) {
    if (_v.state != VoiceRecState.holding) return;
    setState(() => _drag = d.offsetFromOrigin);
    if (-d.offsetFromOrigin.dy > voiceLockDistance) {
      _v.lock();
      setState(() => _drag = Offset.zero);
    } else if (-d.offsetFromOrigin.dx > voiceCancelDistance) {
      _cancelled = true;
      unawaited(_v.cancel());
      setState(() => _drag = Offset.zero);
    }
  }

  Future<void> _end(LongPressEndDetails _) async {
    _v.pressed = false;
    setState(() => _drag = Offset.zero);
    if (_cancelled || _v.state != VoiceRecState.holding) return;
    final item = await _v.finish();
    if (item != null) await widget.onSend(item);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final rc = context.rc;
    return ListenableBuilder(
      listenable: _v,
      builder: (context, _) {
        final holding = _v.state == VoiceRecState.holding;
        final lockProgress = holding ? (-_drag.dy / voiceLockDistance).clamp(0.0, 1.0) : 0.0;
        return Semantics(
          button: true,
          label: 'Записать голосовое: удерживайте или коснитесь',
          child: Listener(
            // Отмена указателя после принятого долгого нажатия не вызывает
            // onLongPressEnd — ловим её здесь.
            onPointerCancel: (_) => _lost(),
            child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 160)),
                (r) => r
                  ..onLongPressStart = widget.enabled ? _start : null
                  ..onLongPressMoveUpdate = _move
                  ..onLongPressEnd = _end
                  ..onLongPressCancel = _lost,
              ),
              TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r.onTap = widget.enabled ? () => unawaited(_v.start(locked: true)) : null,
              ),
            },
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // «Замок» над кнопкой: поднимается вместе с пальцем.
                if (holding)
                  Positioned(
                    bottom: widget.size + 18 + lockProgress * 18,
                    child: IgnorePointer(
                      child: Container(
                        width: 40,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: rc.glass,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: rc.glassBorder, width: 0.5),
                          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 3))],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              lockProgress > 0.9 ? Icons.lock_rounded : Icons.lock_open_rounded,
                              size: 20,
                              color: Color.lerp(rc.textSecondary, cs.primary, lockProgress),
                            ),
                            const SizedBox(height: 4),
                            Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: rc.textTertiary),
                          ],
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: holding ? Offset(math.min(0, _drag.dx), 0) : Offset.zero,
                  child: AnimatedScale(
                    scale: holding ? 1.45 : 1,
                    duration: Motion.normal,
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        color: holding ? cs.primary : cs.primary,
                        shape: BoxShape.circle,
                        boxShadow: holding
                            ? [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 2)]
                            : null,
                      ),
                      child: Icon(Icons.mic_rounded, color: cs.onPrimary, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

/// Полоса записи вместо поля ввода: таймер, живая волна и подсказка
/// (пока держат), кнопки «Удалить» и «Стоп» (на замке), прослушивание с
/// перемоткой (после остановки).
class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({super.key, required this.voice});

  final VoiceRecorderController voice;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final state = voice.state;
        final time = Text(
          formatDuration(voice.elapsed),
          style: context.tt.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        );
        if (state == VoiceRecState.stopped) {
          final draft = voice.draft;
          return Row(
            children: [
              _IconAction(icon: AppIcons.delete, color: rc.danger, label: 'Удалить запись', onTap: voice.cancel),
              Expanded(
                child: draft == null
                    ? const SizedBox.shrink()
                    : _DraftPlayer(media: draft),
              ),
            ],
          );
        }
        final live = _liveLevels(voice.levels);
        return Row(
          children: [
            if (state == VoiceRecState.locked)
              _IconAction(icon: AppIcons.delete, color: rc.danger, label: 'Удалить запись', onTap: voice.cancel)
            else
              const SizedBox(width: Space.m),
            const _RecDot(),
            const SizedBox(width: Space.s),
            time,
            const SizedBox(width: Space.m),
            Expanded(
              child: state == VoiceRecState.holding
                  ? Row(
                      children: [
                        Expanded(child: _Wave(values: live, color: cs.primary)),
                        const SizedBox(width: Space.s),
                        Text('‹ отмена', style: context.tt.bodySmall?.copyWith(color: rc.textTertiary)),
                      ],
                    )
                  : _Wave(values: live, color: cs.primary),
            ),
            if (state == VoiceRecState.locked)
              _IconAction(icon: Icons.stop_rounded, color: rc.danger, label: 'Остановить запись', onTap: voice.stop),
          ],
        );
      },
    );
  }

  /// Последние замеры, нормированные по пику, — живая волна.
  static List<double> _liveLevels(List<double> levels) {
    const count = 36;
    final recent = levels.length > count ? levels.sublist(levels.length - count) : levels;
    if (recent.isEmpty) return const [0.05];
    return normalizeWaveform(recent);
  }
}

class _Wave extends StatelessWidget {
  const _Wave({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: CustomPaint(
        painter: WaveformPainter(values: values, progress: 1, played: color, idle: color),
      ),
    );
  }
}

class _RecDot extends StatefulWidget {
  const _RecDot();

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: context.rc.danger, shape: BoxShape.circle),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: () {
        HapticFeedback.selectionClick();
        unawaited(onTap());
      },
      icon: Icon(icon, color: color),
    );
  }
}

/// Прослушать записанное перед отправкой: кнопка, волна с перемоткой, время.
class _DraftPlayer extends StatelessWidget {
  const _DraftPlayer({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final rc = context.rc;
    final playback = Services.of(context).audio;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final playing = playback.isPlaying(media.id);
        final progress = playback.progressOf(media.id);
        return Row(
          children: [
            IconButton(
              tooltip: playing ? 'Пауза' : 'Прослушать',
              onPressed: () => playback.toggle(media).catchError((Object _) {}),
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.primary),
            ),
            Expanded(
              child: SeekableWaveform(
                values: media.waveform,
                progress: progress,
                played: cs.primary,
                idle: rc.textTertiary.withValues(alpha: 0.5),
                onSeek: (f) => playback.seekFraction(media, f).catchError((Object _) {}),
              ),
            ),
            const SizedBox(width: Space.s),
            Text(
              formatDuration(media.duration ?? Duration.zero),
              style: context.tt.bodyMedium?.copyWith(color: rc.textSecondary),
            ),
          ],
        );
      },
    );
  }
}
