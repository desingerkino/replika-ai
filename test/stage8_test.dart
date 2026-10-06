import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/notifications.dart';
import 'package:replika/data/models/scene_action.dart';
import 'package:replika/features/operator/action_summary.dart';

void main() {
  test('у каждого чата своё постоянное уведомление', () {
    expect(chatNotificationId('chat-veronika'), chatNotificationId('chat-veronika'));
    expect(chatNotificationId('chat-veronika'), isNot(chatNotificationId('chat-mama')));
    expect(chatNotificationId('chat-mama'), greaterThanOrEqualTo(0));
    expect(chatNotificationId('chat-mama'), lessThan(0x40000000));
  });

  test('в таймлайне доступны все группы действий, кроме служебных', () {
    final unavailable = ActionType.values.where((t) => unavailableReason(t) != null).toSet();
    expect(unavailable, {
      ActionType.resume,
      ActionType.reset,
      ActionType.createGroup,
      ActionType.addGroupMember,
      ActionType.removeGroupMember,
    });
  });

  test('описание уведомления в таймлайне', () {
    final action = SceneAction(
      id: 'a',
      sceneId: 's',
      position: 0,
      typeName: ActionType.postNotification.name,
      params: const {'title': 'Сбербанк', 'text': 'Списание 3 400 ₽'},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(actionSummary(action), 'Уведомление: Сбербанк — «Списание 3 400 ₽»');
  });
}
