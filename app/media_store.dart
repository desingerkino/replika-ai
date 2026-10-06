import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/util/ids.dart';
import '../data/models/media_item.dart';
import '../data/repositories/media_repository.dart';
import '../features/media/media_kinds.dart';

/// Что выбирать в системном окне выбора файлов.
enum PickSource { image, video, media, audio, any }

/// Файлы медиатеки: выбор на телефоне, копирование во внутреннюю папку
/// приложения, чтение размеров и длительности, удаление.
///
/// Файл копируется, а не используется по ссылке: если на телефоне удалят
/// оригинал из галереи, сцена всё равно не сломается.
class MediaStore {
  MediaStore(this.repository);

  final MediaRepository repository;

  Directory? _dir;

  /// Папка медиатеки для автотестов (на компьютере нет path_provider).
  static Directory? testDirectory;

  /// Папка медиатеки (для импорта профиля).
  Future<Directory> mediaDirectory() => _mediaDir();

  Future<Directory> _mediaDir() async {
    final test = testDirectory;
    if (test != null) {
      if (!await test.exists()) await test.create(recursive: true);
      return test;
    }
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'media'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  static FileType _fileType(PickSource source) => switch (source) {
        PickSource.image => FileType.image,
        PickSource.video => FileType.video,
        PickSource.media => FileType.media,
        PickSource.audio => FileType.audio,
        PickSource.any => FileType.any,
      };

  /// Открывает системный выбор файлов и добавляет выбранное в медиатеку.
  /// Пустой список — пользователь ничего не выбрал.
  /// [preferred] — назначение: голосовое вместо аудио, видеосообщение вместо видео.
  Future<List<MediaItem>> pickAndImport(PickSource source, {MediaKind? preferred}) async {
    final files = await FilePicker.pickFiles(type: _fileType(source));
    final imported = <MediaItem>[];
    for (final file in files) {
      imported.add(await _import(file, preferred: preferred));
    }
    return imported;
  }

  Future<MediaItem> _import(PlatformFile file, {MediaKind? preferred}) async {
    final dir = await _mediaDir();
    final id = newId();
    final name = file.name;
    final ext = fileExtension(name);
    final target = File(p.join(dir.path, '$id$ext'));

    final sink = target.openWrite();
    try {
      await sink.addStream(file.readAsByteStream());
    } finally {
      await sink.close();
    }

    final kind = kindForFile(name, preferred: preferred);
    final info = await _probe(kind, target.path);
    final item = MediaItem(
      id: id,
      kind: kind,
      path: target.path,
      originalName: name,
      mime: mimeForFile(name),
      sizeBytes: await target.length(),
      durationMs: info.duration?.inMilliseconds,
      width: info.width,
      height: info.height,
      waveform: kind == MediaKind.voice ? decorativeWaveform(id) : const [],
      createdAt: DateTime.now(),
    );
    await repository.insert(item);
    return item;
  }

  /// Размеры и длительность. Ошибка чтения не мешает добавить файл:
  /// тогда превью просто будет без этих сведений.
  Future<({int? width, int? height, Duration? duration})> _probe(
    MediaKind kind,
    String path,
  ) async {
    try {
      switch (kind) {
        case MediaKind.photo:
          final buffer = await ui.ImmutableBuffer.fromFilePath(path);
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          final result = (width: descriptor.width, height: descriptor.height, duration: null);
          descriptor.dispose();
          buffer.dispose();
          return result;
        case MediaKind.video:
        case MediaKind.videoNote:
          final controller = VideoPlayerController.file(File(path));
          try {
            await controller.initialize().timeout(const Duration(seconds: 15));
            final size = controller.value.size;
            return (
              width: size.width.round(),
              height: size.height.round(),
              duration: controller.value.duration,
            );
          } finally {
            await controller.dispose();
          }
        case MediaKind.audio:
        case MediaKind.voice:
          final player = AudioPlayer();
          try {
            final duration =
                await player.setFilePath(path).timeout(const Duration(seconds: 15));
            return (width: null, height: null, duration: duration);
          } finally {
            await player.dispose();
          }
        case MediaKind.file:
          return (width: null, height: null, duration: null);
      }
    } catch (error) {
      debugPrint('Не удалось прочитать сведения о файле: $error');
      return (width: null, height: null, duration: null);
    }
  }

  /// Файл, переданный с Prop Controller (Connect 1.3): переносится
  /// в медиатеку под ключом пульта [id]. Размеры и длительность читаются
  /// из файла; если не получилось — берётся [durationMs] от пульта.
  Future<MediaItem> registerUploaded(
    File part, {
    required String id,
    required MediaKind kind,
    required String name,
    int? durationMs,
  }) async {
    final dir = await _mediaDir();
    final target = File(p.join(dir.path, '$id${fileExtension(name)}'));
    if (await target.exists()) await target.delete();
    final moved = await part.rename(target.path);
    final info = await _probe(kind, moved.path);
    final item = MediaItem(
      id: id,
      kind: kind,
      path: moved.path,
      originalName: name,
      mime: mimeForFile(name),
      sizeBytes: await moved.length(),
      durationMs: info.duration?.inMilliseconds ?? durationMs,
      width: info.width,
      height: info.height,
      waveform: kind == MediaKind.voice ? decorativeWaveform(id) : const [],
      createdAt: DateTime.now(),
    );
    await repository.insert(item);
    return item;
  }

  /// Путь для новой записи внутри папки медиатеки (голосовое с микрофона).
  Future<String> newRecordingPath(String extension) async {
    final dir = await _mediaDir();
    return p.join(dir.path, '${newId()}$extension');
  }

  /// Записанное в приложении голосовое: файл уже в папке медиатеки,
  /// «волна» — настоящая, по громкости записи.
  Future<MediaItem> registerVoice(String path, {required Duration duration, required List<double> waveform}) async {
    final file = File(path);
    final name = 'Голосовое ${_stamp()}.m4a';
    final item = MediaItem(
      id: p.basenameWithoutExtension(path),
      kind: MediaKind.voice,
      path: path,
      originalName: name,
      mime: 'audio/mp4',
      sizeBytes: await file.length(),
      durationMs: duration.inMilliseconds,
      waveform: waveform,
      createdAt: DateTime.now(),
    );
    await repository.insert(item);
    return item;
  }

  /// Записанное камерой видеосообщение: копируется из временной папки
  /// камеры в медиатеку, размеры и длительность читаются из файла.
  Future<MediaItem> registerVideoNote(String tempPath) async {
    final dir = await _mediaDir();
    final id = newId();
    final ext = fileExtension(tempPath).isEmpty ? '.mp4' : fileExtension(tempPath);
    final target = await File(tempPath).copy(p.join(dir.path, '$id$ext'));
    try {
      await File(tempPath).delete();
    } catch (_) {
      // Временный файл камеры система удалит сама.
    }
    final info = await _probe(MediaKind.videoNote, target.path);
    final item = MediaItem(
      id: id,
      kind: MediaKind.videoNote,
      path: target.path,
      originalName: 'Видеосообщение ${_stamp()}$ext',
      mime: mimeForFile(target.path),
      sizeBytes: await target.length(),
      durationMs: info.duration?.inMilliseconds,
      width: info.width,
      height: info.height,
      createdAt: DateTime.now(),
    );
    await repository.insert(item);
    return item;
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.day)}.${two(now.month)} ${two(now.hour)}:${two(now.minute)}';
  }

  /// Удаляет файл из медиатеки вместе с копией на телефоне.
  Future<void> delete(MediaItem item) async {
    await repository.delete(item.id);
    try {
      final file = File(item.path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Файл не удалён с диска: $error');
    }
  }
}
