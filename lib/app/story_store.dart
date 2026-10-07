import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/models/media_item.dart';
import '../data/repositories/settings_repository.dart';

/// Одна история контакта: фото или видео из медиатеки.
@immutable
class Story {
  const Story({
    required this.mediaId,
    required this.kind,
    required this.addedAt,
    this.viewed = false,
  });

  final String mediaId;

  /// [MediaKind.photo] или [MediaKind.video].
  final MediaKind kind;
  final DateTime addedAt;
  final bool viewed;

  Story copyWith({bool? viewed}) =>
      Story(mediaId: mediaId, kind: kind, addedAt: addedAt, viewed: viewed ?? this.viewed);

  Map<String, Object?> toJson() => {
        'mediaId': mediaId,
        'kind': kind.name,
        'addedAt': addedAt.millisecondsSinceEpoch,
        'viewed': viewed,
      };

  static Story? fromJson(Object? json) {
    if (json is! Map) return null;
    final mediaId = json['mediaId'];
    final kindName = json['kind'];
    final at = json['addedAt'];
    if (mediaId is! String || kindName is! String || at is! int) return null;
    final kind = MediaKind.values.where((k) => k.name == kindName).firstOrNull;
    if (kind != MediaKind.photo && kind != MediaKind.video) return null;
    return Story(
      mediaId: mediaId,
      kind: kind!,
      addedAt: DateTime.fromMillisecondsSinceEpoch(at),
      viewed: json['viewed'] == true,
    );
  }
}

/// Истории контактов. Это локальная «проп-система» без сервера: список
/// историй каждого персонажа лежит в настройках приложения одним JSON, сами
/// файлы — в обычной медиатеке. Схема базы не меняется.
class StoryStore extends ChangeNotifier {
  StoryStore(this._settings);

  final SettingsRepository _settings;
  Map<String, List<Story>> _stories = {};

  /// Читает сохранённые истории (вызывается при запуске).
  Future<void> load() async {
    final raw = await _settings.getValue(SettingKeys.stories);
    _stories = parse(raw);
    notifyListeners();
  }

  /// Разбор сохранённого JSON; повреждённые записи пропускаются.
  @visibleForTesting
  static Map<String, List<Story>> parse(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, List<Story>>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! List) return;
        final list = value.map(Story.fromJson).whereType<Story>().toList();
        if (list.isNotEmpty) result[key] = list;
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Истории контакта от старых к новым.
  List<Story> of(String characterId) => List.unmodifiable(_stories[characterId] ?? const <Story>[]);

  bool has(String characterId) => (_stories[characterId] ?? const <Story>[]).isNotEmpty;

  /// Есть хотя бы одна непросмотренная история.
  bool hasUnviewed(String characterId) =>
      (_stories[characterId] ?? const <Story>[]).any((story) => !story.viewed);

  /// Индекс первой непросмотренной (с неё начинается показ); 0, если все просмотрены.
  int firstUnviewedIndex(String characterId) {
    final index = (_stories[characterId] ?? const <Story>[]).indexWhere((story) => !story.viewed);
    return index < 0 ? 0 : index;
  }

  Future<void> add(String characterId, MediaItem media) async {
    if (media.kind != MediaKind.photo && media.kind != MediaKind.video) return;
    final list = [...(_stories[characterId] ?? const <Story>[])];
    list.add(Story(mediaId: media.id, kind: media.kind, addedAt: DateTime.now()));
    _stories[characterId] = list;
    await _save();
  }

  Future<void> markViewed(String characterId, String mediaId) async {
    final list = _stories[characterId];
    if (list == null) return;
    final index = list.indexWhere((story) => story.mediaId == mediaId);
    if (index < 0 || list[index].viewed) return;
    final updated = [...list];
    updated[index] = list[index].copyWith(viewed: true);
    _stories[characterId] = updated;
    await _save();
  }

  /// Убирает все истории контакта (файлы медиатеки остаются).
  Future<void> clear(String characterId) async {
    if (_stories.remove(characterId) == null) return;
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    final json = {for (final entry in _stories.entries) entry.key: [for (final s in entry.value) s.toJson()]};
    await _settings.setValue(SettingKeys.stories, jsonEncode(json));
  }
}
