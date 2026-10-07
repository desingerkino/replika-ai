import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/adaptive.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/unread_badge.dart';
import '../../data/db/tables.dart';
import '../calls/calls_screen.dart';
import '../chat/chat_screen.dart';
import '../chats/chats_screen.dart';
import '../contacts/contacts_screen.dart';
import '../settings/settings_screen.dart';

/// Главный экран: вкладки «Чаты» и «Контакты» текущего телефона.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Вкладка хранится в AppNavigator.homeTab: её переключает и касание,
  // и команда Connect OPEN_SCREEN (CALLS, CONTACTS, CHAT_LIST).
  @override
  void dispose() {
    AppNavigator.twoPane.value = false;
    super.dispose();
  }

  void _setTwoPane(bool wide) {
    if (AppNavigator.twoPane.value == wide) return;
    // Состояние меняем после построения кадра, а не внутри build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppNavigator.twoPane.value = wide;
      if (!wide) {
        AppNavigator.detailChat.value = null;
        AppNavigator.detailScreen.value = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.currentDeviceId,
        services.kino,
        AppNavigator.homeTab,
        AppNavigator.detailChat,
        AppNavigator.detailScreen,
      ]),
      builder: (context, _) {
        final deviceId = services.currentDeviceId.value;
        final index = AppNavigator.homeTab.value;
        final wide = isWideWindow(MediaQuery.sizeOf(context));
        _setTwoPane(wide);
        final tabs = IndexedStack(
          index: index,
          children: [
            ChatsScreen(deviceId: deviceId),
            CallsScreen(deviceId: deviceId),
            ContactsScreen(deviceId: deviceId),
            SettingsScreen(deviceId: deviceId),
          ],
        );
        return PopScope(
          canPop: index == 0 && !services.kino.enabled && !(wide && AppNavigator.detailChat.value != null),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (wide && index == 3 && AppNavigator.detailScreen.value != null) {
              AppNavigator.detailScreen.value = null;
            } else if (wide && AppNavigator.detailChat.value != null) {
              AppNavigator.detailChat.value = null;
            } else {
              AppNavigator.homeTab.value = 0;
            }
          },
          child: Scaffold(
            body: wide
                ? Row(
                    children: [
                      LiveQuery<int>(
                        tables: const {Tables.chats},
                        queryKey: deviceId,
                        load: () => services.chats.totalUnread(deviceId),
                        builder: (context, snapshot) => _Rail(
                          index: index,
                          unread: snapshot.data ?? 0,
                          onSelect: (selected) => AppNavigator.homeTab.value = selected,
                        ),
                      ),
                      VerticalDivider(width: Sizes.line, thickness: Sizes.line, color: context.rc.divider),
                      SizedBox(width: listPaneWidth, child: tabs),
                      VerticalDivider(width: Sizes.line, thickness: Sizes.line, color: context.rc.divider),
                      Expanded(child: _DetailPane(deviceId: deviceId)),
                    ],
                  )
                : tabs,
            bottomNavigationBar: wide
                ? null
                : LiveQuery<int>(
                    tables: const {Tables.chats},
                    queryKey: deviceId,
                    load: () => services.chats.totalUnread(deviceId),
                    builder: (context, snapshot) => _NavBar(
                      index: index,
                      unread: snapshot.data ?? 0,
                      onSelect: (selected) => AppNavigator.homeTab.value = selected,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// Правая панель двухпанельной раскладки: открытый чат или подсказка.
/// Размер окна для содержимого — ширина самой панели, поэтому пузыри и
/// остальное считаются от неё, а не от всего экрана.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(size: Size(constraints.maxWidth, constraints.maxHeight)),
          child: InDetailPane(
            child: ListenableBuilder(
              listenable: Listenable.merge([AppNavigator.detailChat, AppNavigator.detailScreen, AppNavigator.homeTab]),
              builder: (context, _) {
                final screen = AppNavigator.detailScreen.value;
                if (screen != null && AppNavigator.homeTab.value == 3) {
                  return KeyedSubtree(key: ValueKey('${deviceId}_${screen.name}'), child: screen.screen);
                }
                final target = AppNavigator.detailChat.value;
                if (target == null) return const _NoChatSelected();
                return ChatScreen(
                  key: ValueKey('${deviceId}_${target.chatId}_${target.revealMessageId}'),
                  chatId: target.chatId,
                  revealMessageId: target.revealMessageId,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected();

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return ColoredBox(
      color: rc.chatBackground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(
            'Выберите чат или раздел слева',
            style: context.tt.bodyLarge?.copyWith(color: rc.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Боковая навигация широкого экрана: те же четыре раздела, что и внизу.
class _Rail extends StatelessWidget {
  const _Rail({required this.index, required this.unread, required this.onSelect});

  final int index;
  final int unread;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    Widget chatsIcon(IconData icon) => Badge(
          isLabelVisible: unread > 0,
          backgroundColor: rc.badge,
          textColor: rc.onBadge,
          label: Text(UnreadBadge.label(unread)),
          child: Icon(icon),
        );
    return SafeArea(
      right: false,
      child: NavigationRail(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        labelType: NavigationRailLabelType.all,
        destinations: [
          NavigationRailDestination(
            icon: chatsIcon(AppIcons.chats),
            selectedIcon: chatsIcon(AppIcons.chatsActive),
            label: const Text('Чаты'),
          ),
          const NavigationRailDestination(
            icon: Icon(AppIcons.callOutlined),
            selectedIcon: Icon(AppIcons.call),
            label: Text('Звонки'),
          ),
          const NavigationRailDestination(
            icon: Icon(AppIcons.contacts),
            selectedIcon: Icon(AppIcons.contactsActive),
            label: Text('Контакты'),
          ),
          const NavigationRailDestination(
            icon: Icon(AppIcons.settings),
            selectedIcon: Icon(AppIcons.settingsActive),
            label: Text('Настройки'),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.unread, required this.onSelect});

  final int index;
  final int unread;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    Widget chatsIcon(IconData icon) => Badge(
          isLabelVisible: unread > 0,
          backgroundColor: rc.badge,
          textColor: rc.onBadge,
          label: Text(UnreadBadge.label(unread)),
          child: Icon(icon),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: rc.divider, width: Sizes.line)),
      ),
      child: NavigationBar(
        // 64 при обычном шрифте; при крупном — выше, чтобы подписи не обрезались.
        height: 64 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0.0, 24.0) * 1.5,
        selectedIndex: index,
        onDestinationSelected: onSelect,
        destinations: [
          NavigationDestination(
            icon: chatsIcon(AppIcons.chats),
            selectedIcon: chatsIcon(AppIcons.chatsActive),
            label: 'Чаты',
          ),
          const NavigationDestination(
            icon: Icon(AppIcons.callOutlined),
            selectedIcon: Icon(AppIcons.call),
            label: 'Звонки',
          ),
          const NavigationDestination(
            icon: Icon(AppIcons.contacts),
            selectedIcon: Icon(AppIcons.contactsActive),
            label: 'Контакты',
          ),
          const NavigationDestination(
            icon: Icon(AppIcons.settings),
            selectedIcon: Icon(AppIcons.settingsActive),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
