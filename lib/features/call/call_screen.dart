import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../app/call_engine.dart';
import '../../app/call_video_recording.dart';
import '../../app/operator_toast.dart';
import '../../app/services.dart';
import '../../core/design/colors.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/pressable.dart';
import '../../data/models/call_record.dart';
import '../media/media_kinds.dart';
import 'camera_self_view.dart';

/// Экран звонка всегда тёмный (на съёмке нет бликов), независимо от темы
/// приложения. Фон и главные действия берутся из общей палитры.
final Color _callBackground = ReplikaColors.dark.chatBackground;
const Color _endColor = Palette.danger;
const Color _acceptColor = Palette.success;

/// Экран постановочного звонка. Закрывается сам, когда звонок убран.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  late final CallEngine _engine = Services.read(context).callEngine;
  bool _closing = false;

  // Камера: кнопка «Перевернуть» (фронтальная ↔ основная).
  final CameraSelfController _camera = CameraSelfController();

  // Автозапись видеозвонка в один mp4 (экран Replika → галерея).
  CallVideoRecording? _recording;
  bool _recordingClosed = false;
  Timer? _stopTimer;

  // Материалы собеседника в разговоре.
  AudioPlayer? _voice;
  VideoPlayerController? _video;
  String? _voicePath;
  String? _videoPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera.addListener(_onCameraChange);
    _engine.addListener(_onChange);
    _syncPeerMedia();
    _syncRecording();
    _darkScreens = Services.read(context).darkScreens;
    final dark = _darkScreens!;
    scheduleMicrotask(() => dark.value++);
  }

  ValueNotifier<int>? _darkScreens;

  void _onCameraChange() {
    if (mounted) setState(() {});
  }

  /// Запись идёт, пока звонок идёт на экране: старт — при соединении,
  /// остановка — вскоре после завершения (в видео попадает «Звонок завершён»).
  void _syncRecording() {
    if (_recordingClosed || _engine.session?.kind != CallKind.video) return;
    switch (_engine.phase) {
      case CallPhase.connecting:
      case CallPhase.active:
        if (_recording == null) {
          final recording = CallVideoRecording();
          _recording = recording;
          unawaited(recording.start());
        }
      case CallPhase.ended:
        _stopTimer ??= Timer(const Duration(milliseconds: 900), _closeRecording);
      case CallPhase.idle:
        _closeRecording();
      case CallPhase.incoming:
      case CallPhase.outgoing:
        break;
    }
  }

  /// Останавливает и закрывает запись ровно один раз и сохраняет видео в галерею.
  void _closeRecording() {
    _stopTimer?.cancel();
    _stopTimer = null;
    if (_recordingClosed) return;
    _recordingClosed = true;
    final recording = _recording;
    if (recording == null) return;
    unawaited(recording.stopAndSave().then(_reportRecording));
  }

  void _reportRecording(CallRecordingResult result) {
    switch (result.outcome) {
      case CallRecordingOutcome.savedLocally:
        showOperatorToast('Видео звонка сохранено в папке приложения: в галерею записать не удалось');
      case CallRecordingOutcome.failed:
        showOperatorToast('Запись видеозвонка не сохранилась');
      case CallRecordingOutcome.savedToGallery:
      case CallRecordingOutcome.nothing:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Свёрнутое приложение не может снимать камеру, поэтому запись закрываем
    // сразу и целиком (файл не бывает битым). inactive не считаем: так
    // выглядят системные окна разрешений. Пока запись только стартует
    // (системное окно «Начать запись»), тоже ничего не закрываем.
    if (state == AppLifecycleState.paused && _recording?.starting != true) {
      _closeRecording();
    }
  }

  void _onChange() {
    _syncRecording();
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
    _closeRecording();
    WidgetsBinding.instance.removeObserver(this);
    _camera.removeListener(_onCameraChange);
    _camera.dispose();
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
    if (session == null) return Scaffold(backgroundColor: _callBackground);
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
          backgroundColor: _callBackground,
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
                            colors: [tone.withValues(alpha: 0.55), _callBackground],
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 28, height: 1.2, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    // Значок вида звонка (голос / видео) рядом со статусом:
                    // тип звонка читается и без текста.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (phase != CallPhase.ended) ...[
                          Icon(
                            video ? AppIcons.video : AppIcons.call,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: Space.xs + 2),
                        ],
                        Flexible(
                          child: Text(
                            _status(session),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 16,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_engine.muted && phase != CallPhase.ended)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Text('Микрофон выключен',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                      ),
                    const Spacer(),
                    _Controls(
                      engine: _engine,
                      video: video,
                      onFlip: video && showSelf && _camera.canFlip ? _camera.flip : null,
                      flipToRear: _camera.isFront,
                    ),
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
                  child: CameraSelfView(controller: _camera),
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
  const _Controls({required this.engine, required this.video, this.onFlip, this.flipToRear = true});

  final CallEngine engine;
  final bool video;

  /// Переключить камеру; null — кнопки нет (аудиозвонок, камера выключена или у телефона одна камера).
  final VoidCallback? onFlip;
  final bool flipToRear;

  @override
  Widget build(BuildContext context) {
    final phase = engine.phase;
    if (phase == CallPhase.ended) return const SizedBox(height: 96);
    final buttons = <Widget>[];
    if (phase == CallPhase.incoming) {
      buttons
        ..add(_RoundButton(
          icon: AppIcons.callEnd,
          label: 'Отклонить',
          color: _endColor,
          onTap: engine.decline,
        ))
        ..add(_RoundButton(
          icon: video ? AppIcons.video : AppIcons.call,
          label: 'Принять',
          color: _acceptColor,
          onTap: engine.accept,
        ));
    } else {
      buttons.add(_RoundButton(
        icon: engine.muted ? AppIcons.microphoneOff : AppIcons.microphone,
        label: engine.muted ? 'Включить' : 'Микрофон',
        color: engine.muted ? Colors.white : Colors.white24,
        iconColor: engine.muted ? _callBackground : Colors.white,
        onTap: engine.toggleMute,
      ));
      if (video) {
        buttons.add(_RoundButton(
          icon: engine.cameraOff ? AppIcons.videoOff : AppIcons.video,
          label: 'Камера',
          color: engine.cameraOff ? Colors.white : Colors.white24,
          iconColor: engine.cameraOff ? _callBackground : Colors.white,
          onTap: engine.toggleCamera,
        ));
      }
      if (video && onFlip != null && phase != CallPhase.incoming) {
        buttons.add(_RoundButton(
          icon: AppIcons.cameraFlip,
          label: 'Перевернуть',
          color: Colors.white24,
          onTap: onFlip!,
        ));
      }
      buttons.add(_RoundButton(
        icon: AppIcons.callEnd,
        label: 'Завершить',
        color: _endColor,
        onTap: engine.hangUp,
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: buttons.length > 3 ? 0 : Space.xl,
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
    // Область нажатия 88 × ~100 px, кнопка 68 px; вместо Material-волны —
    // короткое сжатие (Pressable). Подпись читается скринридером как кнопка.
    return Pressable(
      tint: false,
      scale: 0.94,
      onTap: onTap,
      semanticsLabel: label,
      child: SizedBox(
        width: 88,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(height: Space.s),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
