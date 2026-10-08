import 'package:flutter/widgets.dart';

import 'theme_manager.dart';

/// Даёт экранам доступ к [ThemeManager] и перестраивает подписчиков при
/// смене темы. Сами цвета экраны берут из Theme.of(context) — так любой
/// виджет получает новую тему без собственных подписок.
class ThemeProvider extends InheritedNotifier<ThemeManager> {
  const ThemeProvider({super.key, required ThemeManager manager, required super.child})
      : super(notifier: manager);

  /// С подпиской на изменения.
  static ThemeManager of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(provider != null, 'ThemeProvider отсутствует в дереве виджетов');
    return provider!.notifier!;
  }

  /// Без подписки (для обработчиков нажатий).
  static ThemeManager read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<ThemeProvider>();
    assert(element != null, 'ThemeProvider отсутствует в дереве виджетов');
    return (element!.widget as ThemeProvider).notifier!;
  }
}
