# Prop Control Protocol v1

Документ для разработчика Prop Controller. Описывает, как управлять
телефонами с Messenger «Реплика» по локальной сети, не изучая сам Messenger.

Образец клиента на Dart: `lib/connect/client/connect_client.dart`.
Им пользуются экран «Проверка Connect» и автотесты.

---

## 1. Понятия

| Понятие | Что это |
|---|---|
| **Device ID** | Физический телефон с Messenger, например `MESSENGER-7F32A1`. Случайный, создаётся один раз, не связан с IMEI и серийным номером. Виден на экране Connect. |
| **Character ID** | Персонаж сценария, например `char-maxim`. Список — LIST_CHARACTERS. |
| **Владелец телефона** | Персонаж, чьими глазами телефон показывает мир. Назначается командой ASSIGN_CHARACTER и может меняться между съёмками. Device ID с персонажем не связан. |
| **Сцена Connect** | Служебная сцена телефона. Все команды выполняются в ней, поэтому RESET_SCENE убирает только то, что добавил Connect. |

## 2. Поиск телефона в сети (с версии Connect 1.1)

UDP, порт **47621**. Пакеты — JSON в UTF-8.

**Маяк.** Каждые 3 секунды телефон рассылает широковещательный пакет
(на 255.255.255.255 и на x.y.z.255 своей сети):

```json
{ "type": "announce", "protocol": "replika-connect", "protocolVersion": 1,
  "deviceId": "MESSENGER-7F32A1", "deviceName": "Телефон Ивана",
  "port": 47620, "connectVersion": "1.1.0", "status": "waiting" }
```

IP телефона — адрес отправителя пакета. После возврата Wi-Fi телефон
рассылает маяк сразу, не дожидаясь таймера.

**Запрос.** Controller может спросить сам: отправить
`{ "type": "discover", "protocol": "replika-connect", "protocolVersion": 1 }`
на порт 47621 (широковещательно или на адрес). Телефон ответит `announce`
на адрес и порт отправителя.

В пакетах поиска нет ключей, имён персонажей и содержимого. Подлинность
телефона проверяется не маяком, а ключом при `hello`: поддельный маяк
не даёт доступа.

Некоторые роутеры блокируют широковещание (изоляция клиентов). Тогда
адрес вводится вручную — он показан на экране Connect.

## 2а. Подключение

- **Транспорт.** WebSocket без TLS: кадры сеанса шифруются самим протоколом,
  см. раздел 4.
- **Адрес.** `ws://<IP телефона>:47620/connect`. IP и порт показаны
  на экране Connect.
- **Сеть.** Интернет не нужен: телефон и Controller должны быть в одной
  локальной сети. Адрес можно найти поиском (раздел 2) или ввести
  вручную.
- **Проверка связи.** Сервер шлёт WebSocket-ping каждые 10 секунд.
  Разорванное соединение обнаруживается само.

## 3. Сопряжение (первый раз)

Нужно, чтобы телефон начал доверять Controller.

1. На телефоне: Connect → «Разрешить новое устройство». Окно сопряжения
   открыто 2 минуты. Без него любой запрос сопряжения получает
   `UNAUTHORIZED`.
2. Controller → телефон (открытый текст):
   ```json
   { "type": "pair_request", "protocolVersion": 1,
     "controllerId": "pc-4f2a91", "controllerName": "Prop Controller",
     "publicKey": "<X25519, 32 байта, base64>", "nonce": "<16 байт, base64>" }
   ```
   `controllerId` — постоянный идентификатор Controller, до 64 символов.
   `publicKey` — постоянный ключ Controller, хранить в защищённом хранилище.
3. Телефон → Controller:
   ```json
   { "type": "pair_challenge", "protocolVersion": 1, "deviceId": "MESSENGER-7F32A1",
     "publicKey": "<X25519 телефона, base64>", "nonce": "<16 байт, base64>" }
   ```
4. **Код сопряжения** считают обе стороны независимо:
   ```
   h = SHA-256( utf8("replika-pair-v1") ‖ pubТелефона ‖ pubController ‖ nonceТелефона ‖ nonceController )
   код = (big-endian uint32(h[0..3]) & 0x7fffffff) mod 1 000 000, дополненный нулями до 6 цифр
   ```
   Controller показывает код на своём экране, телефон — на своём.
   Оператор сверяет коды и нажимает на телефоне «РАЗРЕШИТЬ». Если коды
   различаются, посередине чужое устройство — нажимать «ОТКЛОНИТЬ».
5. Телефон → Controller:
   ```json
   { "type": "pair_result", "protocolVersion": 1, "accepted": true, "deviceId": "MESSENGER-7F32A1" }
   ```
   При отказе приходит `accepted: false`, и соединение закрывается.
   Controller запоминает пару `deviceId → publicKey телефона`.

После сопряжения можно сразу, на том же соединении, отправить `hello`.

## 4. Аутентификация сеанса (каждое подключение)

1. Controller → телефон:
   ```json
   { "type": "hello", "protocolVersion": 1, "controllerId": "pc-4f2a91",
     "ephemeralKey": "<новый X25519 на сеанс, base64>", "nonce": "<16 байт, base64>" }
   ```
2. Телефон → Controller:
   ```json
   { "type": "hello_ok", "protocolVersion": 1, "sessionId": "<uuid>", "deviceId": "MESSENGER-7F32A1",
     "ephemeralKey": "<X25519 телефона на сеанс>", "nonce": "<16 байт>", "expiresAt": 1790000000000 }
   ```
   Неизвестный или отозванный Controller получает
   `{ "type": "error", "error": "UNAUTHORIZED" }`, и соединение закрывается.
3. Ключи сеанса:
   ```
   ikm  = X25519(ephController, ephТелефона) ‖ X25519(staticController, staticТелефона)
   okm  = HKDF-SHA256(ikm, salt = nonceController ‖ nonceТелефона,
                      info = utf8("replika-connect-v1|" + sessionId), 64 байта)
   ключ Controller→телефон = okm[0..31], ключ телефон→Controller = okm[32..63]
   ```
   Второй обмен (постоянных ключей) доказывает обеим сторонам, что это
   именно сопряжённые устройства. Посторонний не сможет ни прочитать, ни
   подделать ни одного кадра.
4. Все дальнейшие кадры — только `enc`:
   ```json
   { "type": "enc", "seq": 1, "nonce": "<12 байт, base64>", "data": "<шифртекст ‖ тег 16 байт, base64>" }
   ```
   - шифр — AES-256-GCM;
   - дополнительные данные: `utf8(sessionId + "|" + направление + "|" + seq)`,
     направление `c2d` (Controller → телефон) или `d2c`;
   - `seq` в каждом направлении начинается с 1 и строго растёт. Повтор
     или старый кадр приводит к `UNAUTHORIZED` и закрытию соединения.
5. **Срок сеанса** — 12 часов. После него телефон отвечает
   `SESSION_EXPIRED` и закрывает соединение. Нужно подключиться заново
   (`hello`).
6. **Завершение** — внутри сеанса `{ "type": "bye" }`. Прочие служебные
   кадры сеанса:
   - `{ "type": "ping", "sentAt": … }` → `{ "type": "pong", "deviceTime": …, "sentAt": … }`.

## 5. Команда и ответ (внутри enc)

**Команда:**
```json
{
  "type": "command",
  "protocolVersion": 1,
  "commandId": "cmd-000142",
  "deviceId": "MESSENGER-7F32A1",
  "actionType": "MESSAGE",
  "timestamp": 1790000000000,
  "policy": "QUEUE",
  "payload": { "fromCharacterId": "char-veronika", "toCharacterId": "char-maxim", "text": "Ты где?" }
}
```

| Поле | Значение |
|---|---|
| `commandId` | Уникальный, до 64 символов. **При переотправке после обрыва используйте тот же `commandId`**: команда не выполнится второй раз. |
| `deviceId` | Необязателен. Если указан и не совпадает с телефоном → `INVALID_TARGET`. |
| `policy` | `QUEUE` (по умолчанию) — встать в очередь. `REJECT_IF_BUSY` — если телефон занят, сразу `DEVICE_NOT_READY`. |
| `executeAt` | Необязателен (Connect 1.1). Момент выполнения по часам телефона, мс с 1970-01-01 UTC, не дальше 10 минут. Команда ждёт своей очереди, затем — этого момента; STOP прерывает ожидание. В ответе: `result.executedAt` (когда начато) и `result.lateMs` (опоздание). |

**Промежуточные статусы** (необязательны для Controller):
`{ "type": "status", "commandId": "…", "status": "RECEIVED" | "QUEUED" | "EXECUTING" }`.

**Ответ:**
```json
{ "type": "result", "protocolVersion": 1, "commandId": "cmd-000142", "success": true,
  "status": "EXECUTED", "message": "", "timestamp": 1790000000150,
  "result": { "sceneId": "connect-device-maxim", "messageId": "…" } }
```

**Статусы:** `EXECUTED`, `FAILED`, `CANCELLED`, `ALREADY_PROCESSED`
(прежний результат лежит в `result.originalStatus`), `UNSUPPORTED_ACTION`,
`INVALID_REQUEST`, `UNAUTHORIZED`.

**Ошибки (`error`):**

| Код | Когда |
|---|---|
| `UNAUTHORIZED` | нет доверия или права на действие |
| `INVALID_REQUEST` | неверная форма или параметры |
| `INVALID_COMMAND` | неизвестный actionType |
| `INVALID_TARGET` | нет такого персонажа, медиа или сообщения; «ни один не владелец телефона» |
| `UNSUPPORTED_ACTION` | действие объявлено, но не реализовано (группы) |
| `DEVICE_NOT_READY` | идёт дубль другой сцены, очередь заполнена, `REJECT_IF_BUSY` |
| `SCENE_ERROR` | сцену Connect не удалось подготовить |
| `ACTION_FAILED` | действие не выполнено, причина в `message` |
| `SESSION_EXPIRED` | срок сеанса истёк |
| `CANCELLED` | команду снял STOP |
| `INTERNAL_ERROR` | внутренняя ошибка; подробностей наружу нет |

**Очередь.**
- Команды, меняющие состояние, выполняются строго по одной, в порядке
  поступления. В очереди — до 50 команд.
- PING, DEVICE_INFO, LIST_CHARACTERS, LIST_MEDIA, LIST_GROUPS, STOP
  и MEDIA_UPLOAD_* выполняются сразу, мимо очереди.

**Защита от повтора.**
- Телефон помнит результаты последних 500 команд, они переживают
  перезапуск приложения.
- Повтор с тем же `commandId` возвращает прежний результат со статусом
  `ALREADY_PROCESSED`, действие не выполняется второй раз.
- Если команда ещё выполняется, повтор ждёт её результата.

## 5а. События телефона (с версии Connect 1.1)

Телефон сам присылает события всем подключённым Controller (кадр `enc`):

```json
{ "type": "event", "protocolVersion": 1, "event": "CALL_STATE",
  "phase": "INCOMING | OUTGOING | CONNECTING | ACTIVE | ENDED | IDLE",
  "outcome": "ANSWERED | MISSED | DECLINED | CANCELLED",
  "characterId": "char-veronika", "direction": "INCOMING | OUTGOING", "kind": "AUDIO | VIDEO",
  "timestamp": 1790000000000 }
```

`outcome` приходит только для `ENDED`. Так Controller узнаёт, что актёр
сам ответил, отклонил или положил трубку.

## 5б. Обрыв связи и переподключение

- **Как телефон видит обрыв.** Соединение, закрытое без `bye` (потеря
  Wi-Fi, сон, выход за зону), телефон считает обрывом. В течение
  90 секунд он показывает «Связь потеряна — ожидание переподключения»,
  затем «Ожидание подключения».
- **Что должен делать Controller:**
  1. Повторять `connect` + `hello` с растущей паузой: 0,25 → 0,5 → 1 → 2
     → 5 секунд. Образец — `ConnectClient.reconnect()`.
  2. После входа **переотправить все команды без ответа с теми же
     `commandId`.** Выполненные придут с `ALREADY_PROCESSED` и прежним
     результатом. Ещё выполняющиеся дождутся своего результата.
     Не выполненные выполнятся один раз.
  3. Сеанс после переподключения новый (новый `hello`). Номера кадров
     `seq` начинаются заново.
- **Штатное отключение** — `{ "type": "bye" }` внутри сеанса.
- **Проверка связи.** Сервер шлёт WebSocket-ping каждые 10 секунд.
  Controller может слать свои `ping`, чтобы оценивать задержку.

## 6. «Кто кому»

Телефон показывает мир глазами своего владельца (см. DEVICE_INFO →
`characterId`). Для MESSAGE, MEDIA, CALL, VIDEO_CALL:

| Условие | Что покажет телефон |
|---|---|
| `toCharacterId` = владелец | входящее от `fromCharacterId` |
| `fromCharacterId` = владелец | исходящее к `toCharacterId` |
| ни тот, ни другой | `INVALID_TARGET` — переписку третьих лиц телефон видит только в группе (`groupId`) |

Чтобы три телефона играли Машу, Ивана и Петю, назначьте каждому владельца:
ASSIGN_CHARACTER. Затем шлите «Маша → Иван» на телефон Ивана (входящее)
и на телефон Маши (исходящее).

## 6а. Группы (Connect 1.2)

`groupId` — ключ, который выбирает Controller (например, `crew`).
- Один и тот же ключ работает на всех телефонах: создайте группу `crew`
  на телефонах Маши, Ивана и Пети. Каждый увидит её своими глазами.
- Группы, созданные вручную на телефоне, доступны по `groupId`
  из LIST_GROUPS.
- RESET_SCENE удаляет группы, созданные командами. У остальных групп он
  возвращает состав участников.

Пример:
```json
{ "actionType": "CREATE_CHAT", "payload": { "groupId": "crew", "title": "Съёмочная группа",
  "memberIds": ["char-masha", "char-ivan", "char-petya"], "fromCharacterId": "char-masha" } }
{ "actionType": "MESSAGE", "payload": { "groupId": "crew", "fromCharacterId": "char-masha", "text": "Встречаемся в 19:00" } }
```

## 7. Действия

| actionType | payload | Результат |
|---|---|---|
| `PING` | `sentAt?` | `deviceTime`, `sentAt` — для оценки смещения часов |
| `DEVICE_INFO` | — | `deviceId, deviceName, characterId, characterName, virtualPhoneId, appVersion, connectVersion, protocolVersion, status, lastSeen, sceneId, supportedActions` |
| `LIST_CHARACTERS` | — | `characters[]: characterId, firstName, lastName, phone, contactName, isOwner` |
| `LIST_MEDIA` | — | `media[]: mediaId, kind (photo/video/voice/audio/videoNote/file), name, durationMs` |
| `ASSIGN_CHARACTER` | `characterId` | телефон начинает показывать мир глазами персонажа; виртуальный телефон создаётся при необходимости; ответ — как DEVICE_INFO |
| `SET_CONTACT` | `characterId, displayName` | как персонаж записан в контактах этого телефона («Мама») |
| `MESSAGE` | `fromCharacterId, toCharacterId, text`; `messageTime?` (1.3) — время у сообщения, мс с 1970-01-01 UTC; для входящего `typingMs?` (сначала «печатает…»); для исходящего `state?` (SENDING/SENT/DELIVERED/READ, по умолчанию READ) и `delivery?: true` (часы → галочки в реальном времени) | `messageId` |
| `TYPING` | `fromCharacterId, durationMs?` (500–120000, по умолчанию 4000) | — |
| `MEDIA` | `fromCharacterId, toCharacterId, mediaId, caption?, typingMs?, messageTime?` (1.3) | `messageId`; вид сообщения — по виду медиа; `file` → `UNSUPPORTED_ACTION` |
| `DELETE_MESSAGE` | `messageId` **или** `characterId` + `target?` (`lastIncoming` — по умолчанию, `lastOutgoing`, `last`) | `messageId` |
| `EDIT_MESSAGE` | как DELETE + `text` | текст меняется, в пузыре появляется «изм.» |
| `MESSAGE_STATUS` | как DELETE + `state` (по умолчанию `lastOutgoing`, READ) | — |
| `CALL` / `VIDEO_CALL` | `fromCharacterId, toCharacterId` | входящий или исходящий по таблице «кто кому»; одновременно — один звонок |
| `CALL_ACCEPT` / `CALL_DECLINE` / `END_CALL` | `characterId?` (если указан — должен совпадать с собеседником звонка) | нет звонка → `INVALID_TARGET` |
| `NOTIFICATION` | `fromCharacterId, text, title?` (по умолчанию имя из контактов) | настоящее уведомление Android; нажатие открывает чат |
| `OPEN_SCREEN` | `screen`: `CHAT` / `PROFILE` (+`characterId`), `CHAT` + `groupId` (1.3), `CHAT_LIST`, `CALLS`, `CONTACTS` (1.3), `BACK` | другие экраны → `INVALID_REQUEST` |
| `DELAY` | `ms` (0–600000) | прерывается STOP |
| `SEQUENCE` | `steps[]: {actionType, payload}` (до 200), `stopOnError?` (true) | `steps[]` с результатом каждого шага; SEQUENCE, STOP и SCENE_NEXT/SCENE_PREVIOUS/SCENE_STOP внутрь не вкладываются |
| `RESET_SCENE` | — | убирает всё, что добавил Connect (сообщения, правки, удаления, статусы, звонки, счётчики, уведомления); остальные данные не трогаются |
| `STOP` | — | прервать текущую команду и снять очередь; снятые получают `CANCELLED` |
| `LIST_GROUPS` | — | `groups[]: groupId, title, members[]` (Connect 1.2) |
| `CREATE_CHAT` | `groupId` (ключ Controller: латиница, цифры, `_`, `-`, до 64), `title`, `memberIds[]`, `fromCharacterId?` (кто создал, иначе владелец) | группа на этом телефоне, владелец входит всегда; событие «Маша создал(а) группу «…»» |
| `ADD_PARTICIPANT` / `REMOVE_PARTICIPANT` | `groupId, characterId, byCharacterId?` | событие «Маша добавил(а) Иван» / «Вы удалили: Петя» |
| `MESSAGE` / `MEDIA` / `TYPING` в группу | вместо `toCharacterId` — `groupId`; `fromCharacterId` должен состоять в группе | от владельца — исходящее, от участника — входящее с его именем над пузырём |

## 7а-0. Управление ходом сцены (аддитивно, версия протокола прежняя)

Команды оператора для Prop Controller. Идут мимо очереди (как `STOP`), чтобы
не ждать в хвосте длинной `SEQUENCE`. Телефон передаёт их в общий слой команд
оператора (`OperatorCommandLayer`), тот же, что обслуживает экран приложения,
кнопки громкости Android и внешнюю клавиатуру. Приоритет везде один: идущий
дубль → идущий звонок → взведённая очередь импровизации.

| actionType | Направление | Право | payload | Ответ (`result`) | Ошибки |
|---|---|---|---|---|---|
| `SCENE_NEXT` | Controller → телефон | `control` | — | `command: "next"`, `handled`, `target` | `UNAUTHORIZED` (нет права), `INVALID_COMMAND` (старая версия Messenger), `INVALID_REQUEST` (внутри `SEQUENCE`) |
| `SCENE_PREVIOUS` | Controller → телефон | `control` | — | `command: "previous"`, `handled`, `target` | те же |
| `SCENE_STOP` | Controller → телефон | `control` | — | `command: "stop"`, `handled`, `target` | те же |
| `RESET_SCENE` | Controller → телефон | `reset` | — | `sceneId`, `reset` | без изменений, см. §7 |

* `target`: `scene` (дубль), `call` (звонок), `improv` (очередь импровизации)
  или `none`. `handled: false` / `target: none` — у команды сейчас нет адресата
  (дубль не идёт, звонка нет, очередь не взведена); это не ошибка.
* `handled: true` означает «принято к выполнению»: для `SCENE_NEXT` и
  `SCENE_PREVIOUS` действие сцены может ещё идти; для `SCENE_STOP` дубль уже
  остановлен.
* `SCENE_NEXT` ведёт дубль в ручном режиме, продолжает после паузы, на
  исходящем звонке означает «собеседник ответил». Случайно не запускает сцену:
  без идущего дубля сцена не стартует.
* `SCENE_PREVIOUS` отменяет последнее действие дубля; на звонке — «сбросил
  / положил трубку»; в импровизации — убирает последний отправленный ответ.
* `SCENE_STOP` останавливает идущий дубль без сброса (показанное остаётся
  на экране). Старое `STOP` по-прежнему прерывает только очередь Connect,
  `DELAY` и `SEQUENCE`; движок сцен оно не затрагивает.
* Старые версии Messenger на незнакомое действие отвечают `INVALID_COMMAND`;
  новые команды видны в `DEVICE_INFO.supportedActions`.

## 7а. Подготовка телефона с пульта (Connect 1.3)

Всё необязательно: клиенты 1.2 работают без изменений. Проверить наличие —
`supportedActions` в DEVICE_INFO.

**Персонажи — `UPSERT_CHARACTER`.** Ключ `characterId` выбирает пульт
(латиница, цифры, `_`, `-`, до 64): он одинаков на всех телефонах, как
`groupId` у групп.

| Поле | Значение |
|---|---|
| `characterId` | ключ пульта, например `masha` |
| `firstName`, `lastName`, `phone`, `statusText`, `description` | меняются только переданные поля |
| `avatarMediaId` | фото, уже переданное на телефон; `null` — убрать аватар |
| `contactName` | как персонаж записан в контактах **текущего профиля** («Мама») |
| `addToContacts` | `false` — не в контактах (в чате виден номер) |

Ответ: `characterId, created, isOwner, contactName?`. Владелец в свои
контакты не записывается. RESET_SCENE персонажей не удаляет.

Порядок подготовки телефона: UPSERT_CHARACTER владельца → ASSIGN_CHARACTER
→ UPSERT_CHARACTER остальных (так они попадают в контакты профиля
владельца).

**Медиа — `MEDIA_UPLOAD_BEGIN` → `MEDIA_UPLOAD_CHUNK`… → `MEDIA_UPLOAD_COMMIT`.**
Мимо очереди; сцену не трогают; RESET_SCENE файлы не удаляет.

| Команда | payload | Ответ |
|---|---|---|
| `MEDIA_UPLOAD_BEGIN` | `mediaId` (ключ пульта), `kind` (photo/video/audio/voice/videoNote), `name` (с расширением), `size` (до 64 МБ), `sha256?` (hex), `durationMs?` | `exists` (файл уже есть — передавать не нужно), `received` (сколько уже получено — продолжать с этого места), `chunkBytes` |
| `MEDIA_UPLOAD_CHUNK` | `mediaId`, `offset`, `data` (base64, до 96 КБ до кодирования) | `received`. Кусок, который уже записан, — не ошибка |
| `MEDIA_UPLOAD_COMMIT` | `mediaId` | `mediaId, kind, sizeBytes`; неверная `sha256` → `ACTION_FAILED`, файл надо передать заново |

`mediaId` удобно брать из содержимого файла (`pcm-` + начало SHA-256):
тогда повторная передача того же файла сразу получает `exists: true`,
а другой файл никогда не займёт чужой ключ.

## 8. Пример последовательности

```json
{ "type": "command", "protocolVersion": 1, "commandId": "scene-12-take-3",
  "actionType": "SEQUENCE",
  "payload": { "stopOnError": true, "steps": [
    { "actionType": "MESSAGE", "payload": { "fromCharacterId": "char-masha", "toCharacterId": "char-ivan", "text": "Ты где?", "typingMs": 1500 } },
    { "actionType": "DELAY",   "payload": { "ms": 3000 } },
    { "actionType": "MESSAGE", "payload": { "fromCharacterId": "char-masha", "toCharacterId": "char-ivan", "text": "Я уже приехала" } },
    { "actionType": "DELAY",   "payload": { "ms": 5000 } },
    { "actionType": "CALL",    "payload": { "fromCharacterId": "char-masha", "toCharacterId": "char-ivan" } },
    { "actionType": "DELAY",   "payload": { "ms": 10000 } },
    { "actionType": "END_CALL","payload": {} }
  ] } }
```

Ответ приходит после последнего шага. При ошибке на шаге N: `success:
false`, в `result.steps` — результаты шагов 1…N.

## 9. Несколько телефонов

Каждый телефон — отдельное соединение и отдельный сеанс.

**Синхронный запуск:**
1. PING каждому телефону. Смещение часов:
   `offset ≈ deviceTime − (sentAt + rtt/2)`, где rtt — время до ответа.
2. Выбрать общий момент T по своим часам, например «сейчас + 2 с».
3. Отправить каждому телефону команду с `executeAt = T + offset`
   этого телефона.
4. По `lateMs` в ответах проверить, насколько точно совпало.

## 10. Ограничения версии 1

- **messageTime** меняет только время у сообщения. Сообщение с прошедшим
  временем встаёт в переписке на своё место по времени.

- **Группы — только команды из раздела 6а.** Смена аватара группы,
  администраторы и упоминания не поддерживаются.
- **Переподключение выполняет Controller.** Телефон — сервер: он ждёт,
  помнит результаты и рассылает маяк. Инициатива подключения всегда
  за Controller.
- **Один звонок одновременно.**
- **Дубль в операторской.** Пока в операторской идёт дубль другой сцены,
  сценарные команды получают `DEVICE_NOT_READY`.
- **Права.** Сейчас доверенное устройство получает все права
  (VIEW, CONTROL, MESSAGES, CALLS, MEDIA, GROUPS, SCREENS, RESET).
  Выборочная выдача не требует изменения протокола.
- **Совместимость.** Controller должен отправлять `protocolVersion: 1`.
  Телефон отказывает в командах более новой версии и сообщает свою
  в DEVICE_INFO.
