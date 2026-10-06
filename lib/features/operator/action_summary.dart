import '../../data/models/message.dart';
import '../../data/models/scene_action.dart';

/// Типы действий, которые умеет выполнять эта версия.
const Set<ActionType> supportedActionTypes = {
  ActionType.showIncoming,
  ActionType.showOutgoing,
  ActionType.sendMessage,
  ActionType.startTyping,
  ActionType.message,
  ActionType.call,
  ActionType.deleteMessage,
  ActionType.editMessage,
  ActionType.setMessageState,
  ActionType.showPhoto,
  ActionType.showVideo,
  ActionType.showVoice,
  ActionType.showVideoNote,
  ActionType.playAudio,
  ActionType.openChat,
  ActionType.openProfile,
  ActionType.navigateBack,
  ActionType.wait,
  ActionType.pause,
  ActionType.finish,
  ActionType.incomingAudioCall,
  ActionType.outgoingAudioCall,
  ActionType.incomingVideoCall,
  ActionType.outgoingVideoCall,
  ActionType.acceptCall,
  ActionType.declineCall,
  ActionType.endCall,
  ActionType.startConversation,
  ActionType.playCallSound,
  ActionType.showCallVideo,
  ActionType.postNotification,
  ActionType.updateNotificationText,
  ActionType.updateNotificationTime,
  ActionType.showEvent,
};

/// Почему тип нельзя добавить в таймлайн (null — можно).
String? unavailableReason(ActionType type) {
  if (supportedActionTypes.contains(type)) return null;
  if (type == ActionType.createGroup || type == ActionType.addGroupMember || type == ActionType.removeGroupMember) {
    return 'Группы — через Connect или экран группы; в редакторе таймлайна появятся позже';
  }
  return switch (type.group) {
    _ => type == ActionType.resume
        ? 'Продолжение после паузы — кнопкой «Далее»'
        : 'Сброс — кнопкой «СБРОС СЦЕНЫ» на панели',
  };
}

String messageStateName(MessageState state) => switch (state) {
      MessageState.sending => 'отправляется',
      MessageState.sent => 'отправлено',
      MessageState.delivered => 'доставлено',
      MessageState.read => 'прочитано',
      MessageState.failed => 'не отправлено',
    };

const Map<String, String> targetNames = {
  'lastIncoming': 'последнее сообщение участника',
  'lastOutgoing': 'последнее сообщение владельца телефона',
  'last': 'последнее сообщение в чате',
};

/// Действия, которые выполняются от имени участника сцены.
const Set<ActionType> participantActionTypes = {
  ActionType.showIncoming,
  ActionType.showOutgoing,
  ActionType.sendMessage,
  ActionType.startTyping,
  ActionType.deleteMessage,
  ActionType.editMessage,
  ActionType.setMessageState,
  ActionType.showPhoto,
  ActionType.showVideo,
  ActionType.showVoice,
  ActionType.showVideoNote,
  ActionType.openChat,
  ActionType.openProfile,
  ActionType.postNotification,
  ActionType.showEvent,
  ActionType.incomingAudioCall,
  ActionType.outgoingAudioCall,
  ActionType.incomingVideoCall,
  ActionType.outgoingVideoCall,
  ActionType.acceptCall,
  ActionType.declineCall,
  ActionType.endCall,
  ActionType.startConversation,
  ActionType.playCallSound,
  ActionType.showCallVideo,
};

/// Время каждого действия от начала сцены в автоматическом режиме
/// (сумма пауз): 00:00, 00:03, 00:07…
List<Duration> timelineOffsets(List<SceneAction> actions) {
  var total = 0;
  return [
    for (final a in actions)
      Duration(milliseconds: total += a.enabled ? a.delayMs : 0),
  ];
}

/// «00:07», «01:15».
String offsetLabel(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// «2,5 с»
String secondsLabel(int ms) {
  final s = ms / 1000;
  final text = s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} с';
}

/// «· прочитано» / «· не прочитано до ответа» у исходящего с настройкой.
String readLabel(Map<String, Object?> params) {
  final flag = params['read'];
  if (flag is! bool) return '';
  return flag ? ' · прочитано' : ' · не прочитано до ответа';
}

/// Короткое описание действия для строки таймлайна.
String actionSummary(SceneAction action, {String peerName = 'Собеседник'}) {
  final p = action.params;
  String text([String key = 'text']) {
    final value = (p[key] as String?)?.trim() ?? '';
    return value.isEmpty ? '(пусто)' : '«$value»';
  }

  int ms(String key) => (p[key] as num?)?.toInt() ?? 0;
  final media = (p['mediaName'] as String?) ?? 'файл не выбран';
  final incoming = p['direction'] != 'out';

  final base = switch (action.type) {
    ActionType.showIncoming =>
      '$peerName: ${text()}${ms('typingMs') > 0 ? ', печатает ${secondsLabel(ms('typingMs'))}' : ''}'
          '${p['replyToActionId'] == null ? '' : ' · ответ на сообщение'}',
    ActionType.showOutgoing => 'Вы → $peerName: ${text()}${readLabel(p)}',
    ActionType.sendMessage => 'Вы → $peerName: ${text()} — с отправкой'
        '${p['read'] is bool ? readLabel(p) : (ms('readMs') > 0 ? ' и прочтением' : '')}',
    ActionType.startTyping => '$peerName печатает ${secondsLabel(ms('durationMs') == 0 ? 4000 : ms('durationMs'))}',
    ActionType.message => '${p['fromName'] ?? '?'} → ${p['toName'] ?? '?'}: ${text()}'
        '${p['state'] == null ? '' : ' (${_stateWord(p['state'])})'}'
        '${ms('typingMs') > 0 ? ', печатает ${secondsLabel(ms('typingMs'))}' : ''}',
    ActionType.call => '${p['fromName'] ?? '?'} → ${p['toName'] ?? '?'}: ${p['video'] == true ? 'видеозвонок' : 'звонок'}',
    ActionType.createGroup => 'Создать группу «${(p['title'] as String?) ?? ''}»',
    ActionType.addGroupMember => 'Добавить в группу',
    ActionType.removeGroupMember => 'Удалить из группы',
    ActionType.editMessage =>
      '$peerName: изменить ${targetNames[p['target']] ?? targetNames['lastIncoming']} на ${text()}',
    ActionType.deleteMessage => '$peerName: удалить ${targetNames[p['target']] ?? targetNames['lastIncoming']}',
    ActionType.setMessageState =>
      '${targetNames[p['target']] ?? targetNames['lastOutgoing']} → '
          '${messageStateName(MessageState.values.firstWhere((s) => s.name == p['state'], orElse: () => MessageState.read))}',
    ActionType.showPhoto ||
    ActionType.showVideo ||
    ActionType.showVoice ||
    ActionType.showVideoNote =>
      '${incoming ? peerName : 'Вы'}: $media',
    ActionType.playAudio => 'Звук: $media',
    ActionType.openChat => 'Открыть чат: $peerName',
    ActionType.openProfile => 'Открыть профиль: $peerName',
    ActionType.navigateBack => 'Системное «назад»',
    ActionType.wait => 'Ждать ${secondsLabel(ms('ms') == 0 ? 1000 : ms('ms'))}',
    ActionType.pause => 'Остановиться до «Далее»',
    ActionType.postNotification =>
      'Уведомление: ${(p['title'] as String?)?.trim().isNotEmpty == true ? '${p['title']} — ' : ''}${text()}',
    ActionType.updateNotificationText => 'Новый текст уведомления: ${text()}',
    ActionType.updateNotificationTime => 'Время уведомления: ${(p['time'] as String?) ?? '—'}',
    ActionType.showEvent => 'Событие в чате: ${text()}',
    ActionType.incomingAudioCall => '$peerName звонит (аудио)',
    ActionType.incomingVideoCall => '$peerName звонит (видео)',
    ActionType.outgoingAudioCall => 'Звонок: $peerName (аудио)',
    ActionType.outgoingVideoCall => 'Звонок: $peerName (видео)',
    ActionType.acceptCall => '$peerName: трубку сняли',
    ActionType.declineCall => '$peerName: звонок отклонён',
    ActionType.endCall => '$peerName: трубку положили',
    ActionType.startConversation => 'Сразу разговор (без «Соединение…»)',
    ActionType.playCallSound => 'Голос в звонке: $media',
    ActionType.showCallVideo => 'Видео в звонке: $media',
    ActionType.finish => 'Конец сцены',
    null => 'Не поддерживается этой версией',
    _ => unavailableReason(action.type!) ?? '',
  };
  // Событие, привязанное к конкретному сообщению или звонку сцены.
  final ref = p['refLabel'] as String?;
  return ref == null ? base : '$base — событие $ref';
}

String _stateWord(Object? name) => switch (name) {
      'sending' => 'отправляется',
      'sent' => 'отправлено',
      'delivered' => 'доставлено',
      'read' => 'прочитано',
      'failed' => 'не доставлено',
      _ => '$name',
    };
