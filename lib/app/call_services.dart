import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/util/ids.dart';
import '../data/models/call_record.dart';
import '../data/models/message.dart';
import '../data/models/origin.dart';
import 'call_engine.dart';
import 'services.dart';

/// Запись звонка: строка в истории звонков и запись в переписке
/// («Пропущенный аудиозвонок»). Звонок сцены помечается сценой и
/// исчезает при «СБРОС СЦЕНЫ».
class ServicesCallRecorder implements CallRecorder {
  ServicesCallRecorder(this.services);

  final AppServices services;

  @override
  Future<void> record(CallSession session, CallOutcome outcome, DateTime startedAt, Duration talked) async {
    await writeCall(
      services,
      deviceId: session.deviceId,
      peerId: session.characterId,
      chatId: session.chatId,
      direction: session.direction,
      kind: session.kind,
      outcome: outcome,
      startedAt: startedAt,
      talked: talked,
      sceneId: session.sceneId,
    );
    // Зеркальная запись у собеседника, если его профиль — на этом устройстве.
    final mirror = session.mirrorDeviceId;
    final mirrorPeer = session.mirrorCharacterId;
    if (mirror != null && mirrorPeer != null) {
      await writeCall(
        services,
        deviceId: mirror,
        peerId: mirrorPeer,
        direction: session.direction == CallDirection.incoming ? CallDirection.outgoing : CallDirection.incoming,
        kind: session.kind,
        outcome: mirrorOutcome(session.direction, outcome),
        startedAt: startedAt,
        talked: talked,
        sceneId: session.sceneId,
      );
    }
  }
}

/// Итог звонка глазами второй стороны: сброшенный вызывающим — у того,
/// кому звонили, пропущенный.
CallOutcome mirrorOutcome(CallDirection direction, CallOutcome outcome) {
  if (direction == CallDirection.outgoing && outcome == CallOutcome.cancelled) return CallOutcome.missed;
  if (direction == CallDirection.incoming && outcome == CallOutcome.missed) return CallOutcome.cancelled;
  return outcome;
}

/// Записать звонок в историю профиля и в его переписку: строка в звонках,
/// «Пропущенный аудиозвонок» в чате, счётчик и уведомление для
/// пропущенного входящего. Звонок сцены помечается сценой и исчезает
/// при «СБРОС СЦЕНЫ».
Future<({String callId, String messageId, String chatId, bool unread})> writeCall(
  AppServices services, {
  required String deviceId,
  required String peerId,
  String? chatId,
  required CallDirection direction,
  required CallKind kind,
  required CallOutcome outcome,
  required DateTime startedAt,
  required Duration talked,
  String? sceneId,
}) async {
  final origin = sceneId == null ? DataOrigin.base : DataOrigin.scene;
  final callId = newId();
  await services.calls.insert(CallRecord(
    id: callId,
    deviceId: deviceId,
    characterId: peerId,
    direction: direction,
    kind: kind,
    outcome: outcome,
    startedAt: startedAt,
    durationMs: talked.inMilliseconds,
    origin: origin,
    sceneId: sceneId,
  ));
  final chat = chatId ?? await services.chats.openOrCreateDirect(deviceId: deviceId, characterId: peerId);
  final header = await services.chats.header(chat);
  if (header == null) return (callId: callId, messageId: '', chatId: chat, unread: false);
  final incoming = direction == CallDirection.incoming;
  final message = await services.messages.insertSceneMessage(
    chatId: chat,
    senderId: incoming ? peerId : header.ownerCharacterId,
    type: MessageType.call,
    text: callSummary(direction, kind, outcome, talked),
    sceneId: sceneId,
    origin: origin,
    state: MessageState.read,
    sentAt: sceneId == null ? null : services.engine.sceneNow(),
  );
  final missed = incoming && outcome != CallOutcome.answered;
  final onScreen = services.currentDeviceId.value == deviceId && services.openChatId.value == chat;
  if (missed && !onScreen) {
    await services.chats.incrementUnread(chat);
    if (services.currentDeviceId.value == deviceId) {
      unawaited(services.notifyIncoming(chat, callSummary(direction, kind, outcome, talked)));
    }
  }
  return (callId: callId, messageId: message.id, chatId: chat, unread: missed && !onScreen);
}

/// Звуки звонка из ресурсов приложения (собственные, без сети).
class AssetCallSounds implements CallSounds {
  AudioPlayer? _player;

  AudioPlayer get _p => _player ??= AudioPlayer();

  Future<void> _play(String asset, {required bool loop}) async {
    try {
      await _p.stop();
      await _p.setAsset(asset);
      await _p.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      unawaited(_p.play());
    } catch (error) {
      debugPrint('Звук звонка не воспроизведён: $error');
    }
  }

  @override
  void ringtone() => unawaited(_play('assets/sounds/ringtone.wav', loop: true));

  @override
  void ringback() => unawaited(_play('assets/sounds/ringback.wav', loop: true));

  @override
  void hangup() => unawaited(_play('assets/sounds/hangup.wav', loop: false));

  @override
  void stop() {
    final player = _player;
    if (player != null) unawaited(player.stop());
  }
}
