import 'package:flutter_test/flutter_test.dart';
import 'package:replika/features/media/media_kinds.dart';

void main() {
  test('громкость записи в высоту столбика', () {
    expect(levelFromDb(0), 1.0);
    expect(levelFromDb(-30), closeTo(0.25, 0.001));
    expect(levelFromDb(-160), 0.04, reason: 'тишина — минимальный столбик, а не пустота');
    expect(levelFromDb(double.negativeInfinity), 0.04);
  });

  test('сжатие замеров до 40 столбиков', () {
    final samples = [for (var i = 0; i < 400; i++) (i % 10) / 10];
    final bars = downsampleWaveform(samples);
    expect(bars.length, 40);
    expect(bars.every((v) => v >= 0.05 && v <= 1.0), isTrue);
  });

  test('тихая речь даёт настоящую волну, а не ровные полоски', () {
    // Тихо: −45…−30 дБ, с паузами.
    final samples = [
      for (var i = 0; i < 200; i++) levelFromDb(i % 25 < 5 ? -58 : -45 + (i % 7) * 2.0),
    ];
    final bars = downsampleWaveform(samples);
    expect(bars.reduce((a, b) => a > b ? a : b), 1.0, reason: 'волна нормирована по пику записи');
    expect(bars.toSet().length, greaterThan(5), reason: 'столбики разной высоты');
  });

  test('короткая запись и пустая запись', () {
    expect(downsampleWaveform([0.8, 0.2], bars: 40).length, 40);
    expect(downsampleWaveform(const []).every((v) => v == 0.05), isTrue);
  });
}
