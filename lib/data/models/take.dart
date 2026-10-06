import '../../core/util/db_values.dart';

enum TakeStatus {
  running('Идёт'),
  finished('Завершён'),
  aborted('Прерван'),
  good('Хороший'),
  bad('Брак');

  const TakeStatus(this.label);
  final String label;
}

/// Дубль сцены.
class Take {
  const Take({
    required this.id,
    required this.sceneId,
    required this.number,
    required this.startedAt,
    this.finishedAt,
    this.status = TakeStatus.running,
    this.result = '',
    this.comment = '',
    this.logJson,
  });

  final String id;
  final String sceneId;
  final int number;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final TakeStatus status;
  final String result;
  final String comment;

  /// Журнал выполненных действий дубля (JSON), заполняется Scene Engine.
  final String? logJson;

  factory Take.fromRow(Map<String, Object?> row) => Take(
        id: row['id'] as String,
        sceneId: row['scene_id'] as String,
        number: readInt(row, 'number'),
        startedAt: intToDate(row['started_at']),
        finishedAt: intToDateOrNull(row['finished_at']),
        status: enumByName(TakeStatus.values, row['status'], TakeStatus.finished),
        result: readString(row, 'result'),
        comment: readString(row, 'comment'),
        logJson: readStringOrNull(row, 'log_json'),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'scene_id': sceneId,
        'number': number,
        'started_at': dateToInt(startedAt),
        'finished_at': finishedAt == null ? null : dateToInt(finishedAt!),
        'status': status.name,
        'result': result,
        'comment': comment,
        'log_json': logJson,
      };
}
