import '../../core/util/ids.dart';
import '../db/tables.dart';
import '../models/character.dart';
import '../models/device.dart';
import 'repository.dart';

class DeviceRepository extends Repository {
  DeviceRepository(super.database);

  Future<List<Device>> list() async {
    final rows = await db.query(Tables.devices, orderBy: 'sort_order, created_at');
    return rows.map(Device.fromRow).toList();
  }

  Future<String> create({required String name, required String ownerCharacterId}) async {
    final id = newId();
    final all = await list();
    await db.insert(
      Tables.devices,
      Device(
        id: id,
        name: name.trim(),
        ownerCharacterId: ownerCharacterId,
        sortOrder: all.length,
        createdAt: DateTime.now(),
      ).toRow(),
    );
    notify({Tables.devices});
    return id;
  }

  /// Новый профиль: персонаж-владелец и его пустой телефон.
  Future<String> createProfile({required String firstName, String lastName = '', String phone = ''}) async {
    final now = DateTime.now();
    final characterId = newId();
    final deviceId = newId();
    final order = (await list()).length;
    await db.transaction((txn) async {
      await txn.insert(
        Tables.characters,
        Character(
          id: characterId,
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          phone: phone.trim(),
          createdAt: now,
          updatedAt: now,
        ).toRow(),
      );
      final name = [firstName.trim(), lastName.trim()].where((s) => s.isNotEmpty).join(' ');
      await txn.insert(
        Tables.devices,
        Device(id: deviceId, name: 'Телефон: $name', ownerCharacterId: characterId, sortOrder: order, createdAt: now)
            .toRow(),
      );
    });
    notify({Tables.devices, Tables.characters});
    return deviceId;
  }

  /// Профили телефона с именами владельцев.
  Future<List<({Device device, String ownerName})>> profiles() async {
    final rows = await db.rawQuery('''
      SELECT d.*, TRIM(c.first_name || ' ' || c.last_name) AS owner_name
      FROM devices d JOIN characters c ON c.id = d.owner_character_id
      ORDER BY d.sort_order, d.created_at
    ''');
    return [
      for (final r in rows)
        (device: Device.fromRow(r), ownerName: (r['owner_name'] as String?)?.trim().isNotEmpty == true ? r['owner_name'] as String : 'Без имени'),
    ];
  }

  /// Удалить профиль целиком (контакты, чаты, сообщения, звонки, сцены).
  Future<void> delete(String id) async {
    await db.delete(Tables.scenes, where: 'device_id = ?', whereArgs: [id]);
    await db.delete(Tables.devices, where: 'id = ?', whereArgs: [id]);
    notify({Tables.devices, Tables.chats, Tables.messages, Tables.deviceContacts, Tables.calls, Tables.scenes});
  }

  Future<Device?> byId(String id) async {
    final rows = await db.query(
      Tables.devices,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Device.fromRow(rows.first);
  }
}
