import '../../data/models/message.dart';

String messageStateLabel(MessageState state) => switch (state) {
      MessageState.sending => 'Отправляется',
      MessageState.sent => 'Отправлено',
      MessageState.delivered => 'Доставлено',
      MessageState.read => 'Прочитано',
      MessageState.failed => 'Не отправлено',
    };

String messageTypeLabel(MessageType type) => switch (type) {
      MessageType.text => 'Сообщение',
      MessageType.photo => 'Фото',
      MessageType.video => 'Видео',
      MessageType.audio => 'Аудио',
      MessageType.voice => 'Голосовое сообщение',
      MessageType.videoNote => 'Видеосообщение',
      MessageType.file => 'Файл',
      MessageType.system => 'Событие',
      MessageType.call => 'Звонок',
    };
