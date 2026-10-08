import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../data/models/message.dart';
import '../media/media_kinds.dart';

/// Компактный плеер над перепиской: виден, пока играет голосовое или
/// аудио из этого чата. Связан с конкретным сообщением: касание —
/// прокрутить к нему, другое сообщение — плеер переключается, дослушали —
/// плеер исчезает.
class ChatAudioBar extends StatelessWidget {
  const ChatAudioBar({
    super.key,
    required this.messages,
    required this.senderName,
    required this.onReveal,
  });

  /// Голосовые и аудио этого чата по id сообщения.
  final Map<String, Message> messages;
  final String Function(Message message) senderName;
  final ValueChanged<String> onReveal;

  @override
  Widget build(BuildContext context) {
    final playback = Services.of(context).audio;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final id = playback.currentMessageId;
        final message = id == null ? null : messages[id];
        final media = playback.currentMedia;
        final visible = message != null && media != null;
        return AnimatedSwitcher(
          duration: Motion.normal,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: !visible
              ? const SizedBox(key: ValueKey('none'), width: double.infinity)
              : _Bar(
                  key: const ValueKey('bar'),
                  title: message.type == MessageType.voice ? 'Голосовое сообщение' : (media.originalName ?? 'Аудио'),
                  subtitle: senderName(message),
                  playing: playback.playing,
                  position: playback.position,
                  duration: playback.duration ?? media.duration,
                  progress: playback.progressOf(media.id),
                  onToggle: () => playback.toggle(media, messageId: message.id).catchError((Object _) {}),
                  onClose: playback.stop,
                  onTap: () => onReveal(message.id),
                ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.playing,
    required this.position,
    required this.duration,
    required this.progress,
    required this.onToggle,
    required this.onClose,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool playing;
  final Duration position;
  final Duration? duration;
  final double progress;
  final VoidCallback onToggle;
  final VoidCallback onClose;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final time = duration == null
        ? formatDuration(position)
        : '${formatDuration(position)} / ${formatDuration(duration!)}';
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: rc.glass,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: playing ? 'Пауза' : 'Воспроизвести',
                        onPressed: onToggle,
                        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.primary),
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
                              style: context.tt.labelLarge?.copyWith(fontSize: 14),
                            ),
                            Text(
                              '$subtitle · $time',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.tt.bodySmall?.copyWith(
                                color: rc.textSecondary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть плеер',
                        onPressed: onClose,
                        icon: Icon(Icons.close_rounded, color: rc.textSecondary, size: 20),
                      ),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  color: cs.primary,
                  backgroundColor: rc.divider.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
