# «Реплика» 0.17.0 — Connect 1.3 для Prop Controller (M1–M4)

Доработки по отчёту PROP_CONTROLLER_AUDIT.md: обязательные пункты M1–M4.
Структура Messenger не менялась: только новые действия Connect и точечные
правки там, где они выполняются.

**Статус: BUILD NOT RUN, NOT PHYSICALLY VERIFIED.** В этой среде нет Flutter —
код не компилировался и тесты не запускались. Проверка: сборка в GitHub Actions
(анализ, APK, `flutter test`) и два телефона + пульт на площадке.

## Что добавлено

**M1. `UPSERT_CHARACTER`** (область `control`, через очередь). Создаёт или
обновляет персонажа с ключом пульта (`characterId`). Частичное обновление:
меняются только переданные поля. `avatarMediaId` — аватар из медиа, переданного
с пульта (`null` — убрать). `contactName` — как записан в контактах;
`addToContacts: false` — не в контактах (в чате виден номер). Владелец телефона
в свои контакты не попадает. `RESET_SCENE` персонажей пульта не удаляет.

**M2. Передача медиа кусками:** `MEDIA_UPLOAD_BEGIN` → `MEDIA_UPLOAD_CHUNK` →
`MEDIA_UPLOAD_COMMIT` (область `media`, мимо очереди сцены — идут во время
подготовки, не мешают дублю). Кусок до 96 КБ, файл до 64 МБ. Недокачанное
лежит в `media/.connect_uploads/*.part`; после обрыва `BEGIN` возвращает,
сколько уже получено, и передача продолжается с этого места. Контрольная
сумма SHA-256 проверяется до записи в медиатеку. Повтор с тем же `mediaId` —
`exists: true`, файл не передаётся второй раз.

**M3. Время у сообщения:** необязательное `messageTime` (мс) у `MESSAGE` и
`MEDIA` — какое время показать у сообщения в чате (например 23:47 по сценарию).

**M4. `OPEN_SCREEN`:** вкладки `CALLS`, `CONTACTS`, `CHAT_LIST` и групповой чат
(`screen: CHAT` + `groupId`).

`DEVICE_INFO` сообщает `connectVersion: 1.3.0` и новые действия в
`supportedActions` — по ним пульт понимает, что подготовка с пульта доступна.

## Файлы

Новые:
- `lib/connect/actions/media_upload.dart` — приём файлов кусками (M2).
- `test/connect_prep_test.dart` — 12 тестов: DEVICE_INFO 1.3, M1 ×5, M2 ×4, M3, M4.

Изменённые:
- `lib/connect/protocol/protocol.dart` — Connect 1.3.0; действия
  `UPSERT_CHARACTER`, `MEDIA_UPLOAD_*`; экраны `CALLS`, `CONTACTS`; лимиты загрузки.
- `lib/connect/actions/connect_actions.dart` — обработчики M1–M4.
- `lib/app/media_store.dart` — регистрация загруженного файла в медиатеке.
- `lib/data/repositories/contact_repository.dart` — персонаж с заданным ключом.
- `lib/data/repositories/message_repository.dart` — время сообщения (M3).
- `lib/app/navigator.dart`, `lib/features/shell/home_shell.dart` — переключение вкладки главного экрана (M4).
- `lib/core/brand/brand.dart`, `pubspec.yaml` — версия 0.17.0+19.
- `PROP_CONTROL_PROTOCOL.md` — раздел 7а «Connect 1.3», таблицы действий и ограничений.

## Совместимость

Протокол остаётся v1: старый пульт (или образец клиента) работает как раньше.
Новые поля необязательны. Проекты, медиатека и журнал «Реплики» не мигрируются.

## Риск, замеченный при проверке (не исправлялся)

`lib/features/profiles/profiles_screen.dart` вызывает `FilePicker.platform.saveFile/pickFiles`,
а медиатека (`lib/app/media_store.dart`) — `FilePicker.pickFiles` (без `.platform`).
В file_picker 12 верна только одна из форм. Если сборка упадёт на одной из
этих строк — привести её к форме второй. Пульт использует ту же форму, что медиатека.

## Не сделано (желательные M5–M9)

История звонков без звонка на экране, уведомление со звуком/без, заряд батареи
в DEVICE_INFO, выборочные права при сопряжении, удаление «у себя / для всех».
