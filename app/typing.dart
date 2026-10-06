import 'dart:async';

import 'package:flutter/foundation.dart';

/// Кто сейчас «печатает». Состояние живёт только в памяти: после
/// перезапуска приложения никто не печатает — как в настоящем мессенджере.
/// Включают и выключают печать сцены и импровизация (Этапы 4–6);
/// интерфейс (шапка чата, список чатов, лента) только отображает её.
class TypingRegistry extends ChangeNotifier {
  final Map<String, Timer> _timers = {};

  bool isTyping(String chatId) => _timers.containsKey(chatId);

  /// Показать «печатает…» в чате; само выключится через [duration].
  void start(String chatId, {Duration duration = const Duration(seconds: 6)}) {
    _timers.remove(chatId)?.cancel();
    _timers[chatId] = Timer(duration, () => stop(chatId));
    notifyListeners();
  }

  void stop(String chatId) {
    final timer = _timers.remove(chatId);
    if (timer == null) return;
    timer.cancel();
    notifyListeners();
  }

  void stopAll() {
    if (_timers.isEmpty) return;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
