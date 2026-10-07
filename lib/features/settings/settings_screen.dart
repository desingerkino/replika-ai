import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/brand/brand.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/pressable.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/contact.dart';

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'Как в системе',
      ThemeMode.light => 'Светлая',
      ThemeMode.dark => 'Тёмная',
    };

/// Настройки телефона: профиль владельца, избранное, оформление.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.deviceId});

  final String deviceId;

  Future<_SettingsData?> _load(AppServices services) async {
    final device = await services.devices.byId(deviceId);
    if (device == null) return null;
    final owner = await services.contacts.view(deviceId, device.ownerCharacterId);
    final favorites = await services.chats.favorites(deviceId);
    return _SettingsData(
      deviceName: device.name,
      ownerId: device.ownerCharacterId,
      owner: owner,
      favoritesCount: favorites.length,
    );
  }

  Future<void> _pickTheme(BuildContext context, AppServices services) async {
    final current = services.themeMode.value;
    final mode = await showActionSheet<ThemeMode>(
      context,
      header: Text('Тема', style: context.tt.titleMedium),
      actions: [
        for (final (mode, icon) in const [
          (ThemeMode.system, AppIcons.themeSystem),
          (ThemeMode.light, AppIcons.themeLight),
          (ThemeMode.dark, AppIcons.themeDark),
        ])
          SheetAction(
            value: mode,
            icon: icon,
            label: themeModeLabel(mode),
            selected: mode == current,
          ),
      ],
    );
    if (mode != null) await services.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ColoredBox(
      color: context.cs.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const ScreenHeader(title: 'Настройки'),
            Expanded(
              child: LiveQuery<_SettingsData?>(
                tables: const {
                  Tables.devices,
                  Tables.characters,
                  Tables.deviceContacts,
                  Tables.messages,
                  Tables.media,
                },
                queryKey: deviceId,
                load: () => _load(services),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  return ListenableBuilder(
                    listenable: Listenable.merge([services.themeMode, services.kino]),
                    builder: (context, _) {
                      final mode = services.themeMode.value;
                      final kino = services.kino.enabled;
                      return ListView(
                      padding: const EdgeInsets.only(bottom: Space.xl),
                      children: [
                        if (data != null)
                          _OwnerCard(
                            data: data,
                            onTap: () => AppNavigator.openContactEditor(
                              deviceId: deviceId,
                              characterId: data.ownerId,
                              ownerMode: true,
                            ),
                          ),
                        const SectionLabel('Сообщения'),
                        SettingsTile(
                          icon: AppIcons.star,
                          title: 'Избранное',
                          trailing: data == null || data.favoritesCount == 0
                              ? null
                              : '${data.favoritesCount}',
                          onTap: () => AppNavigator.openFavorites(deviceId),
                        ),
                        if (!kino) SettingsTile(
                          icon: Icons.perm_media_outlined,
                          title: 'Медиатека',
                          subtitle: 'Фото, видео, аудио и голосовые для переписок',
                          onTap: AppNavigator.openMediaLibrary,
                        ),
                        const SectionLabel('Оформление'),
                        SettingsTile(
                          icon: AppIcons.theme,
                          title: 'Тема',
                          trailing: themeModeLabel(mode),
                          onTap: () => _pickTheme(context, services),
                        ),
                        if (!kino) const SectionLabel('Профили телефона'),
                        if (!kino)
                          const SettingsTile(
                            icon: Icons.phone_android_rounded,
                            title: 'Профили телефона',
                            subtitle: 'Сменить, создать, импорт и экспорт',
                            onTap: AppNavigator.openProfiles,
                          ),
                        if (!kino) const SectionLabel('Дополнения'),
                        if (!kino) const SettingsTile(
                          icon: Icons.extension_outlined,
                          title: 'Дополнения',
                          subtitle: 'Операторский режим, кнопки громкости',
                          onTap: AppNavigator.openAddons,
                        ),
                        if (!kino) const SectionLabel('О приложении'),
                        if (!kino) SettingsTile(
                          icon: AppIcons.info,
                          title: '${Brand.name} ${Brand.version}',
                          subtitle: 'Все данные хранятся только на этом телефоне',
                        ),
                      ],
                    );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsData {
  const _SettingsData({
    required this.deviceName,
    required this.ownerId,
    required this.owner,
    required this.favoritesCount,
  });

  final String deviceName;
  final String ownerId;
  final Contact? owner;
  final int favoritesCount;
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.data, required this.onTap});

  final _SettingsData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final character = data.owner?.character;
    final name = character?.fullName ?? '';
    final shown = name.isEmpty ? data.deviceName : name;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l + 4, Space.s, Space.l, Space.m),
        child: Row(
          children: [
            Avatar(
              name: shown,
              size: 64,
              imagePath: data.owner?.avatarPath,
              tone: character?.avatarTone,
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shown, style: tt.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if ((character?.phone ?? '').isNotEmpty)
                    Text(character!.phone, style: tt.bodyMedium?.copyWith(color: context.rc.textSecondary)),
                ],
              ),
            ),
            Icon(AppIcons.edit, size: 20, color: context.rc.textTertiary),
          ],
        ),
      ),
    );
  }
}
