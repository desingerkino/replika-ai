import '../../core/util/db_values.dart';
import '../../core/util/json.dart';

enum SceneStatus {
  draft('Черновик'),
  ready('Готова'),
  running('Идёт'),
  paused('Пауза'),
  finished('Завершена');

  const SceneStatus(this.label);
  final String label;
}

/// Постановочная сцена. Действия хранятся отдельно (SceneAction),
/// дубли — отдельно (Take).
class Scene {
  const Scene({
    required this.id,
    this.number = '',
    required this.name,
    this.description = '',
    this.deviceId,
    this.chatId,
    this.status = SceneStatus.draft,
    this.durationMs = 0,
    this.currentPosition = 0,
    this.takeNumber = 0,
    this.initialState = const {},
    this.copiedFromId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Номер сцены по сценарию, строкой: «12», «12А».
  final String number;
  final String name;
  final String description;
  final String? deviceId;
  final String? chatId;
  final SceneStatus status;
  final int durationMs;

  /// Индекс текущего действия таймлайна.
  final int currentPosition;
  final int takeNumber;

  /// Снимок исходного состояния для «СБРОС СЦЕНЫ» (формируется на Этапе 4).
  final Map<String, Object?> initialState;
  final String? copiedFromId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Scene.fromRow(Map<String, Object?> row) => Scene(
        id: row['id'] as String,
        number: readString(row, 'number'),
        name: readString(row, 'name'),
        description: readString(row, 'description'),
        deviceId: readStringOrNull(row, 'device_id'),
        chatId: readStringOrNull(row, 'chat_id'),
        status: enumByName(SceneStatus.values, row['status'], SceneStatus.draft),
        durationMs: readInt(row, 'duration_ms'),
        currentPosition: readInt(row, 'current_position'),
        takeNumber: readInt(row, 'take_number'),
        initialState: decodeJsonMap(readStringOrNull(row, 'initial_state_json')),
        copiedFromId: readStringOrNull(row, 'copied_from_id'),
        createdAt: intToDate(row['created_at']),
        updatedAt: intToDate(row['updated_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'number': number,
        'name': name,
        'description': description,
        'device_id': deviceId,
        'chat_id': chatId,
        'status': status.name,
        'duration_ms': durationMs,
        'current_position': currentPosition,
        'take_number': takeNumber,
        'initial_state_json': encodeJsonMap(initialState),
        'copied_from_id': copiedFromId,
        'created_at': dateToInt(createdAt),
        'updated_at': dateToInt(updatedAt),
      };
}
