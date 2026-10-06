// Скрытые жесты оператора: касание двумя пальцами — «Далее»,
// свайп двумя пальцами вверх — «Назад».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/hidden_gestures.dart';

Future<({List<String> calls})> pumpGestures(WidgetTester tester, {Widget? child}) async {
  final calls = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: HiddenGestures(
      onNext: () => calls.add('next'),
      onPrevious: () => calls.add('previous'),
      onOperator: () => calls.add('operator'),
      child: Scaffold(body: child ?? const SizedBox.expand()),
    ),
  ));
  return (calls: calls);
}

void main() {
  testWidgets('касание двумя пальцами — «Далее»', (tester) async {
    final r = await pumpGestures(tester);
    final a = await tester.startGesture(const Offset(100, 400), pointer: 1);
    final b = await tester.startGesture(const Offset(220, 400), pointer: 2);
    await a.up();
    await b.up();
    expect(r.calls, ['next']);
  });

  testWidgets('два пальца вверх — «Назад», и «Далее» не срабатывает', (tester) async {
    final r = await pumpGestures(tester);
    final a = await tester.startGesture(const Offset(100, 500), pointer: 1);
    final b = await tester.startGesture(const Offset(220, 500), pointer: 2);
    await a.moveBy(const Offset(0, -60));
    await b.moveBy(const Offset(0, -60));
    expect(r.calls, isEmpty, reason: 'слишком короткое движение');
    await a.moveBy(const Offset(0, -40));
    await b.moveBy(const Offset(0, -40));
    expect(r.calls, ['previous']);
    await a.moveBy(const Offset(0, -80));
    await b.up();
    await a.up();
    expect(r.calls, ['previous'], reason: 'один жест — одна команда');
  });

  testWidgets('два пальца вниз и в сторону — не «Назад»', (tester) async {
    final r = await pumpGestures(tester);
    final a = await tester.startGesture(const Offset(100, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(220, 300), pointer: 2);
    await a.moveBy(const Offset(0, 120));
    await b.moveBy(const Offset(0, 120));
    await a.up();
    await b.up();
    final c = await tester.startGesture(const Offset(100, 300), pointer: 3);
    final d = await tester.startGesture(const Offset(220, 300), pointer: 4);
    await c.moveBy(const Offset(150, -90));
    await d.moveBy(const Offset(150, -90));
    await c.up();
    await d.up();
    expect(r.calls, isEmpty);
  });

  testWidgets('один палец вверх — ничего', (tester) async {
    final r = await pumpGestures(tester);
    final a = await tester.startGesture(const Offset(100, 500), pointer: 1);
    await a.moveBy(const Offset(0, -200));
    await a.up();
    expect(r.calls, isEmpty);
  });

  testWidgets('три пальца вверх — не «Назад»', (tester) async {
    final r = await pumpGestures(tester);
    final g = [
      await tester.startGesture(const Offset(80, 500), pointer: 1),
      await tester.startGesture(const Offset(180, 500), pointer: 2),
      await tester.startGesture(const Offset(280, 500), pointer: 3),
    ];
    for (final f in g) {
      await f.moveBy(const Offset(0, -150));
    }
    for (final f in g) {
      await f.up();
    }
    expect(r.calls, isEmpty);
  });

  testWidgets('в текстовом поле жест не перехватывается', (tester) async {
    final r = await pumpGestures(tester, child: const TextField(autofocus: true));
    await tester.pump();
    final a = await tester.startGesture(const Offset(100, 500), pointer: 1);
    final b = await tester.startGesture(const Offset(220, 500), pointer: 2);
    await a.moveBy(const Offset(0, -120));
    await b.moveBy(const Offset(0, -120));
    await a.up();
    await b.up();
    expect(r.calls, isEmpty);
  });
}
