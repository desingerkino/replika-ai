// Replika Next: система тем, папки чатов, истории, реакции, контекст ИИ.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:replika/app/ai_context.dart';
import 'package:replika/app/call_engine.dart';
import 'package:replika/app/services.dart';
import 'package:replika/connect/security/secret_store.dart';
import 'package:replika/core/design/colors.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/core/theme/app_style.dart';
import 'package:replika/core/theme/app_theme_id.dart';
import 'package:replika/core/theme/theme_manager.dart';
import 'package:replika/core/util/time_format.dart';
import 'package:replika/data/models/chat.dart';
import 'package:replika/data/models/media_item.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/data/seed/demo_seed.dart';
import 'package:replika/features/chats/chat_filter.dart';
import 'package:replika/features/profile/shared_media.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

Message msg(String id, String sender, String text, {MessageType type = MessageType.text, bool deleted = false}) =>
    Message(
      id: id,
      chatId: 'c',
      senderId: sender,
      type: type,
      text: text,
      sentAt: DateTime(2026, 10, 8, 12),
      createdAt: DateTime(2026, 10, 8, 12),
      deleted: deleted,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Система тем', () {
    test('неизвестное имя темы даёт тему по умолчанию', () {
      expect(AppThemeId.parse('telegram'), AppThemeId.telegram);
      expect(AppThemeId.parse('replika'), AppThemeId.replika);
      expect(AppThemeId.parse('cinema-2030'), AppThemeId.fallback);
      expect(AppThemeId.parse(null), AppThemeId.fallback);
    });

    test('тема Telegram: палитра из дизайн-системы и свой стиль', () {
      final light = AppTheme.build(AppThemeId.telegram, Brightness.light);
      expect(light.colorScheme.primary, const Color(0xFF007AFF));
      expect(light.colorScheme.onSurface, const Color(0xFF1C1C1E));
      expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
      final rc = light.extension<ReplikaColors>()!;
      expect(rc.bubbleOut, const Color(0xFF2B86FD));
      expect(rc.badge, const Color(0xFF007AFF));
      expect(rc.groupedBackground, const Color(0xFFF2F2F7));
      final style = light.extension<AppStyle>()!;
      expect(style.tabBar, TabBarLook.floating);
      expect(style.groupedSettings, isTrue);
      expect(style.chatWallpaper, isTrue);
      final replika = AppTheme.build(AppThemeId.replika, Brightness.light).extension<AppStyle>()!;
      expect(replika.tabBar, TabBarLook.floating);
    });

    test('ThemeData кэшируется: переключение не пересобирает тему', () {
      expect(identical(AppTheme.build(AppThemeId.telegram, Brightness.dark),
          AppTheme.build(AppThemeId.telegram, Brightness.dark)), isTrue);
    });

    test('менеджер тем мгновенно меняет тему и сохраняет выбор', () async {
      final saved = <String, String>{};
      final manager = ThemeManager.restore(
        savedId: 'replika',
        savedMode: 'dark',
        persist: (k, v) async => saved[k] = v,
      );
      expect(manager.id, AppThemeId.replika);
      expect(manager.mode, ThemeMode.dark);
      var notified = 0;
      manager.addListener(() => notified++);
      await manager.setTheme(AppThemeId.telegram);
      expect(manager.id, AppThemeId.telegram);
      expect(manager.light.colorScheme.primary, const Color(0xFF007AFF));
      expect(saved[ThemeSettingKeys.themeId], 'telegram');
      await manager.setMode(ThemeMode.light);
      expect(saved[ThemeSettingKeys.themeMode], 'light');
      expect(notified, 2);
      manager.dispose();
    });

    // Цвет исходящего пузыря задан палитрой (#2B86FD); белый текст на нём
    // проходит порог 3:1 (крупный и полужирный текст), основной синий
    // кнопок #007AFF — около 4:1.
    test('белый текст на синем Telegram читается', () {
      double lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      double lum(Color c) => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
      double ratio(Color bg) => (1.0 + 0.05) / (lum(bg) + 0.05);
      expect(ratio(ReplikaColors.telegramLight.bubbleOut), greaterThan(3.0));
      expect(ratio(const Color(0xFF007AFF)), greaterThan(3.9));
    });
  });

  group('Папки и превью', () {
    ChatListItem item(String id, {int unread = 0, bool group = false}) => ChatListItem(
          chat: Chat(
            id: id,
            deviceId: 'd',
            isGroup: group,
            unreadCount: unread,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
          peer: const ChatPeer(displayName: 'X'),
          ownerCharacterId: 'me',
        );

    test('папки: непрочитанные, личные, группы', () {
      final all = [item('a', unread: 2), item('b'), item('g', group: true, unread: 1)];
      expect(filterByFolder(all, ChatFolder.all).length, 3);
      expect(filterByFolder(all, ChatFolder.unread).map((i) => i.chat.id), ['a', 'g']);
      expect(filterByFolder(all, ChatFolder.personal).map((i) => i.chat.id), ['a', 'b']);
      expect(filterByFolder(all, ChatFolder.groups).map((i) => i.chat.id), ['g']);
    });

    test('значок типа в превью', () {
      expect(previewGlyph(msg('1', 'x', '', type: MessageType.photo)), PreviewGlyph.photo);
      expect(previewGlyph(msg('2', 'x', 'Пропущенный звонок', type: MessageType.call)), PreviewGlyph.missedCall);
      expect(previewGlyph(msg('3', 'x', 'привет')), isNull);
      expect(previewGlyph(msg('4', 'x', '', type: MessageType.voice, deleted: true)), isNull);
    });

    test('«назад» по-русски', () {
      final now = DateTime(2026, 10, 8, 18, 30);
      expect(formatAgo(now.subtract(const Duration(seconds: 20)), now), 'только что');
      expect(formatAgo(now.subtract(const Duration(minutes: 15)), now), '15 минут назад');
      expect(formatAgo(now.subtract(const Duration(minutes: 21)), now), '21 минуту назад');
      expect(formatAgo(now.subtract(const Duration(hours: 3)), now), '3 часа назад');
      expect(formatAgo(DateTime(2026, 10, 7, 18, 21), now), 'вчера в 18:21');
    });

    test('общее содержимое профиля раскладывается по вкладкам', () {
      final media = MediaItem(id: 'm', kind: MediaKind.photo, path: '/x.jpg', createdAt: DateTime(2026));
      final photo = Message(
        id: 'p',
        chatId: 'c',
        senderId: 'x',
        type: MessageType.photo,
        sentAt: DateTime(2026),
        createdAt: DateTime(2026),
        media: media,
      );
      final split = splitShared([photo, msg('l', 'x', 'смотри https://kino.ru/scene'), msg('t', 'x', 'привет')]);
      expect(split[SharedTab.media]!.single.id, 'p');
      expect(split[SharedTab.links]!.single.id, 'l');
      expect(split[SharedTab.files], isEmpty);
    });
  });

  group('Контекст ИИ', () {
    test('медиа становится меткой, подряд идущие реплики склеиваются', () {
      final history = buildAiHistory([
        msg('1', 'me', 'Привет'),
        msg('2', 'me', 'Ты где?'),
        msg('3', 'her', '', type: MessageType.photo),
        msg('4', 'her', 'Вот тут'),
        msg('5', 'me', 'Красиво'),
        msg('6', 'me', 'удалено', deleted: true),
      ], 'me');
      expect(history.length, 3);
      expect(history[0].fromOwner, isTrue);
      expect(history[0].text, 'Привет\nТы где?');
      expect(history[1].text, '[фото]\nВот тут');
      expect(history[2].text, 'Красиво');
    });

    test('история начинается с реплики владельца', () {
      final history = buildAiHistory([
        msg('1', 'her', 'Ты тут?'),
        msg('2', 'me', 'Да'),
      ], 'me');
      expect(history.single.fromOwner, isTrue);
    });

    test('новый пустой чат — первое сообщение даёт контекст из одной реплики', () {
      final history = buildAiHistory([msg('1', 'me', 'Здравствуйте!')], 'me');
      expect(history.single.text, 'Здравствуйте!');
    });
  });

  group('Истории и реакции на настоящей базе', () {
    late Directory dir;
    late AppServices s;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppServices.testCallSounds = _Silent.new;
      AppServices.testSecretStore = MemorySecretStore.new;
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('replika_next_');
      s = await AppServices.open(databasePath: p.join(dir.path, 'replika.db'));
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await s.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<MediaItem> photo(String id) async {
      final item = MediaItem(id: id, kind: MediaKind.photo, path: p.join(dir.path, '$id.jpg'), createdAt: DateTime.now());
      await s.media.repository.insert(item);
      return item;
    }

    test('реакция сохраняется и снимается', () async {
      final m = (await s.messages.forChat('chat-veronika')).first;
      await s.messages.setReaction(m.id, '❤️');
      expect((await s.messages.forChat('chat-veronika')).firstWhere((x) => x.id == m.id).reaction, '❤️');
      await s.messages.setReaction(m.id, null);
      expect((await s.messages.forChat('chat-veronika')).firstWhere((x) => x.id == m.id).reaction, isNull);
    });

    test('истории группируются по авторам, свои — первыми, просмотр отмечается', () async {
      const device = DemoSeed.deviceId;
      final owner = (await s.devices.byId(device))!.ownerCharacterId;
      final contact = (await s.contacts.forDevice(device)).firstWhere((c) => c.id != owner).id;
      final now = DateTime.now();
      await s.stories.add(deviceId: device, characterId: contact, mediaId: (await photo('a')).id,
          postedAt: now.subtract(const Duration(minutes: 30)));
      final second = await s.stories.add(deviceId: device, characterId: contact, mediaId: (await photo('b')).id,
          postedAt: now.subtract(const Duration(minutes: 5)));
      await s.stories.add(deviceId: device, characterId: owner, mediaId: (await photo('c')).id);
      // Старше суток — не показывается.
      await s.stories.add(deviceId: device, characterId: contact, mediaId: (await photo('d')).id,
          postedAt: now.subtract(const Duration(hours: 30)));

      var authors = await s.stories.authorsForDevice(device);
      expect(authors.length, 2);
      expect(authors.first.isOwner, isTrue);
      final their = authors[1];
      expect(their.stories.length, 2);
      expect(their.hasUnseen, isTrue);
      expect(their.startIndex, 0);

      await s.stories.markSeen(their.stories.first.id);
      authors = await s.stories.authorsForDevice(device);
      expect(authors[1].startIndex, 1, reason: 'просмотр продолжается с непросмотренной');
      await s.stories.markSeen(second.id);
      authors = await s.stories.authorsForDevice(device);
      expect(authors[1].hasUnseen, isFalse);

      await s.stories.markAllUnseen(device);
      expect((await s.stories.authorsForDevice(device))[1].hasUnseen, isTrue);
    });
  });
}

