import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../volume_keys.dart';
import 'operator_commands.dart';

/// Кнопки и жесты на экране самого приложения (скрытый жест двумя пальцами,
/// кнопки пульта на экране).
class AppOperatorInput implements OperatorInput {
  AppOperatorInput(this.layer);

  final OperatorCommandLayer layer;

  @override
  OperatorInputSource get source => OperatorInputSource.app;

  @override
  void attach() {}

  @override
  void detach() {}

  void next() => layer.post(OperatorCommand.next, source);
  void previous() => layer.post(OperatorCommand.previous, source);
  void stop() => layer.post(OperatorCommand.stop, source);
  void reset() => layer.post(OperatorCommand.reset, source);
}

/// Кнопки громкости Android. Разбор нажатий и забор клавиш у системы —
/// прежний [VolumeKeyControl], без изменений; здесь он лишь переводит
/// свои команды в [OperatorCommand].
class AndroidVolumeInput implements OperatorInput {
  AndroidVolumeInput(this.layer, {required ValueListenable<bool> enabled})
      : _control = VolumeKeyControl(
          enabled: enabled,
          takeActive: () => layer.canHandle(OperatorCommand.next),
          sceneLoaded: () => layer.canHandle(OperatorCommand.reset),
          onCommand: (command) => layer.post(
            switch (command) {
              VolumeCommand.next => OperatorCommand.next,
              VolumeCommand.back => OperatorCommand.previous,
              VolumeCommand.reset => OperatorCommand.reset,
            },
            OperatorInputSource.androidVolume,
          ),
        );

  final OperatorCommandLayer layer;
  final VolumeKeyControl _control;

  @override
  OperatorInputSource get source => OperatorInputSource.androidVolume;

  @override
  void attach() => _control.attach();

  @override
  void detach() => _control.detach();
}

/// Внешняя клавиатура (в том числе Bluetooth на iPhone и iPad).
///
/// * стрелки вверх и вправо — «Далее», вниз и влево — «Назад»;
/// * пробел — «Стоп»;
/// * Esc, удерживаемый [holdForReset], — «Сброс сцены». Короткий Esc
///   сбросом не становится и по-прежнему закрывает окна.
///
/// Клавиши берутся у системы, только когда у команды есть адресат и
/// пользователь не печатает текст: иначе стрелки и пробел работают как
/// обычно.
class KeyboardInput implements OperatorInput {
  KeyboardInput(this.layer, {this.holdForReset = const Duration(milliseconds: 1200)});

  final OperatorCommandLayer layer;
  final Duration holdForReset;

  Timer? _resetTimer;
  AppLifecycleListener? _lifecycle;

  @override
  OperatorInputSource get source => OperatorInputSource.keyboard;

  @override
  void attach() {
    HardwareKeyboard.instance.addHandler(_handle);
    _lifecycle ??= AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _cancelReset();
      },
    );
  }

  @override
  void detach() {
    HardwareKeyboard.instance.removeHandler(_handle);
    _lifecycle?.dispose();
    _lifecycle = null;
    _cancelReset();
  }

  void _cancelReset() {
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  static OperatorCommand? _commandFor(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowRight) return OperatorCommand.next;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowLeft) return OperatorCommand.previous;
    if (key == LogicalKeyboardKey.space) return OperatorCommand.stop;
    return null;
  }

  static bool _typing() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText || context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _handle(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _escape(event);
      return false; // Esc остаётся системе: короткое нажатие закрывает окна
    }
    final command = _commandFor(key);
    if (command == null) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) return false;
    if (_typing() || !layer.canHandle(command)) return false;
    if (event is KeyDownEvent) layer.post(command, source);
    return event is! KeyUpEvent; // автоповтор не должен листать сцену
  }

  void _escape(KeyEvent event) {
    if (event is KeyDownEvent) {
      _cancelReset();
      if (!layer.canHandle(OperatorCommand.reset)) return;
      _resetTimer = Timer(holdForReset, () {
        _resetTimer = null;
        layer.post(OperatorCommand.reset, source);
      });
    } else if (event is KeyUpEvent) {
      _cancelReset();
    }
  }
}

/// Источники, зависящие от платформы. Единственное место, где выбор
/// источников зависит от ОС: кнопки громкости есть только на Android.
List<OperatorInput> createPlatformOperatorInputs(
  OperatorCommandLayer layer, {
  required ValueListenable<bool> volumeKeysEnabled,
}) =>
    [
      if (Platform.isAndroid) AndroidVolumeInput(layer, enabled: volumeKeysEnabled),
    ];
