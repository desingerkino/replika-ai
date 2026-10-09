import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models/media_item.dart';

/// Единый проигрыватель голосовых и аудио: одновременно звучит только
/// одно сообщение, как в настоящем мессенджере.
///
/// Состояние воспроизведения (что играет, где курсор) живёт здесь и не
/// смешивается со статусом доставки сообщения. Когда голосовое дослушано
/// до конца, вызывается [onCompleted] с id сообщения — по нему сообщение
/// получает отметку «прослушано», а плеер над чатом исчезает.
class AudioPlayback extends ChangeNotifier {
  AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  String? _currentId;
  String? _currentMessageId;
  MediaItem? _currentMedia;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  /// Голосовое (id сообщения) дослушано до конца.
  void Function(String messageId)? onCompleted;

  String? get currentId => _currentId;

  /// Сообщение, которое сейчас в плеере (null — файл без сообщения).
  String? get currentMessageId => _currentMessageId;
  MediaItem? get currentMedia => _currentMedia;
  bool get playing => _playing;
  Duration get position => _position;
  Duration? get duration => _duration;

  bool isCurrent(String mediaId) => _currentId == mediaId;
  bool isPlaying(String mediaId) => _currentId == mediaId && _playing;

  /// Доля проигранного для [mediaId] (0..1).
  double progressOf(String mediaId) {
    final total = _duration;
    if (_currentId != mediaId || total == null || total.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _subscriptions.add(player.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    }));
    _subscriptions.add(player.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero) {
        _duration = duration;
        notifyListeners();
      }
    }));
    _subscriptions.add(player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        final finished = _currentMessageId;
        _playing = false;
        _position = Duration.zero;
        _currentId = null;
        _currentMessageId = null;
        _currentMedia = null;
        unawaited(player.pause());
        unawaited(player.seek(Duration.zero));
        if (finished != null) onCompleted?.call(finished);
      } else {
        _playing = state.playing;
      }
      notifyListeners();
    }));
    return _player = player;
  }

  Future<void> _load(MediaItem media, String? messageId) async {
    final player = _ensurePlayer();
    _currentId = media.id;
    _currentMessageId = messageId;
    _currentMedia = media;
    _position = Duration.zero;
    _duration = media.duration;
    notifyListeners();
    try {
      final duration = await player.setFilePath(media.path);
      _duration = duration ?? _duration;
    } catch (error) {
      debugPrint('Не удалось открыть аудио: $error');
      _currentId = null;
      _currentMessageId = null;
      _currentMedia = null;
      _playing = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Запуск или пауза сообщения.
  Future<void> toggle(MediaItem media, {String? messageId}) async {
    final player = _ensurePlayer();
    if (_currentId == media.id) {
      if (_playing) {
        await player.pause();
      } else {
        unawaited(player.play());
      }
      return;
    }
    await _load(media, messageId);
    unawaited(player.play());
  }

  /// Перемотка на долю [fraction] (0..1). Если играло другое — переключается
  /// на это сообщение и начинает с нужного места.
  Future<void> seekFraction(MediaItem media, double fraction, {String? messageId}) async {
    final player = _ensurePlayer();
    if (_currentId != media.id) {
      await _load(media, messageId);
      unawaited(player.play());
    }
    final total = _duration ?? media.duration;
    if (total == null || total <= Duration.zero) return;
    final target = Duration(milliseconds: (total.inMilliseconds * fraction.clamp(0.0, 1.0)).round());
    _position = target;
    notifyListeners();
    await player.seek(target);
  }

  Future<void> stop() async {
    await _player?.stop();
    _currentId = null;
    _currentMessageId = null;
    _currentMedia = null;
    _playing = false;
    _position = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player?.dispose();
    super.dispose();
  }
}
