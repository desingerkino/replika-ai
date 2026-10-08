/// Запись экрана и сохранение видео в галерею.
///
/// iOS: ReplayKit записывает экран самого приложения со звуком, готовый
/// файл кладётся в «Фото». Android: MediaProjection записывает экран,
/// файл кладётся в галерею (Movies/Replika) через MediaStore.
library;

import 'package:flutter/services.dart';

/// Ошибка записи. [code]: denied — пользователь не разрешил запись,
/// unavailable — запись экрана недоступна, busy — уже идёт запись,
/// failed — любой другой сбой, save_failed / no_access — сохранение в галерею.
class RecorderException implements Exception {
  const RecorderException(this.code, this.message);

  final String code;
  final String message;

  bool get denied => code == 'denied';

  @override
  String toString() => 'RecorderException($code): $message';
}

class ReplikaRecorder {
  ReplikaRecorder._();

  static const MethodChannel _channel = MethodChannel('ru.kinoprop.replika/recorder');

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw RecorderException(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw const RecorderException('unavailable', 'Запись экрана не поддерживается на этом устройстве');
    }
  }

  /// Запись экрана доступна на этом устройстве.
  static Future<bool> isSupported() async {
    try {
      return await _call<bool>('isSupported') ?? false;
    } on RecorderException {
      return false;
    }
  }

  /// Спрашивает разрешение на сохранение в галерею (iOS: «добавление в Фото»).
  /// true — сохранять в галерею можно.
  static Future<bool> requestGalleryAccess() async {
    try {
      return await _call<bool>('requestGalleryAccess') ?? false;
    } on RecorderException {
      return false;
    }
  }

  /// Начинает запись экрана. Система сама покажет своё окно с запросом.
  static Future<void> start({bool microphone = true}) =>
      _call<void>('start', {'microphone': microphone});

  /// Останавливает запись и закрывает файл. Возвращает путь к готовому
  /// mp4 во временной папке или null, если записать нечего.
  static Future<String?> stop() => _call<String>('stop');

  /// Копирует видео в системную галерею под именем [name] (например,
  /// Replika_2026-10-07_03-45-12.mp4). Возвращает true при успехе.
  static Future<bool> saveToGallery(String path, String name) async =>
      await _call<bool>('saveToGallery', {'path': path, 'name': name}) ?? false;

  /// Звонок: глушит микрофон (и в идущей записи экрана). Тихо ничего не
  /// делает, если платформа не поддерживает.
  static Future<void> setMicrophoneMuted(bool muted) => _quiet('setMicrophoneMuted', {'muted': muted});

  /// Звонок: экран гаснет, когда телефон поднесён к уху.
  static Future<void> setProximityMonitoring(bool enabled) =>
      _quiet('setProximityMonitoring', {'enabled': enabled});

  static Future<void> _quiet(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Нет нативной части (тесты, десктоп) — ничего не делаем.
    } on PlatformException {
      // Не критично для звонка.
    }
  }
}
