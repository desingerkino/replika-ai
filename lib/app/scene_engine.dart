import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/util/time_format.dart';
import '../data/models/scene_action.dart';
import '../data/models/take.dart';
import 'scene_chat_view.dart';

/// Состояние движка сцен.
enum EngineStatus {
  idle('Сцена не выбрана'),
  ready('Готово'),
  running('Идёт'),
  waiting('Ждёт «Далее»'),
  paused('Пауза'),
  finished('Завершено');

  const EngineStatus(this.label);
  final String label;
}

/// Участник сцены — персонаж, от имени которого выполняются действия.
@immutable
class SceneParticipant {
  const SceneParticipant({
    required this.characterId,
    required this.name,
    this.avatarTone,
    this.avatarPath,
  });

  final String characterId;

  /// Как участник записан на телефоне сцены.
  final String name;
  final int? avatarTone;
  final String? avatarPath;
}

/// Сведения о сцене, которые нужны при выполнении действий.
///
/// Сцена — это не один чат, а участники: каждое действие выполняется
/// от имени своего участника в его чате на телефоне сцены.
class SceneRunInfo {
  SceneRunInfo({
    required this.sceneId,
    required this.sceneTitle,
    required this.deviceId,
    required this.ownerId,
    this.chatId,
    this.peerId,
    this.chatName = '',
    this.clockStart,
    this.participants = const [],
    Set<String>? chatIds,
  }) : chatIds = {...?chatIds, if (chatId != null) chatId};

  final String sceneId;
  final String sceneTitle;
  final String deviceId;
  final String ownerId;

  /// Чат, который открывается «В КАДР» (необязателен).
  final String? chatId;

  /// Участник по умолчанию — для действий, где участник не указан
  /// (сцены, созданные до многоконтактного режима).
  final String? peerId;
  final String chatName;
  final List<SceneParticipant> participants;

  /// Все чаты, которых касается сцена: сообщения актёра в них во время
  /// дубля принадлежат сцене. Пополняется по ходу дубля.
  final Set<String> chatIds;

  /// Текущий прогон — репетиция (изменения откатываются по окончании).
  bool rehearsal = false;

  String nameOf(String? characterId) {
    for (final p in participants) {
      if (p.characterId == characterId) return p.name;
    }
    return chatName.isEmpty ? 'Собеседник' : chatName;
  }

  /// «Время в кадре» на начало дубля (например, сегодня 23:47);
  /// null — сообщения сцены получают реальное время.
  final DateTime? clockStart;
}

/// Всё, что движок делает с данными и экраном. Отделено от движка:
/// очерёдность, паузы и режимы проверяются автотестами без базы.
abstract class SceneEffects {
  Future<SceneRunInfo> prepare(String sceneId);
  Future<List<SceneAction>> loadActions(String sceneId);
  Future<int> beginTake(SceneRunInfo info);
  Future<void> perform(SceneAction action, SceneRunInfo info, bool Function() cancelled);

  /// Отменить последнее выполненное действие (громкость вниз — «Назад»).
  /// Действия, выполненные вручную (не из таймлайна), тоже отменяются.
  Future<void> undoLast(SceneRunInfo info);
  Future<void> endTake(SceneRunInfo info, {required bool completed});
  Future<void> markTake(SceneRunInfo info, TakeStatus status);

  /// [restoreScreen] — вернуть на экран чат сцены, если он был открыт
  /// в начале дубля (сброс кнопками громкости прямо «в кадре»).
  Future<void> reset(SceneRunInfo info, {bool restoreScreen = false});
}

/// Дубль, найденный в базе после перезапуска приложения.
class ResumedTake {
  const ResumedTake({required this.number, required this.startedAt, required this.progress});

  final int number;
  final DateTime startedAt;

  /// То, что движок сохранил в [SceneProgressStore.saveProgress].
  final Map<String, Object?> progress;
}

/// Необязательная возможность SceneEffects: сохранять ход дубля в базе,
/// чтобы после закрытия приложения сцена продолжилась с того же места
/// (какие события выполнены, шаги для «Назад», позиция общего таймлайна).
abstract interface class SceneProgressStore {
  Future<void> saveProgress(SceneRunInfo info, Map<String, Object?> progress);

  /// Незавершённый дубль сцены или null, если продолжать нечего.
  Future<ResumedTake?> resumeTake(SceneRunInfo info);
}

/// Типы, которые выполняет сам движок, а не SceneEffects.
const Set<ActionType> engineControlTypes = {
  ActionType.wait,
  ActionType.pause,
  ActionType.resume,
  ActionType.finish,
  ActionType.reset,
};

/// Scene Engine: выполняет таймлайн сцены в автоматическом или ручном
/// режиме. Интерфейс только читает его состояние и нажимает кнопки.
class SceneEngine extends ChangeNotifier {
  SceneEngine(this.effects, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final SceneEffects effects;
  final DateTime Function() _clock;

  /// Скорость автоматического режима: паузы и «печатает…» делятся на неё.
  double _speed = 1.0;

  /// Сколько осталось до следующего действия в автоматическом режиме.
  int _remainingMs = 0;
  DateTime? _takeStartedAt;

  SceneRunInfo? _info;
  List<SceneAction> _actions = const [];
  int _index = 0;
  EngineStatus _status = EngineStatus.idle;
  bool _manual = true;
  int _generation = 0;
  int? _takeNumber;
  final List<String> _log = [];

  /// Индексы действий, которые изменили данные, — для шага «Назад».
  /// −1 — действие, выполненное вручную с панели (не из таймлайна).
  final List<int> _history = [];

  /// Ручные действия, соответствующие записям [_history] (для «Повторить»).
  final List<SceneAction?> _historyActions = [];

  /// Отменённые ручные действия — их можно вернуть (redo).
  final List<SceneAction> _redo = [];

  bool _rehearsal = false;

  /// Выполненные события (id действий) текущего дубля. Событие одно:
  /// выполнено из личного таймлайна — выполнено и в общем.
  final Set<String> _executed = {};

  bool isExecuted(String actionId) => _executed.contains(actionId);

  /// Чат, в личном таймлайне которого сейчас работает оператор. Пока он
  /// выбран, «Далее» из любого источника (панель, жест в кадре, кнопки,
  /// внешняя клавиатура, Prop Controller) выполняет следующее событие этого
  /// чата. null — общий таймлайн: «Далее» работает как прежде.
  String? _workChatKey;
  String? get workChatKey => _workChatKey;

  void setWorkChat(String? chatKey) => _workChatKey = chatKey;

  /// Режим следующего прогона: репетиция или съёмочный дубль.
  bool get rehearsal => _rehearsal;
  bool get canRedo => _redo.isNotEmpty && hasTake;

  void setRehearsal(bool value) {
    if (hasTake) return; // режим меняется между прогонами
    _rehearsal = value;
    notifyListeners();
  }

  /// Участник, выбранный на панели для ручных действий. Хранится в движке,
  /// чтобы выбор не терялся при уходе с панели и возвращении.
  String? _activeParticipantId;

  /// Записывать ручные действия в таймлайн сцены.
  bool _recordLive = false;
  bool get recordLive => _recordLive;

  void setRecordLive(bool value) {
    _recordLive = value;
    notifyListeners();
  }
  DateTime? _lastLiveAt;

  /// Поколение, в котором сейчас крутится автоматический цикл.
  int? _autoLoopGeneration;

  SceneRunInfo? get info => _info;
  List<SceneAction> get actions => _actions;
  int get index => _index;
  EngineStatus get status => _status;
  bool get manual => _manual;

  String? get activeParticipantId {
    final info = _info;
    if (info == null) return null;
    final ids = info.participants.map((p) => p.characterId);
    if (_activeParticipantId != null && ids.contains(_activeParticipantId)) return _activeParticipantId;
    return ids.isEmpty ? info.peerId : ids.first;
  }

  void selectParticipant(String characterId) {
    _activeParticipantId = characterId;
    notifyListeners();
  }
  double get speed => _speed;
  int get remainingMs => _remainingMs;
  int? get takeNumber => _takeNumber;
  List<String> get log => List.unmodifiable(_log);

  bool get isActive =>
      _status == EngineStatus.running || _status == EngineStatus.waiting || _status == EngineStatus.paused;

  /// Дубль начат и ещё не сброшен (в том числе завершён) — физические
  /// кнопки управляют сценой, а не громкостью.
  bool get hasTake => isActive || _status == EngineStatus.finished;

  /// Текущее «время в кадре»: начало сцены плюс время, прошедшее
  /// с начала дубля. null — время сообщений реальное.
  DateTime? sceneNow() {
    final start = _info?.clockStart;
    final startedAt = _takeStartedAt;
    if (start == null || startedAt == null || !hasTake) return null;
    return start.add(_clock().difference(startedAt));
  }

  void setSpeed(double speed) {
    _speed = speed.clamp(0.25, 4.0);
    notifyListeners();
  }

  /// Перечитать сведения о сцене (например, после смены «времени в кадре»),
  /// не трогая ход дубля.
  Future<void> refreshInfo() async {
    final info = _info;
    if (info == null) return;
    _info = await effects.prepare(info.sceneId);
    notifyListeners();
  }

  /// Сцена, к которой относятся сообщения, отправленные в этом чате
  /// во время дубля (их тоже убирает «СБРОС СЦЕНЫ»).
  String? sceneIdForChat(String chatId) {
    final info = _info;
    return info != null && hasTake && info.chatIds.contains(chatId) ? info.sceneId : null;
  }

  void _note(String text) {
    _log.insert(0, '${formatClock(DateTime.now())}  $text');
    if (_log.length > 60) _log.removeLast();
  }

  void _set(EngineStatus status) {
    _status = status;
    notifyListeners();
  }

  /// Загрузить сцену. Идущий дубль при этом останавливается.
  Future<void> load(String sceneId) async {
    await stop();
    _info = await effects.prepare(sceneId);
    _actions = (await effects.loadActions(sceneId)).where((a) => a.enabled).toList();
    _index = 0;
    _takeNumber = null;
    _executed.clear();
    _workChatKey = null;
    _log.clear();
    final store = effects;
    final loaded = _info;
    if (store is SceneProgressStore && loaded != null) {
      try {
        final resumed = await store.resumeTake(loaded);
        if (resumed != null) {
          _restore(resumed);
          return;
        }
      } catch (error) {
        debugPrint('Дубль не восстановлен: $error');
      }
    }
    _set(EngineStatus.ready);
  }

  /// Продолжить дубль, прерванный закрытием приложения.
  void _restore(ResumedTake resumed) {
    final ids = {for (final a in _actions) a.id};
    final progress = resumed.progress;
    _takeNumber = resumed.number;
    _takeStartedAt = resumed.startedAt;
    _executed.addAll([
      for (final id in (progress['executed'] as List?) ?? const [])
        if (id is String && ids.contains(id)) id,
    ]);
    _history
      ..clear()
      ..addAll([
        for (final v in (progress['history'] as List?) ?? const [])
          if (v is num) v.toInt(),
      ]);
    _historyActions
      ..clear()
      ..addAll(List<SceneAction?>.filled(_history.length, null));
    _redo.clear();
    final saved = (progress['index'] as num?)?.toInt() ?? 0;
    _index = saved.clamp(0, _actions.length);
    _skipExecuted();
    _note('Дубль ${resumed.number} продолжен после перезапуска');
    _set(_manual ? EngineStatus.waiting : EngineStatus.paused);
  }

  /// Позиция общего таймлайна не стоит на уже выполненном событии
  /// (его могли выполнить из личного таймлайна чата).
  void _skipExecuted() {
    while (_index < _actions.length && _executed.contains(_actions[_index].id)) {
      _index++;
    }
  }

  /// Сохранить ход дубля в базе (если эффекты это умеют).
  Future<void> _persist() async {
    final store = effects;
    final info = _info;
    if (store is! SceneProgressStore || info == null || !hasTake) return;
    try {
      await store.saveProgress(info, {
        'executed': _executed.toList(),
        'history': List<int>.of(_history),
        'index': _index,
      });
    } catch (error) {
      debugPrint('Ход дубля не сохранён: $error');
    }
  }

  // ---------- Личные таймлайны чатов ----------

  /// Чат действия на телефоне сцены (null — только общий таймлайн).
  String? chatKeyOf(SceneAction action) {
    final info = _info;
    if (info == null) return null;
    return sceneChatKeyOf(
      action,
      ownerId: info.ownerId,
      defaultPeerId: info.peerId,
      byId: {for (final a in _actions) a.id: a},
    );
  }

  /// Личный таймлайн чата: индексы действий — свои и привязанные
  /// («показывать также в чате»). Это представление, а не копии событий.
  List<int> chatView(String chatKey) {
    final info = _info;
    if (info == null) return const [];
    return sceneChatView(_actions, chatKey, ownerId: info.ownerId, defaultPeerId: info.peerId);
  }

  /// Сколько событий личного таймлайна выполнено и сколько всего.
  ({int done, int total}) chatProgress(String chatKey) {
    final view = chatView(chatKey);
    return (done: view.where((i) => _executed.contains(_actions[i].id)).length, total: view.length);
  }

  /// Первое невыполненное событие личного таймлайна.
  int? nextIndexInChat(String chatKey) {
    for (final i in chatView(chatKey)) {
      if (!_executed.contains(_actions[i].id)) return i;
    }
    return null;
  }

  /// «Далее» в личном таймлайне чата: выполнить его следующее событие
  /// (в том числе привязанное чужое — оно остаётся событием своего чата).
  Future<void> nextInChat(String chatKey) async {
    final info = _info;
    if (info == null) return;
    final index = nextIndexInChat(chatKey);
    if (index == null) {
      _note('В этом чате событий больше нет');
      notifyListeners();
      return;
    }
    await performAt(index);
  }

  /// Выполнить событие по индексу (из личного таймлайна, вне общей очереди).
  /// Позиция общего таймлайна сдвигается, только если это его текущий шаг.
  Future<void> performAt(int index) async {
    final info = _info;
    if (info == null || index < 0 || index >= _actions.length) return;
    if (_status == EngineStatus.running) return;
    final action = _actions[index];
    if (_executed.contains(action.id) || engineControlTypes.contains(action.type)) return;
    if (!hasTake) await _beginTake(info);
    final generation = _generation;
    final before = _status;
    _set(EngineStatus.running);
    _note('Из личного таймлайна:');
    await _perform(action, generation, index: index, mark: true);
    if (generation != _generation) return;
    _skipExecuted();
    if (_index >= _actions.length) {
      await _complete();
    } else if (_status == EngineStatus.running) {
      _set(before == EngineStatus.paused ? EngineStatus.paused : EngineStatus.waiting);
    }
  }

  /// Перечитать действия (после правки таймлайна), если сцена не идёт.
  Future<void> reloadActions() async {
    final info = _info;
    if (info == null || isActive) return;
    _actions = (await effects.loadActions(info.sceneId)).where((a) => a.enabled).toList();
    _index = 0;
    notifyListeners();
  }

  void setManual(bool manual) {
    if (isActive) return;
    _manual = manual;
    notifyListeners();
  }

  /// Начать новый дубль с первого действия.
  Future<void> start() async {
    final info = _info;
    if (info == null || isActive) return;
    final generation = await _beginTake(info);
    if (generation != _generation) return;
    if (!_manual) {
      _set(EngineStatus.running);
      unawaited(_runAuto(generation));
    }
  }

  /// Дубль начат, таймлайн стоит в начале (ждёт «Далее» или продолжения).
  Future<int> _beginTake(SceneRunInfo info) async {
    final generation = ++_generation;
    _index = 0;
    _executed.clear();
    _log.clear();
    _history.clear();
    _historyActions.clear();
    _redo.clear();
    _takeStartedAt = _clock();
    _lastLiveAt = null;
    info.rehearsal = _rehearsal;
    _takeNumber = await effects.beginTake(info);
    if (generation == _generation) {
      _note('${_rehearsal ? 'Репетиция' : 'Дубль'} $_takeNumber: ${_manual ? 'ручной режим' : 'автоматический режим'}');
      _set(_manual ? EngineStatus.waiting : EngineStatus.paused);
    }
    return generation;
  }

  /// Команда извне (Connect): как ручное действие, но ошибка не только
  /// пишется в журнал, а возвращается вызывающему — чтобы Controller
  /// получил понятный результат. «Назад» и сброс отменяют и эти команды.
  Future<void> performCommand(SceneAction action, {bool Function()? cancelled}) async {
    final info = _info;
    if (info == null) throw StateError('сцена не загружена');
    if (!hasTake) await _beginTake(info);
    final generation = _generation;
    _history.add(-1);
    _historyActions.add(action);
    _redo.clear();
    _note('Connect: ${action.label}');
    try {
      await effects.perform(
        action,
        info,
        () => generation != _generation || (cancelled?.call() ?? false),
      );
    } catch (error) {
      _note('Ошибка: ${action.label} — $error');
      notifyListeners();
      rethrow;
    }
    unawaited(_persist());
    notifyListeners();
  }

  /// Ручное действие оператора от имени участника (не из таймлайна).
  /// Если дубль не идёт, он начинается — таймлайн при этом стоит в начале.
  /// При включённой [recordLive] действие дописывается в таймлайн с паузой,
  /// равной времени с предыдущего ручного действия: так сцена «пишется»
  /// прямо во время репетиции.
  Future<SceneAction?> performLive(SceneAction action) async {
    final info = _info;
    if (info == null) return null;
    if (!hasTake) await _beginTake(info);
    final now = _clock();
    final sinceLast = _lastLiveAt == null ? 0 : now.difference(_lastLiveAt!).inMilliseconds;
    _lastLiveAt = now;
    _note('Вручную: ${info.nameOf(action.params['characterId'] as String?)}');
    await _perform(action, _generation, index: -1);
    if (!_recordLive) return null;
    return action.copyWithDelay(sinceLast.clamp(0, 60000));
  }

  /// «Далее»: следующее действие в ручном режиме или продолжение после паузы.
  Future<void> next() async {
    switch (_status) {
      case EngineStatus.ready:
      case EngineStatus.finished:
        await start();
      case EngineStatus.waiting:
        final chat = _workChatKey;
        if (chat != null) {
          await nextInChat(chat);
        } else {
          await _step(_generation);
        }
      case EngineStatus.paused:
        resume();
      case EngineStatus.running:
      case EngineStatus.idle:
        break;
    }
  }

  /// Скрытый жест в кадре: срабатывает, только когда дубль уже идёт,
  /// чтобы случайное касание не запустило сцену.
  void hiddenNext() {
    if (_status == EngineStatus.waiting || _status == EngineStatus.paused) {
      unawaited(next());
    }
  }

  void pause() {
    if (_status == EngineStatus.running && !_manual) {
      _note('Пауза');
      _set(EngineStatus.paused);
    }
  }

  void resume() {
    if (_status != EngineStatus.paused) return;
    _note('Продолжение');
    _set(_manual ? EngineStatus.waiting : EngineStatus.running);
    if (!_manual && _autoLoopGeneration != _generation) {
      unawaited(_runAuto(_generation));
    }
  }

  /// «Назад»: отменить последнее выполненное действие. Сцена встаёт
  /// на него и ждёт «Далее» (в автоматическом режиме — на паузе).
  Future<void> back() async {
    final info = _info;
    if (info == null || !hasTake) return;
    _generation++; // останавливает автоцикл, ожидания и «печатает…»
    if (_history.isEmpty) {
      _index = 0;
      _note('Назад: это начало сцены');
      _set(_manual ? EngineStatus.waiting : EngineStatus.paused);
      return;
    }
    final index = _history.removeLast();
    final undone = _historyActions.isEmpty ? null : _historyActions.removeLast();
    if (undone != null) _redo.add(undone);
    try {
      await effects.undoLast(info);
    } catch (error) {
      _note('Ошибка отмены: $error');
    }
    if (index >= 0) {
      _executed.remove(_actions[index].id);
      // Событие, выполненное из личного таймлайна «вне очереди», не должно
      // уводить общий таймлайн вперёд.
      if (index < _index) _index = index;
      _note('Назад: ${_actions[index].label}');
    } else {
      _note('Назад: отменено ручное действие');
    }
    unawaited(_persist());
    _set(_manual ? EngineStatus.waiting : EngineStatus.paused);
  }

  /// Остановить дубль без сброса (всё показанное остаётся на экране).
  Future<void> stop() async {
    final info = _info;
    final wasActive = isActive;
    _generation++;
    if (info != null && wasActive) {
      await effects.endTake(info, completed: false);
      _note('Дубль остановлен');
      if (info.rehearsal) {
        await _rollBackRehearsal(info);
        return;
      }
    }
    if (_info != null) _set(EngineStatus.ready);
  }

  /// Перейти к шагу таймлайна. Назад — выполненные после него действия
  /// отменяются; вперёд — пропущенные не выполняются.
  Future<void> jumpTo(int index) async {
    final info = _info;
    if (info == null || !hasTake || _status == EngineStatus.running || _actions.isEmpty) return;
    final target = index.clamp(0, _actions.length - 1);
    _generation++;
    if (target < _index) {
      while (_history.isNotEmpty && (_history.last >= target || _history.last < 0)) {
        final undoneIndex = _history.removeLast();
        if (undoneIndex >= 0 && undoneIndex < _actions.length) _executed.remove(_actions[undoneIndex].id);
        if (_historyActions.isNotEmpty) _historyActions.removeLast();
        try {
          await effects.undoLast(info);
        } catch (error) {
          _note('Ошибка отмены: $error');
        }
      }
    }
    _index = target;
    unawaited(_persist());
    _note('Переход к шагу ${target + 1}: ${_actions[target].label}');
    _set(_manual ? EngineStatus.waiting : EngineStatus.paused);
  }

  /// Выполнить действие вне очереди (например, повторить «печатает…»).
  /// Позиция таймлайна не меняется; «Назад» отменит и это действие.
  Future<void> performNow(int index) async {
    if (_info == null || !hasTake || _status == EngineStatus.running) return;
    if (index < 0 || index >= _actions.length) return;
    _note('Вне очереди:');
    await _perform(_actions[index], _generation, index: index);
  }

  /// «Повторить» (redo): вернуть последнее отменённое ручное действие.
  /// Действия таймлайна возвращаются обычным «Далее».
  Future<void> redo() async {
    if (!canRedo || _status == EngineStatus.running) return;
    final action = _redo.removeLast();
    final keep = List<SceneAction>.of(_redo);
    _note('Повтор: ${action.label}');
    await _perform(action, _generation, index: -1);
    _redo
      ..clear()
      ..addAll(keep); // _perform очищает redo для новых действий — возвращаем очередь
    notifyListeners();
  }

  /// «ПОВТОРИТЬ СЦЕНУ»: вернуть телефон в состояние до прогона и начать
  /// новый дубль (его номер — следующий; история прежних дублей сохраняется).
  Future<void> repeat() async {
    if (_info == null) return;
    if (hasTake || _status == EngineStatus.finished) await reset();
    await start();
  }

  /// «СБРОС СЦЕНЫ»: всё, что добавила и изменила сцена, отменяется.
  Future<void> reset({bool restoreScreen = false}) async {
    final info = _info;
    if (info == null) return;
    _generation++;
    await effects.reset(info, restoreScreen: restoreScreen);
    _history.clear();
    _executed.clear();
    _index = 0;
    _note('Сброс сцены');
    _set(EngineStatus.ready);
  }

  Future<void> markTake(TakeStatus status) async {
    final info = _info;
    if (info == null) return;
    await effects.markTake(info, status);
    _note('Дубль ${_takeNumber ?? ''}: ${status.label.toLowerCase()}');
    notifyListeners();
  }

  // ---------- Выполнение ----------

  Future<void> _runAuto(int generation) async {
    _autoLoopGeneration = generation;
    try {
      await _autoLoop(generation);
    } finally {
      if (_autoLoopGeneration == generation) _autoLoopGeneration = null;
    }
  }

  Future<void> _autoLoop(int generation) async {
    while (generation == _generation && _index < _actions.length) {
      if (!await _waitWhilePaused(generation)) return;
      _skipExecuted();
      if (_index >= _actions.length) break;
      final action = _actions[_index];
      if (action.delayMs > 0 && !await _sleep(action.delayMs, generation)) return;
      if (generation != _generation) return;
      await _perform(action, generation, mark: true);
      if (generation != _generation) return;
      _index++;
      _skipExecuted();
      notifyListeners();
    }
    if (generation == _generation) await _complete();
  }

  Future<void> _step(int generation) async {
    _skipExecuted();
    if (_index >= _actions.length) {
      await _complete();
      return;
    }
    _set(EngineStatus.running);
    await _perform(_actions[_index], generation, mark: true);
    if (generation != _generation) return;
    _index++;
    _skipExecuted();
    if (_index >= _actions.length) {
      await _complete();
    } else if (_status == EngineStatus.running) {
      _set(EngineStatus.waiting);
    }
  }

  Future<void> _perform(SceneAction action, int generation, {int? index, bool mark = false}) async {
    final info = _info;
    final type = action.type;
    if (info == null) return;
    try {
      switch (type) {
        case null:
          _note('Пропущено: ${action.label}');
        case ActionType.wait:
          if (!_manual) await _sleep(_paramMs(action, 'ms', 1000), generation);
          _note(action.label);
        case ActionType.pause:
          if (!_manual) {
            _note('Пауза по таймлайну — ждёт «Далее»');
            _set(EngineStatus.paused);
            await _waitWhilePaused(generation);
          }
        case ActionType.resume:
          break;
        case ActionType.finish:
          _index = _actions.length - 1;
          _note(action.label);
        case ActionType.reset:
          _note('Сброс по таймлайну');
          await effects.reset(info);
          _history.clear();
          _executed.clear();
        default:
          _history.add(index ?? _index);
          _historyActions.add(index == -1 ? action : null);
          if (index == -1) _redo.clear();
          await effects.perform(action, info, () => generation != _generation);
          if (generation == _generation) _note(action.label);
      }
      // Выполнено без ошибки — событие получает статус «выполнено».
      if (mark && generation == _generation && type != ActionType.reset) _executed.add(action.id);
    } catch (error) {
      _note('Ошибка: ${action.label} — $error');
      debugPrint('Действие сцены не выполнено: $error');
    }
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> _complete() async {
    final info = _info;
    _generation++;
    if (info != null) await effects.endTake(info, completed: true);
    if (info != null && info.rehearsal) {
      await _rollBackRehearsal(info);
      return;
    }
    _note('Сцена завершена');
    _set(EngineStatus.finished);
  }

  /// Репетиция не меняет профили: по окончании всё откатывается,
  /// а запись о прогоне остаётся в истории дублей.
  Future<void> _rollBackRehearsal(SceneRunInfo info) async {
    await effects.reset(info);
    _history.clear();
    _historyActions.clear();
    _redo.clear();
    _executed.clear();
    _index = 0;
    _note('Репетиция окончена — изменения откачены');
    _set(EngineStatus.ready);
  }

  /// Пауза в движке: время идёт, только пока статус «Идёт».
  Future<bool> _sleep(int ms, int generation) async {
    var left = (ms / _speed).round();
    var ticks = 0;
    _remainingMs = left;
    notifyListeners();
    try {
      while (left > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (generation != _generation) return false;
        if (_status == EngineStatus.running) left -= 25;
        _remainingMs = left < 0 ? 0 : left;
        if (++ticks % 8 == 0) notifyListeners(); // обратный отсчёт на панели
      }
      return true;
    } finally {
      _remainingMs = 0;
    }
  }

  Future<bool> _waitWhilePaused(int generation) async {
    while (_status == EngineStatus.paused) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (generation != _generation) return false;
    }
    return generation == _generation;
  }

  static int _paramMs(SceneAction action, String key, int fallback) {
    final value = action.params[key];
    return value is num ? value.toInt() : fallback;
  }
}
