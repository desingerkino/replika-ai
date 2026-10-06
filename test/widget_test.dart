import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/core/design/colors.dart';
import 'package:replika/core/design/icons.dart';
import 'package:replika/core/design/theme.dart';
import 'package:replika/core/design/widgets/avatar.dart';
import 'package:replika/core/design/widgets/states.dart';
import 'package:replika/core/design/widgets/unread_badge.dart';
import 'package:replika/data/models/message.dart';
import 'package:replika/features/chat/message_ticks.dart';

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('аватар без фото показывает инициалы', (tester) async {
    await tester.pumpWidget(host(const Avatar(name: 'Алексей Громов')));
    expect(find.text('АГ'), findsOneWidget);
  });

  testWidgets('«прочитано» — две галочки цветом прочтения', (tester) async {
    const readColor = Color(0xFF00FF00);
    await tester.pumpWidget(host(const MessageTicks(
      state: MessageState.read,
      color: Color(0xFF000000),
      readColor: readColor,
    )));
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.tickDouble));
    expect(icon.color, readColor);
  });

  testWidgets('«отправлено» — одна галочка', (tester) async {
    await tester.pumpWidget(host(const MessageTicks(
      state: MessageState.sent,
      color: Color(0xFF000000),
      readColor: Color(0xFF00FF00),
    )));
    expect(find.byIcon(AppIcons.tickSent), findsOneWidget);
    expect(find.byIcon(AppIcons.tickDouble), findsNothing);
  });

  testWidgets('счётчик непрочитанных', (tester) async {
    await tester.pumpWidget(host(const UnreadBadge(count: 1200)));
    expect(find.text('999+'), findsOneWidget);
    await tester.pumpWidget(host(const UnreadBadge(count: 0)));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('пустое состояние', (tester) async {
    await tester.pumpWidget(host(const EmptyState(
      icon: AppIcons.emptyChats,
      title: 'Чатов пока нет',
      message: 'Откройте контакт',
    )));
    expect(find.text('Чатов пока нет'), findsOneWidget);
    expect(find.text('Откройте контакт'), findsOneWidget);
  });

  testWidgets('тёмная тема содержит фирменные цвета', (tester) async {
    const probe = Key('probe');
    await tester.pumpWidget(host(const SizedBox(key: probe), theme: AppTheme.dark));
    final theme = Theme.of(tester.element(find.byKey(probe)));
    expect(theme.brightness, Brightness.dark);
    expect(
      theme.extension<ReplikaColors>()!.chatBackground,
      ReplikaColors.dark.chatBackground,
    );
  });
}
