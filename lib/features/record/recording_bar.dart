import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/pressable.dart';
import '../media/media_content.dart';
import '../media/media_kinds.dart';
import 'voice_recording.dart';

/// Строка записи вместо поля ввода: красная точка, таймер и подсказка.
/// Пока палец держит микрофон — «влево — отмена» (уезжает за пальцем);
/// после фиксации — волна и «Отмена».
class RecordingBar extends StatelessWidget {
  const RecordingBar({super.key, required this.controller});

  final VoiceRecordingController controller;

  /// Высота волны в зафиксированной записи.
  static const double waveHeight = 28;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final elapsed = controller.elapsed;
    // Точка мягко мигает раз в секунду (при отключённых анимациях горит ровно).
    final dotOn = reduceMotion || (elapsed.inMilliseconds ~/ 500).isEven;
    final locked = controller.locked;
    return SizedBox(
      height: Sizes.minTouch,
      child: Row(
        children: [
          const SizedBox(width: Space.m),
          AnimatedOpacity(
            opacity: dotOn ? 1 : 0.3,
            duration: reduceMotion ? Duration.zero : Motion.fast,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: rc.danger, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: Space.s),
          SizedBox(
            width: 48,
            child: Text(
              formatDuration(elapsed),
              style: context.tt.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: locked
                ? Row(
                    children: [
                      Expanded(
                        // Высота волны жёсткая, рисование обрезано по ней:
                        // панель записи не может вырасти выше своей строки.
                        child: ClipRect(
                          child: SizedBox(
                            height: waveHeight,
                            child: CustomPaint(
                              size: const Size(double.infinity, waveHeight),
                              painter: WaveformPainter(
                                values: controller.liveWaveform,
                                progress: 1,
                                played: cs.primary,
                                idle: rc.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Pressable(
                        onTap: controller.cancel,
                        semanticsLabel: 'Отмена записи',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                          child: Text('Отмена', style: context.tt.labelLarge?.copyWith(color: rc.danger)),
                        ),
                      ),
                    ],
                  )
                : Opacity(
                    opacity: 1 - controller.cancelProgress,
                    child: Transform.translate(
                      offset: Offset(-controller.cancelProgress * 48, 0),
                      child: Row(
                        children: [
                          Icon(AppIcons.back, size: 18, color: rc.textSecondary),
                          const SizedBox(width: Space.xs),
                          Flexible(
                            child: Text(
                              'Влево — отмена',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.tt.bodyMedium?.copyWith(color: rc.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Небольшая «капсула» с замком над микрофоном: показывает, куда вести
/// палец, чтобы зафиксировать запись. Поднимается вместе с движением.
class LockHint extends StatelessWidget {
  const LockHint({super.key, required this.progress});

  /// 0..1 — как близко палец к фиксации.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    return Container(
      width: 40,
      height: 64,
      decoration: BoxDecoration(
        color: rc.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: rc.divider, width: Sizes.line),
      ),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: Space.m),
      child: Icon(
        AppIcons.lock,
        size: 20,
        color: Color.lerp(rc.textSecondary, cs.primary, progress),
      ),
    );
  }
}
