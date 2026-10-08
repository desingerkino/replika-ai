import 'package:flutter/material.dart';

import 'app_theme_id.dart';

/// Вид нижней панели вкладок.
enum TabBarLook {
  /// Плавающая капсула с размытием (Replika).
  floating,

  /// Прикреплённая панель с «таблеткой» под активной вкладкой (Telegram).
  docked,
}

/// Вид шапки списка чатов.
enum ChatListHeaderLook {
  /// Крупный заголовок «Чаты», под ним поиск.
  largeTitle,

  /// Сверху поиск-«таблетка», под ним вкладки-папки (Telegram).
  searchFirst,
}

/// Не-цветовая часть темы: формы, раскладки, декор. Цвета — в
/// [ReplikaColors] и [ColorScheme], всё остальное — здесь. Экран читает
/// `context.style` и не знает, какая тема выбрана.
@immutable
class AppStyle extends ThemeExtension<AppStyle> {
  const AppStyle({
    required this.id,
    required this.tabBar,
    required this.chatListHeader,
    required this.chatWallpaper,
    required this.listDividers,
    required this.avatarList,
    required this.bubbleRadius,
    required this.bubbleTail,
    required this.searchRadius,
    required this.settingsQuickActions,
    required this.mediaMaxWidth,
  });

  final AppThemeId id;
  final TabBarLook tabBar;
  final ChatListHeaderLook chatListHeader;

  /// Узор-«дудл» на фоне переписки.
  final bool chatWallpaper;

  /// Тонкие разделители между строками списков.
  final bool listDividers;

  /// Диаметр аватара в списке чатов.
  final double avatarList;

  /// Скругление пузыря и его «хвостика».
  final double bubbleRadius;
  final double bubbleTail;

  /// Скругление поля поиска (999 — «таблетка»).
  final double searchRadius;

  /// Кнопки быстрых действий под профилем в настройках.
  final bool settingsQuickActions;

  /// Предел ширины фото и видео в пузыре.
  final double mediaMaxWidth;

  static const AppStyle replika = AppStyle(
    id: AppThemeId.replika,
    tabBar: TabBarLook.floating,
    chatListHeader: ChatListHeaderLook.largeTitle,
    chatWallpaper: false,
    listDividers: true,
    avatarList: 56,
    bubbleRadius: 18,
    bubbleTail: 4,
    searchRadius: 12,
    settingsQuickActions: false,
    mediaMaxWidth: 320,
  );

  static const AppStyle telegram = AppStyle(
    id: AppThemeId.telegram,
    tabBar: TabBarLook.docked,
    chatListHeader: ChatListHeaderLook.searchFirst,
    chatWallpaper: true,
    listDividers: false,
    avatarList: 54,
    bubbleRadius: 18,
    bubbleTail: 6,
    searchRadius: 999,
    settingsQuickActions: true,
    mediaMaxWidth: 340,
  );

  static AppStyle of(AppThemeId id) => switch (id) {
        AppThemeId.replika => replika,
        AppThemeId.telegram => telegram,
      };

  @override
  AppStyle copyWith({
    AppThemeId? id,
    TabBarLook? tabBar,
    ChatListHeaderLook? chatListHeader,
    bool? chatWallpaper,
    bool? listDividers,
    double? avatarList,
    double? bubbleRadius,
    double? bubbleTail,
    double? searchRadius,
    bool? settingsQuickActions,
    double? mediaMaxWidth,
  }) {
    return AppStyle(
      id: id ?? this.id,
      tabBar: tabBar ?? this.tabBar,
      chatListHeader: chatListHeader ?? this.chatListHeader,
      chatWallpaper: chatWallpaper ?? this.chatWallpaper,
      listDividers: listDividers ?? this.listDividers,
      avatarList: avatarList ?? this.avatarList,
      bubbleRadius: bubbleRadius ?? this.bubbleRadius,
      bubbleTail: bubbleTail ?? this.bubbleTail,
      searchRadius: searchRadius ?? this.searchRadius,
      settingsQuickActions: settingsQuickActions ?? this.settingsQuickActions,
      mediaMaxWidth: mediaMaxWidth ?? this.mediaMaxWidth,
    );
  }

  /// Формы между темами не «перетекают»: переключение мгновенное.
  @override
  AppStyle lerp(ThemeExtension<AppStyle>? other, double t) {
    if (other is! AppStyle) return this;
    return t < 0.5 ? this : other;
  }
}
