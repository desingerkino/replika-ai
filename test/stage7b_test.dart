import 'package:flutter_test/flutter_test.dart';
import 'package:replika/features/media/media_kinds.dart';

void main() {
  test('громкость записи в высоту столбика', () {
    expect(levelFromDb(0), 1.0);
    expect(levelFromDb(-25), closeTo(0.5, 0.001));
    expect(levelFromDb(-160), 0.05, reason: 'тишина — минимальный столбик, а не пустота');
  });

  test('сжатие замеров до 40 столбиков', () {
    final samples = [for (var i = 0; i < 400; i++) (i % 10) / 10];
    final bars = downsampleWaveform(samples);
    expect(bars.length, 40);
    expect(bars.every((v) => v >= 0.05 && v <= 1.0), isTrue);
  });

  test('короткая запись и пустая запись', () {
    expect(downsampleWaveform([0.8, 0.2], bars: 40).length, 40);
    expect(downsampleWaveform(const []).every((v) => v == 0.1), isTrue);
  });
}
