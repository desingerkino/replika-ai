// MASTER PROMPT v2: архив, фон чата, «прослушано», настоящая волна WAV,
// каталог фонов и вписывание видео — на настоящей SQLite и чистых функциях.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/data/db/schema.dart';
import 'package:replika/features/chat/chat_backgrounds.dart';
import 'package:replika/features/media/media_kinds.dart';
import 'package:replika/features/media/media_viewer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const veronikaChat = 'chat-veronika';

class _Silent implements CallSounds {
  @override
  void ringtone() {}
  @override
  void ringback() {}
  @override
  void hangup() {}
  @override
  void stop() {}
}

/// 16-битный моно WAV: [quiet] отсчётов тишины, затем [loud] громких.
Uint8List _wav({required int quiet, required int loud}) {
  final frames = quiet + loud;
  final data = ByteData(44 + frames * 2);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + frames * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // моно
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    final v = i < quiet ? 0 : (math.sin(i * 0.3) * 20000).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Данные v2 (миграция 6)', () {
    late Directory tempDir;
    late String dbPath;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppServices.testCallSounds = _Silent.new;
      AppServices.testSecretStore = MemorySecretStore.new;
    });

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('replika_v2_');
      dbPath = p.join(tempDir.path, 'replika.db');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<void> close(AppServices s) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await s.close();
    }

    test('новые колонки на месте', () async {
      final s = await AppServices.open(databasePath: dbPath);
      expect(Schema.version, greaterThanOrEqualTo(6));
      Future<Set<String>> columns(String table) async =>
          {for (final row in await s.database.db.rawQuery('PRAGMA table_info($table)')) row['name']! as String};
      expect(await columns('chats'), containsAll(['archived_at', 'background']));
      expect(await columns('messages'), contains('played_at'));
      await close(s);
    });

    test('архив: чат помечается, счётчик вкладки его не считает, разархивация возвращает', () async {
      final s = await AppServices.open(databasePath: dbPath);
      final header = (await s.chats.header(veronikaChat))!;
      final device = header.chat.deviceId;
      await s.chats.incrementUnread(veronikaChat);
      final before = await s.chats.totalUnread(device);
      expect(before, greaterThan(0));

      await s.chats.setArchived(veronikaChat, true);
      expect((await s.chats.header(veronikaChat))!.chat.isArchived, isTrue);
      expect(await s.chats.totalUnread(device), lessThan(before));

      await s.chats.setArchived(veronikaChat, false);
      expect((await s.chats.header(veronikaChat))!.chat.isArchived, isFalse);
      expect(await s.chats.totalUnread(device), before);
      await close(s);
    });

    test('фон чата сохраняется по chatId и сбрасывается', () async {
      final s = await AppServices.open(databasePath: dbPath);
      expect((await s.chats.header(veronikaChat))!.chat.background, isNull);
      await s.chats.setBackground(veronikaChat, 'mint');
      expect((await s.chats.header(veronikaChat))!.chat.background, 'mint');
      await close(s);

      // После перезапуска выбор на месте.
      final again = await AppServices.open(databasePath: dbPath);
      expect((await again.chats.header(veronikaChat))!.chat.background, 'mint');
      await again.chats.setBackground(veronikaChat, null);
      expect((await again.chats.header(veronikaChat))!.chat.background, isNull);
      await close(again);
    });

    test('«прослушано» ставится один раз и не трогает статус доставки', () async {
      final s = await AppServices.open(databasePath: dbPath);
      final message = (await s.messages.forChat(veronikaChat)).first;
      expect(message.played, isFalse);
      await s.messages.setPlayed(message.id);
      final played = (await s.messages.byId(message.id))!;
      expect(played.played, isTrue);
      expect(played.state, message.state, reason: 'доставка и воспроизведение — разные состояния');
      final firstAt = played.playedAt;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await s.messages.setPlayed(message.id);
      expect((await s.messages.byId(message.id))!.playedAt, firstAt);
      await close(s);
    });
  });

  group('Волна и медиа', () {
    test('волна WAV строится по настоящей громкости', () {
      final bars = wavWaveform(_wav(quiet: 4000, loud: 4000));
      expect(bars.length, 40);
      final first = bars.sublist(0, 18);
      final last = bars.sublist(22);
      expect(first.every((v) => v <= 0.1), isTrue, reason: 'тишина — низкие столбики');
      expect(last.every((v) => v > 0.5), isTrue, reason: 'звук — высокие столбики');
    });

    test('не WAV — пустая волна (честная дорожка вместо выдуманной)', () {
      expect(wavWaveform(Uint8List.fromList(List<int>.filled(100, 7))), isEmpty);
    });

    test('видео вписывается в экран целиком и по центру пропорций', () {
      // Вертикальная запись экрана на горизонтальном окне и наоборот.
      expect(fitContain(const Size(1170, 2532), const Size(800, 400)).height, closeTo(400, 0.01));
      expect(fitContain(const Size(1920, 1080), const Size(390, 844)).width, closeTo(390, 0.01));
      final f = fitContain(const Size(1920, 1080), const Size(390, 844));
      expect(f.width / f.height, closeTo(1920 / 1080, 0.001));
      expect(fitContain(Size.zero, const Size(390, 844)), const Size(390, 844));
    });
  });

  group('Каталог фонов', () {
    test('id уникальны, «Стандартный» — по умолчанию, неизвестный id не ломает чат', () {
      final ids = ChatBackgrounds.all.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ChatBackgrounds.all.first, same(ChatBackgrounds.standard));
      expect(ChatBackgrounds.byId(null), same(ChatBackgrounds.standard));
      expect(ChatBackgrounds.byId('нет-такого'), same(ChatBackgrounds.standard));
      expect(ChatBackgrounds.byId('dark').brightness, Brightness.dark);
      for (final name in ['Стандартный', 'Светлый', 'Тёмный', 'Минималистичный']) {
        expect(ChatBackgrounds.all.any((b) => b.name == name), isTrue, reason: name);
      }
    });
  });
}
