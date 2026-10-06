import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Точка входа фоновой службы. Работы в отдельном потоке нет: сервер Connect
/// живёт в основном процессе приложения, а служба лишь не даёт Android
/// «заморозить» процесс при погашенном экране или свёрнутом приложении
/// и держит Wi-Fi активным (allowWifiLock).
@pragma('vm:entry-point')
void connectForegroundStart() {
  FlutterForegroundTask.setTaskHandler(_ConnectTaskHandler());
}

class _ConnectTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Работа Connect при погашенном экране.
///
/// * Android: foreground-служба с типом connectedDevice (Android 14+).
/// * iOS: аналога нет — система приостанавливает приложение при блокировке
///   экрана. Поэтому вместо службы экран не гаснет, пока Connect включён
///   (wakelock): Connect работает, пока «Реплика» открыта на экране.
///
/// Про Android:
/// Android не позволяет держать сеть приложения в фоне без постоянного
/// уведомления — обходить это нельзя. Поэтому уведомление максимально
/// нейтральное: без имён персонажей, текстов и содержимого сцен.
class ConnectForeground {
  bool _initialized = false;

  void _init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'connect_service',
        channelName: 'Connect',
        channelDescription: 'Работа Connect при погашенном экране',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  /// [shooting] — режим «Съёмка»: минимум текста в уведомлении.
  Future<bool> start({required bool shooting}) async {
    if (Platform.isIOS) {
      try {
        await WakelockPlus.enable();
        return true;
      } catch (error) {
        debugPrint('Экран не удалось оставить включённым: $error');
        return false;
      }
    }
    if (!Platform.isAndroid) return false;
    try {
      _init();
      final title = shooting ? 'Реплика' : 'Connect';
      final text = shooting ? 'Активно' : 'Система управления съёмочным реквизитом активна';
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 4701,
          notificationTitle: title,
          notificationText: text,
          callback: connectForegroundStart,
        );
      }
      return true;
    } catch (error) {
      debugPrint('Фоновая служба Connect не запущена: $error');
      return false;
    }
  }

  /// Исключено ли приложение из энергосбережения Android.
  Future<bool> ignoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  /// Системный запрос «Не ограничивать в фоне» (Doze).
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (error) {
      debugPrint('Запрос энергосбережения не выполнен: $error');
    }
  }

  Future<void> stop() async {
    if (Platform.isIOS) {
      try {
        await WakelockPlus.disable();
      } catch (error) {
        debugPrint('Wakelock не снят: $error');
      }
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    } catch (error) {
      debugPrint('Фоновая служба Connect не остановлена: $error');
    }
  }
}
