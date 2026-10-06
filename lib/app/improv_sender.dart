import 'dart:async';

import '../data/models/message.dart';
import '../data/models/origin.dart';
import 'improv.dart';
import 'services.dart';

/// Отправка импровизации в настоящую переписку: «печатает…», прочтение
/// исходящих, счётчик непрочитанных и «время в кадре» — как у сцены.
/// Если в этом чате идёт дубль, ответы привязываются к сцене и исчезают
/// при «СБРОС СЦЕНЫ».
class ServicesImprovSender implements ImprovSender {
  ServicesImprovSender(this.services);

  final AppServices services;

  @override
  Future<String> send(String chatId, QueuedReply reply) async {
    final header = await services.chats.header(chatId);
    if (header == null) throw StateError('Чат не найден');
    final owner = header.ownerCharacterId;
    final peer = header.chat.peerCharacterId;

    if (!reply.fromOwner && reply.typingMs > 0) {
      services.typing.start(chatId, duration: Duration(milliseconds: reply.typingMs + 1500));
      await Future<void>.delayed(Duration(milliseconds: reply.typingMs));
      services.typing.stop(chatId);
    }
    if (!reply.fromOwner) await services.messages.markOutgoingRead(chatId, owner);

    final sceneId = services.engine.sceneIdForChat(chatId);
    final message = await services.messages.insertSceneMessage(
      chatId: chatId,
      senderId: reply.fromOwner ? owner : peer,
      type: MessageType.text,
      text: reply.text.trim(),
      sceneId: sceneId,
      state: improvState(reply),
      sentAt: sceneId == null ? null : services.engine.sceneNow(),
      origin: DataOrigin.improv,
    );
    if (!reply.fromOwner && services.openChatId.value != chatId) {
      await services.chats.incrementUnread(chatId);
      unawaited(services.notifyIncoming(chatId, reply.text.trim(),
          time: sceneId == null ? null : services.engine.sceneNow()));
    }
    return message.id;
  }

  @override
  Future<void> delete(String messageId) => services.messages.delete(messageId);
}
