import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/services.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/util/time_format.dart';
import '../../data/models/media_item.dart';
import '../../data/models/story.dart';
import '../../data/repositories/story_repository.dart';

/// Полноэкранный просмотр историй: полоски прогресса сверху, касание
/// справа — дальше, слева — назад, удержание — пауза, смахивание вниз —
/// закрыть. Внизу — ответ автору (уходит сообщением в личный чат).
class StoryViewer extends StatefulWidget {
  const StoryViewer({
    super.key,
    required this.deviceId,
    required this.authors,
    this.startAuthor = 0,
  });

  final String deviceId;
  final List<StoryAuthor> authors;
  final int startAuthor;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  static const Duration photoDuration = Duration(seconds: 5);

  late final PageController _pages = PageController(initialPage: widget.startAuthor);
  late final AnimationController _progress = AnimationController(vsync: this, duration: photoDuration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _next();
    });
  final TextEditingController _reply = TextEditingController();
  final FocusNode _replyFocus = FocusNode();

  late int _author = widget.startAuthor;
  late int _story = widget.authors[widget.startAuthor].startIndex;
  VideoPlayerController? _video;
  double _dragDown = 0;
  bool _paused = false;

  StoryAuthor get _current => widget.authors[_author];
  Story get _currentStory => _current.stories[_story];

  @override
  void initState() {
    super.initState();
    _replyFocus.addListener(() => _setPaused(_replyFocus.hasFocus));
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    Services.read(context).darkScreens.value++;
  }

  @override
  void dispose() {
    _services?.darkScreens.value--;
    _progress.dispose();
    _video?.dispose();
    _pages.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  AppServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = Services.read(context);
  }

  Future<void> _show() async {
    if (!mounted) return;
    final story = _currentStory;
    unawaited(_services?.stories.markSeen(story.id));
    _progress.stop();
    _progress.value = 0;
    final old = _video;
    _video = null;
    await old?.dispose();
    final media = story.media;
    if (media != null && media.kind == MediaKind.video && File(media.path).existsSync()) {
      final controller = VideoPlayerController.file(File(media.path));
      _video = controller;
      try {
        await controller.initialize();
        if (!mounted || _video != controller) return;
        _progress.duration = controller.value.duration > Duration.zero ? controller.value.duration : photoDuration;
        await controller.play();
      } catch (error) {
        debugPrint('Видео истории не открылось: $error');
        _progress.duration = photoDuration;
      }
    } else {
      _progress.duration = photoDuration;
    }
    if (!mounted) return;
    setState(() {});
    if (!_paused) unawaited(_progress.forward());
  }

  void _setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    if (paused) {
      _progress.stop();
      _video?.pause();
    } else {
      unawaited(_progress.forward());
      _video?.play();
    }
  }

  void _next() {
    if (_story < _current.stories.length - 1) {
      setState(() => _story++);
      _show();
    } else if (_author < widget.authors.length - 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _previous() {
    if (_story > 0) {
      setState(() => _story--);
      _show();
    } else if (_author > 0) {
      _pages.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    } else {
      _show();
    }
  }

  void _onAuthorChanged(int index) {
    setState(() {
      _author = index;
      _story = widget.authors[index].startIndex;
    });
    _show();
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    final services = _services;
    if (text.isEmpty || services == null) return;
    _reply.clear();
    _replyFocus.unfocus();
    try {
      final device = await services.devices.byId(widget.deviceId);
      if (device == null) return;
      final chatId = await services.chats.openOrCreateDirect(
        deviceId: widget.deviceId,
        characterId: _current.characterId,
      );
      await services.messages.sendText(chatId: chatId, senderId: device.ownerCharacterId, text: text);
      unawaited(services.autoReply.onOwnerMessage(chatId));
      HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ответ отправлен')));
      }
    } catch (error) {
      debugPrint('Ответ на историю не отправлен: $error');
    }
  }

  Future<void> _delete() async {
    _setPaused(true);
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить историю?',
      message: 'История исчезнет с этого телефона.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!mounted) return;
    if (!ok) {
      _setPaused(false);
      return;
    }
    await _services?.stories.delete(_currentStory.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          onVerticalDragUpdate: (d) => setState(() => _dragDown = (_dragDown + d.delta.dy).clamp(0, 400)),
          onVerticalDragEnd: (d) {
            if (_dragDown > 120 || (d.primaryVelocity ?? 0) > 700) {
              Navigator.of(context).maybePop();
            } else {
              setState(() => _dragDown = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(0, _dragDown),
            child: Opacity(
              opacity: (1 - _dragDown / 500).clamp(0.4, 1),
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.authors.length,
                onPageChanged: _onAuthorChanged,
                itemBuilder: (context, index) {
                  final author = widget.authors[index];
                  final storyIndex = index == _author ? _story : author.startIndex;
                  final story = author.stories[storyIndex];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _StoryContent(story: story, video: index == _author ? _video : null),
                      // Касания: слева — назад, справа — дальше, удержание — пауза.
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _previous,
                              onLongPressStart: (_) => _setPaused(true),
                              onLongPressEnd: (_) => _setPaused(false),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _next,
                              onLongPressStart: (_) => _setPaused(true),
                              onLongPressEnd: (_) => _setPaused(false),
                            ),
                          ),
                        ],
                      ),
                      // Затемнение сверху и снизу — подписи читаются на любом фото.
                      const Positioned(top: 0, left: 0, right: 0, height: 160, child: _Shade(top: true)),
                      const Positioned(bottom: 0, left: 0, right: 0, height: 200, child: _Shade(top: false)),
                      Positioned(
                        top: media.padding.top + 8,
                        left: 10,
                        right: 6,
                        child: Column(
                          children: [
                            _ProgressBars(
                              count: author.stories.length,
                              index: storyIndex,
                              progress: index == _author ? _progress : null,
                            ),
                            const SizedBox(height: 10),
                            _Header(
                              author: author,
                              story: story,
                              onClose: () => Navigator.of(context).maybePop(),
                              onDelete: _delete,
                            ),
                          ],
                        ),
                      ),
                      if (story.caption.isNotEmpty)
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: media.padding.bottom + (author.isOwner ? 32 : 92),
                          child: Text(
                            story.caption,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.3, fontWeight: FontWeight.w500),
                          ),
                        ),
                      if (!author.isOwner)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: media.viewInsets.bottom > 0 ? 8 : media.padding.bottom + 12,
                          child: _ReplyField(controller: _reply, focusNode: _replyFocus, onSend: _sendReply),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryContent extends StatelessWidget {
  const _StoryContent({required this.story, this.video});

  final Story story;
  final VideoPlayerController? video;

  @override
  Widget build(BuildContext context) {
    final media = story.media;
    if (media == null || !File(media.path).existsSync()) {
      return const Center(
        child: Text('Файл истории удалён', style: TextStyle(color: Colors.white70, fontSize: 16)),
      );
    }
    if (media.kind == MediaKind.video) {
      final controller = video;
      if (controller == null || !controller.value.isInitialized) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }
      final size = controller.value.size;
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(controller)),
      );
    }
    return Image.file(
      File(media.path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) =>
          const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
    );
  }
}

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({required this.count, required this.index, this.progress});

  final int count;
  final int index;
  final Animation<double>? progress;

  static Widget _bar(double value) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 2.5,
          color: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.35),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final animation = progress;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: i == index && animation != null
                  ? AnimatedBuilder(animation: animation, builder: (context, _) => _bar(animation.value))
                  : _bar(i < index ? 1 : 0),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.author, required this.story, required this.onClose, required this.onDelete});

  final StoryAuthor author;
  final Story story;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Avatar(name: author.displayName, imagePath: author.avatarPath, tone: author.avatarTone, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                author.isOwner ? 'Моя история' : author.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                formatAgo(story.postedAt, DateTime.now()),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Удалить историю',
          onPressed: onDelete,
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
        ),
        IconButton(
          tooltip: 'Закрыть',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ],
    );
  }
}

class _Shade extends StatelessWidget {
  const _Shade({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _ReplyField extends StatelessWidget {
  const _ReplyField({required this.controller, required this.focusNode, required this.onSend});

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              color: Colors.black.withValues(alpha: 0.25),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              cursorColor: Colors.white,
              decoration: InputDecoration.collapsed(
                hintText: 'Ответить…',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => IconButton(
            tooltip: value.text.trim().isEmpty ? 'Нравится' : 'Отправить',
            onPressed: value.text.trim().isEmpty
                ? () {
                    controller.text = '❤️';
                    onSend();
                  }
                : onSend,
            icon: Icon(
              value.text.trim().isEmpty ? Icons.favorite_border_rounded : Icons.send_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }
}
