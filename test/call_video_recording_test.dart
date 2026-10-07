import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/call_video_recording.dart';
import 'package:replika_recorder/replika_recorder.dart';

class _FakeBackend implements ScreenRecorderBackend {
  _FakeBackend({this.supported = true, this.startError, this.galleryOk = true, this.stopPath});

  final bool supported;
  final RecorderException? startError;
  final bool galleryOk;
  String? stopPath;

  int starts = 0;
  int stops = 0;
  bool? micRequested;
  String? savedName;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> requestGalleryAccess() async => true;

  @override
  Future<void> start({required bool microphone}) async {
    starts++;
    micRequested = microphone;
    if (startError != null) throw startError!;
  }

  @override
  Future<String?> stop() async {
    stops++;
    return stopPath;
  }

  @override
  Future<bool> saveToGallery(String path, String name) async {
    savedName = name;
    return galleryOk;
  }
}

void main() {
  late Directory temp;
  late File video;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('rec_test');
    video = File('${temp.path}/raw.mp4')..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  CallVideoRecording make(_FakeBackend backend) => CallVideoRecording(
        backend: backend,
        askMicrophone: () async => true,
        localFolder: () async => temp,
        now: () => DateTime(2026, 10, 7, 3, 45, 12),
      );

  test('имя файла читаемое', () {
    expect(callRecordingFileName(DateTime(2026, 10, 7, 3, 45, 12)), 'Replika_2026-10-07_03-45-12.mp4');
  });

  test('обычный звонок: один файл уходит в галерею, временный удаляется', () async {
    final backend = _FakeBackend(stopPath: video.path);
    final rec = make(backend);
    await rec.start();
    expect(rec.active, isTrue);
    final result = await rec.stopAndSave();
    expect(result.outcome, CallRecordingOutcome.savedToGallery);
    expect(backend.savedName, 'Replika_2026-10-07_03-45-12.mp4');
    expect(backend.micRequested, isTrue);
    expect(video.existsSync(), isFalse);
  });

  test('повторная остановка закрывает рекордер ровно один раз', () async {
    final backend = _FakeBackend(stopPath: video.path);
    final rec = make(backend);
    await rec.start();
    await Future.wait([rec.stopAndSave(), rec.stopAndSave()]);
    await rec.stopAndSave();
    expect(backend.stops, 1);
    expect(backend.starts, 1);
  });

  test('остановка во время запуска не оставляет открытой запись', () async {
    final backend = _FakeBackend(stopPath: video.path);
    final rec = make(backend);
    final starting = rec.start();
    final result = await rec.stopAndSave();
    await starting;
    expect(backend.stops, backend.starts); // сколько открыли, столько и закрыли
    expect(result.outcome, anyOf(CallRecordingOutcome.nothing, CallRecordingOutcome.savedToGallery));
  });

  test('не удалось в галерею — видео остаётся в папке приложения', () async {
    final backend = _FakeBackend(stopPath: video.path, galleryOk: false);
    final result = await make(backend).let((r) async {
      await r.start();
      return r.stopAndSave();
    });
    expect(result.outcome, CallRecordingOutcome.savedLocally);
    expect(File(result.path!).existsSync(), isTrue);
  });

  test('пользователь отказал в записи: звонок не страдает, ошибка не вылетает', () async {
    final backend = _FakeBackend(startError: const RecorderException('denied', 'нет'));
    final rec = make(backend);
    await rec.start();
    expect(rec.active, isFalse);
    final result = await rec.stopAndSave();
    expect(result.outcome, CallRecordingOutcome.failed);
    expect(backend.stops, 0);
  });

  test('запись не поддерживается: тихо ничего не делаем', () async {
    final backend = _FakeBackend(supported: false);
    final rec = make(backend);
    await rec.start();
    expect(backend.starts, 0);
  });
}

extension _Let<T> on T {
  Future<R> let<R>(Future<R> Function(T) f) => f(this);
}
