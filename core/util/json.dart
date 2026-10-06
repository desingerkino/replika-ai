import 'dart:convert';

/// Безопасно разбирает JSON-объект из базы. Повреждённое значение
/// не роняет приложение, а превращается в пустую карту.
Map<String, Object?> decodeJsonMap(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
  try {
    final value = jsonDecode(raw);
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
  } on FormatException {
    // Повреждённая строка: возвращаем пустую карту ниже.
  }
  return <String, Object?>{};
}

/// Кодирует карту в JSON; пустая карта хранится как NULL.
String? encodeJsonMap(Map<String, Object?> map) =>
    map.isEmpty ? null : jsonEncode(map);

/// Разбирает JSON-массив чисел (например, волновую форму голосового).
List<double> decodeDoubleList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <double>[];
  try {
    final value = jsonDecode(raw);
    if (value is List) {
      return [for (final v in value) if (v is num) v.toDouble()];
    }
  } on FormatException {
    // Повреждённая строка: возвращаем пустой список ниже.
  }
  return const <double>[];
}

String? encodeDoubleList(List<double> values) =>
    values.isEmpty ? null : jsonEncode(values);
