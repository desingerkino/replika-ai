import '../../core/util/db_values.dart';
import 'character.dart';
import '../../core/util/media_paths.dart';

/// Персонаж так, как он записан в контактах конкретного телефона.
/// Например, Вероника Лебедева на телефоне Максима — «Красотка».
class Contact {
  const Contact({
    required this.character,
    required this.displayName,
    this.favorite = false,
    this.avatarPath,
    this.saved = true,
  });

  final Character character;
  final String displayName;
  final bool favorite;
  final String? avatarPath;

  /// false — персонаж не записан в контактах этого телефона
  /// (например, контакт удалили, а переписка осталась).
  final bool saved;

  String get id => character.id;

  /// Строка запроса: characters.* + display_name, favorite, avatar_path.
  factory Contact.fromRow(Map<String, Object?> row) => Contact(
        character: Character.fromRow(row),
        displayName: readString(row, 'display_name'),
        favorite: intToBool(row['favorite']),
        avatarPath: MediaPaths.resolveOrNull(readStringOrNull(row, 'avatar_path')),
        saved: row['display_name'] != null,
      );

  /// Имя для показа: как записан, иначе номер, иначе настоящее имя.
  String get shownName {
    if (saved && displayName.trim().isNotEmpty) return displayName;
    if (character.phone.trim().isNotEmpty) return character.phone;
    final full = character.fullName;
    return full.isEmpty ? 'Без имени' : full;
  }
}
