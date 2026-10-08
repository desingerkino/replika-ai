import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db/app_database.dart';
import '../data/models/call_record.dart';
import '../data/repositories/call_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../data/repositories/device_repository.dart';
import '../data/repositories/media_repository.dart';
import '../data/repositories/prepared_reply_repository.dart';
import '../data/repositories/scene_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/story_repository.dart';
import '../data/seed/demo_seed.dart';
import 'audio_playback.dart';
import 'call_audio.dart';
import 'call_engine.dart';
import 'call_services.dart';
import 'navigator.dart';
import '../connect/security/secret_store.dart';
import '../connect/service/connect_service.dart';
import '../connect/service/foreground.dart';
import '../data/profile_transfer.dart';
import 'auto_reply.dart';
import 'improv.dart';
import 'kino.dart';
import 'notifications.dart';
import 'improv_sender.dart';
import 'media_store.dart';
import 'scene_effects.dart';
import 'scene_engine.dart';
import 'operator_toast.dart';
import 'typing.dart';
import 'operator/operator_commands.dart';
import 'operator/operator_inputs.dart';
import '../connect/actions/prop_controller_input.dart';
import '../core/util/media_paths.dart';
import '../core/theme/app_theme_id.dart';
import '../core/theme/theme_manager.dart';

/// Все службы приложения. Создаются один раз при запуске.
class AppServices {
  AppServices._({
    required this.database,
    required this.settings,
    required this.devices,
    required this.contacts,
    required this.chats,
    required this.messages,
    required this.media,
    required this.scenes,
    required this.replies,
    required this.calls,
    required this.currentDeviceId,
    required this.theme,
    required this.volumeKeysEnabled,
    required this.resetToastEnabled,
    required this.kino,
    required this.notificationsEnabled,
  });

  final AppDatabase database;
  final SettingsRepository settings;
  final DeviceRepository devices;
  final ContactRepository contacts;
  final ChatRepository chats;
  final MessageRepository messages;

  /// Медиатека: выбор, копирование и удаление файлов.
  final MediaStore media;

  /// Проигрыватель голосовых и аудио.
  final AudioPlayback audio = AudioPlayback();

  final SceneRepository scenes;

  /// Движок сцен.
  late final SceneEngine engine = SceneEngine(SceneDataEffects(this));

  final PreparedReplyRepository replies;

  final CallRepository calls;

  /// Истории персонажей (вкладка «Истории» и кольца над списком чатов).
  late final StoryRepository stories = StoryRepository(database);

  /// Постановочные звонки.
  /// Только для автотестов: хранилище ключей в памяти вместо Keystore.
  static SecretStore Function()? testSecretStore;

  /// Connect — управление с Prop Controller по локальной сети.
  late final ConnectService connect = ConnectService(
    services: this,
    store: testSecretStore?.call() ?? KeystoreSecretStore(),
    foreground: testSecretStore == null ? ConnectForeground() : null,
  );

  /// Только для автотестов: звуки звонка без проигрывателя.
  static CallSounds Function()? testCallSounds;

  late final CallEngine callEngine = CallEngine(
    recorder: ServicesCallRecorder(this),
    sounds: testCallSounds?.call() ?? AssetCallSounds(),
  )..addListener(_onCallChanged);

  CallPhase _lastCallPhase = CallPhase.idle;

  /// Маршрут звука звонка: разговорный динамик / громкая связь, микрофон,
  /// датчик приближения. После звонка сессия возвращается к медиа.
  final CallAudio callAudio = CallAudio();

  /// Звонок начался — показать экран звонка поверх всего.
  void _onCallChanged() {
    final phase = callEngine.phase;
    if (_lastCallPhase == CallPhase.idle && phase != CallPhase.idle) {
      unawaited(audio.stop());
      unawaited(AppNavigator.openCall());
    }
    _lastCallPhase = phase;
    _syncCallAudio(phase);
  }

  /// Входящий звонит как рингтон (громко); с вызова и до конца разговора —
  /// звук телефонного разговора.
  void _syncCallAudio(CallPhase phase) {
    switch (phase) {
      case CallPhase.outgoing:
      case CallPhase.connecting:
      case CallPhase.active:
        final video = callEngine.session?.kind == CallKind.video;
        unawaited(() async {
          if (callAudio.active) {
            if (callAudio.speaker != callEngine.speaker) await callAudio.setSpeaker(callEngine.speaker);
          } else {
            await callAudio.begin(speaker: callEngine.speaker, video: video);
          }
          await callAudio.setMicrophoneMuted(callEngine.muted);
        }());
      case CallPhase.ended:
      case CallPhase.idle:
        unawaited(callAudio.end());
      case CallPhase.incoming:
        break;
    }
  }

  /// Экспорт и импорт профилей (виртуальных телефонов персонажей).
  late final ProfileTransfer profiles =
      ProfileTransfer(database.db, database.changes, mediaDir: media.mediaDirectory);

  /// Импровизация и очередь ответов.
  late final ImprovController improv = ImprovController(ServicesImprovSender(this));

  /// Автоответы ИИ (только в сборке «Реплика AI», иначе ничего не делает).
  late final AutoReplyController autoReply = AutoReplyController(this);

  /// Единый слой команд оператора: все источники управления (экран,
  /// кнопки громкости Android, клавиатура, Prop Controller) приходят сюда,
  /// а дальше — прежняя логика приоритетов: дубль, звонок, импровизация.
  late final OperatorCommandLayer operatorCommands = OperatorCommandLayer(
    engine: engine,
    calls: callEngine,
    improv: improv,
    // Ощутимый отклик без звука и без элементов в кадре.
    onResetStart: () => unawaited(HapticFeedback.heavyImpact()),
    onResetDone: () {
      if (resetToastEnabled.value) showOperatorToast('Сцена сброшена');
    },
  );

  /// Кнопки и жесты на экране приложения.
  late final AppOperatorInput appInput = AppOperatorInput(operatorCommands);

  /// Команды SCENE_NEXT, SCENE_PREVIOUS, SCENE_STOP из Connect.
  late final PropControllerInput propInput = PropControllerInput(operatorCommands);

  /// Все источники команд. Выбор по платформе — только в
  /// [createPlatformOperatorInputs].
  late final List<OperatorInput> operatorInputs = [
    appInput,
    KeyboardInput(operatorCommands),
    propInput,
    ...createPlatformOperatorInputs(operatorCommands, volumeKeysEnabled: volumeKeysEnabled),
  ];

  /// Какой чат сейчас открыт на экране (движок не увеличивает
  /// счётчик непрочитанных, если собеседник пишет в открытый чат).
  final ValueNotifier<String?> openChatId = ValueNotifier<String?>(null);

  /// Кнопки громкости управляют сценой (Настройки → Дополнения).
  final ValueNotifier<bool> volumeKeysEnabled;

  /// Показывать плашку «Сцена сброшена» после сброса кнопками.
  final ValueNotifier<bool> resetToastEnabled;

  /// КИНОРЕЖИМ.
  final KinoController kino;

  /// Показывать уведомления о новых сообщениях (Настройки → Дополнения).
  final ValueNotifier<bool> notificationsEnabled;

  /// Уведомления Android.
  late final NotificationService notifications = NotificationService(
    onOpenChat: (chatId) => unawaited(AppNavigator.openChat(chatId)),
  );

  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled.value = value;
    await settings.setValue(SettingKeys.notifications, value ? '1' : '0');
    if (value) {
      await notifications.ensurePermission();
    } else {
      await notifications.cancelAll();
    }
  }

  /// Входящее в чат, который сейчас не открыт: уведомление, как у
  /// настоящего мессенджера. Чаты «без звука» уведомлений не дают.
  Future<void> notifyIncoming(String chatId, String text, {DateTime? time, String? senderName}) async {
    if (!notificationsEnabled.value || openChatId.value == chatId) return;
    final header = await chats.header(chatId);
    if (header == null || header.chat.muted) return;
    await notifications.showMessage(
      chatId: chatId,
      chatName: header.peer.displayName,
      avatarPath: header.peer.avatarPath,
      message: NotificationMessage(
        sender: senderName ?? header.peer.displayName,
        text: text,
        time: time ?? DateTime.now(),
      ),
    );
  }

  /// Сколько открыто тёмных экранов (звонок, просмотр фото и видео):
  /// своя строка состояния над ними рисуется светлыми значками.
  final ValueNotifier<int> darkScreens = ValueNotifier<int>(0);

  Future<void> setVolumeKeys(bool value) async {
    volumeKeysEnabled.value = value;
    await settings.setValue(SettingKeys.volumeKeys, value ? '1' : '0');
  }

  Future<void> setResetToast(bool value) async {
    resetToastEnabled.value = value;
    await settings.setValue(SettingKeys.resetToast, value ? '1' : '0');
  }

  /// Освободить ресурсы (в приложении не нужно — живёт до выхода;
  /// используется автотестами, чтобы «перезапустить» приложение).
  Future<void> close() async {
    await connect.stop();
    for (final input in operatorInputs) {
      input.detach();
    }
    typing.stopAll();
    kino.dispose();
    await database.close();
  }

  /// Переключить виртуальный телефон (точку зрения).
  /// Сменить профиль (виртуальный телефон). Идущая сцена не останавливается:
  /// её события адресованы профилям персонажей, а не экрану.
  Future<void> setCurrentDevice(String deviceId) async {
    if (currentDeviceId.value == deviceId) return;
    typing.stopAll();
    await audio.stop();
    currentDeviceId.value = deviceId;
    // Открытое справа принадлежало другому телефону.
    AppNavigator.detailChat.value = null;
    AppNavigator.detailScreen.value = null;
    await settings.setValue(SettingKeys.currentDeviceId, deviceId);
  }

  /// Текущий виртуальный телефон (точка зрения).
  final ValueNotifier<String> currentDeviceId;

  /// Тема оформления (Replika, Telegram) и яркость.
  final ThemeManager theme;

  /// Как в системе, светлая или тёмная.
  ValueNotifier<ThemeMode> get themeMode => theme.themeMode;

  /// Индикатор «печатает…» по чатам.
  final TypingRegistry typing = TypingRegistry();

  Future<void> setThemeMode(ThemeMode mode) => theme.setMode(mode);

  Future<void> setTheme(AppThemeId id) => theme.setTheme(id);

  /// [databasePath] — только для автотестов (временная база).
  static Future<AppServices> open({String? databasePath}) async {
    final database = await AppDatabase.open(path: databasePath);
    try {
      await DemoSeed(database).ensure();
      final settings = SettingsRepository(database);
      final devices = DeviceRepository(database);

      var deviceId = await settings.getValue(SettingKeys.currentDeviceId);
      if (deviceId == null || await devices.byId(deviceId) == null) {
        final all = await devices.list();
        if (all.isEmpty) {
          throw StateError('В базе нет ни одного виртуального телефона');
        }
        deviceId = all.first.id;
        await settings.setValue(SettingKeys.currentDeviceId, deviceId);
      }

      final theme = ThemeManager.restore(
        savedId: await settings.getValue(ThemeSettingKeys.themeId),
        savedMode: await settings.getValue(ThemeSettingKeys.themeMode),
        persist: settings.setValue,
      );

      final volumeKeys = await settings.getValue(SettingKeys.volumeKeys);
      final resetToast = await settings.getValue(SettingKeys.resetToast);
      final activeScene = await settings.getValue(SettingKeys.activeSceneId);
      final kinoJson = await settings.getValue(SettingKeys.kino);
      final notificationsSetting = await settings.getValue(SettingKeys.notifications);

      final services = AppServices._(
        database: database,
        settings: settings,
        devices: devices,
        contacts: ContactRepository(database),
        chats: ChatRepository(database),
        messages: MessageRepository(database),
        media: MediaStore(MediaRepository(database)),
        scenes: SceneRepository(database),
        replies: PreparedReplyRepository(database),
        calls: CallRepository(database),
        currentDeviceId: ValueNotifier<String>(deviceId),
        theme: theme,
        volumeKeysEnabled: ValueNotifier<bool>(volumeKeys != '0'),
        resetToastEnabled: ValueNotifier<bool>(resetToast != '0'),
        notificationsEnabled: ValueNotifier<bool>(notificationsSetting != '0'),
        kino: KinoController(
          KinoSettings.fromJson(kinoJson),
          persist: (json) => settings.setValue(SettingKeys.kino, json),
        ),
      );
      try {
        MediaPaths.configure((await services.media.mediaDirectory()).path);
      } catch (error) {
        // Папки приложения нет (автотесты без path_provider): пути берутся как есть.
        MediaPaths.reset();
        debugPrint('Папка медиатеки недоступна: $error');
      }
      // Голосовое дослушано до конца — отметка «прослушано» (не статус доставки).
      services.audio.onCompleted = (messageId) => unawaited(
            services.messages.setPlayed(messageId).catchError((Object e) => debugPrint('Отметка не сохранена: $e')),
          );
      services.kino.apply();
      await services.notifications.init();
      // Connect поднимается в фоне: запуск приложения его не ждёт.
      unawaited(services.connect.init().catchError((Object e) => debugPrint('Connect не запущен: $e')));

      // После перезапуска сцена снова выбрана: «Назад» недоступен (дубль
      // не идёт), но сброс — и кнопками, и на панели — работает по
      // сохранённому журналу дубля.
      if (activeScene != null) {
        try {
          await services.engine.load(activeScene);
        } catch (error) {
          debugPrint('Сцена не восстановлена: $error');
          await settings.setValue(SettingKeys.activeSceneId, null);
        }
      }
      for (final input in services.operatorInputs) {
        input.attach();
      }
      return services;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }
}

/// Доступ к службам из любого экрана.
class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  /// С подпиской на изменения (для build).
  static AppServices of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<Services>();
    assert(widget != null, 'Services отсутствует в дереве виджетов');
    return widget!.services;
  }

  /// Без подписки (для initState и обработчиков).
  static AppServices read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<Services>();
    assert(element != null, 'Services отсутствует в дереве виджетов');
    return (element!.widget as Services).services;
  }

  @override
  bool updateShouldNotify(Services oldWidget) => oldWidget.services != services;
}
