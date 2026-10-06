import '../../core/util/text.dart';
import '../../data/models/contact.dart';

/// Поиск по имени в контактах, по настоящему имени персонажа и по номеру.
List<Contact> filterContacts(List<Contact> contacts, String query) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return contacts;
  final digits = digitsOnly(q);
  return contacts.where((contact) {
    if (normalizeForSearch(contact.displayName).contains(q)) return true;
    if (normalizeForSearch(contact.character.fullName).contains(q)) return true;
    return digits.length >= 2 && digitsOnly(contact.character.phone).contains(digits);
  }).toList();
}

/// Буква раздела алфавитного списка.
String sectionLetter(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '#';
  final letter = String.fromCharCodes(trimmed.runes.take(1)).toUpperCase();
  if (letter == 'Ё') return 'Е';
  return RegExp(r'[A-ZА-Я]').hasMatch(letter) ? letter : '#';
}
