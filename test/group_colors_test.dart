// Цвета участников групп и «мягкое» удаление из состава (этап 1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/core/design/tokens.dart';
import 'package:replika/data/models/message.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const device = 'device-maxim';
const veronika = 'char-veronika';
const aleksey = 'char-aleksey';
const nina = 'char-nina';
const maxim = 'char-maxim';

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

late Directory tempDir;
late AppServices s;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppServices.testCallSounds = _Silent.new;
    AppServices.testSecretStore = MemorySecretStore.new;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('replika_group_colors_');
    s = await AppServices.open(databasePath: p.join(tempDir.path, 'replika.db'));
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await s.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('у каждого участника свой цвет, он сохраняется в базе', () async {
    final id = await s.chats.createGroup(deviceId: device, title: 'Беседа', memberIds: [veronika, aleksey]);
    final members = await s.chats.members(id);
    expect(members.length, 3);
    expect(members.map((m) => m.colorTone).toSet().length, 3, reason: 'цвета различаются');
    final again = await s.chats.members(id);
    expect({for (final m in members) m.characterId: m.colorTone}, {for (final m in again) m.characterId: m.colorTone});
  });

  test('удалённый участник: старые сообщения сохраняют имя и цвет, состав не включает его', () async {
    final id = await s.chats.createGroup(deviceId: device, title: 'Беседа', memberIds: [veronika, aleksey]);
    final before = (await s.chats.members(id)).firstWhere((m) => m.characterId == aleksey);
    await s.messages.insertSceneMessage(
      chatId: id,
      senderId: aleksey,
      type: MessageType.text,
      text: 'Я буду',
      sceneId: null,
    );

    await s.chats.removeMember(id, aleksey);
    expect(await s.chats.isMember(id, aleksey), isFalse);
    expect((await s.chats.members(id)).any((m) => m.characterId == aleksey), isFalse);

    final all = await s.chats.members(id, includeRemoved: true);
    final gone = all.firstWhere((m) => m.characterId == aleksey);
    expect(gone.removed, isTrue);
    expect(gone.name, before.name);
    expect(gone.colorTone, before.colorTone);
  });

  test('новый участник получает свободный цвет, чужие цвета не меняются', () async {
    final id = await s.chats.createGroup(deviceId: device, title: 'Беседа', memberIds: [veronika]);
    final old = {for (final m in await s.chats.members(id)) m.characterId: m.colorTone};
    await s.chats.addMember(id, aleksey);
    final now = {for (final m in await s.chats.members(id)) m.characterId: m.colorTone};
    for (final entry in old.entries) {
      expect(now[entry.key], entry.value, reason: 'цвет ${entry.key} не изменился');
    }
    expect(old.values.contains(now[aleksey]), isFalse, reason: 'новому достался свободный цвет');
  });

  test('вернувшийся в группу участник получает прежний цвет', () async {
    final id = await s.chats.createGroup(deviceId: device, title: 'Беседа', memberIds: [veronika, aleksey]);
    final color = (await s.chats.members(id)).firstWhere((m) => m.characterId == aleksey).colorTone;
    await s.chats.removeMember(id, aleksey);
    await s.chats.addMember(id, aleksey);
    final back = (await s.chats.members(id)).firstWhere((m) => m.characterId == aleksey);
    expect(back.removed, isFalse);
    expect(back.colorTone, color);
  });

  test('оператор вручную меняет цвет участника', () async {
    final id = await s.chats.createGroup(deviceId: device, title: 'Беседа', memberIds: [veronika]);
    await s.chats.setMemberColor(id, veronika, 5);
    final m = (await s.chats.members(id)).firstWhere((m) => m.characterId == veronika);
    expect(m.colorTone, 5 % AvatarTones.all.length);
  });

  test('отмена добавления (forget) не оставляет «призрака», если сообщений не было', () async {
    final id = await s.chats.createGroup(deviceId: device, title: 'Беседа', memberIds: [veronika]);
    await s.chats.addMember(id, nina);
    await s.chats.removeMember(id, nina, forget: true);
    final all = await s.chats.members(id, includeRemoved: true);
    expect(all.any((m) => m.characterId == nina), isFalse);
  });

  test('отмена добавления участника, у которого есть сообщения, сохраняет историю', () async {
    final id = await s.chats.createGroup(deviceId: device, title: 'Беседа', memberIds: [veronika, nina]);
    await s.messages.insertSceneMessage(
      chatId: id,
      senderId: nina,
      type: MessageType.text,
      text: 'Привет',
      sceneId: null,
    );
    await s.chats.removeMember(id, nina, forget: true);
    final all = await s.chats.members(id, includeRemoved: true);
    expect(all.firstWhere((m) => m.characterId == nina).removed, isTrue);
  });
}
