import '../../core/util/db_values.dart';

/// Виртуальный телефон (точка зрения): «Телефон Максима», «Телефон мамы»…
/// У каждого телефона свой владелец-персонаж, свои контакты и чаты.
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.ownerCharacterId,
    this.sortOrder = 0,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String ownerCharacterId;
  final int sortOrder;
  final DateTime createdAt;

  factory Device.fromRow(Map<String, Object?> row) => Device(
        id: row['id'] as String,
        name: readString(row, 'name'),
        ownerCharacterId: row['owner_character_id'] as String,
        sortOrder: readInt(row, 'sort_order'),
        createdAt: intToDate(row['created_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'owner_character_id': ownerCharacterId,
        'sort_order': sortOrder,
        'created_at': dateToInt(createdAt),
      };
}
