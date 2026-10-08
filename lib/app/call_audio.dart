import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:replika_recorder/replika_recorder.dart';

/// Звук постановочного звонка: как у настоящего телефона.
///
/// * Разговор идёт в разговорный (верхний) динамик; кнопка «Динамик»
///   переключает на громкую связь и обратно — переключается настоящий
///   маршрут звука, а не только значок.
/// * «Микрофон выкл.» действительно глушит микрофон (и в записи экрана).
/// * Пока телефон у уха, датчик приближения гасит экран.
/// * После звонка звуковая сессия возвращается к обычному режиму
///   медиа (голосовые и видео в чатах снова звучат в громком динамике).
///
/// Ошибки маршрута звука не роняют звонок: пишутся в журнал.
class CallAudio {
  /// Атрибуты для плееров разговора на Android: голосовая связь, чтобы
  /// звук шёл в разговорный динамик, а не в мультимедийный.
  static const AndroidAudioAttributes voiceAttributes = AndroidAudioAttributes(
    contentType: AndroidAudioContentType.speech,
    usage: AndroidAudioUsage.voiceCommunication,
  );

  /// Рингтон входящего звонит как телефон, в громкий динамик.
  static const AndroidAudioAttributes ringtoneAttributes = AndroidAudioAttributes(
    contentType: AndroidAudioContentType.sonification,
    usage: AndroidAudioUsage.notificationRingtone,
  );

  bool _active = false;
  bool _speaker = false;
  bool _video = false;
  bool _proximity = false;
  bool _micMuted = false;

  bool get active => _active;
  bool get speaker => _speaker;

  bool get _supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> _guard(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Звук звонка ($what): $error');
    }
  }

  /// Начало разговора (вызов, соединение, разговор).
  Future<void> begin({required bool speaker, required bool video}) async {
    if (!_supported) return;
    _video = video;
    if (!_active) {
      _active = true;
      await _guard('сессия', () async {
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: video ? AVAudioSessionMode.videoChat : AVAudioSessionMode.voiceChat,
          androidAudioAttributes: voiceAttributes,
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ));
        await session.setActive(true);
        if (Platform.isAndroid) {
          await AndroidAudioManager().setMode(AndroidAudioHardwareMode.inCommunication);
        }
      });
    }
    await setSpeaker(speaker);
  }

  /// Громкая связь вкл./выкл.
  Future<void> setSpeaker(bool on) async {
    if (!_supported || !_active) return;
    _speaker = on;
    await _guard('динамик', () async {
      if (Platform.isIOS) {
        await AVAudioSession().overrideOutputAudioPort(
          on ? AVAudioSessionPortOverride.speaker : AVAudioSessionPortOverride.none,
        );
      } else {
        await AndroidAudioManager().setSpeakerphoneOn(on);
      }
    });
    await _updateProximity();
  }

  /// Микрофон звонка выкл./вкл. (глушится и в записи видеозвонка).
  Future<void> setMicrophoneMuted(bool muted) async {
    if (!_supported || _micMuted == muted) return;
    _micMuted = muted;
    await _guard('микрофон', () => ReplikaRecorder.setMicrophoneMuted(muted));
  }

  /// Экран гаснет у уха — только в аудиозвонке через разговорный динамик.
  Future<void> _updateProximity() async {
    final wanted = _active && !_speaker && !_video;
    if (wanted == _proximity) return;
    _proximity = wanted;
    await _guard('датчик приближения', () => ReplikaRecorder.setProximityMonitoring(wanted));
  }

  /// Звонок закончился: всё вернуть как было.
  Future<void> end() async {
    if (!_supported || !_active) return;
    _active = false;
    _speaker = false;
    await setMicrophoneMuted(false);
    await _updateProximity();
    await _guard('возврат к медиа', () async {
      if (Platform.isAndroid) {
        await AndroidAudioManager().setSpeakerphoneOn(false);
        await AndroidAudioManager().setMode(AndroidAudioHardwareMode.normal);
      } else {
        await AVAudioSession().overrideOutputAudioPort(AVAudioSessionPortOverride.none);
      }
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    });
  }
}
