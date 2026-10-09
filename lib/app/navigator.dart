import 'package:flutter/material.dart';

import '../features/chat/chat_backgrounds.dart';
import '../features/call/call_screen.dart';
import '../features/chat/chat_screen.dart';
import '../data/models/media_item.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/connect/connect_settings_screen.dart';
import '../features/groups/group_screens.dart';
import '../features/improv/improv_screen.dart';
import '../features/profiles/profiles_screen.dart';
import '../features/kino/kino_screen.dart';
import '../features/media/media_library_screen.dart';
import '../features/operator/operator_home_screen.dart';
import '../features/operator/scene_editor_screen.dart';
import '../features/operator/scene_chats_screen.dart';
import '../features/operator/scene_panel_screen.dart';
import '../features/settings/addons_screen.dart';
import '../features/settings/sections/section_screens.dart';
import '../features/settings/sections/themes_screen.dart';
import '../features/profile/contact_edit_screen.dart';
import '../features/profile/contact_profile_screen.dart';

/// Навигация, доступная не только из экранов: с Этапа 4 её использует
/// Scene Engine для действий «Открыть чат», «Открыть профиль» и «Назад».
abstract final class AppNavigator {
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  /// Экраны настроек, которые в двухпанельной раскладке открываются справа.
  /// Только те, что не закрывают себя через Navigator.pop и не возвращают
  /// результат.
  static const Set<String> _settingsPaneRoutes = {
    '/favorites', '/media', '/profiles', '/addons',
    '/themes', '/settings/notifications', '/settings/privacy', '/settings/ai', '/settings/storage', '/about',
  };

  static Future<T?> _push<T>(String name, Widget screen, [Object? arguments]) async {
    final navigator = key.currentState;
    if (navigator == null) return null;
    if (twoPane.value &&
        homeTab.value == 4 &&
        !navigator.canPop() &&
        _settingsPaneRoutes.contains(name)) {
      detailChat.value = null;
      detailScreen.value = DetailScreen(name, screen);
      return null;
    }
    return navigator.push<T>(
      MaterialPageRoute<T>(
        settings: RouteSettings(name: name, arguments: arguments),
        builder: (_) => screen,
      ),
    );
  }

  /// Двухпанельная раскладка: HomeShell выставляет true, пока на экране
  /// список слева и чат справа (широкое окно, например iPad).
  static final ValueNotifier<bool> twoPane = ValueNotifier<bool>(false);

  /// Чат, открытый в правой панели; null — ничего не выбрано.
  static final ValueNotifier<ChatTarget?> detailChat = ValueNotifier<ChatTarget?>(null);

  /// Экран настроек, открытый в правой панели (вкладка «Настройки»).
  static final ValueNotifier<DetailScreen?> detailScreen = ValueNotifier<DetailScreen?>(null);

  /// Открыть чат; [revealMessageId] — прокрутить к сообщению и подсветить его.
  /// В двухпанельной раскладке чат открывается справа, если сверху нет других
  /// экранов (операторская, звонок): тогда, как и раньше, поверх них.
  static Future<void> openChat(String chatId, {String? revealMessageId}) {
    final navigator = key.currentState;
    if (twoPane.value && navigator != null && !navigator.canPop()) {
      detailScreen.value = null;
      detailChat.value = ChatTarget(chatId, revealMessageId: revealMessageId);
      return Future<void>.value();
    }
    return _push<void>('/chat', ChatScreen(chatId: chatId, revealMessageId: revealMessageId), chatId);
  }

  static Future<void> openProfile({required String deviceId, required String characterId}) =>
      _push<void>(
        '/profile',
        ContactProfileScreen(deviceId: deviceId, characterId: characterId),
        characterId,
      );

  /// Редактор контакта. Без [characterId] — новый контакт;
  /// [ownerMode] — профиль владельца телефона (без имени в контактах).
  static Future<void> openContactEditor({
    required String deviceId,
    String? characterId,
    bool ownerMode = false,
  }) =>
      _push<void>(
        '/contact-edit',
        ContactEditScreen(deviceId: deviceId, characterId: characterId, ownerMode: ownerMode),
      );

  static Future<void> openFavorites(String deviceId) =>
      _push<void>('/favorites', FavoritesScreen(deviceId: deviceId));

  /// Экран звонка: поверх всего, без анимации «сдвига» — как системный вызов.
  static Future<void> openCall() async {
    final navigator = key.currentState;
    if (navigator == null) return;
    await navigator.push<void>(PageRouteBuilder<void>(
      settings: const RouteSettings(name: '/call'),
      pageBuilder: (_, __, ___) => const CallScreen(),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    ));
  }

  static Future<void> openGroupInfo(String chatId) => _push<void>('/group', GroupInfoScreen(chatId: chatId), chatId);

  static Future<void> openNewGroup() => _push<void>('/group/new', const NewGroupScreen());

  static Future<void> openProfiles() => _push<void>('/profiles', const ProfilesScreen());

  static Future<void> openConnect() => _push<void>('/connect', const ConnectSettingsScreen());

  static Future<void> openKino() => _push<void>('/kino', const KinoScreen());

  static Future<void> openImprov() => _push<void>('/improv', const ImprovScreen());

  static Future<void> openAddons() => _push<void>('/addons', const AddonsScreen());

  static Future<void> openChatBackground(String chatId) =>
      _push<void>('/chat/background', ChatBackgroundScreen(chatId: chatId), chatId);

  static Future<void> openThemes() => _push<void>('/themes', const ThemesScreen());

  static Future<void> openNotificationSettings() =>
      _push<void>('/settings/notifications', const NotificationsSettingsScreen());

  static Future<void> openPrivacy() => _push<void>('/settings/privacy', const PrivacySettingsScreen());

  static Future<void> openAiSettings() => _push<void>('/settings/ai', const AiSettingsScreen());

  static Future<void> openStorage() => _push<void>('/settings/storage', const StorageSettingsScreen());

  static Future<void> openAbout() => _push<void>('/about', const AboutScreen());

  static Future<void> openMediaLibrary() =>
      _push<void>('/media', const MediaLibraryScreen());

  /// Выбор файла из медиатеки; null — ничего не выбрано.
  static Future<MediaItem?> pickFromLibrary(Set<MediaKind> kinds) =>
      _push<MediaItem>('/media-pick', MediaLibraryScreen(pickKinds: kinds));

  /// Операторская открыта (чтобы скрытый жест не открывал её дважды).
  static bool operatorOpen = false;

  static Future<void> openOperator() async {
    if (operatorOpen) return;
    await _push<void>('/operator', const OperatorHomeScreen());
  }

  static Future<void> openSceneEditor(String sceneId) =>
      _push<void>('/scene-edit', SceneEditorScreen(sceneId: sceneId), sceneId);

  /// Выбор чата сцены: личные таймлайны чатов и общий таймлайн.
  static Future<void> openSceneChats(String sceneId) =>
      _push<void>('/scene-chats', SceneChatsScreen(sceneId: sceneId), sceneId);

  /// Панель сцены. С [chatKey] — личный таймлайн чата, без него — общий.
  static Future<void> openScenePanel(String sceneId, {String? chatKey}) =>
      _push<void>('/scene-panel', ScenePanelScreen(sceneId: sceneId, chatKey: chatKey), sceneId);

  /// «В кадр»: закрыть операторские экраны и открыть чат сцены.
  static void showInFrame(String chatId) {
    final navigator = key.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    if (twoPane.value) {
      detailChat.value = ChatTarget(chatId);
    } else {
      openChat(chatId);
    }
  }

  /// Вкладка главного экрана: 0 — чаты, 1 — контакты, 2 — звонки,
  /// 3 — истории, 4 — настройки. Меняется касанием и командой Connect OPEN_SCREEN.
  static final ValueNotifier<int> homeTab = ValueNotifier<int>(0);

  /// «Назад»: закрыть верхний экран; в двухпанельной раскладке без верхних
  /// экранов — закрыть чат справа.
  static void back() {
    final navigator = key.currentState;
    if (navigator == null) return;
    if (twoPane.value && !navigator.canPop()) {
      if (detailScreen.value != null && homeTab.value == 4) {
        detailScreen.value = null;
        return;
      }
      if (detailChat.value != null) {
        detailChat.value = null;
        return;
      }
    }
    navigator.maybePop();
  }

  /// Вернуться к главному экрану (список чатов). Для Connect: OPEN_SCREEN CHAT_LIST.
  static void toRoot() {
    key.currentState?.popUntil((route) => route.isFirst);
    detailChat.value = null;
    detailScreen.value = null;
  }
}

/// Экран настроек в правой панели.
@immutable
class DetailScreen {
  const DetailScreen(this.name, this.screen);

  final String name;
  final Widget screen;
}

/// Чат в правой панели (и сообщение, к которому надо прокрутить).
@immutable
class ChatTarget {
  const ChatTarget(this.chatId, {this.revealMessageId});

  final String chatId;
  final String? revealMessageId;

  @override
  bool operator ==(Object other) =>
      other is ChatTarget && other.chatId == chatId && other.revealMessageId == revealMessageId;

  @override
  int get hashCode => Object.hash(chatId, revealMessageId);
}
