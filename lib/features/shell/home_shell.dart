import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/adaptive.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/floating_tab_bar.dart';
import '../../core/design/widgets/unread_badge.dart';
import '../../data/db/tables.dart';
import '../calls/calls_screen.dart';
import '../chat/chat_screen.dart';
import '../chats/chats_screen.dart';
import '../contacts/contacts_screen.dart';
import '../settings/settings_screen.dart';
import '../stories/stories_screen.dart';

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
            ContactsScreen(deviceId: deviceId),
            CallsScreen(deviceId: deviceId),
            StoriesScreen(deviceId: deviceId),
            SettingsScreen(deviceId: deviceId),
          ],
        );
        return PopScope(
          canPop: index == 0 && !services.kino.enabled && !(wide && AppNavigator.detailChat.value != null),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (wide && index == 4 && AppNavigator.detailScreen.value != null) {
              AppNavigator.detailScreen.value = null;
            } else if (wide && AppNavigator.detailChat.value != null) {
              AppNavigator.detailChat.value = null;
            } else {
              AppNavigator.homeTab.value = 0;
            }
          },
          child: Scaffold(
            extendBody: true,
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
                      VerticalDivider(width: 1, thickness: 0.6, color: context.rc.divider),
                      SizedBox(width: listPaneWidth, child: tabs),
                      VerticalDivider(width: 1, thickness: 0.6, color: context.rc.divider),
                      Expanded(child: _DetailPane(deviceId: deviceId)),
                    ],
                  )
                : Stack(
                    children: [
                      // Контент знает, что снизу плавает панель, и оставляет
                      // под неё место в своих отступах.
                      Positioned.fill(
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            padding: MediaQuery.paddingOf(context).copyWith(
                              bottom: MediaQuery.paddingOf(context).bottom + AppTabBar.contentInset(context),
                            ),
                          ),
                          child: tabs,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LiveQuery<int>(
                          tables: const {Tables.chats},
                          queryKey: deviceId,
                          load: () => services.chats.totalUnread(deviceId),
                          builder: (context, snapshot) => AppTabBar(
                            index: index,
                            items: _tabItems(snapshot.data ?? 0),
                            onSelect: (selected) {
                              if (selected != AppNavigator.homeTab.value) HapticFeedback.selectionClick();
                              AppNavigator.homeTab.value = selected;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

List<TabBarItem> _tabItems(int unread) => [
      TabBarItem(
        icon: AppIcons.chats,
        activeIcon: AppIcons.chatsActive,
        label: 'Чаты',
        badge: unread,
      ),
      const TabBarItem(
        icon: AppIcons.contacts,
        activeIcon: AppIcons.contactsActive,
        label: 'Контакты',
      ),
      const TabBarItem(icon: Icons.call_outlined, activeIcon: Icons.call_rounded, label: 'Звонки'),
      const TabBarItem(
        icon: Icons.motion_photos_on_outlined,
        activeIcon: Icons.motion_photos_on,
        label: 'Истории',
      ),
      const TabBarItem(
        icon: AppIcons.settings,
        activeIcon: AppIcons.settingsActive,
        label: 'Настройки',
      ),
    ];

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
                if (screen != null && AppNavigator.homeTab.value == 4) {
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

/// Боковая навигация широкого экрана: те же пять разделов, что и внизу.
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
            icon: Icon(AppIcons.contacts),
            selectedIcon: Icon(AppIcons.contactsActive),
            label: Text('Контакты'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call_rounded),
            label: Text('Звонки'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.motion_photos_on_outlined),
            selectedIcon: Icon(Icons.motion_photos_on),
            label: Text('Истории'),
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
