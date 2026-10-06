import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../app/call_engine.dart';
import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../data/models/call_record.dart';
import '../media/media_kinds.dart';
import 'camera_self_view.dart';

/// Экран постановочного звонка. Закрывается сам, когда звонок убран.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallEngine _engine = Services.read(context).callEngine;
  bool _closing = false;

  // Материалы собеседника в разговоре.
  AudioPlayer? _voice;
  VideoPlayerController? _video;
  String? _voicePath;
  String? _videoPath;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onChange);
    _syncPeerMedia();
    _darkScreens = Services.read(context).darkScreens;
    final dark = _darkScreens!;
    scheduleMicrotask(() => dark.value++);
  }

  ValueNotifier<int>? _darkScreens;

  void _onChange() {
    if (_engine.phase == CallPhase.idle) {
      if (!_closing && mounted) {
        _closing = true;
        Navigator.of(context).maybePop();
      }
      return;
    }
    _syncPeerMedia();
    if (mounted) setState(() {});
  }

  /// Голос и видео собеседника звучат и видны только в разговоре.
  void _syncPeerMedia() {
    final session = _engine.session;
    final talking = _engine.phase == CallPhase.active;
    final audioPath = talking ? session?.peerAudioPath : null;
    final videoPath = session?.kind == CallKind.video && talking ? session?.peerVideoPath : null;

    if (audioPath != _voicePath) {
      _voicePath = audioPath;
      final old = _voice;
      _voice = null;
      unawaited(old?.dispose());
      if (audioPath != null && File(audioPath).existsSync()) {
        final player = AudioPlayer();
        _voice = player;
        player.setFilePath(audioPath).then((_) => player.play()).catchError((Object error) {
          debugPrint('Голос собеседника не воспроизведён: $error');
        });
      }
    }
    if (videoPath != _videoPath) {
      _videoPath = videoPath;
      final old = _video;
      _video = null;
      unawaited(old?.dispose());
      if (videoPath != null && File(videoPath).existsSync()) {
        final controller = VideoPlayerController.file(File(videoPath));
        _video = controller;
        controller.initialize().then((_) async {
          await controller.setLooping(true);
          await controller.play();
          if (mounted) setState(() {});
        }).catchError((Object error) {
          debugPrint('Видео собеседника не воспроизведено: $error');
        });
      }
    }
  }

  @override
  void dispose() {
    final dark = _darkScreens;
    if (dark != null) scheduleMicrotask(() => dark.value = dark.value > 0 ? dark.value - 1 : 0);
    _engine.removeListener(_onChange);
    unawaited(_voice?.dispose());
    unawaited(_video?.dispose());
    super.dispose();
  }

  String _status(CallSession session) {
    final video = session.kind == CallKind.video;
    return switch (_engine.phase) {
      CallPhase.incoming => video ? 'Входящий видеозвонок…' : 'Входящий аудиозвонок…',
      CallPhase.outgoing => 'Вызов…',
      CallPhase.connecting => 'Соединение…',
      CallPhase.active => formatDuration(_engine.talked),
      CallPhase.ended => switch (_engine.outcome) {
          CallOutcome.missed => session.direction == CallDirection.outgoing ? 'Нет ответа' : 'Пропущенный звонок',
          CallOutcome.declined => 'Звонок отклонён',
          CallOutcome.cancelled => 'Вызов отменён',
          _ => 'Звонок завершён',
        },
      CallPhase.idle => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = _engine.session;
    if (session == null) return const Scaffold(backgroundColor: Color(0xFF0B1115));
    final phase = _engine.phase;
    final video = session.kind == CallKind.video;
    final remote = _video;
    final showRemote = remote != null && remote.value.isInitialized;
    final showSelf = video && !_engine.cameraOff && phase != CallPhase.ended;
    final tone = session.avatarTone != null ? AvatarTones.at(session.avatarTone!) : AvatarTones.forKey(session.displayName);

    return PopScope(
      canPop: phase == CallPhase.idle || phase == CallPhase.ended,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF0B1115),
          // expand: без него Scaffold даёт Stack «свободные» размеры, и он
          // сжимается до ширины самого широкого содержимого (полэкрана).
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Фон: видео собеседника или мягкий свет цвета его аватара.
              Positioned.fill(
                child: showRemote
                    ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: remote.value.size.width,
                          height: remote.value.size.height,
                          child: VideoPlayer(remote),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -0.35),
                            radius: 1.1,
                            colors: [tone.withValues(alpha: 0.55), const Color(0xFF0B1115)],
                          ),
                        ),
                      ),
              ),
              SafeArea(
                // В ландшафте iPhone экран низкий: содержимое прокручивается,
                // а не выходит за край; Spacer работает за счёт IntrinsicHeight.
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                  children: [
                    const SizedBox(height: Space.xl),
                    if (!showRemote) ...[
                      Avatar(
                        name: session.displayName,
                        size: _avatarSize(context),
                        tone: session.avatarTone,
                        imagePath: session.avatarPath,
                      ),
                      const SizedBox(height: Space.l),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      child: Text(
                        session.displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      _status(session),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 16,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (_engine.muted && phase != CallPhase.ended)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Text('Микрофон выключен',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                      ),
                    const Spacer(),
                    _Controls(engine: _engine, video: video),
                    const SizedBox(height: Space.xl),
                  ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showSelf)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + Space.l,
                  right: Space.l,
                  child: const CameraSelfView(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Размер аватара на экране звонка: меньше в низком окне (ландшафт iPhone),
/// крупнее на планшете. Решает размер окна, а не модель устройства.
double _avatarSize(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.height < 500) return 72;
  return size.shortestSide >= 600 ? 148 : 116;
}

class _Controls extends StatelessWidget {
  const _Controls({required this.engine, required this.video});

  final CallEngine engine;
  final bool video;

  @override
  Widget build(BuildContext context) {
    final phase = engine.phase;
    if (phase == CallPhase.ended) return const SizedBox(height: 96);
    final buttons = <Widget>[];
    if (phase == CallPhase.incoming) {
      buttons
        ..add(_RoundButton(
          icon: Icons.call_end_rounded,
          label: 'Отклонить',
          color: const Color(0xFFE5483E),
          onTap: engine.decline,
        ))
        ..add(_RoundButton(
          icon: video ? Icons.videocam_rounded : Icons.call_rounded,
          label: 'Принять',
          color: const Color(0xFF34B36B),
          onTap: engine.accept,
        ));
    } else {
      buttons.add(_RoundButton(
        icon: engine.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        label: engine.muted ? 'Включить' : 'Микрофон',
        color: engine.muted ? Colors.white : Colors.white24,
        iconColor: engine.muted ? const Color(0xFF0B1115) : Colors.white,
        onTap: engine.toggleMute,
      ));
      if (video) {
        buttons.add(_RoundButton(
          icon: engine.cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          label: 'Камера',
          color: engine.cameraOff ? Colors.white : Colors.white24,
          iconColor: engine.cameraOff ? const Color(0xFF0B1115) : Colors.white,
          onTap: engine.toggleCamera,
        ));
      }
      buttons.add(_RoundButton(
        icon: Icons.call_end_rounded,
        label: 'Завершить',
        color: const Color(0xFFE5483E),
        onTap: engine.hangUp,
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: Space.xl,
        runSpacing: Space.l,
        children: buttons,
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: color,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(width: 68, height: 68, child: Icon(icon, color: iconColor, size: 30)),
            ),
          ),
          const SizedBox(height: Space.s),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
