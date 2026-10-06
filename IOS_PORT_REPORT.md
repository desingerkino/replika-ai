# Отчёт о портировании на iOS (iPhone и iPad)

Исходная версия: 0.17.0+19. Работа велась без Flutter SDK, Xcode и Mac:
**код не компилировался и не запускался ни разу.** Проверялись только чтением
кода и скриптом проверки парности скобок по всем `.dart`-файлам. Это не
замена `flutter analyze`.

## Реализовано

### Слой команд оператора (этапы 2–7)
* `lib/app/operator/operator_commands.dart`: `OperatorCommand` (`next`,
  `previous`, `stop`, `reset`), `OperatorInputSource`, `OperatorOutcome`,
  `OperatorInput`, `OperatorCommandLayer` (`dispatch`, `post`, `canHandle`).
  Приоритет прежний: дубль → звонок → импровизация.
* `lib/app/operator/operator_inputs.dart`: `AppOperatorInput`,
  `AndroidVolumeInput` (оборачивает прежний `VolumeKeyControl`),
  `KeyboardInput`, `createPlatformOperatorInputs` (единственный выбор по
  платформе).
* `lib/connect/actions/prop_controller_input.dart`: `PropControllerInput`.
* Connect: `SCENE_NEXT`, `SCENE_PREVIOUS`, `SCENE_STOP` (право `control`,
  мимо очереди, версия протокола прежняя; `STOP` и `RESET_SCENE` не менялись).
  Документация: `OPERATOR_COMMANDS.md`, `PROP_CONTROL_PROTOCOL.md` §7а-0.
* Scene Engine не менялся.

### iOS-платформа (этапы 8–9)
* `tool/prepare_ios.sh` (создаёт `ios/`, название, Bundle ID, iOS 14.0, русские
  тексты разрешений, иконка, делегат уведомлений), `tool/app_config.sh`
  (название, организация, Bundle ID: одно место для обеих платформ),
  `.github/workflows/build-ios.yml` (ручной запуск, без подписи),
  `IOS_SETUP.md`.
* Локальные уведомления iOS (баннер, звук, экран блокировки, группировка по
  чату, запрос разрешения, переход в чат).
* Connect при погашенном экране: на iOS экран не гаснет (wakelock_plus),
  фоновой службы нет. Тексты и настройки раздельны по платформам.
* Keychain: доступ после первой разблокировки, без переноса через копию.
* Пути к медиафайлам привязываются к текущей папке приложения при чтении
  (`MediaPaths`): на iOS контейнер может сменить путь.
* Тексты про «Android» нейтральные или раздельные по платформе; переключатель
  кнопок громкости на iOS скрыт.

### Адаптивность (этапы 10–12, частично)
* Порог двух панелей: ширина окна ≥ 840 и высота ≥ 480 (`adaptive.dart`).
* Оболочка: рейл + список + правая панель с чатом; все открытия чата идут через
  `AppNavigator`. Настройки: «Дополнения», «Медиатека», «Профили», «Избранное»
  открываются справа.
* Чат: ширина переписки ≤ 720, пузырь ≤ 520, пузыри считаются от ширины панели.
* Панель сцены: на широком экране две колонки (управление / таймлайн и
  журнал); кнопка «НАЗАД» через слой команд.
* Операторская главная и медиатека ограничены по ширине.
* Панель сцены на широком экране: плитка 2×2 ПРЕДЫДУЩЕЕ / ДАЛЕЕ / СТОП / СБРОС
  СЦЕНЫ (первые три через слой команд, сброс с подтверждением); запуск и
  пауза остаются на большой кнопке выше.
* Кинорежим: на iOS строка состояния занимает всю системную область сверху
  (время слева от выреза или Dynamic Island, значки справа), без выреза и на
  iPad это обычная полоса. Размеры берутся из системных отступов
  (`kinoStatusBand`), экраны получают отступ под неё.
* Звонок: прокручиваемое содержимое, аватар по размеру окна. Камера и
  видеокружок: пропорции берутся у камеры (учитывают ориентацию), круг
  подстраивается под свободную высоту.

## Android: что осталось без изменений
Scene Engine, SQLite (схема и миграции), Connect-протокол (кроме трёх новых
команд), `VolumeKeyInterpreter` и `VolumeKeyControl`, Android-ветки
уведомлений и фоновой службы, `RESET_SCENE`, `STOP`, 173 существующих теста.

## Регрессионный разбор Android (статический)
* Кнопки громкости: те же правила забора клавиш (`takeActive` = `canHandle(next)`,
  `sceneLoaded` = `canHandle(reset)`), тот же сброс с вибрацией и плашкой.
  Подключаются через список источников; **сверить на телефоне по
  `QA_CHECKLIST.md`.**
* Уведомления: Android-ветка прежняя; изменено условие запуска
  (`Android || iOS`) и проверка разрешения идёт через ту же системную функцию.
* Что изменилось и на Android:
  * на Android-планшетах и раскладных телефонах с окном ≥ 840 × 480 включится
    двухпанельный режим;
  * кнопка «НАЗАД» на панели сцены и клавиатурное управление (стрелки,
    пробел, удержание Esc) есть и на Android;
  * экран звонка теперь прокручивается и использует `IntrinsicHeight`;
  * в проект добавлен плагин `wakelock_plus`.

## Ограничения iOS
* Кнопки громкости приложению недоступны (без private API и обходов). Вместо
  них: кнопки панели, жест двумя пальцами, внешняя клавиатура, Prop Controller.
* При блокировке экрана приложение приостанавливается; Connect работает, пока
  «Реплика» открыта на экране.
* Автопоиск Connect (UDP broadcast) на iOS может требовать entitlement
  `multicast` от Apple (платный аккаунт, заявка); в проект он не добавлен,
  подключение по IP не зависит от него.
* Сам вырез и Dynamic Island скрыть нельзя; строка состояния кинорежима
  рисуется вокруг них.

## Что проверено

| Проверка | Результат |
|---|---|
| `flutter analyze` | GitHub Actions: нашёл 14 ошибок (исходная версия 0.17.0: конфликт `log` в Connect, цепочка `..` в экране проверки Connect; мой код: API `file_picker` 12), все исправлены, повторный запуск ещё не подтверждён |
| `flutter test` | GitHub Actions (Ubuntu): 181 прошёл, 31 упал; причины: необработанные ошибки отправки в поиске телефонов (`discovery.dart`) и гонка «кадр ошибки / закрытие» в клиенте Connect (исходный код) плюс неверный id персонажа в моём тесте; исправлено, повторный запуск ещё не подтверждён |
| `flutter build apk` | NOT RUN |
| `flutter build ios --no-codesign` | NOT RUN |
| Xcode, симулятор, реальный iPhone и iPad | NOT RUN |
| Парность скобок во всех `.dart` | выполнено (153 файла) |
| `bash -n` для `prepare_ios.sh` и `prepare_android.sh` | выполнено |
| Иконка iOS | сгенерирована, осмотрена |

## Что НЕ проверено (всё остальное)
* Компиляция вообще: возможны опечатки и ошибки типов, прежде всего в
  `KeyboardInput` (проверка «печатает ли пользователь»), панели сцены
  (разделение на `controls` и `timeline`), `HomeShell` (двухпанельный режим).
* Работа `prepare_ios.sh` на Mac (PlistBuddy, правка `AppDelegate.swift`,
  замена `IPHONEOS_DEPLOYMENT_TARGET`).
* Зависимости: `flutter_secure_storage` поднят с 9.x до ^11.2.0 (9.x несовместим
  с `file_picker` 12 по `win32`, пакеты не ставились), `wakelock_plus: ^1.6.0`.
  На Android новая версия `flutter_secure_storage` должна сама перенести
  сохранённые данные; если нет, Prop Controller придётся спарить заново.
  Другие конфликты версий возможны, их покажет `flutter pub get`.
* Нужны ли `NSPhotoLibraryUsageDescription` и `NSAppleMusicUsageDescription`
  для `file_picker` 12.x (указаны по документации).
* Уведомления на iOS (запрос, баннер при открытом приложении, экран блокировки,
  нажатие), камера, микрофон, переключение audio session после записи,
  выбор файлов, Connect и Local Network на реальных устройствах.
* Внешний вид на iPhone разных размеров и на iPad в обеих ориентациях,
  Split View.
* Android: все пункты «Регрессионного разбора» выше.

## Что осталось
* Сетка медиатеки (сейчас список шириной ≤ 720), редактор сцен «список +
  деталь», плотные списки контактов и звонков на iPad.
* Профиль и информация о группе открываются на весь экран, а не справа.
* Кинорежим на iOS: строку состояния нужно посмотреть на устройствах с
  вырезом, Dynamic Island и на iPad (положение времени и значков подобрано по
  геометрии, а не по рендеру). Реальную строку скрывает режим «иммерсивный»
  Flutter; как он ведёт себя на iOS, не проверено.
* Планирования уведомлений в приложении нет (сцена показывает их сразу);
  проверки «после закрытия приложения» не применимы.

## Что сделать вручную
1. На Mac: `bash tool/prepare_ios.sh`, `flutter pub get`,
   `cd ios && pod install`, `open Runner.xcworkspace`, выбрать Team.
2. `flutter analyze` и `flutter test`; исправить найденное.
3. Пройти список «Проверить на реальном устройстве» в `IOS_SETUP.md`.
4. На Android: `QA_CHECKLIST.md`, особенно кнопки громкости.

## Изменённые файлы
Новые: `lib/app/operator/operator_commands.dart`,
`lib/app/operator/operator_inputs.dart`,
`lib/connect/actions/prop_controller_input.dart`,
`lib/core/design/adaptive.dart`, `lib/core/util/media_paths.dart`,
`lib/core/util/platform_info.dart`, `tool/app_config.sh`, `tool/prepare_ios.sh`,
`tool/ios_res/AppIcon.appiconset/*`, `.github/workflows/build-ios.yml`,
`IOS_SETUP.md`, `OPERATOR_COMMANDS.md`, `IOS_PORT_REPORT.md`,
`test/operator_commands_test.dart`, `test/connect_scene_commands_test.dart`,
`test/adaptive_test.dart` (в том числе `kinoStatusBand`).

Изменённые: `pubspec.yaml`, `README.md`, `PROP_CONTROL_PROTOCOL.md`,
`tool/prepare_android.sh`, `tool/generate_icons.py`, `lib/app/services.dart`,
`lib/app/app.dart`, `lib/app/navigator.dart`, `lib/app/notifications.dart`,
`lib/connect/protocol/protocol.dart`, `lib/connect/actions/connect_actions.dart`,
`lib/connect/service/foreground.dart`, `lib/connect/security/secret_store.dart`,
`lib/core/brand/brand.dart`, `lib/core/design/tokens.dart`,
`lib/core/design/widgets/top_bar.dart`, `lib/data/models/{media_item,contact,chat}.dart`,
`lib/data/repositories/{call,scene}_repository.dart`, `lib/data/profile_transfer.dart`,
`lib/features/shell/home_shell.dart`, `lib/features/chat/{chat_screen,message_bubble}.dart`,
`lib/features/operator/{scene_panel_screen,operator_home_screen,action_editor_screen,scene_editor_screen}.dart`,
`lib/features/settings/addons_screen.dart`, `lib/features/connect/connect_settings_screen.dart`,
`lib/features/kino/{kino_screen,fake_status_bar}.dart`, `lib/features/media/media_library_screen.dart`,
`lib/features/call/{call_screen,camera_self_view}.dart`,
`lib/features/record/{video_note_recorder,voice_recorder_sheet}.dart`.
