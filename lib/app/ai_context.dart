import '../data/models/message.dart';
import 'auto_reply.dart';

/// Подпись вместо медиа в контексте ИИ: модель понимает, что было
/// отправлено фото или голосовое, хотя содержимого не видит.
String? aiMediaLabel(Message m) => switch (m.type) {
      MessageType.photo => '[фото]',
      MessageType.video => '[видео]',
      MessageType.voice => '[голосовое сообщение]',
      MessageType.videoNote => '[видеосообщение]',
      MessageType.audio => '[аудиозапись]',
      MessageType.file => '[файл]',
      _ => null,
    };

/// Контекст переписки для ИИ-собеседника.
///
/// * текст и подписи к медиа идут как есть, медиа без подписи — меткой
///   «[фото]» и т. п.; звонки, системные и удалённые сообщения пропускаются;
/// * подряд идущие реплики одного человека склеиваются в одну (модели
///   ждут чередования «пользователь — собеседник»);
/// * остаются последние [limit] реплик, и первая из них — от владельца
///   телефона (ответ ИИ без вопроса сбивает модель).
List<AiTurn> buildAiHistory(List<Message> messages, String ownerId, {int limit = 12}) {
  final turns = <AiTurn>[];
  for (final m in messages) {
    if (m.deleted || m.type == MessageType.system || m.type == MessageType.call) continue;
    final caption = m.text.trim();
    final label = aiMediaLabel(m);
    final text = label == null ? caption : (caption.isEmpty ? label : '$label $caption');
    if (text.isEmpty) continue;
    final fromOwner = m.senderId == ownerId;
    if (turns.isNotEmpty && turns.last.fromOwner == fromOwner) {
      turns[turns.length - 1] = AiTurn(fromOwner: fromOwner, text: '${turns.last.text}\n$text');
    } else {
      turns.add(AiTurn(fromOwner: fromOwner, text: text));
    }
  }
  var recent = turns.length > limit ? turns.sublist(turns.length - limit) : turns;
  while (recent.isNotEmpty && !recent.first.fromOwner) {
    recent = recent.sublist(1);
  }
  return recent;
}
