/// Нормализация строки для поиска: регистр, «ё», лишние пробелы.
String normalizeForSearch(String value) =>
    value.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Сворачивает многострочный текст в одну строку для превью.
String singleLine(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Только цифры из строки (для поиска по номеру телефона).
String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

/// Ключ сортировки имён: «ё» стоит рядом с «е», регистр не важен.
String sortKey(String value) => normalizeForSearch(value);

/// Приведение для поиска совпадений без изменения длины строки
/// (регистр и «ё»), чтобы подсветить найденное место в исходном тексте.
String foldForMatch(String value) => value.toLowerCase().replaceAll('ё', 'е');

/// Первое вхождение [query] в [text] без учёта регистра и «ё».
({int start, int end})? findMatch(String text, String query) {
  final needle = foldForMatch(query.trim());
  if (needle.isEmpty) return null;
  final haystack = foldForMatch(text);
  if (haystack.length != text.length) return null;
  final start = haystack.indexOf(needle);
  if (start < 0) return null;
  return (start: start, end: start + needle.length);
}

/// Фрагмент длинного текста вокруг совпадения — для строки результата поиска.
String excerpt(String text, String query, {int before = 28}) {
  final flat = singleLine(text);
  final match = findMatch(flat, query);
  if (match == null || match.start <= before) return flat;
  var cut = match.start - before;
  final space = flat.indexOf(' ', cut);
  if (space >= 0 && space < match.start) cut = space + 1;
  return '…${flat.substring(cut)}';
}
