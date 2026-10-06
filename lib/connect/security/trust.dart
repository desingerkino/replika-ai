import 'dart:convert';

import '../protocol/protocol.dart';
import 'crypto.dart';
import 'secret_store.dart';

/// Доверенный Controller: запоминается после сопряжения.
class TrustedController {
  TrustedController({
    required this.id,
    required this.name,
    required this.publicKey,
    required this.pairedAt,
    this.lastSeen,
    Set<ConnectScope>? scopes,
  }) : scopes = scopes ?? ConnectScope.values.toSet();

  final String id;
  final String name;
  final List<int> publicKey;
  final DateTime pairedAt;
  DateTime? lastSeen;

  /// Права. В C1 — все; позже выдаются выборочно.
  final Set<ConnectScope> scopes;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'publicKey': toB64(publicKey),
        'pairedAt': pairedAt.millisecondsSinceEpoch,
        if (lastSeen != null) 'lastSeen': lastSeen!.millisecondsSinceEpoch,
        'scopes': [for (final s in scopes) s.name],
      };

  static TrustedController? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return TrustedController(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Controller',
        publicKey: fromB64(json['publicKey'], length: 32),
        pairedAt: DateTime.fromMillisecondsSinceEpoch(json['pairedAt'] as int),
        lastSeen: json['lastSeen'] is int ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int) : null,
        scopes: {
          for (final name in (json['scopes'] as List?) ?? const [])
            for (final s in ConnectScope.values)
              if (s.name == name) s,
        },
      );
    } catch (_) {
      return null;
    }
  }
}

/// Кто этот телефон для Connect: Device ID и постоянный ключ.
class ConnectIdentity {
  const ConnectIdentity({required this.deviceId, required this.key});

  /// Стабильный идентификатор физического телефона: «MESSENGER-7F32A1».
  /// Случайный, не связан с IMEI и серийным номером.
  final String deviceId;
  final KeyPairX key;
}

/// Ключ телефона и доверенные устройства — в защищённом хранилище.
class TrustStore {
  TrustStore(this.store);

  final SecretStore store;

  static const String _identityKey = 'connect.identity.v1';
  static const String _trustedKey = 'connect.trusted.v1';

  ConnectIdentity? _identity;
  List<TrustedController>? _trusted;

  Future<ConnectIdentity> identity() async {
    final cached = _identity;
    if (cached != null) return cached;
    final raw = await store.read(_identityKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map;
        return _identity = ConnectIdentity(
          deviceId: json['deviceId'] as String,
          key: await KeyPairX.fromPrivate(fromB64(json['privateKey'], length: 32)),
        );
      } catch (_) {
        // Повреждённая запись — создаём новую личность (доверие придётся
        // выдать заново, но телефон не останется без Connect).
      }
    }
    final key = await KeyPairX.generate();
    final hex = randomBytes(3).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    final identity = ConnectIdentity(deviceId: 'MESSENGER-$hex', key: key);
    await store.write(_identityKey, jsonEncode({'deviceId': identity.deviceId, 'privateKey': toB64(key.privateKey)}));
    return _identity = identity;
  }

  Future<List<TrustedController>> trusted() async {
    final cached = _trusted;
    if (cached != null) return cached;
    final raw = await store.read(_trustedKey);
    final list = <TrustedController>[];
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          final c = TrustedController.fromJson(item);
          if (c != null) list.add(c);
        }
      } catch (_) {
        // Повреждённый список — доверенных нет, нужно новое сопряжение.
      }
    }
    return _trusted = list;
  }

  Future<TrustedController?> find(String id) async {
    for (final c in await trusted()) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> add(TrustedController controller) async {
    final list = await trusted();
    list.removeWhere((c) => c.id == controller.id);
    list.add(controller);
    await _save();
  }

  /// Отозвать доверие: при следующем подключении — UNAUTHORIZED.
  Future<void> revoke(String id) async {
    final list = await trusted();
    list.removeWhere((c) => c.id == id);
    await _save();
  }

  Future<void> touch(String id, DateTime when) async {
    final c = await find(id);
    if (c == null) return;
    c.lastSeen = when;
    await _save();
  }

  Future<void> _save() async {
    final list = _trusted ?? const [];
    await store.write(_trustedKey, jsonEncode([for (final c in list) c.toJson()]));
  }
}
