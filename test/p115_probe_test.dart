// ВРЕМЕННАЯ диагностика P1.15 (будет удалена): ломает ли send на UDP-порт 0 сокет.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe: send на порт 0', () async {
    final report = StringBuffer();
    for (final target in ['255.255.255.255', '127.0.0.1']) {
      final a = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true);
      a.broadcastEnabled = true;
      final errors = <String>[];
      var done = false;
      var got = false;
      a.listen((e) {
        if (e == RawSocketEvent.read && a.receive() != null) got = true;
        if (e == RawSocketEvent.closed) done = true;
      }, onError: (Object e) => errors.add('$e'), onDone: () => done = true);
      String sendResult;
      try {
        sendResult = 'ret=${a.send(utf8.encode('x'), InternetAddress(target), 0)}';
      } catch (e) {
        sendResult = 'throw $e';
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final b = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      b.send(utf8.encode('ping'), InternetAddress.loopbackIPv4, a.port);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      report.writeln('target=$target port0: $sendResult; errors=$errors; done=$done; ПОСЛЕ ЭТОГО ping дошёл=$got');
      b.close();
      a.close();
    }
    fail('PROBE: $report');
  });
}
