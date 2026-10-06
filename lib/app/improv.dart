import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/util/text.dart';
import '../data/models/message.dart';
import '../data/models/origin.dart';
import '../data/models/prepared_reply.dart';

/// Реплика в очереди импровизации.
@immutable
class QueuedReply {
  const QueuedReply({required this.text, this.typingMs = 2000, this.fromOwner = false});

  final String text;
  final int typingMs;

  /// true — пишет владелец телефона, false — собеседник.
  final bool fromOwner;
}

/// Очередь ответов: оператор готовит её заранее, в кадре ответы
/// отправляются по одному (громкость вверх или касание двумя пальцами).
class ReplyQueue {
  final List<QueuedReply> _items = [];

  List<QueuedReply> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  void add(QueuedReply reply) => _items.add(reply);
  void removeAt(int index) => _items.removeAt(index);
  void clear() => _items.clear();

  QueuedReply? takeNext() => _items.isEmpty ? null : _items.removeAt(0);

  /// Вернуть отменённый ответ в начало очереди.
  void putBack(QueuedReply reply) => _items.insert(0, reply);
}

/// Как импровизация пишет в переписку. Отделено для автотестов.
abstract class ImprovSender {
  /// Возвращает id созданного сообщения.
  Future<String> send(String chatId, QueuedReply reply);
  Future<void> delete(String messageId);
}

/// Импровизация: очередь, отправка и отмена последнего ответа.
class ImprovController extends ChangeNotifier {
  ImprovController(this.sender);

  final ImprovSender sender;
  final ReplyQueue queue = ReplyQueue();
  final List<(String, QueuedReply)> _sent = [];

  String? _chatId;
  bool _armed = false;
  bool _busy = false;

  /// Чат, куда отправляется очередь.
  String? get chatId => _chatId;

  /// Очередь «взведена»: кнопки громкости отправляют ответы.
  bool get armed => _armed && _chatId != null;
  bool get busy => _busy;
  int get sentCount => _sent.length;

  void setChat(String? chatId) {
    if (_chatId == chatId) return;
    _chatId = chatId;
    _sent.clear();
    notifyListeners();
  }

  void enqueue(QueuedReply reply) {
    if (reply.text.trim().isEmpty) return;
    queue.add(reply);
    notifyListeners();
  }

  void removeAt(int index) {
    queue.removeAt(index);
    notifyListeners();
  }

  void clearQueue() {
    queue.clear();
    notifyListeners();
  }

  void arm(bool value) {
    _armed = value;
    notifyListeners();
  }

  /// Отправить ответ сразу (из панели оператора).
  Future<void> sendNow(String chatId, QueuedReply reply) async {
    if (_busy || reply.text.trim().isEmpty) return;
    _busy = true;
    notifyListeners();
    try {
      final id = await sender.send(chatId, reply);
      if (chatId == _chatId) _sent.add((id, reply));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Следующий ответ из очереди (громкость вверх в кадре).
  Future<void> sendNext() async {
    final chatId = _chatId;
    if (!armed || _busy || chatId == null) return;
    final reply = queue.takeNext();
    if (reply == null) return;
    _busy = true;
    notifyListeners();
    try {
      final id = await sender.send(chatId, reply);
      _sent.add((id, reply));
    } catch (error) {
      queue.putBack(reply);
      debugPrint('Ответ не отправлен: $error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Отменить последний отправленный ответ: сообщение исчезает,
  /// реплика возвращается в начало очереди (громкость вниз).
  Future<void> undoLast() async {
    if (_busy || _sent.isEmpty) return;
    final (id, reply) = _sent.removeLast();
    try {
      await sender.delete(id);
    } catch (error) {
      debugPrint('Ответ не отменён: $error');
    }
    queue.putBack(reply);
    notifyListeners();
  }
}

/// Какие категории заготовок подходят в ответ на реплику героя.
///
/// Это подбор по ключевым словам, а не ИИ: интерфейс так и подписывает
/// подсказку. Первая категория — самая подходящая.
List<ReplyCategory> suggestReplyCategories(String heroMessage) {
  final text = normalizeForSearch(heroMessage);
  if (text.isEmpty) return const [ReplyCategory.neutral, ReplyCategory.short];
  final words = text.split(RegExp(r'[^а-яa-z0-9]+')).where((w) => w.isNotEmpty).toSet();
  // Основы слов («прости» → «простите») ищем подстрокой, короткие слова — целиком.
  bool has(List<String> stems) => stems.any(text.contains);
  bool hasWord(List<String> list) => list.any(words.contains);

  if (has(['прости', 'извини', 'виноват', 'не хотел'])) {
    return const [ReplyCategory.emotional, ReplyCategory.refuse, ReplyCategory.agree];
  }
  if (has(['люблю', 'скучаю', 'обиделась', 'обиделся', 'злишься', 'ненавижу'])) {
    return const [ReplyCategory.emotional, ReplyCategory.short];
  }
  if (has(['давай', 'можешь', 'приходи', 'приезжай', 'позвони', 'встретимся', 'пойдем'])) {
    return const [ReplyCategory.agree, ReplyCategory.refuse, ReplyCategory.action];
  }
  if (text.contains('?') ||
      hasWord(['где', 'когда', 'почему', 'зачем', 'кто', 'что', 'как', 'сколько', 'куда'])) {
    return const [ReplyCategory.explain, ReplyCategory.short, ReplyCategory.question];
  }
  if (has(['привет', 'доброе', 'здравствуй', 'добрый'])) {
    return const [ReplyCategory.short, ReplyCategory.neutral, ReplyCategory.question];
  }
  return const [ReplyCategory.neutral, ReplyCategory.question, ReplyCategory.short];
}

/// Статус нового сообщения импровизации.
MessageState improvState(QueuedReply reply) =>
    reply.fromOwner ? MessageState.read : MessageState.delivered;

/// Происхождение сообщений импровизации (для «Убрать импровизацию»).
const DataOrigin improvOrigin = DataOrigin.improv;
