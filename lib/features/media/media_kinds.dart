import 'dart:typed_data';
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
/// Громкость (дБ полной шкалы) → высота столбика 0..1. Диапазон −60…0 дБ
/// и плавная кривая: тихая речь тоже даёт различимую «волну».
double levelFromDb(double db) {
  if (db.isNaN || db.isInfinite) return 0.04;
  final linear = ((db + 60) / 60).clamp(0.0, 1.0);
  return (linear * linear).clamp(0.04, 1.0);
}

/// Нормирует столбики по самому громкому месту записи: форма волны та же,
/// но заполняет всю высоту (как у мессенджеров). Тишина остаётся низкой.
List<double> normalizeWaveform(List<double> values) {
  if (values.isEmpty) return values;
  final peak = values.reduce((a, b) => a > b ? a : b);
  if (peak < 0.02) return [for (final v in values) double.parse(v.clamp(0.05, 1.0).toStringAsFixed(2))];
  return [for (final v in values) double.parse((v / peak).clamp(0.05, 1.0).toStringAsFixed(2))];
}

/// Сжимает замеры громкости до [bars] столбиков (среднее по отрезкам).
List<double> downsampleWaveform(List<double> samples, {int bars = 40}) {
  if (samples.isEmpty) return List<double>.filled(bars, 0.05);
  final result = <double>[];
  for (var i = 0; i < bars; i++) {
    final start = (i * samples.length / bars).floor();
    final end = ((i + 1) * samples.length / bars).ceil().clamp(start + 1, samples.length);
    final slice = samples.sublist(start.clamp(0, samples.length - 1), end);
    final avg = slice.reduce((a, b) => a + b) / slice.length;
    // Пик отрезка весомее среднего: слоги не «размазываются».
    final peak = slice.reduce((a, b) => a > b ? a : b);
    result.add((avg * 0.4 + peak * 0.6).clamp(0.0, 1.0));
  }
  return normalizeWaveform(result);
}

/// Волна WAV-файла по отсчётам PCM (8/16/24/32 бит): громкость (RMS) по
/// [bars] отрезкам → те же 0..1, что у записи с микрофона. Пустой список —
/// формат не распознан.
List<double> wavWaveform(Uint8List bytes, {int bars = 40}) {
  if (bytes.length < 44) return const [];
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return const [];
  var offset = 12;
  int? channels;
  int? bits;
  int? format;
  int? dataStart;
  int? dataLength;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataStart = body;
      dataLength = size.clamp(0, bytes.length - body);
      break;
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  if (dataStart == null || dataLength == null || channels == null || bits == null || channels <= 0) {
    return const [];
  }
  // 1 — целые PCM, 3 — float, 0xFFFE — расширенный формат (обычно PCM).
  if (format != 1 && format != 3 && format != 0xFFFE) return const [];
  final bytesPerSample = bits ~/ 8;
  if (bytesPerSample <= 0) return const [];
  final frameSize = bytesPerSample * channels;
  final frames = dataLength ~/ frameSize;
  if (frames <= 0) return const [];

  double sampleAt(int at) {
    if (format == 3 && bytesPerSample == 4) return data.getFloat32(at, Endian.little);
    return switch (bytesPerSample) {
      1 => (bytes[at] - 128) / 128,
      2 => data.getInt16(at, Endian.little) / 32768,
      3 => (((bytes[at + 2] << 24) | (bytes[at + 1] << 16) | (bytes[at] << 8)) >> 8) / 8388608,
      4 => data.getInt32(at, Endian.little) / 2147483648,
      _ => 0,
    };
  }

  final result = <double>[];
  // Не больше ~4000 отсчётов на столбик: длинные файлы считаются быстро.
  final perBar = (frames / bars).ceil();
  final stride = (perBar / 4000).ceil().clamp(1, 1 << 20);
  for (var b = 0; b < bars; b++) {
    final start = b * perBar;
    final end = ((b + 1) * perBar).clamp(0, frames);
    if (start >= end) {
      result.add(0.05);
      continue;
    }
    var sum = 0.0;
    var n = 0;
    for (var f = start; f < end; f += stride) {
      final v = sampleAt(dataStart + f * frameSize);
      sum += v * v;
      n++;
    }
    final rms = n == 0 ? 0.0 : sqrt(sum / n);
    final db = rms <= 0 ? -160.0 : 20 * log(rms) / ln10;
    result.add(levelFromDb(db));
  }
  return normalizeWaveform(result);
}
