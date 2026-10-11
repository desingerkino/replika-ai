import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/background_activity.dart';

/// Уведомления на заблокированном экране: что можно проверить без телефона.
/// Сам показ на экране блокировки iPhone проверяется только на устройстве.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  test('BackgroundActivity возвращает результат работы (вне iOS — без продления)', () async {
    final value = await BackgroundActivity.run('тест', () async => 42);
    expect(value, 42);
  });

  test('BackgroundActivity пробрасывает ошибку работы', () async {
    expect(
      BackgroundActivity.run<void>('тест', () async => throw StateError('сбой')),
      throwsStateError,
    );
  });

  test('приложение на экране, пока не ушло в фон', () {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(appInForeground, isTrue);
  });

  test('экран заблокирован или приложение свёрнуто — приложение не на экране', () {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      binding.handleAppLifecycleStateChanged(state);
      expect(appInForeground, isFalse, reason: '$state');
    }
  });
}
