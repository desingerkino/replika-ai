import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Где Connect хранит ключи и список доверенных устройств.
///
/// Секреты не попадают ни в SQLite, ни в обычные настройки, ни в журнал.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore и iOS Keychain (через flutter_secure_storage): значения
/// шифруются ключом, который хранится в аппаратном хранилище телефона и не
/// извлекается из него.
///
/// iOS: запись доступна после первой разблокировки (Connect должен работать
/// при заблокированном экране) и не переносится на другое устройство через
/// резервную копию.
class KeystoreSecretStore implements SecretStore {
  static final FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Хранилище в памяти — только для автотестов.
class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
