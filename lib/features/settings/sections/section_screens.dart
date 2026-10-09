import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/auto_reply.dart';
import '../../../app/live_query.dart';
import '../../../app/navigator.dart';
import '../../../app/services.dart';
import '../../../core/brand/brand.dart';
import '../../../core/brand/logo.dart';
import '../../../core/design/context.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/form.dart';
import '../../../data/db/tables.dart';
import '../../media/media_kinds.dart';
import '../addons_screen.dart';
import 'settings_page.dart';

Widget _addon(BuildContext context, String id) {
  for (final addon in addons) {
    if (addon.id == id) return addon.builder(context);
  }
  return const SizedBox.shrink();
}

/// Настройки → Уведомления и звуки.
class NotificationsSettingsScreen extends StatelessWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Уведомления и звуки',
      children: [
        SettingsGroup(
          title: 'Сообщения',
          footer: 'Отключить звук отдельного чата можно свайпом влево по нему '
              'в списке чатов — «Без звука».',
          children: [
            _addon(context, 'notifications'),
            _addon(context, 'notifications_test'),
          ],
        ),
      ],
    );
  }
}

/// Настройки → Конфиденциальность.
class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final kino = Services.of(context).kino.enabled;
    return SettingsPage(
      title: 'Конфиденциальность',
      children: [
        const SettingsGroup(title: 'Данные', children: [
        SettingsTile(
          icon: Icons.lock_outline_rounded,
          title: 'Всё хранится на этом устройстве',
          subtitle: 'Переписки, контакты, фото и истории не уходят в интернет',
        ),
        SettingsTile(
          icon: Icons.cloud_off_outlined,
          title: 'Работает без сети',
          subtitle: 'Приложению не нужен интернет ни для чатов, ни для ИИ',
        ),
        ]),
        if (!kino)
          const SettingsGroup(title: 'Управление по сети', children: [
          SettingsTile(
            icon: Icons.wifi_tethering_rounded,
            title: 'Connect',
            subtitle: 'Сопряжение с Prop Controller шифруется; доступ — только подтверждённым',
            onTap: AppNavigator.openConnect,
          ),
          SettingsTile(
            icon: Icons.phone_android_rounded,
            title: 'Экспорт и импорт профилей',
            subtitle: 'Перенос телефона персонажа файлом',
            onTap: AppNavigator.openProfiles,
          ),
          ]),
      ],
    );
  }
}

/// Настройки → ИИ-собеседник.
class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final available = AutoReplyController.engine != null;
    return SettingsPage(
      title: 'ИИ-собеседник',
      children: [
        SettingsGroup(
          title: 'Автоответы',
          footer: 'Собеседник отвечает в личных чатах от имени контакта: характер берётся '
              'из поля «Описание» в его профиле, контекст — из последних сообщений '
              'переписки. В группах и во время дубля сцены ИИ молчит. Ответ можно '
              'стереть вместе с импровизацией.',
          children: [
            if (available)
              _addon(context, 'ai')
            else
              const SettingsTile(
                icon: Icons.smart_toy_outlined,
                title: 'ИИ недоступен в этой сборке',
                subtitle: 'Автоответы есть в сборке «Реплика AI» (модель Qwen на телефоне)',
              ),
          ],
        ),
      ],
    );
  }
}

/// Настройки → Данные и память: сколько занимают файлы и база.
class StorageSettingsScreen extends StatelessWidget {
  const StorageSettingsScreen({super.key});

  Future<_Usage> _load(AppServices services) async {
    final items = await services.media.repository.list();
    var bytes = 0;
    final byKind = <String, int>{};
    for (final m in items) {
      final size = m.sizeBytes ?? 0;
      bytes += size;
      byKind[m.kind.label] = (byKind[m.kind.label] ?? 0) + 1;
    }
    var dbBytes = 0;
    try {
      dbBytes = await File(services.database.db.path).length();
    } catch (_) {}
    return _Usage(files: items.length, mediaBytes: bytes, dbBytes: dbBytes, byKind: byKind);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return LiveQuery<_Usage>(
      tables: const {Tables.media, Tables.messages, Tables.stories},
      load: () => _load(services),
      builder: (context, snapshot) {
        final usage = snapshot.data;
        return SettingsPage(
          title: 'Данные и память',
          children: [
            SettingsGroup(title: 'Использование', children: [
            SettingsTile(
              icon: Icons.perm_media_outlined,
              title: 'Медиатека',
              trailing: usage == null ? '…' : '${usage.files} · ${formatBytes(usage.mediaBytes)}',
              onTap: services.kino.enabled ? null : AppNavigator.openMediaLibrary,
            ),
            SettingsTile(
              icon: Icons.storage_rounded,
              title: 'Переписки и настройки',
              trailing: usage == null ? '…' : formatBytes(usage.dbBytes),
            ),
            ]),
            if (usage != null && usage.byKind.isNotEmpty)
              SettingsGroup(
                title: 'Файлы по типам',
                footer: 'Файлы копируются во внутреннюю папку приложения: если удалить '
                    'оригинал из галереи, переписка и сцены не сломаются.',
                children: [
                  for (final entry in usage.byKind.entries)
                    SettingsTile(icon: Icons.folder_outlined, title: entry.key, trailing: '${entry.value}'),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _Usage {
  const _Usage({required this.files, required this.mediaBytes, required this.dbBytes, required this.byKind});

  final int files;
  final int mediaBytes;
  final int dbBytes;
  final Map<String, int> byKind;
}

/// Настройки → О приложении.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'О приложении',
      children: [
        const SizedBox(height: Space.xxl),
        const Center(child: AnimatedReplikaLogo(size: 104)),
        const SizedBox(height: Space.l),
        Center(child: Text(Brand.name, style: context.tt.headlineSmall)),
        const SizedBox(height: Space.xs),
        Center(
          child: Text(
            'Версия ${Brand.version}',
            style: context.tt.bodyMedium?.copyWith(color: context.rc.textSecondary),
          ),
        ),
        const SettingsGroup(children: [
        SettingsTile(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Мессенджер нового поколения',
          subtitle: 'Чаты, истории, звонки, голосовые и видео — на одном телефоне, без сети',
        ),
        SettingsTile(
          icon: Icons.movie_filter_outlined,
          title: Brand.tagline,
          subtitle: 'Персонажи, постановочные переписки, сцены и операторский режим',
        ),
        ]),
      ],
    );
  }
}
