import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/models/media_item.dart';

/// Единый проигрыватель голосовых и аудио: одновременно звучит только
/// одно сообщение, как в настоящем мессенджере.
class AudioPlayback extends ChangeNotifier {
  AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  String? _currentId;
  MediaItem? _currentMedia;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  String? get currentId => _currentId;

  /// Сообщение, которое сейчас активно (играет или на паузе); null — тишина.
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
    _subscriptions.add(player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playing = false;
        _position = Duration.zero;
        unawaited(player.pause());
        unawaited(player.seek(Duration.zero));
      } else {
        _playing = state.playing;
      }
      notifyListeners();
    }));
    return _player = player;
  }

  /// Запуск или пауза сообщения.
  Future<void> toggle(MediaItem media) async {
    final player = _ensurePlayer();
    if (_currentId == media.id) {
      if (_playing) {
        await player.pause();
      } else {
        unawaited(player.play());
      }
      return;
    }
    _currentId = media.id;
    _currentMedia = media;
    _position = Duration.zero;
    _duration = media.duration;
    notifyListeners();
    try {
      final duration = await player.setFilePath(media.path);
      _duration = duration ?? _duration;
      unawaited(player.play());
    } catch (error) {
      debugPrint('Не удалось воспроизвести: $error');
      _currentId = null;
      _currentMedia = null;
      _playing = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Перемотка активного сообщения; [fraction] — 0..1 от длительности.
  Future<void> seekFraction(double fraction) async {
    final total = _duration;
    final player = _player;
    if (_currentId == null || total == null || total.inMilliseconds <= 0 || player == null) return;
    final target = Duration(milliseconds: (total.inMilliseconds * fraction.clamp(0.0, 1.0)).round());
    _position = target;
    notifyListeners();
    await player.seek(target);
  }

  /// Пауза или продолжение активного сообщения (кнопка верхнего плеера).
  Future<void> togglePlayPause() async {
    final player = _player;
    if (_currentId == null || player == null) return;
    if (_playing) {
      await player.pause();
    } else {
      unawaited(player.play());
    }
  }

  Future<void> stop() async {
    await _player?.stop();
    _currentId = null;
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
