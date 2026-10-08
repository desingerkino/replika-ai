import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/brand/brand.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/quick_action.dart';
import '../../core/design/widgets/top_bar.dart';
import '../stories/story_actions.dart';
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

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ColoredBox(
      color: context.cs.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!context.style.settingsQuickActions) const ScreenHeader(title: 'Настройки'),
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
                    listenable: Listenable.merge([services.theme, services.kino]),
                    builder: (context, _) {
                      final kino = services.kino.enabled;
                      final themeLabel = '${services.theme.id.label} · ${themeModeLabel(services.theme.mode)}';
                      void editOwner() {
                        if (data == null) return;
                        AppNavigator.openContactEditor(
                          deviceId: deviceId,
                          characterId: data.ownerId,
                          ownerMode: true,
                        );
                      }

                      return ListView(
                        padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.paddingOf(context).bottom),
                        children: [
                          if (data != null)
                            context.style.settingsQuickActions
                                ? _ProfileHeader(
                                    data: data,
                                    onEdit: editOwner,
                                    onStory: () => addStory(context, deviceId: deviceId),
                                    onThemes: AppNavigator.openThemes,
                                  )
                                : _OwnerCard(data: data, onTap: editOwner),
                          const SectionLabel('Аккаунт'),
                          SettingsTile(
                            icon: Icons.person_outline_rounded,
                            title: 'Личные данные',
                            subtitle: 'Имя, номер, фото и статус владельца телефона',
                            onTap: editOwner,
                          ),
                          SettingsTile(
                            icon: Icons.motion_photos_on_outlined,
                            title: 'Мои истории',
                            onTap: () => AppNavigator.homeTab.value = 3,
                          ),
                          SettingsTile(
                            icon: Icons.call_outlined,
                            title: 'Недавние звонки',
                            onTap: () => AppNavigator.homeTab.value = 2,
                          ),
                          SettingsTile(
                            icon: AppIcons.starOutline,
                            title: 'Избранное',
                            trailing: data == null || data.favoritesCount == 0 ? null : '${data.favoritesCount}',
                            onTap: () => AppNavigator.openFavorites(deviceId),
                          ),
                          if (!kino)
                            const SettingsTile(
                              icon: Icons.phone_android_rounded,
                              title: 'Профили телефона',
                              subtitle: 'Сменить, создать, импорт и экспорт',
                              onTap: AppNavigator.openProfiles,
                            ),
                          const SectionLabel('Настройки'),
                          const SettingsTile(
                            icon: Icons.notifications_none_rounded,
                            title: 'Уведомления и звуки',
                            onTap: AppNavigator.openNotificationSettings,
                          ),
                          const SettingsTile(
                            icon: Icons.lock_outline_rounded,
                            title: 'Конфиденциальность',
                            onTap: AppNavigator.openPrivacy,
                          ),
                          const SettingsTile(
                            icon: Icons.smart_toy_outlined,
                            title: 'ИИ-собеседник',
                            onTap: AppNavigator.openAiSettings,
                          ),
                          const SettingsTile(
                            icon: Icons.data_usage_rounded,
                            title: 'Данные и память',
                            onTap: AppNavigator.openStorage,
                          ),
                          SettingsTile(
                            icon: Icons.palette_outlined,
                            title: 'Темы',
                            trailing: themeLabel,
                            onTap: AppNavigator.openThemes,
                          ),
                          if (!kino)
                            SettingsTile(
                              icon: Icons.perm_media_outlined,
                              title: 'Медиатека',
                              subtitle: 'Фото, видео, аудио и голосовые для переписок',
                              onTap: AppNavigator.openMediaLibrary,
                            ),
                          if (!kino)
                            const SettingsTile(
                              icon: Icons.extension_outlined,
                              title: 'Дополнения',
                              subtitle: 'Операторский режим, кнопки громкости',
                              onTap: AppNavigator.openAddons,
                            ),
                          const SectionLabel('О приложении'),
                          SettingsTile(
                            icon: AppIcons.info,
                            title: '${Brand.name} ${Brand.version}',
                            subtitle: 'Все данные хранятся только на этом телефоне',
                            onTap: AppNavigator.openAbout,
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

/// Шапка профиля в стиле Telegram: крупный аватар по центру, имя, номер
/// и три быстрых действия.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.data, required this.onEdit, required this.onStory, required this.onThemes});

  final _SettingsData data;
  final VoidCallback onEdit;
  final VoidCallback onStory;
  final VoidCallback onThemes;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final rc = context.rc;
    final character = data.owner?.character;
    final name = character?.fullName ?? '';
    final shown = name.isEmpty ? data.deviceName : name;
    final phone = character?.phone ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
      child: Column(
        children: [
          GestureDetector(
            onTap: onEdit,
            child: Avatar(name: shown, size: 96, imagePath: data.owner?.avatarPath, tone: character?.avatarTone),
          ),
          const SizedBox(height: Space.m),
          Text(shown, textAlign: TextAlign.center, style: tt.titleLarge?.copyWith(fontSize: 22)),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(phone, style: tt.bodyMedium?.copyWith(color: rc.textSecondary)),
          ],
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(child: QuickAction(icon: Icons.photo_camera_outlined, label: 'Фото профиля', onTap: onEdit)),
              const SizedBox(width: Space.s),
              Expanded(child: QuickAction(icon: Icons.add_circle_outline_rounded, label: 'Новая история', onTap: onStory)),
              const SizedBox(width: Space.s),
              Expanded(child: QuickAction(icon: Icons.palette_outlined, label: 'Темы', onTap: onThemes)),
            ],
          ),
        ],
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
    return InkWell(
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
