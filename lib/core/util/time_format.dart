/// Русские форматы дат и времени без внешних библиотек.
library;

const List<String> _monthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

const List<String> _monthsShort = [
  'янв.', 'февр.', 'мар.', 'апр.', 'мая', 'июн.',
  'июл.', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.',
];

const List<String> _weekdaysShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

String _two(int value) => value.toString().padLeft(2, '0');

/// «09:05»
String formatClock(DateTime time) => '${_two(time.hour)}:${_two(time.minute)}';

/// Разница в календарных днях (b − a) без влияния перехода на летнее время.
int daysBetween(DateTime a, DateTime b) {
  final dayA = DateTime.utc(a.year, a.month, a.day);
  final dayB = DateTime.utc(b.year, b.month, b.day);
  return dayB.difference(dayA).inDays;
}

/// Время в списке чатов: сегодня — «14:05», вчера — «вчера»,
/// на этой неделе — «пн», в этом году — «10 сент.», раньше — «31.12.25».
String formatChatListTime(DateTime time, DateTime now) {
  final days = daysBetween(time, now);
  if (days <= 0) return formatClock(time);
  if (days == 1) return 'вчера';
  if (days < 7) return _weekdaysShort[time.weekday - 1];
  if (time.year == now.year) return '${time.day} ${_monthsShort[time.month - 1]}';
  return '${_two(time.day)}.${_two(time.month)}.${_two(time.year % 100)}';
}

/// Разделитель дней в чате: «Сегодня», «Вчера», «10 сентября», «31 декабря 2025».
String formatDaySeparator(DateTime time, DateTime now) {
  final days = daysBetween(time, now);
  if (days == 0) return 'Сегодня';
  if (days == 1) return 'Вчера';
  final base = '${time.day} ${_monthsGenitive[time.month - 1]}';
  return time.year == now.year ? base : '$base ${time.year}';
}

/// Русское число с существительным: 1 минута, 2 минуты, 5 минут.
String pluralRu(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

/// «только что», «15 минут назад», «3 часа назад», «вчера в 18:21»,
/// «10 сент. в 09:05» — для историй и статуса «был(а)».
String formatAgo(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m ${pluralRu(m, 'минуту', 'минуты', 'минут')} назад';
  }
  final days = daysBetween(time, now);
  if (days == 0) {
    final h = diff.inHours;
    return '$h ${pluralRu(h, 'час', 'часа', 'часов')} назад';
  }
  if (days == 1) return 'вчера в ${formatClock(time)}';
  return '${time.day} ${_monthsShort[time.month - 1]} в ${formatClock(time)}';
}
