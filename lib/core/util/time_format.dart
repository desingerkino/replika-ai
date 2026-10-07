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

const List<String> _weekdaysFull = [
  'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье',
];

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

/// Время на карточке чата (главный экран): сегодня — «14:05», вчера —
/// «Вчера», на этой неделе — «Понедельник», в этом году — «10 сент.»,
/// раньше — «31.12.25».
String formatChatCardTime(DateTime time, DateTime now) {
  final days = daysBetween(time, now);
  if (days <= 0) return formatClock(time);
  if (days == 1) return 'Вчера';
  if (days < 7) return _weekdaysFull[time.weekday - 1];
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
