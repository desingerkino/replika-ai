/// Темы оформления «Реплики». Тема меняет весь дизайн-язык приложения:
/// цвета, навигацию, список чатов, пузыри, фон переписки, настройки.
///
/// Новая тема добавляется так:
/// 1) значение в этот enum (с подписью и описанием);
/// 2) палитра в [ReplikaColors] и стиль в [AppStyle];
/// 3) ветка в `AppTheme.build`.
/// Сохранённое в настройках имя темы, которого нет в enum, превращается
/// в тему по умолчанию — старые сборки не ломаются.
enum AppThemeId {
  /// Фирменная тема «Реплики»: синий бренд, плавающая панель вкладок.
  replika('Replika', 'Фирменная: плавающая панель, крупные заголовки'),

  /// Светлая и воздушная, в духе Telegram: один синий акцент,
  /// поиск и папки сверху, фон переписки с узором.
  telegram('Telegram', 'Светлая и воздушная, синий акцент, узор в переписке');

  const AppThemeId(this.label, this.description);

  /// Название в настройках.
  final String label;

  /// Пояснение под названием.
  final String description;

  static const AppThemeId fallback = AppThemeId.telegram;

  static AppThemeId parse(String? name) {
    for (final id in values) {
      if (id.name == name) return id;
    }
    return fallback;
  }
}
