import '../../core/util/db_values.dart';
import '../../core/util/json.dart';

/// Персонаж. Существует один раз на весь проект; на каждом виртуальном
/// телефоне он может быть записан под своим именем (см. Contact).
class Character {
  const Character({
    required this.id,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.description = '',
    this.avatarMediaId,
    this.avatarTone,
    this.statusText = '',
    this.extra = const {},
    this.behavior = const {},
    this.callAudioMediaId,
    this.callVideoMediaId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String description;
  final String? avatarMediaId;

  /// Индекс фирменного тона аватара-инициалов (AvatarTones).
  final int? avatarTone;

  /// Как статус виден собеседнику: «в сети», «был недавно»…
  final String statusText;

  /// Дополнительные данные профиля (день рождения, почта и т.п.).
  final Map<String, Object?> extra;

  /// Настройки поведения персонажа для сцен и импровизации
  /// (скорость печати, задержки ответов). Используются с Этапа 4.
  final Map<String, Object?> behavior;

  /// Материалы для постановочных звонков (Этап 7).
  final String? callAudioMediaId;
  final String? callVideoMediaId;

  final DateTime createdAt;
  final DateTime updatedAt;

  String get fullName => '$firstName $lastName'.trim();

  bool get isOnline => statusText.trim().toLowerCase() == 'в сети';

  factory Character.fromRow(Map<String, Object?> row) => Character(
        id: row['id'] as String,
        firstName: readString(row, 'first_name'),
        lastName: readString(row, 'last_name'),
        phone: readString(row, 'phone'),
        description: readString(row, 'description'),
        avatarMediaId: readStringOrNull(row, 'avatar_media_id'),
        avatarTone: readIntOrNull(row, 'avatar_tone'),
        statusText: readString(row, 'status_text'),
        extra: decodeJsonMap(readStringOrNull(row, 'extra_json')),
        behavior: decodeJsonMap(readStringOrNull(row, 'behavior_json')),
        callAudioMediaId: readStringOrNull(row, 'call_audio_media_id'),
        callVideoMediaId: readStringOrNull(row, 'call_video_media_id'),
        createdAt: intToDate(row['created_at']),
        updatedAt: intToDate(row['updated_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'description': description,
        'avatar_media_id': avatarMediaId,
        'avatar_tone': avatarTone,
        'status_text': statusText,
        'extra_json': encodeJsonMap(extra),
        'behavior_json': encodeJsonMap(behavior),
        'call_audio_media_id': callAudioMediaId,
        'call_video_media_id': callVideoMediaId,
        'created_at': dateToInt(createdAt),
        'updated_at': dateToInt(updatedAt),
      };
}
