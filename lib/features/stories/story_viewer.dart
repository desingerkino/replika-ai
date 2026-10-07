import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/services.dart';
import '../../app/story_store.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../data/models/media_item.dart';
import '../media/fitted_media.dart';

/// Полноэкранный просмотр историй контакта.
Future<void> openStoryViewer(
  BuildContext context, {
  required String characterId,
  required String name,
  String? avatarPath,
  int? avatarTone,
}) {
  return Navigator.of(context).push<void>(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: Motion.normal,
    reverseTransitionDuration: Motion.fast,
    pageBuilder: (_, __, ___) => StoryViewerScreen(
      characterId: characterId,
      name: name,
      avatarPath: avatarPath,
      avatarTone: avatarTone,
    ),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
  ));
}

/// Сколько показывается фото.
const Duration storyPhotoDuration = Duration(seconds: 5);

const SystemUiOverlayStyle _darkOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// Истории: сегменты прогресса сверху, касание слева — назад, справа — вперёд,
/// удержание — пауза, свайп вниз — закрыть. Просмотренная история
/// помечается сразу при показе.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.characterId,
    required this.name,
    this.avatarPath,
    this.avatarTone,
  });

  final String characterId;
  final String name;
  final String? avatarPath;
  final int? avatarTone;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this, duration: storyPhotoDuration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _next();
    });

  late final AppServices _services = Services.read(context);
  late final List<Story> _stories = _services.stories.of(widget.characterId);
  int _index = 0;
  MediaItem? _media;
  VideoPlayerController? _video;
  bool _failed = false;
  bool _paused = false;
  int _token = 0;
  ValueNotifier<int>? _darkScreens;

  @override
  void initState() {
    super.initState();
    final dark = _darkScreens = _services.darkScreens;
    scheduleMicrotask(() => dark.value++);
    unawaited(_services.audio.stop());
    if (_stories.isEmpty) {
      scheduleMicrotask(() {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else {
      _index = _services.stories.firstUnviewedIndex(widget.characterId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_show(_index));
      });
    }
  }

  @override
  void dispose() {
    _token++;
    _progress.dispose();
    _video?.dispose();
    final dark = _darkScreens;
    if (dark != null) scheduleMicrotask(() => dark.value = dark.value > 0 ? dark.value - 1 : 0);
    super.dispose();
  }

  Future<void> _show(int index) async {
    final token = ++_token;
    _progress
      ..stop()
      ..value = 0;
    final oldVideo = _video;
    _video = null;
    setState(() {
      _index = index;
      _media = null;
      _failed = false;
    });
    await oldVideo?.dispose();
    final story = _stories[index];
    final media = await _services.media.repository.byId(story.mediaId);
    if (!mounted || token != _token) return;
    if (media == null || !File(media.path).existsSync()) {
      // Файл удалён из медиатеки: эту историю пропускаем.
      setState(() => _failed = true);
      _progress.duration = const Duration(seconds: 2);
      if (!_paused) unawaited(_progress.forward());
      return;
    }
    unawaited(_services.stories.markViewed(widget.characterId, story.mediaId));
    if (story.kind == MediaKind.video) {
      final controller = VideoPlayerController.file(File(media.path));
      try {
        await controller.initialize();
      } catch (error) {
        debugPrint('История не открылась: $error');
        await controller.dispose();
        if (mounted && token == _token) {
          setState(() => _failed = true);
          _progress.duration = const Duration(seconds: 2);
          if (!_paused) unawaited(_progress.forward());
        }
        return;
      }
      if (!mounted || token != _token) {
        await controller.dispose();
        return;
      }
      _video = controller;
      final length = controller.value.duration;
      _progress.duration = length > Duration.zero ? length : storyPhotoDuration;
      setState(() => _media = media);
      if (!_paused) {
        unawaited(controller.play());
        unawaited(_progress.forward());
      }
    } else {
      _progress.duration = storyPhotoDuration;
      setState(() => _media = media);
      if (!_paused) unawaited(_progress.forward());
    }
  }

  void _next() {
    if (!mounted) return;
    if (_index >= _stories.length - 1) {
      Navigator.of(context).maybePop();
    } else {
      unawaited(_show(_index + 1));
    }
  }

  void _previous() {
    unawaited(_show(_index > 0 ? _index - 1 : 0));
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _progress.stop();
    unawaited(_video?.pause());
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    if (_media != null || _failed) unawaited(_progress.forward());
    unawaited(_video?.play());
  }

  void _onTapUp(TapUpDetails details, double width) {
    if (details.localPosition.dx < width / 3) {
      _previous();
    } else {
      _next();
    }
  }

  Widget _content() {
    final media = _media;
    if (_failed) {
      return const Center(
        child: Text('История недоступна', style: TextStyle(color: Colors.white70)),
      );
    }
    if (media == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final video = _video;
    if (video != null) {
      // Размер кадра читается из контроллера при каждом его изменении:
      // если плеер уточнит размер после запуска, раскладка обновится.
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: video,
        builder: (context, value, _) => FittedContent(size: value.size, child: VideoPlayer(video)),
      );
    }
    return FittedPhoto(image: FileImage(File(media.path)));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _darkOverlay,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _onTapUp(details, constraints.maxWidth),
            onLongPressStart: (_) => _pause(),
            onLongPressEnd: (_) => _resume(),
            onLongPressCancel: _resume,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
            },
            child: FullscreenStage(
              content: SafeArea(child: _content()),
              overlays: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.xs, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Segments(count: _stories.length, index: _index, progress: _progress),
                        const SizedBox(height: Space.s),
                        Row(
                          children: [
                            Avatar(
                              name: widget.name,
                              size: 36,
                              imagePath: widget.avatarPath,
                              tone: widget.avatarTone,
                            ),
                            const SizedBox(width: Space.s),
                            Expanded(
                              child: Text(
                                widget.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Закрыть',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(AppIcons.clear, color: Colors.white, size: 26),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Сегменты прогресса: пройденные залиты, текущий заполняется, остальные пустые.
class _Segments extends StatelessWidget {
  const _Segments({required this.count, required this.index, required this.progress});

  final int count;
  final int index;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) => Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: i < index ? 1 : (i == index ? progress.value : 0),
                  color: Colors.white,
                  backgroundColor: Colors.white30,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
