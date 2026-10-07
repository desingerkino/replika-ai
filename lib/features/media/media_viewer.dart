import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/services.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../data/models/media_item.dart';
import 'fitted_media.dart';
import 'media_kinds.dart';

Future<void> openPhotoViewer(BuildContext context, MediaItem media) =>
    Navigator.of(context).push<void>(_fadeRoute(PhotoViewerScreen(media: media)));

Future<void> openVideoViewer(BuildContext context, MediaItem media) =>
    Navigator.of(context).push<void>(_fadeRoute(VideoViewerScreen(media: media)));

PageRoute<void> _fadeRoute(Widget screen) => PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Motion.normal,
      reverseTransitionDuration: Motion.fast,
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );

const SystemUiOverlayStyle _darkOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// Общая «рамка» просмотрщика: чёрный фон, кнопка закрытия,
/// касание прячет и показывает элементы управления.
class _ViewerFrame extends StatefulWidget {
  const _ViewerFrame({required this.child, this.bottom});

  final Widget child;
  final Widget? bottom;

  @override
  State<_ViewerFrame> createState() => _ViewerFrameState();
}

class _ViewerFrameState extends State<_ViewerFrame> {
  bool _chrome = true;
  ValueNotifier<int>? _darkScreens;

  @override
  void initState() {
    super.initState();
    _darkScreens = Services.read(context).darkScreens;
    final dark = _darkScreens!;
    scheduleMicrotask(() => dark.value++);
  }

  @override
  void dispose() {
    final dark = _darkScreens;
    if (dark != null) scheduleMicrotask(() => dark.value = dark.value > 0 ? dark.value - 1 : 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _darkOverlay,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _chrome = !_chrome),
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: Motion.fast,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xs),
                    child: IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(AppIcons.clear, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
              if (widget.bottom != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _chrome ? 1 : 0,
                    duration: Motion.fast,
                    child: SafeArea(top: false, child: widget.bottom!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    // Размер берётся из области просмотра, а не из файла (см. FittedPhoto).
    return _ViewerFrame(
      child: SafeArea(
        child: FittedPhoto(image: FileImage(File(media.path)), zoomable: true),
      ),
    );
  }
}

class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({super.key, required this.media});

  final MediaItem media;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final VideoPlayerController _controller =
      VideoPlayerController.file(File(widget.media.path));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    Services.read(context).audio.stop();
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      unawaited(_controller.play());
    }).catchError((Object error) {
      debugPrint('Видео не открылось: $error');
      if (mounted) setState(() => _failed = true);
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final value = _controller.value;
    if (!value.isInitialized) return;
    if (value.isPlaying) {
      _controller.pause();
    } else {
      if (value.position >= value.duration) _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    Widget content;
    if (_failed) {
      content = const Center(
        child: Text('Не удалось открыть видео', style: TextStyle(color: Colors.white70)),
      );
    } else if (!value.isInitialized) {
      content = const Center(child: CircularProgressIndicator(color: Colors.white));
    } else {
      content = SafeArea(
        child: FittedContent(size: value.size, child: VideoPlayer(_controller)),
      );
    }

    final bottom = !value.isInitialized
        ? null
        : Container(
            padding: const EdgeInsets.fromLTRB(Space.s, Space.xl, Space.l, Space.m),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xAA000000), Color(0x00000000)],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? 'Пауза' : 'Воспроизвести',
                  onPressed: _togglePlay,
                  icon: Icon(
                    value.isPlaying ? AppIcons.pause : AppIcons.play,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                Text(
                  formatDuration(value.position),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: Space.m),
                    colors: const VideoProgressColors(
                      playedColor: Palette.tungsten,
                      bufferedColor: Color(0x55FFFFFF),
                      backgroundColor: Color(0x33FFFFFF),
                    ),
                  ),
                ),
                const SizedBox(width: Space.m),
                Text(
                  formatDuration(value.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          );

    return _ViewerFrame(bottom: bottom, child: content);
  }
}
