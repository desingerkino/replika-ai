import 'dart:io';

import 'package:flutter/material.dart';

import '../context.dart';
import '../tokens.dart';
import 'story_ring.dart';

export 'story_ring.dart' show StoryRing;

/// Инициалы: «Алексей Громов» → «АГ», «Мама» → «М».
String initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  String first(String word) =>
      String.fromCharCodes(word.runes.take(1)).toUpperCase();
  if (parts.length == 1) return first(parts.first);
  return first(parts[0]) + first(parts[1]);
}

/// Аватар: фото из медиатеки или инициалы на фирменном тоне.
///
/// Кольцо ([ring]) рисуется снаружи [size] и не меняет размер аватара:
/// вокруг нужно оставить [ringExtent] свободного места.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.size = Sizes.avatarList,
    this.imagePath,
    this.tone,
    this.online = false,
    this.ring = StoryRing.none,
  });

  /// Толщина кольца и зазор между кольцом и фото.
  static const double ringWidth = 3.5;
  static const double ringGap = 2;

  /// Сколько места кольцо занимает снаружи фото с каждой стороны.
  static const double ringExtent = ringWidth + ringGap;

  final String name;
  final double size;
  final String? imagePath;

  /// Индекс тона из AvatarTones; если не задан — выбирается по имени.
  final int? tone;
  final bool online;
  final StoryRing ring;

  @override
  Widget build(BuildContext context) {
    final color = tone != null ? AvatarTones.at(tone!) : AvatarTones.forKey(name);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(
          initialsOf(name),
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            height: 1,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );

    Widget picture = fallback;
    final path = imagePath;
    if (path != null && path.isNotEmpty) {
      final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
      picture = ClipOval(
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cachePx,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      );
    }

    final dot = size * 0.26;
    return Semantics(
      label: name,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (ring != StoryRing.none)
              Positioned(
                left: -ringExtent,
                top: -ringExtent,
                right: -ringExtent,
                bottom: -ringExtent,
                child: IgnorePointer(
                  child: StoryRingView(
                    ring: ring,
                    width: ringWidth,
                    viewedColor: context.rc.storyViewed,
                  ),
                ),
              ),
            Positioned.fill(child: picture),
            if (online)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: context.rc.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.cs.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
