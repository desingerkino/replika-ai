import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Номер уведомления чата: одно уведомление на чат, новые сообщения
/// обновляют его, открытие чата убирает.
int chatNotificationId(String chatId) {
  var hash = 17;
  for (final unit in chatId.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return hash;
}

/// Сообщение в уведомлении мессенджера.
@immutable
class NotificationMessage {
  const NotificationMessage({required this.sender, required this.text, required this.time});

  final String sender;
  final String text;
  final DateTime time;
}

/// Настоящие локальные уведомления: Android (каналы, звук, вибрация) и iOS
/// (баннер, экран блокировки, звук). Переход в чат по нажатию. Сервер и
/// push не используются.
class NotificationService {
  NotificationService({required this.onOpenChat});

  static const String messagesChannel = 'messages';
  static const String eventsChannel = 'events';

  /// Нажали на уведомление — открыть чат с этим id.
  final void Function(String chatId) onOpenChat;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;

  /// Последние сообщения по чатам — уведомление показывает переписку,
  /// как у мессенджеров.
  final Map<String, List<NotificationMessage>> _history = {};

  bool get ready => _ready;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  /// Сообщение с экрана блокировки iOS группируется по чату; баннер и звук
  /// показываются и когда приложение открыто (как на Android).
  static DarwinNotificationDetails _darwin({String? thread}) => DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        threadIdentifier: thread,
      );

  Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher_monochrome'),
          // Разрешение на iOS спрашиваем сами, в нужный момент, а не при запуске.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final chatId = response.payload;
          if (chatId != null && chatId.isNotEmpty) onOpenChat(chatId);
        },
      );
      final android = _android;
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        messagesChannel,
        'Сообщения',
        description: 'Новые сообщения в чатах',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        eventsChannel,
        'События сцены',
        description: 'Уведомления, которые показывает сцена',
        importance: Importance.high,
      ));
      _ready = true;

      // Приложение открыли нажатием на уведомление — перейти в чат.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) && payload != null && payload.isNotEmpty) {
        Timer(const Duration(milliseconds: 600), () => onOpenChat(payload));
      }
    } catch (error) {
      debugPrint('Уведомления недоступны: $error');
    }
  }

  /// Разрешение (Android 13+ и iOS). Спрашиваем один раз за запуск.
  Future<bool> ensurePermission() async {
    if (!_ready) return false;
    if (_permissionAsked) return enabledInSystem();
    _permissionAsked = true;
    try {
      final ios = _ios;
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (error) {
      debugPrint('Разрешение на уведомления не получено: $error');
      return false;
    }
  }

  Future<bool> enabledInSystem() async {
    if (!_ready) return false;
    final ios = _ios;
    if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? false;
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Новое сообщение в чате (как у мессенджеров: имя, текст, переписка).
  Future<void> showMessage({
    required String chatId,
    required String chatName,
    required NotificationMessage message,
    String? avatarPath,
  }) async {
    if (!_ready) return;
    await ensurePermission();
    final list = _history.putIfAbsent(chatId, () => [])..add(message);
    if (list.length > 6) list.removeAt(0);
    final icon = avatarPath != null && File(avatarPath).existsSync()
        ? BitmapFilePathAndroidIcon(avatarPath)
        : null;
    final style = MessagingStyleInformation(
      const Person(name: 'Вы'),
      conversationTitle: list.length > 1 ? chatName : null,
      messages: [
        for (final m in list) Message(m.text, m.time, Person(name: m.sender, icon: icon)),
      ],
    );
    try {
      await _plugin.show(
        chatNotificationId(chatId),
        chatName,
        message.text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            messagesChannel,
            'Сообщения',
            channelDescription: 'Новые сообщения в чатах',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            styleInformation: style,
            when: message.time.millisecondsSinceEpoch,
            showWhen: true,
            autoCancel: true,
          ),
          iOS: _darwin(thread: chatId),
        ),
        payload: chatId,
      );
    } catch (error) {
      debugPrint('Уведомление не показано: $error');
    }
  }

  /// Уведомление сцены с произвольным заголовком и текстом.
  Future<void> showEvent({
    required int id,
    required String title,
    required String text,
    DateTime? time,
    String? chatId,
  }) async {
    if (!_ready) return;
    await ensurePermission();
    try {
      await _plugin.show(
        id,
        title,
        text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            eventsChannel,
            'События сцены',
            channelDescription: 'Уведомления, которые показывает сцена',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(text),
            when: (time ?? DateTime.now()).millisecondsSinceEpoch,
            showWhen: true,
            autoCancel: true,
          ),
          iOS: _darwin(thread: chatId),
        ),
        payload: chatId,
      );
    } catch (error) {
      debugPrint('Уведомление сцены не показано: $error');
    }
  }

  /// Убрать уведомление чата (чат открыли).
  Future<void> clearChat(String chatId) async {
    _history.remove(chatId);
    if (!_ready) return;
    try {
      await _plugin.cancel(chatNotificationId(chatId));
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    _history.clear();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
