import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/repositories/settings_repository.dart';

/// Архив чатов: какие чаты убраны с главного списка в «Архив».
///
/// Хранится списком идентификаторов в настройках (одна запись JSON), схема
/// базы не меняется. Сам чат, его сообщения и счётчики остаются как были —
/// архив влияет только на то, под каким фильтром чат показан.
class ChatArchive extends ChangeNotifier {
  ChatArchive(this._settings);

  final SettingsRepository _settings;
  Set<String> _ids = <String>{};

  /// Идентификаторы архивных чатов.
  Set<String> get ids => Set<String>.unmodifiable(_ids);

  bool contains(String chatId) => _ids.contains(chatId);

  /// Читает сохранённый архив (вызывается при запуске).
  Future<void> load() async {
    _ids = parse(await _settings.getValue(SettingKeys.archivedChats));
    notifyListeners();
  }

  /// Разбор сохранённого JSON; повреждённая запись даёт пустой архив.
  @visibleForTesting
  static Set<String> parse(String? raw) {
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> setArchived(String chatId, bool archived) async {
    final changed = archived ? _ids.add(chatId) : _ids.remove(chatId);
    if (!changed) return;
    notifyListeners();
    await _settings.setValue(SettingKeys.archivedChats, jsonEncode(_ids.toList()..sort()));
  }
}
