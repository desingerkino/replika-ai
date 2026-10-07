import 'package:flutter/material.dart';

/// Размер области просмотра: ограничения родителя, а при их отсутствии — экран.
/// Размер самого файла (и превью) в раскладке не участвует.
Size viewportFor(BuildContext context, BoxConstraints constraints) {
  final screen = MediaQuery.sizeOf(context);
  return Size(
    constraints.hasBoundedWidth ? constraints.maxWidth : screen.width,
    constraints.hasBoundedHeight ? constraints.maxHeight : screen.height,
  );
}

/// Фото на весь доступный экран с сохранением пропорций (BoxFit.contain:
/// и маленькое превью увеличивается, и большое фото уменьшается).
/// Общий для просмотра сообщений и историй.
class FittedPhoto extends StatelessWidget {
  const FittedPhoto({
    super.key,
    required this.image,
    this.zoomable = false,
    this.errorText = 'Не удалось открыть фото',
  });

  final ImageProvider image;

  /// Щипок и перемещение (просмотр сообщений). В историях касания заняты.
  final bool zoomable;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = viewportFor(context, constraints);
        final photo = SizedBox(
          width: view.width,
          height: view.height,
          child: Image(
            image: image,
            width: view.width,
            height: view.height,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => Center(
              child: Text(errorText, style: const TextStyle(color: Colors.white70)),
            ),
          ),
        );
        if (!zoomable) return photo;
        return InteractiveViewer(minScale: 1, maxScale: 5, child: photo);
      },
    );
  }
}

/// Любое содержимое с собственным размером (видео) по центру на весь экран,
/// пропорции сохраняются. [size] — реальный размер кадра; пока он неизвестен
/// (нулевой), берётся 16:9.
class FittedContent extends StatelessWidget {
  const FittedContent({super.key, required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final valid = size.width > 0 && size.height > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = viewportFor(context, constraints);
        return SizedBox(
          width: view.width,
          height: view.height,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: SizedBox(
              width: valid ? size.width : 1600,
              height: valid ? size.height : 900,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
