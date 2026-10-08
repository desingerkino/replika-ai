import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/widgets/avatar.dart';

/// Аватар с кольцом истории: цветное — есть новые, серое — всё просмотрено.
/// [adding] — значок «+» (своя история).
class StoryAvatar extends StatelessWidget {
  const StoryAvatar({
    super.key,
    required this.name,
    this.imagePath,
    this.tone,
    this.size = 64,
    this.unseen = false,
    this.hasStories = true,
    this.adding = false,
  });

  final String name;
  final String? imagePath;
  final int? tone;
  final double size;
  final bool unseen;

  /// Нет историй — кольцо не рисуется.
  final bool hasStories;
  final bool adding;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final ring = size * 0.045 + 1;
    final gap = size * 0.05;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasStories)
            Positioned.fill(
              child: CustomPaint(
                painter: _RingPainter(
                  width: ring,
                  colors: unseen ? [rc.storyRingStart, rc.storyRingEnd, rc.storyRingStart] : [rc.storySeen, rc.storySeen],
                ),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(ring + gap),
              child: Avatar(name: name, imagePath: imagePath, tone: tone, size: size - 2 * (ring + gap)),
            ),
          ),
          if (adding)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.32,
                height: size * 0.32,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                child: Icon(Icons.add_rounded, size: size * 0.22, color: cs.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.width, required this.colors});

  final double width;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(
        colors: colors,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.width != width || oldDelegate.colors != colors;
}
