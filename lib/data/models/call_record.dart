import '../../core/util/db_values.dart';
import 'origin.dart';

enum CallDirection {
  incoming('Входящий'),
  outgoing('Исходящий');

  const CallDirection(this.label);
  final String label;
}

enum CallKind {
  audio('Аудиозвонок'),
  video('Видеозвонок');

  const CallKind(this.label);
  final String label;
}

enum CallOutcome {
  answered('Состоялся'),
  missed('Пропущен'),
  declined('Отклонён'),
  cancelled('Отменён');

  const CallOutcome(this.label);
  final String label;
}

/// Запись истории постановочных звонков.
class CallRecord {
  const CallRecord({
    required this.id,
    required this.deviceId,
    this.characterId,
    required this.direction,
    required this.kind,
    required this.outcome,
    required this.startedAt,
    this.durationMs = 0,
    this.origin = DataOrigin.base,
    this.sceneId,
  });

  final String id;
  final String deviceId;
  final String? characterId;
  final CallDirection direction;
  final CallKind kind;
  final CallOutcome outcome;
  final DateTime startedAt;
  final int durationMs;
  final DataOrigin origin;
  final String? sceneId;

  factory CallRecord.fromRow(Map<String, Object?> row) => CallRecord(
        id: row['id'] as String,
        deviceId: row['device_id'] as String,
        characterId: readStringOrNull(row, 'character_id'),
        direction: enumByName(CallDirection.values, row['direction'], CallDirection.incoming),
        kind: enumByName(CallKind.values, row['kind'], CallKind.audio),
        outcome: enumByName(CallOutcome.values, row['outcome'], CallOutcome.answered),
        startedAt: intToDate(row['started_at']),
        durationMs: readInt(row, 'duration_ms'),
        origin: enumByName(DataOrigin.values, row['origin'], DataOrigin.base),
        sceneId: readStringOrNull(row, 'scene_id'),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'device_id': deviceId,
        'character_id': characterId,
        'direction': direction.name,
        'kind': kind.name,
        'outcome': outcome.name,
        'started_at': dateToInt(startedAt),
        'duration_ms': durationMs,
        'origin': origin.name,
        'scene_id': sceneId,
      };
}
