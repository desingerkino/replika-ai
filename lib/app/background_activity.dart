import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Приложение сейчас на экране (не в фоне и не под экраном блокировки).
/// До первого кадра и в автотестах состояние неизвестно — считаем, что
/// на экране (так ведёт себя приложение и до этого изменения).
bool get appInForeground {
  final AppLifecycleState? state;
  try {
    state = WidgetsBinding.instance.lifecycleState;
  } catch (_) {
    return true; // привязка Flutter не создана (чистые автотесты Dart)
  }
  return state == null || state == AppLifecycleState.resumed;
}

/// Начатая работа, которую нужно доделать, даже если экран заблокировали.
///
/// Уведомления «Реплики» локальные: их показывает Dart-код, когда шаг
/// сцены доходит до сообщения. На iOS после блокировки экрана приложение
/// приостанавливается примерно через 5 секунд, и шаг с задержкой или
/// «печатает…» не доходил до уведомления. [run] просит у iOS штатное
/// продление (UIApplication.beginBackgroundTask) на время работы и
/// возвращает его сразу по окончании. На Android и в автотестах — ничего
/// не делает (там приложение не приостанавливается так быстро, а Connect
/// держит фоновую службу).
class BackgroundActivity {
  BackgroundActivity._();

  static const MethodChannel _channel = MethodChannel('ru.kinoprop.replika/background');

  /// Канала нет (старый нативный код, автотест) — больше не пытаемся.
  static bool _unavailable = false;

  static bool get _supported => !kIsWeb && Platform.isIOS && !_unavailable;

  /// Выполнить [body], не давая iOS приостановить приложение посередине
  /// (в пределах времени, которое даёт система).
  static Future<T> run<T>(String name, Future<T> Function() body) async {
    final id = await _begin(name);
    try {
      return await body();
    } finally {
      if (id != null) unawaited(_end(id));
    }
  }

  static Future<int?> _begin(String name) async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<int>('begin', {'name': name});
    } on MissingPluginException {
      _unavailable = true;
    } catch (error) {
      debugPrint('Продление работы в фоне недоступно: $error');
    }
    return null;
  }

  static Future<void> _end(int id) async {
    try {
      await _channel.invokeMethod<void>('end', {'id': id});
    } catch (error) {
      debugPrint('Не удалось завершить фоновую активность: $error');
    }
  }
}
