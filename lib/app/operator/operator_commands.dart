import 'dart:async';

import 'package:flutter/foundation.dart';

import '../call_engine.dart';
import '../improv.dart';
import '../scene_engine.dart';

/// Команды оператора. Единый словарь для всех источников управления:
/// экран приложения, кнопки громкости Android, клавиатура, Prop Controller.
enum OperatorCommand { next, previous, stop, reset }

/// Откуда пришла команда. Движок сцен этого не знает и знать не должен;
/// источник нужен журналу и диагностике.
enum OperatorInputSource { app, androidVolume, keyboard, propController }

/// Что именно выполнило команду (порядок приоритета: дубль → звонок →
/// очередь импровизации).
enum OperatorTarget { scene, call, improv, none }

/// Итог команды. [handled] — команда принята к выполнению; для «Далее» и
/// «Назад» это не значит, что действие уже закончилось.
@immutable
class OperatorOutcome {
  const OperatorOutcome(this.command, this.source, this.target);

  final OperatorCommand command;
  final OperatorInputSource source;
  final OperatorTarget target;

  bool get handled => target != OperatorTarget.none;
}

/// Источник команд оператора. Только превращает физическое или сетевое
/// действие в [OperatorCommand] и отдаёт его в [OperatorCommandLayer].
abstract class OperatorInput {
  OperatorInputSource get source;

  /// Начать слушать (клавиатура, кнопки). Для источников, которые сами
  /// вызывают слой (экран, Connect), ничего не делает.
  void attach();

  void detach();
}

/// Единая точка обработки команд оператора.
///
/// Здесь живёт приоритет, который раньше был в AppServices: пока идёт
/// дубль, команды управляют сценой; иначе — идущим звонком; иначе —
/// взведённой очередью импровизации.
class OperatorCommandLayer {
  OperatorCommandLayer({
    required this.engine,
    required this.calls,
    required this.improv,
    this.onResetStart,
    this.onResetDone,
  });

  final SceneEngine engine;
  final CallEngine calls;
  final ImprovController improv;

  /// Перед сбросом сцены (например, отклик вибрацией).
  final void Function()? onResetStart;

  /// После сброса сцены (например, плашка «Сцена сброшена»).
  final void Function()? onResetDone;

  final List<OperatorOutcome> _recent = [];

  /// Последние команды (для диагностики и тестов).
  List<OperatorOutcome> get recent => List.unmodifiable(_recent);

  /// Есть ли у команды адресат прямо сейчас. Нужно источникам, которые
  /// делят клавиши с системой (клавиатура, кнопки громкости): когда
  /// адресата нет, нажатие остаётся системе.
  bool canHandle(OperatorCommand command) => switch (command) {
        OperatorCommand.next || OperatorCommand.previous => engine.hasTake || calls.inCall || improv.armed,
        OperatorCommand.stop => engine.isActive,
        OperatorCommand.reset => engine.info != null,
      };

  /// Выполнить команду и дождаться итога. «Далее» и «Назад» не ждут конца
  /// действия сцены (как и раньше); «Стоп» и «Сброс» ждут.
  Future<OperatorOutcome> dispatch(OperatorCommand command, OperatorInputSource source) async {
    final target = switch (command) {
      OperatorCommand.next => _next(),
      OperatorCommand.previous => _previous(),
      OperatorCommand.stop => await _stop(),
      OperatorCommand.reset => await _reset(),
    };
    final outcome = OperatorOutcome(command, source, target);
    _recent.insert(0, outcome);
    if (_recent.length > 30) _recent.removeLast();
    return outcome;
  }

  /// Выполнить команду «и забыть» — для кнопок и жестов. Ошибка не
  /// должна ронять приложение посреди съёмки.
  void post(OperatorCommand command, OperatorInputSource source) {
    unawaited(dispatch(command, source).then<void>((_) {}, onError: (Object error) {
      debugPrint('Команда оператора ${command.name} (${source.name}) не выполнена: $error');
    }));
  }

  OperatorTarget _next() {
    if (engine.hasTake) {
      engine.hiddenNext();
      return OperatorTarget.scene;
    }
    if (calls.inCall) {
      calls.operatorNext();
      return OperatorTarget.call;
    }
    if (improv.armed) {
      unawaited(improv.sendNext());
      return OperatorTarget.improv;
    }
    return OperatorTarget.none;
  }

  OperatorTarget _previous() {
    if (engine.hasTake) {
      unawaited(engine.back());
      return OperatorTarget.scene;
    }
    if (calls.inCall) {
      calls.operatorBack();
      return OperatorTarget.call;
    }
    if (improv.armed) {
      unawaited(improv.undoLast());
      return OperatorTarget.improv;
    }
    return OperatorTarget.none;
  }

  Future<OperatorTarget> _stop() async {
    if (!engine.isActive) return OperatorTarget.none;
    await engine.stop();
    return OperatorTarget.scene;
  }

  Future<OperatorTarget> _reset() async {
    if (engine.info == null) return OperatorTarget.none;
    onResetStart?.call();
    await engine.reset(restoreScreen: true);
    onResetDone?.call();
    return OperatorTarget.scene;
  }
}
