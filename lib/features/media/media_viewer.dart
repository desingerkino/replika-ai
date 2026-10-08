import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../data/models/media_item.dart';
import 'media_kinds.dart';

Future<void> openPhotoViewer(BuildContext context, MediaItem media) =>
    Navigator.of(context).push<void>(_fadeRoute(PhotoViewerScreen(media: media)));

Future<void> openVideoViewer(BuildContext context, MediaItem media) =>
    Navigator.of(context).push<void>(_fadeRoute(VideoViewerScreen(media: media)));

/// Прозрачный маршрут: при смахивании вниз сквозь затухающий фон видно чат.
PageRoute<void> _fadeRoute(Widget screen) => PageRouteBuilder<void>(
      opaque: false,
      barrierColor: MediaPalette.transparent,
      transitionDuration: Motion.normal,
      reverseTransitionDuration: Motion.fast,
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );

const SystemUiOverlayStyle _darkOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// Размер, в который [content] вписывается в [box] целиком, без обрезки
/// и искажений (как BoxFit.contain). Пустой размер — весь [box].
@visibleForTesting
Size fitContain(Size content, Size box) {
  if (content.width <= 0 || content.height <= 0 || box.width <= 0 || box.height <= 0) return box;
  final scale = math.min(box.width / content.width, box.height / content.height);
  return Size(content.width * scale, content.height * scale);
}

/// Общая «рамка» полноэкранного просмотра: тёмный фон на весь экран,
/// кнопка закрытия, касание прячет и показывает элементы управления,
/// смахивание вниз (или вверх) закрывает. Закрыть можно и системной
/// кнопкой «Назад».
class _ViewerFrame extends StatefulWidget {
  const _ViewerFrame({required this.child, this.bottom, this.center, this.canDismiss});

  final Widget child;
  final Widget? bottom;

  /// Поверх содержимого по центру (кнопка «Воспроизвести»).
  final Widget? center;

  /// Можно ли сейчас смахнуть (фото не увеличено).
  final ValueListenable<bool>? canDismiss;

  @override
  State<_ViewerFrame> createState() => _ViewerFrameState();
}

class _ViewerFrameState extends State<_ViewerFrame> with SingleTickerProviderStateMixin {
  bool _chrome = true;
  ValueNotifier<int>? _darkScreens;
  double _drag = 0;
  late final AnimationController _back = AnimationController(vsync: this, duration: Motion.fast)
    ..addListener(() => setState(() => _drag = _dragFrom * (1 - Curves.easeOut.transform(_back.value))));
  double _dragFrom = 0;

  static const double _dismissDistance = 120;

  @override
  void initState() {
    super.initState();
    _darkScreens = Services.read(context).darkScreens;
    final dark = _darkScreens!;
    scheduleMicrotask(() => dark.value++);
  }

  @override
  void dispose() {
    _back.dispose();
    final dark = _darkScreens;
    if (dark != null) scheduleMicrotask(() => dark.value = dark.value > 0 ? dark.value - 1 : 0);
    super.dispose();
  }

  void _dragUpdate(DragUpdateDetails d) {
    _back.stop();
    setState(() => _drag += d.delta.dy);
  }

  void _dragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (_drag.abs() > _dismissDistance || (velocity.abs() > 900 && _drag.abs() > 24)) {
      Navigator.of(context).maybePop();
      return;
    }
    _dragFrom = _drag;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final canDismiss = widget.canDismiss;
    if (canDismiss == null) return _frame(context, true);
    return ValueListenableBuilder<bool>(
      valueListenable: canDismiss,
      builder: (context, dismissible, _) => _frame(context, dismissible),
    );
  }

  /// [dismissible] — смахивание закрывает; иначе (фото увеличено)
  /// вертикальные жесты отдаются перемещению картинки.
  Widget _frame(BuildContext context, bool dismissible) {
    final height = MediaQuery.sizeOf(context).height;
    final progress = (_drag.abs() / (height * 0.5)).clamp(0.0, 1.0);
    final chrome = _chrome && _drag == 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _darkOverlay,
      child: Scaffold(
        backgroundColor: MediaPalette.background.withValues(alpha: 1 - progress * 0.85),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _chrome = !_chrome),
          onVerticalDragUpdate: dismissible ? _dragUpdate : null,
          onVerticalDragEnd: dismissible ? _dragEnd : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: Offset(0, _drag),
                child: Transform.scale(scale: 1 - progress * 0.15, child: widget.child),
              ),
              if (widget.center != null && _drag == 0) Center(child: widget.center),
              Positioned(
                left: 0,
                top: 0,
                child: IgnorePointer(
                  ignoring: !chrome,
                  child: AnimatedOpacity(
                    opacity: chrome ? 1 : 0,
                    duration: Motion.fast,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xs),
                        child: IconButton(
                          tooltip: 'Закрыть',
                          style: IconButton.styleFrom(backgroundColor: MediaPalette.scrimLight),
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded, color: MediaPalette.onMedia, size: 26),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.bottom != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !chrome,
                    child: AnimatedOpacity(
                      opacity: chrome ? 1 : 0,
                      duration: Motion.fast,
                      child: widget.bottom!,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полноэкранное фото: по центру, вписано в экран целиком; щипок —
/// увеличение, двойное касание — увеличить в точке / вернуть, при
/// увеличении — перемещение.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({super.key, required this.media});

  final MediaItem media;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  final ValueNotifier<bool> _unzoomed = ValueNotifier<bool>(true);
  late final AnimationController _zoom = AnimationController(vsync: this, duration: Motion.normal)
    ..addListener(() {
      final animation = _zoomAnimation;
      if (animation != null) _transform.value = animation.value;
    });
  Animation<Matrix4>? _zoomAnimation;
  TapDownDetails? _doubleTap;

  static const double _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    _unzoomed.value = _transform.value.getMaxScaleOnAxis() <= 1.01;
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _zoom.dispose();
    _transform.dispose();
    _unzoomed.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _zoomAnimation = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOutCubic));
    _zoom.forward(from: 0);
  }

  void _onDoubleTap() {
    if (!_unzoomed.value) {
      _animateTo(Matrix4.identity());
      return;
    }
    final point = _doubleTap?.localPosition ?? Offset.zero;
    // Увеличение вокруг точки касания.
    final target = Matrix4.diagonal3Values(_doubleTapScale, _doubleTapScale, 1)
      ..setTranslationRaw(-point.dx * (_doubleTapScale - 1), -point.dy * (_doubleTapScale - 1), 0);
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return _ViewerFrame(
      canDismiss: _unzoomed,
      child: GestureDetector(
        onDoubleTapDown: (d) => _doubleTap = d,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 5,
          child: SizedBox.expand(
            child: Semantics(
              image: true,
              label: 'Фото. Двойное касание — увеличить',
              child: Image.file(
                File(widget.media.path),
                fit: BoxFit.contain,
                alignment: Alignment.center,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => const Center(
                  child: Text(
                    'Не удалось открыть фото',
                    style: TextStyle(color: MediaPalette.onMediaDim),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Полноэкранное видео: своё отображение (не миниатюра из чата), видео
/// вписано в экран с правильными пропорциями на тёмном фоне; пауза,
/// перемотка, текущее время и длительность.
class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({super.key, required this.media});

  final MediaItem media;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final VideoPlayerController _controller = VideoPlayerController.file(File(widget.media.path));
  bool _failed = false;

  /// Перемотка пальцем: пока тянут, показываем позицию ползунка.
  double? _scrub;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    unawaited(Services.read(context).audio.stop());
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
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _togglePlay() {
    final value = _controller.value;
    if (!value.isInitialized) return;
    if (value.isPlaying) {
      unawaited(_controller.pause());
    } else {
      if (value.duration > Duration.zero && value.position >= value.duration) {
        unawaited(_controller.seekTo(Duration.zero));
      }
      unawaited(_controller.play());
    }
  }

  Duration _at(double fraction) =>
      Duration(milliseconds: (_controller.value.duration.inMilliseconds * fraction).round());

  /// Размер кадра, как его сообщает плеер (поворот записи плеер уже учёл).
  Size _frameSize(VideoPlayerValue value) => value.size;

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    Widget content;
    if (_failed) {
      content = const Center(
        child: Text('Не удалось открыть видео', style: TextStyle(color: MediaPalette.onMediaDim)),
      );
    } else if (!value.isInitialized) {
      content = const Center(child: CircularProgressIndicator(color: MediaPalette.onMedia));
    } else {
      final frame = _frameSize(value);
      content = LayoutBuilder(
        builder: (context, constraints) {
          final fitted = fitContain(frame, constraints.biggest);
          return Center(
            child: SizedBox(
              width: fitted.width,
              height: fitted.height,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: frame.width > 0 ? frame.width : fitted.width,
                  height: frame.height > 0 ? frame.height : fitted.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          );
        },
      );
    }

    final total = value.duration;
    final fraction = _scrub ??
        (total.inMilliseconds <= 0 ? 0.0 : (value.position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0));
    final shownPosition = _scrub == null ? value.position : _at(_scrub!);

    final bottom = !value.isInitialized
        ? null
        : DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xAA000000), Color(0x00000000)],
              ),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: Space.s),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.s, Space.xl, Space.l, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: value.isPlaying ? 'Пауза' : 'Воспроизвести',
                      onPressed: _togglePlay,
                      icon: Icon(
                        value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: MediaPalette.onMedia,
                        size: 32,
                      ),
                    ),
                    _Time(formatDuration(shownPosition)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: MediaPalette.onMedia,
                          inactiveTrackColor: const Color(0x44FFFFFF),
                          thumbColor: MediaPalette.onMedia,
                          overlayColor: const Color(0x22FFFFFF),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        ),
                        child: Slider(
                          value: fraction,
                          semanticFormatterCallback: (_) => formatDuration(shownPosition),
                          onChangeStart: (f) {
                            _wasPlaying = value.isPlaying;
                            unawaited(_controller.pause());
                            setState(() => _scrub = f);
                          },
                          onChanged: (f) => setState(() => _scrub = f),
                          onChangeEnd: (f) async {
                            await _controller.seekTo(_at(f));
                            if (!mounted) return;
                            setState(() => _scrub = null);
                            if (_wasPlaying) unawaited(_controller.play());
                          },
                        ),
                      ),
                    ),
                    _Time(formatDuration(total)),
                  ],
                ),
              ),
            ),
          );

    final center = value.isInitialized && !value.isPlaying && _scrub == null
        ? Material(
            color: MediaPalette.scrim,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _togglePlay,
              child: const SizedBox(
                width: 72,
                height: 72,
                child: Icon(Icons.play_arrow_rounded, color: MediaPalette.onMedia, size: 44, semanticLabel: 'Воспроизвести'),
              ),
            ),
          )
        : null;

    return _ViewerFrame(bottom: bottom, center: center, child: content);
  }
}

class _Time extends StatelessWidget {
  const _Time(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: MediaPalette.onMedia,
          fontSize: 13,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
}
