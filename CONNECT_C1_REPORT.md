# Отчёт: Connect C1

Дата: 26.09.2026. Версия Messenger 0.13.0. Схема базы не менялась.

## Итог

```
BUILD:  NOT RUN — в среде разработки нет Flutter и Android SDK.
        Анализ, форматирование, тесты и сборку debug/release выполнит
        GitHub Actions после загрузки. Результат сюда не вписан, потому что
        его ещё нет.
APK:    NOT BUILT — появится в Artifacts сборки (replika-apk, release).
TESTS:  NOT RUN — 39 новых тестов Connect написаны и разобраны вручную
        по коду; всего тестов 142.
PHONE:  NOT PHYSICALLY VERIFIED
```

Выполнены только проверки, доступные без Flutter:
- скобки, импорты и ссылки на токены во всех 135 файлах Dart;
- правка манифеста — на образце шаблона Flutter, включая повторный запуск;
- криптографическая схема и сценарии тестов — вручную по коду.

Всё, что ниже названо «реализовано», **реализовано в коде**. «Работает»
будет можно сказать после зелёной сборки и проверки на телефоне.

---

## 1. Изменённые файлы

| Файл | Что изменено |
|---|---|
| `pubspec.yaml` | Зависимости `flutter_secure_storage` ^9.2.4, `cryptography` ^2.7.0, `flutter_foreground_task` ^9.2.0; версия 0.13.0 |
| `tool/prepare_android.sh` | Разрешения **INTERNET**, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_NETWORK_STATE, CHANGE_WIFI_MULTICAST_STATE, WAKE_LOCK, FOREGROUND_SERVICE, FOREGROUND_SERVICE_CONNECTED_DEVICE в основном манифесте (раньше INTERNET был только в debug); объявление фоновой службы с типом `connectedDevice` |
| `lib/app/services.dart` | Служба `connect`; запуск в фоне при старте; остановка в `close()`; хранилище в памяти для тестов |
| `lib/app/scene_engine.dart` | Новый метод `performCommand()` — команда с результатом. Существующие методы не менялись |
| `lib/app/scene_effects.dart` | `lastCreatedMessageId`; удаление, правка, статус по `messageId`; действие «Изменить сообщение» с отменой |
| `lib/app/navigator.dart` | `toRoot()` (OPEN_SCREEN CHAT_LIST), `openConnect()` |
| `lib/data/models/scene_action.dart` | Тип действия `editMessage` |
| `lib/data/repositories/message_repository.dart` | `byId()`, `updateText()` |
| `lib/data/repositories/scene_repository.dart` | `create(id:)` — сцена с заданным id |
| `lib/data/repositories/settings_repository.dart` | Ключи настроек Connect |
| `lib/features/operator/action_summary.dart`, `action_editor_screen.dart` | «Изменить сообщение» в таймлайне |
| `lib/features/operator/operator_home_screen.dart` | Карточка Connect |
| `lib/features/settings/addons_screen.dart` | Пункт Connect в «Дополнениях» |
| `lib/core/brand/brand.dart` | Версия |
| `test/integration_test.dart` | Хранилище ключей в памяти |

`android/` в репозитории нет: папку создаёт `flutter create` при каждой
сборке, а все правки Android вносит `tool/prepare_android.sh`.

## 2. Новые файлы

```
lib/connect/protocol/protocol.dart
lib/connect/security/secret_store.dart
lib/connect/security/crypto.dart
lib/connect/security/trust.dart
lib/connect/server/connect_server.dart
lib/connect/queue/command_queue.dart
lib/connect/actions/connect_actions.dart
lib/connect/scene/connect_scene.dart
lib/connect/service/connect_service.dart
lib/connect/service/foreground.dart
lib/connect/client/connect_client.dart
lib/features/connect/connect_settings_screen.dart
lib/features/connect/connect_test_screen.dart
test/connect_protocol_test.dart
test/connect_security_test.dart
test/connect_queue_test.dart
test/connect_integration_test.dart
PROP_CONTROL_PROTOCOL.md
CONNECT_C1_REPORT.md
```

## 3. Архитектура

```
Connect (lib/connect/)
├── Protocol   protocol/protocol.dart         версия 1, ConnectAction (whitelist), статусы, ошибки,
│                                             CommandRequest / CommandResult, лимиты
├── Server     server/connect_server.dart     WebSocket (dart:io), состояния соединения:
│                                             сопряжение → hello → зашифрованный сеанс
├── Security   security/crypto.dart           X25519, код сопряжения, HKDF, AES-256-GCM, защита от повтора кадров
│              security/trust.dart            Device ID, ключ телефона, доверенные устройства, отзыв
│              security/secret_store.dart     Android Keystore (flutter_secure_storage)
├── Pairing    server/connect_server.dart     pair_request / pair_challenge / pair_result
│              service/connect_service.dart   окно сопряжения 2 мин, код на экране, «Разрешить»
├── Queue      queue/command_queue.dart       по одной, повтор commandId, STOP, REJECT_IF_BUSY
├── Actions    actions/connect_actions.dart   таблица ActionType → обработчик, проверка параметров,
│                                             SEQUENCE / DELAY, «кто кому»
├── Scene      scene/connect_scene.dart       сцена «Connect» → существующий Scene Engine
├── Service    service/connect_service.dart   состояние, настройки, журнал, DEVICE_INFO
│              service/foreground.dart        фоновая служба, режим «Съёмка»
├── Client     client/connect_client.dart     клиент протокола (проверка и тесты, образец для Controller)
└── Tests      test/connect_*_test.dart
UI: lib/features/connect/connect_settings_screen.dart, connect_test_screen.dart
```

Путь команды:

```
сокет → ConnectServer (расшифровка, права) → CommandQueue → ConnectActions
→ ConnectScene → SceneEngine.performCommand → SceneDataEffects → репозитории → SQLite
→ экраны обновляются сами
```

## 4. Протокол

Полное описание — в `PROP_CONTROL_PROTOCOL.md`. Кратко:

- **Команда:** `type, protocolVersion, commandId, deviceId?, actionType,
  timestamp, policy, payload`.
- **Ответ:** `commandId, success, status, error?, message, timestamp,
  result`.
- **commandId** — уникальный; повтор возвращает `ALREADY_PROCESSED`
  без повторного выполнения.
- **deviceId** — физический телефон (`MESSENGER-XXXXXX`).
- **characterId** — персонаж. Задаётся в payload
  (`fromCharacterId`, `toCharacterId`, `characterId`). Владельца телефона
  назначает ASSIGN_CHARACTER — персонаж не привязан к телефону навсегда.
- **Версия** — `protocolVersion: 1`; более новые команды отклоняются.
- **Ошибки:** UNAUTHORIZED, INVALID_REQUEST, INVALID_COMMAND,
  INVALID_TARGET, UNSUPPORTED_ACTION, DEVICE_NOT_READY, SCENE_ERROR,
  ACTION_FAILED, SESSION_EXPIRED, CANCELLED, INTERNAL_ERROR. Трассировки
  и внутренние подробности наружу не отдаются.

## 5. Реализованные ActionType (в коде)

**Служебные:** PING, DEVICE_INFO, LIST_CHARACTERS, LIST_MEDIA,
ASSIGN_CHARACTER, SET_CONTACT, STOP.

**Сцена:** MESSAGE, TYPING, MEDIA (фото, видео, голосовое, аудио как
голосовое, видеосообщение), DELETE_MESSAGE, EDIT_MESSAGE, MESSAGE_STATUS,
CALL, VIDEO_CALL, CALL_ACCEPT, CALL_DECLINE, END_CALL, NOTIFICATION,
OPEN_SCREEN (CHAT, CHAT_LIST, PROFILE, BACK), DELAY, SEQUENCE, RESET_SCENE.

## 6. Не реализованы

- **Группы** — CREATE_CHAT, ADD_PARTICIPANT, REMOVE_PARTICIPANT.
  Объявлены в протоколе и отвечают `UNSUPPORTED_ACTION` / «Group actions
  are not implemented yet». В Messenger нет интерфейса групп — этап C3,
  только по вашему разрешению.
- **Файл как сообщение** (MEDIA с видом `file`) — в движке нет такого
  действия, ответ `UNSUPPORTED_ACTION`.
- **Сообщение между двумя персонажами, ни один из которых не владелец
  телефона,** — `INVALID_TARGET`: такое бывает только в группах.
- **Отложено до C2:** поиск телефонов в сети (UDP), выполнение
  по `executeAt`, автоматическое переподключение со стороны Messenger.

## 7. Безопасность

- **Сопряжение.**
  - Работает только при открытом окне (2 минуты, кнопка на телефоне).
  - Обмен ключами X25519; 6-значный код из ключей и случайных чисел обеих
    сторон; сверка кодов оператором и «РАЗРЕШИТЬ» на телефоне.
  - Устройство посередине меняет код, и коды на экранах не совпадут.
- **Хранение ключей.** Ключ телефона и список доверенных устройств — в
  Android Keystore через `flutter_secure_storage`. В SQLite, настройках,
  журнале и исходниках секретов нет.
- **Сеанс.**
  - `hello` с разовым ключом.
  - Ключи сеанса выводятся (HKDF-SHA256) из двух обменов: разовых ключей
    и постоянных. Второй подтверждает, что это именно доверенный
    Controller и именно этот телефон.
  - Срок — 12 часов, затем `SESSION_EXPIRED`.
- **Шифрование.** Каждый кадр — AES-256-GCM. Номер кадра и направление
  входят в проверяемые данные: подделка, чужой ключ или повтор кадра →
  `UNAUTHORIZED` и разрыв соединения.
- **Отзыв доверия.** Кнопка «Отозвать» закрывает сеанс; следующее
  подключение получает `UNAUTHORIZED`.
- **Защита от повторного выполнения.**
  - Кэш последних 500 результатов по `commandId` в памяти; 200 из них
    сохраняются в настройки и переживают перезапуск.
  - Пока команда выполняется, повтор ждёт её результата.
- **Что исключено.**
  - Выполняются только ActionType из списка.
  - Экраны — только из перечня OPEN_SCREEN.
  - Медиа — только по id из медиатеки, путей к файлам нет.
  - Нет shell, произвольного кода, Activity и Intent извне.
  - Размеры параметров ограничены.
- **Права.** VIEW, CONTROL, MESSAGES, CALLS, MEDIA, GROUPS, SCREENS, RESET
  проверяются на каждую команду и на каждый шаг SEQUENCE. В C1
  доверенному устройству выдаются все.
- **Журнал** пишет тип команды и commandId — без текстов сообщений,
  ключей и токенов.

## 8. Связь со Scene Engine

Connect не пишет в SQLite:

```dart
// ConnectActions: MESSAGE «Маша → Иван» → действие сцены от имени участника
_action(ActionType.showIncoming, 'char-masha', {'text': 'Ты где?', 'typingMs': 1500})

// ConnectScene.run → существующий движок
await services.engine.performCommand(action, cancelled: () => cancel.cancelled);

// SceneEngine.performCommand → тот же SceneDataEffects, что у таймлайна
// и ручных действий: сообщения, «печатает…», звонки, уведомления,
// журнал отмены и сброс.
```

- **Сцена Connect** — `connect-<виртуальный телефон>`. Создаётся при
  первой команде, участники добавляются сами.
- **RESET_SCENE** — это `SceneEngine.reset()` этой сцены. Обычные данные
  и другие сцены не затрагиваются; это проверяет отдельный тест.
- **Дубль в операторской.** Пока в операторской идёт дубль другой сцены,
  Connect отвечает `DEVICE_NOT_READY` и чужую сцену не прерывает.

## 9. Тесты

**Не запускались.** Их запустит сборка на GitHub.

| Файл | Тестов | Что проверяет |
|---|---|---|
| `connect_protocol_test.dart` | 9 | сериализация и разбор, повреждённые пакеты, версия протокола, неизвестный и неподдерживаемый actionType, ответы без трассировок |
| `connect_security_test.dart` | 6 | совпадение и зависимость кода сопряжения, шифрование, повтор кадра, подделка, чужой ключ, стабильный Device ID, выдача и отзыв доверия |
| `connect_queue_test.dart` | 8 | порядок 001 → 002 → 003, повтор во время и после выполнения, кэш после перезапуска, REJECT_IF_BUSY, STOP, служебные мимо очереди, переполнение |
| `connect_integration_test.dart` | 16 | настоящий сервер и клиент по сокету + настоящая SQLite + Scene Engine — см. ниже |

**Интеграционные тесты:**
- **Подключение и безопасность:**
  - сопряжение при закрытом окне;
  - совпадение кодов, отклонение и разрешение;
  - неизвестное устройство;
  - подключение, отключение, повторное подключение;
  - отзыв доверия;
  - истёкший сеанс;
  - мусор вместо кадра.
- **Команды:**
  - MESSAGE и повтор commandId;
  - ошибки параметров и группы;
  - TYPING, EDIT, STATUS, DELETE;
  - CALL и END_CALL;
  - NOTIFICATION и OPEN_SCREEN;
  - SEQUENCE с DELAY и ошибкой внутри;
  - STOP;
  - RESET_SCENE не трогает чужие данные;
  - ASSIGN_CHARACTER.

Пропущенных нет.

**Физическая проверка на телефоне:** не выполнялась — NOT PHYSICALLY
VERIFIED.

## 10. APK

- **Сборка:** не выполнялась мной. GitHub Actions собирает **release**
  (`flutter build apk --release`).
- **Debug APK:** workflow не собирает. Если нужен, добавьте шаг
  `flutter build apk --debug`.
- **Где будет APK:** Artifacts → `replika-apk` → `app-release.apk`.
- **Размер:** станет известен после сборки.
- **Ошибки:** неизвестны до сборки.

**Главные риски сборки** — три новых нативных плагина:
- `flutter_foreground_task` 9 — я взял его API из документации 9.2,
  возможны расхождения в именах параметров;
- `flutter_secure_storage` 9;
- `cryptography` — чистый Dart, нативного риска нет.

Если анализ или Gradle упадут — пришлите фото красного шага.

### Как проверить Connect на телефоне

1. Настройки → Дополнения → **Connect** → включить. Статус станет
   «Ожидание подключения», виден Device ID и адрес.
2. **«ПРОВЕРКА CONNECT»** → «СОПРЯЖЕНИЕ». Коды «Controller» и телефона
   должны совпасть → «РАЗРЕШИТЬ» → в результатах «Сеанс открыт».
3. **«MESSAGE «Тест Connect»»** → EXECUTED. В чате с собеседником
   появится сообщение.
4. **«ПОВТОР ПОСЛЕДНЕЙ КОМАНДЫ»** → ALREADY_PROCESSED, второго сообщения
   нет.
5. TYPING, CALL / END_CALL, NOTIFICATION, SEQUENCE → смотрите на экран.
6. **Ошибки:** «Неизвестная команда» → INVALID_COMMAND; «Группа» →
   UNSUPPORTED_ACTION; «Пустой текст» → INVALID_REQUEST.
7. **RESET_SCENE** → сообщения Connect исчезли, обычные переписки
   на месте.
8. **Работа при погашенном экране** → включить, в шторке появится
   уведомление «Connect». Затем «Режим «Съёмка»» → «Реплика · Активно».
9. **Доверенные устройства** → «Отозвать» → повторное «Подключиться»
   на экране проверки → UNAUTHORIZED.

Проверка с другого устройства по Wi-Fi возможна только клиентом
протокола (см. `PROP_CONTROL_PROTOCOL.md`). Отдельного Prop Controller
по условиям задачи нет.

## Ограничения

- **Звонок поверх экрана блокировки** не показывается (из прошлого этапа).
- **Фоновая работа.** Держится, пока работает фоновая служба. Оболочки
  производителей (Xiaomi, Huawei) могут её останавливать — поможет
  «без ограничений» в настройках батареи для «Реплики». Физически
  не проверено.
- **Порт 47620.** Если он занят, статус «Ошибка» и понятный текст.

## Дальше

Работа остановлена после C1. C2 и группы начнутся только по вашему
отдельному подтверждению после сборки и проверки на телефоне.
