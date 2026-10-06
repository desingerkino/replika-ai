/// Преобразования значений между Dart и SQLite.
library;

int boolToInt(bool value) => value ? 1 : 0;

bool intToBool(Object? value) => value == 1 || value == true;

int dateToInt(DateTime value) => value.millisecondsSinceEpoch;

DateTime intToDate(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch((value as num? ?? 0).toInt());

DateTime? intToDateOrNull(Object? value) =>
    value == null ? null : intToDate(value);

String readString(Map<String, Object?> row, String key,
        [String fallback = '']) =>
    (row[key] as String?) ?? fallback;

String? readStringOrNull(Map<String, Object?> row, String key) =>
    row[key] as String?;

int readInt(Map<String, Object?> row, String key, [int fallback = 0]) =>
    (row[key] as num?)?.toInt() ?? fallback;

int? readIntOrNull(Map<String, Object?> row, String key) =>
    (row[key] as num?)?.toInt();

/// Находит значение перечисления по имени; неизвестное имя даёт [fallback].
T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
