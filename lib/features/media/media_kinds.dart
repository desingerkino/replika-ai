import 'dart:math';

import '../../data/models/media_item.dart';
import '../../data/models/message.dart';

const Set<String> _imageExt = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.heif', '.bmp'};
const Set<String> _videoExt = {'.mp4', '.mov', '.m4v', '.3gp', '.webm', '.mkv'};
const Set<String> _audioExt = {'.mp3', '.m4a', '.aac', '.ogg', '.oga', '.opus', '.wav', '.flac', '.amr'};

String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot).toLowerCase();
}

/// Вид медиа по имени файла. [preferred] уточняет назначение:
/// видео можно добавить как видеосообщение, аудио — как голосовое.
MediaKind kindForFile(String name, {MediaKind? preferred}) {
  final ext = fileExtension(name);
  if (_imageExt.contains(ext)) return MediaKind.photo;
  if (_videoExt.contains(ext)) {
    return preferred == MediaKind.videoNote ? MediaKind.videoNote : MediaKind.video;
  }
  if (_audioExt.contains(ext)) {
    return preferred == MediaKind.voice ? MediaKind.voice : MediaKind.audio;
  }
  return MediaKind.file;
}

String mimeForFile(String name) => switch (fileExtension(name)) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.heic' || '.heif' => 'image/heic',
      '.mp4' || '.m4v' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      '.3gp' => 'video/3gpp',
      '.mp3' => 'audio/mpeg',
      '.m4a' || '.aac' => 'audio/mp4',
      '.ogg' || '.oga' || '.opus' => 'audio/ogg',
      '.wav' => 'audio/wav',
      _ => 'application/octet-stream',
    };

MessageType messageTypeFor(MediaKind kind) => switch (kind) {
      MediaKind.photo => MessageType.photo,
      MediaKind.video => MessageType.video,
      MediaKind.audio => MessageType.audio,
      MediaKind.voice => MessageType.voice,
      MediaKind.videoNote => MessageType.videoNote,
      MediaKind.file => MessageType.file,
    };

/// «0:07», «12:40», «1:02:03».
String formatDuration(Duration duration) {
  final total = duration.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
  return '$m:$s';
}

/// «820 КБ», «12,4 МБ».
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0).replaceAll('.', ',')} МБ';
}

/// Декоративная «волна» голосового сообщения для загруженного файла.
/// Это не анализ громкости: форма стабильна для файла и похожа на речь
/// (всплески, паузы). Настоящая волна появится у записанных в приложении
/// голосовых.
List<double> decorativeWaveform(String seed, {int bars = 40}) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final random = Random(hash);
  final values = <double>[];
  var level = 0.45;
  for (var i = 0; i < bars; i++) {
    level = (level + (random.nextDouble() - 0.5) * 0.5).clamp(0.15, 1.0);
    final pause = random.nextDouble() < 0.08;
    final value = pause ? 0.1 : level * (0.7 + 0.3 * random.nextDouble());
    values.add(double.parse(value.clamp(0.1, 1.0).toStringAsFixed(2)));
  }
  return values;
}

/// Громкость записи в dBFS (от −160 до 0) → высота столбика «волны» 0,05–1.
double levelFromDb(double db) => ((db + 50) / 50).clamp(0.05, 1.0);

/// Сжимает замеры громкости до [bars] столбиков (среднее по отрезкам).
List<double> downsampleWaveform(List<double> samples, {int bars = 40}) {
  if (samples.isEmpty) return List<double>.filled(bars, 0.1);
  final result = <double>[];
  for (var i = 0; i < bars; i++) {
    final start = (i * samples.length / bars).floor();
    final end = ((i + 1) * samples.length / bars).ceil().clamp(start + 1, samples.length);
    final slice = samples.sublist(start.clamp(0, samples.length - 1), end);
    final avg = slice.reduce((a, b) => a + b) / slice.length;
    result.add(double.parse(avg.clamp(0.05, 1.0).toStringAsFixed(2)));
  }
  return result;
}
