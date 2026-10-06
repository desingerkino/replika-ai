# Команды оператора

Единый словарь управления ходом съёмки. Движок сцен не знает, откуда пришла
команда: источники только переводят действие в `OperatorCommand` и отдают его
слою `OperatorCommandLayer` (`lib/app/operator/operator_commands.dart`).

```
Источники ввода                            Слой команд              Движок
─────────────────────────────────────      ─────────────────       ─────────────
AppOperatorInput   (экран, жесты)      ┐
AndroidVolumeInput (кнопки громкости)  ├─▶ OperatorCommandLayer ─▶  SceneEngine /
KeyboardInput      (внешняя клавиатура)│                            CallEngine /
PropControllerInput (Connect, Wi-Fi)   ┘                            Improv
```

## Команды

| Команда | Что делает |
|---|---|
| `next` | дубль: следующее действие (ручной режим) или продолжение после паузы; звонок: «ответил»; импровизация: отправить следующий ответ |
| `previous` | дубль: отменить последнее действие; звонок: «сбросил / положил трубку»; импровизация: убрать последний ответ |
| `stop` | остановить идущий дубль без сброса |
| `reset` | СБРОС СЦЕНЫ: вернуть телефон в состояние до дубля |

Приоритет адресата один для всех источников: **дубль → звонок → очередь
импровизации**. `next` без идущего дубля сцену не запускает. Если адресата нет,
команда ничего не делает, а `OperatorOutcome.handled` равен `false`.

## Источники

| Источник | Платформа | Как управляет |
|---|---|---|
| `AppOperatorInput` | все | скрытый жест двумя пальцами — `next`; свайп двумя пальцами вверх — `previous`; кнопка «НАЗАД» на панели сцены — `previous`; методы `next/previous/stop/reset` для остальных кнопок |
| `AndroidVolumeInput` | только Android | громкость вверх — `next`, вниз — `previous`, обе кнопки 1,2 с — `reset`. Разбор нажатий прежний (`VolumeKeyControl`) |
| `KeyboardInput` | все, где есть внешняя клавиатура | ↑ / → — `next`; ↓ / ← — `previous`; пробел — `stop`; Esc, удержанный 1,2 с — `reset` |
| `PropControllerInput` | все | `SCENE_NEXT`, `SCENE_PREVIOUS`, `SCENE_STOP` из Connect (право `control`) |

Клавиатура берёт клавиши у системы, только когда у команды есть адресат и
фокус не в поле ввода; короткий Esc `reset` не вызывает и закрывает окна как
обычно. На iOS кнопки громкости не перехватываются: без private API и
обходов это невозможно.

## Где что находится

* `lib/app/operator/operator_commands.dart` — `OperatorCommand`,
  `OperatorInputSource`, `OperatorTarget`, `OperatorOutcome`, `OperatorInput`,
  `OperatorCommandLayer` (`dispatch`, `post`, `canHandle`).
* `lib/app/operator/operator_inputs.dart` — `AppOperatorInput`,
  `AndroidVolumeInput`, `KeyboardInput`, `createPlatformOperatorInputs`
  (единственное место, где источники выбираются по платформе).
* `lib/connect/actions/prop_controller_input.dart` — `PropControllerInput`.
* `lib/app/services.dart` — `operatorCommands`, `appInput`, `propInput`,
  `operatorInputs`; подключение и отключение источников.

Сетевые команды описаны в `PROP_CONTROL_PROTOCOL.md`, §7а-0.

## Кнопки панели сцены

Большие кнопки панели (СТАРТ / ДАЛЕЕ / ПАУЗА / ПРОДОЛЖИТЬ, СТОП, СБРОС СЦЕНЫ)
зависят от состояния панели (запуск дубля, пауза, подтверждение сброса,
защита от двойного нажатия) и вызывают движок сцен напрямую. Через слой
команд идут «НАЗАД», жест двумя пальцами, клавиатура, Prop Controller и
кнопки громкости Android.
