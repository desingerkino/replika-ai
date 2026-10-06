import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../app/services.dart';
import '../../data/models/media_item.dart';
import '../protocol/protocol.dart';

/// Незавершённая передача файла.
class _Upload {
  _Upload({
    required this.kind,
    required this.name,
    required this.size,
    required this.sha256,
    required this.durationMs,
    required this.part,
  });

  final MediaKind kind;
  final String name;
  final int size;
  final String? sha256;
  final int? durationMs;
  final File part;
}

/// Приём файла с Prop Controller (Connect 1.3): BEGIN → CHUNK… → COMMIT.
///
/// * `mediaId` выбирает пульт (обычно по содержимому файла), поэтому один
///   и тот же файл на телефоне не дублируется: повторный BEGIN отвечает
///   `exists: true`.
/// * Куски пишутся во временный файл рядом с медиатекой. После обрыва
///   BEGIN сообщает, сколько байт уже получено, — передача продолжается
///   с этого места.
/// * В медиатеку файл попадает только на COMMIT, после проверки размера
///   и контрольной суммы. Сцену загрузка не трогает, RESET_SCENE файлы
///   не удаляет.
class MediaUploads {
  MediaUploads(this.services);

  final AppServices services;
  final Map<String, _Upload> _active = {};

  static final RegExp _key = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

  static const Set<MediaKind> _kinds = {
    MediaKind.photo,
    MediaKind.video,
    MediaKind.audio,
    MediaKind.voice,
    MediaKind.videoNote,
  };

  Future<Directory> _dir() async {
    final base = await services.media.mediaDirectory();
    final dir = Directory(p.join(base.path, '.connect_uploads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _mediaId(Map<String, Object?> payload) {
    final v = payload['mediaId'];
    if (v is! String || !_key.hasMatch(v)) {
      throw const ConnectException(
          ConnectError.invalidRequest, 'mediaId: латиница, цифры, «_» или «-», до 64 символов');
    }
    return v;
  }

  Future<Map<String, Object?>> begin(Map<String, Object?> payload) async {
    final id = _mediaId(payload);
    final kindName = payload['kind'];
    final kind = _kinds.where((k) => k.name == kindName).firstOrNull;
    if (kind == null) {
      throw const ConnectException(
          ConnectError.invalidRequest, 'kind: photo, video, audio, voice или videoNote');
    }
    final name = payload['name'];
    if (name is! String || name.trim().isEmpty || name.length > 200) {
      throw const ConnectException(ConnectError.invalidRequest, 'нужно имя файла (name) с расширением');
    }
    final size = payload['size'];
    if (size is! int || size <= 0 || size > ConnectLimits.uploadBytes) {
      throw const ConnectException(ConnectError.invalidRequest, 'size: от 1 байта до 64 МБ');
    }
    final sha = payload['sha256'];
    if (sha != null && (sha is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha))) {
      throw const ConnectException(ConnectError.invalidRequest, 'sha256: 64 шестнадцатеричных символа');
    }
    final duration = payload['durationMs'];

    final existing = await services.media.repository.byId(id);
    if (existing != null) {
      if (existing.kind == kind && existing.sizeBytes == size) {
        return {'mediaId': id, 'exists': true, 'received': size};
      }
      throw const ConnectException(ConnectError.invalidTarget,
          'Медиа с таким mediaId уже есть на телефоне и отличается — выберите другой mediaId');
    }

    final part = File(p.join((await _dir()).path, '$id.part'));
    var received = await part.exists() ? await part.length() : 0;
    if (received > size) {
      await part.delete();
      received = 0;
    }
    _active[id] = _Upload(
      kind: kind,
      name: name.trim(),
      size: size,
      sha256: (sha as String?)?.toLowerCase(),
      durationMs: duration is int && duration > 0 ? duration : null,
      part: part,
    );
    return {
      'mediaId': id,
      'exists': false,
      'received': received,
      'chunkBytes': ConnectLimits.uploadChunkBytes,
    };
  }

  _Upload _upload(String id) {
    final upload = _active[id];
    if (upload == null) {
      throw const ConnectException(ConnectError.invalidRequest, 'Сначала MEDIA_UPLOAD_BEGIN для этого mediaId');
    }
    return upload;
  }

  Future<Map<String, Object?>> chunk(Map<String, Object?> payload) async {
    final id = _mediaId(payload);
    final upload = _upload(id);
    final offset = payload['offset'];
    if (offset is! int || offset < 0) {
      throw const ConnectException(ConnectError.invalidRequest, 'offset: число байт от начала файла');
    }
    final data = payload['data'];
    if (data is! String) throw const ConnectException(ConnectError.invalidRequest, 'data: кусок файла в base64');
    final List<int> bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      throw const ConnectException(ConnectError.invalidRequest, 'data: неверный base64');
    }
    if (bytes.isEmpty || bytes.length > ConnectLimits.uploadChunkBytes) {
      throw const ConnectException(ConnectError.invalidRequest, 'кусок: от 1 байта до 96 КБ');
    }
    final current = await upload.part.exists() ? await upload.part.length() : 0;
    if (offset != current) {
      // Этот кусок уже записан (повтор после обрыва с новым commandId).
      if (offset + bytes.length <= current) return {'mediaId': id, 'received': current};
      throw ConnectException(ConnectError.invalidRequest, 'offset: ожидалось $current');
    }
    if (current + bytes.length > upload.size) {
      throw const ConnectException(ConnectError.invalidRequest, 'данных больше, чем объявлено в size');
    }
    await upload.part.writeAsBytes(bytes, mode: FileMode.append, flush: true);
    return {'mediaId': id, 'received': current + bytes.length};
  }

  Future<Map<String, Object?>> commit(Map<String, Object?> payload) async {
    final id = _mediaId(payload);
    final existing = await services.media.repository.byId(id);
    if (existing != null && !_active.containsKey(id)) {
      return {'mediaId': id, 'kind': existing.kind.name, 'sizeBytes': existing.sizeBytes, 'exists': true};
    }
    final upload = _upload(id);
    final length = await upload.part.exists() ? await upload.part.length() : 0;
    if (length != upload.size) {
      throw ConnectException(ConnectError.invalidRequest, 'получено $length из ${upload.size} байт');
    }
    final expected = upload.sha256;
    if (expected != null) {
      final hash = await Sha256().hash(await upload.part.readAsBytes());
      final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (hex != expected) {
        _active.remove(id);
        await upload.part.delete();
        throw const ConnectException(
            ConnectError.actionFailed, 'Контрольная сумма не совпала — файл нужно передать заново');
      }
    }
    final item = await services.media.registerUploaded(
      upload.part,
      id: id,
      kind: upload.kind,
      name: upload.name,
      durationMs: upload.durationMs,
    );
    _active.remove(id);
    return {'mediaId': item.id, 'kind': item.kind.name, 'sizeBytes': item.sizeBytes, 'exists': false};
  }
}
