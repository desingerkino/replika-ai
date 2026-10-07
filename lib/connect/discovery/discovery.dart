import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/protocol.dart';

/// Поиск телефонов с Messenger в локальной сети (UDP, только dart:io).
///
/// * Маяк: каждые [beaconInterval] телефон рассылает широковещательный
///   пакет `announce` — Controller видит телефоны, просто слушая порт 47621.
/// * Запрос: на пакет `discover` телефон отвечает `announce` напрямую
///   отправителю.
///
/// В пакетах только то, что нужно найти телефон: Device ID, имя, порт
/// WebSocket и версии. Ключей, имён персонажей и содержимого нет.
/// Поддельный маяк ничего не даёт: подлинность телефона проверяется
/// ключом при каждом hello.
class ConnectDiscovery {
  ConnectDiscovery({
    required this.announce,
    this.port = discoveryPort,
    this.beaconInterval = const Duration(seconds: 3),
  });

  /// Содержимое пакета announce (без поля type).
  final Map<String, Object?> Function() announce;
  final int port;
  final Duration beaconInterval;

  RawDatagramSocket? _socket;
  Timer? _beacon;

  bool get running => _socket != null;
  int? get boundPort => _socket?.port;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
    socket.broadcastEnabled = true;
    _socket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null || datagram.data.length > 2048) return;
      try {
        final json = jsonDecode(utf8.decode(datagram.data));
        if (json is Map && json['type'] == 'discover' && json['protocol'] == discoveryTag) {
          socket.send(_packet(), datagram.address, datagram.port);
        }
      } catch (_) {
        // Чужие или повреждённые пакеты молча игнорируются.
      }
    },
        // Ошибки отправки (нет сети, на iOS без разрешения на широковещание)
        // приходят сюда, а не из send: без обработчика они считаются
        // необработанными. Маяк повторится по таймеру.
        onError: (Object error) {});
    _beacon = Timer.periodic(beaconInterval, (_) => burst());
    burst();
  }

  List<int> _packet() => utf8.encode(jsonEncode({
        'type': 'announce',
        'protocol': discoveryTag,
        'protocolVersion': protocolVersion,
        ...announce(),
      }));

  /// Разослать маяк сейчас (например, сразу после возврата Wi-Fi).
  Future<void> burst() async {
    final socket = _socket;
    if (socket == null) return;
    final packet = _packet();
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in interfaces) {
        for (final a in i.addresses) {
          // Широковещательный адрес типичной домашней и площадочной сети /24.
          final parts = a.address.split('.');
          if (parts.length == 4) targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
        }
      }
    } catch (_) {}
    // Порт назначения — реально занятый порт сокета. При `port: 0` («выбрать
    // свободный») отправка на порт 0 недопустима и закрывает сокет, после чего
    // телефон перестаёт отвечать на запросы; в обычной работе он равен [port].
    final destinationPort = socket.port;
    for (final t in targets) {
      try {
        socket.send(packet, t, destinationPort);
      } catch (_) {
        // Сети нет — маяк повторится по таймеру.
      }
    }
  }

  Future<void> stop() async {
    _beacon?.cancel();
    _beacon = null;
    _socket?.close();
    _socket = null;
  }
}

/// Найти телефоны: отправить запрос и собрать ответы (для «Проверки Connect»
/// и как образец для Prop Controller).
Future<List<Map<String, Object?>>> discoverDevices({
  Iterable<String> hosts = const ['255.255.255.255'],
  int port = discoveryPort,
  Duration wait = const Duration(milliseconds: 1500),
}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final found = <String, Map<String, Object?>>{};
  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null) return;
    try {
      final json = jsonDecode(utf8.decode(d.data));
      if (json is Map && json['type'] == 'announce' && json['protocol'] == discoveryTag) {
        final map = Map<String, Object?>.from(json)..['address'] = d.address.address;
        found['${map['deviceId']}'] = map;
      }
    } catch (_) {}
  }, onError: (Object error) {});
  final probe = utf8.encode(jsonEncode({'type': 'discover', 'protocol': discoveryTag, 'protocolVersion': protocolVersion}));
  for (final h in hosts) {
    try {
      socket.send(probe, InternetAddress(h), port);
    } catch (_) {}
  }
  await Future<void>.delayed(wait);
  await sub.cancel();
  socket.close();
  return found.values.toList();
}
