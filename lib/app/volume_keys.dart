import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Команды физического пульта.
enum VolumeCommand { next, back, reset }

/// Разбор нажатий кнопок громкости (без привязки к платформе — проверяется
/// автотестами):
/// * одно короткое нажатие «вверх» — «Далее», «вниз» — «Назад»; команда
///   срабатывает при отпускании, чтобы успеть распознать комбинацию;
/// * обе кнопки вместе, удерживать [holdForReset] — «Сброс сцены».
///
/// Возвращаемое значение — забрать ли нажатие у системы. Если не забрать,
/// Android как обычно изменит громкость.
class VolumeKeyInterpreter {
  VolumeKeyInterpreter({
    required this.onCommand,
    this.holdForReset = const Duration(milliseconds: 1200),
  });

  final void Function(VolumeCommand command) onCommand;
  final Duration holdForReset;

  bool _up = false;
  bool _down = false;
  bool _combo = false;
  bool _consumedUp = false;
  bool _consumedDown = false;
  Timer? _timer;

  bool get comboActive => _combo;

  /// [takeActive] — дубль идёт: одиночные нажатия управляют сценой.
  /// [sceneLoaded] — сцена выбрана: комбинация сброса доступна.
  bool keyDown({required bool isUp, required bool takeActive, required bool sceneLoaded}) {
    if (isUp) {
      _up = true;
    } else {
      _down = true;
    }
    if (_up && _down && sceneLoaded) {
      if (!_combo) {
        _combo = true;
        _timer?.cancel();
        _timer = Timer(holdForReset, () {
          if (_up && _down) onCommand(VolumeCommand.reset);
        });
      }
      _markConsumed(isUp);
      return true;
    }
    if (takeActive) _markConsumed(isUp);
    return takeActive;
  }

  /// Автоповтор при удержании: громкость не должна «уплывать».
  bool keyRepeat({required bool isUp}) => _combo || (isUp ? _consumedUp : _consumedDown);

  bool keyUp({required bool isUp, required bool takeActive}) {
    final consumed = isUp ? _consumedUp : _consumedDown;
    if (isUp) {
      _up = false;
      _consumedUp = false;
    } else {
      _down = false;
      _consumedDown = false;
    }
    if (_combo) {
      if (!_up && !_down) {
        _combo = false;
        _timer?.cancel();
      }
      return true;
    }
    if (!consumed) return false;
    if (takeActive) onCommand(isUp ? VolumeCommand.next : VolumeCommand.back);
    return true;
  }

  void _markConsumed(bool isUp) {
    if (isUp) {
      _consumedUp = true;
    } else {
      _consumedDown = true;
    }
  }

  /// Приложение свернули или заблокировали: отпускание кнопок могло
  /// прийти системе, а не нам. Начинаем с чистого состояния.
  void clear() {
    _timer?.cancel();
    _up = _down = _combo = _consumedUp = _consumedDown = false;
  }
}

/// Подключение к клавиатурным событиям Flutter на Android.
///
/// Кнопки громкости приходят в приложение как клавиши audioVolumeUp и
/// audioVolumeDown, пока оно на экране. Если обработчик вернул true,
/// Android не меняет громкость; false — громкость меняется как обычно.
/// При заблокированном экране или свёрнутом приложении события получает
/// система — это ограничение Android, не приложения.
class VolumeKeyControl {
  VolumeKeyControl({
    required this.enabled,
    required this.takeActive,
    required this.sceneLoaded,
    required void Function(VolumeCommand command) onCommand,
  }) : interpreter = VolumeKeyInterpreter(onCommand: onCommand);

  final ValueListenable<bool> enabled;
  final bool Function() takeActive;
  final bool Function() sceneLoaded;
  final VolumeKeyInterpreter interpreter;
  AppLifecycleListener? _lifecycle;

  void attach() {
    HardwareKeyboard.instance.addHandler(_handle);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) interpreter.clear();
      },
    );
  }

  void detach() {
    HardwareKeyboard.instance.removeHandler(_handle);
    _lifecycle?.dispose();
    interpreter.clear();
  }

  bool _handle(KeyEvent event) {
    final key = event.logicalKey;
    final isUp = key == LogicalKeyboardKey.audioVolumeUp;
    if (!isUp && key != LogicalKeyboardKey.audioVolumeDown) return false;
    if (!enabled.value) return false;
    if (event is KeyDownEvent) {
      return interpreter.keyDown(isUp: isUp, takeActive: takeActive(), sceneLoaded: sceneLoaded());
    }
    if (event is KeyRepeatEvent) return interpreter.keyRepeat(isUp: isUp);
    if (event is KeyUpEvent) return interpreter.keyUp(isUp: isUp, takeActive: takeActive());
    return false;
  }
}
