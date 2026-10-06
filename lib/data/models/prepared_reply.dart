import '../../core/util/db_values.dart';

/// Категории подготовленных ответов для импровизации (ТЗ, п. 35).
enum ReplyCategory {
  short('Короткие'),
  neutral('Нейтральные'),
  emotional('Эмоциональные'),
  question('Вопросы'),
  agree('Согласие'),
  refuse('Отказ'),
  explain('Объяснение'),
  action('Действие');

  const ReplyCategory(this.label);
  final String label;
}

class PreparedReply {
  const PreparedReply({
    required this.id,
    required this.category,
    required this.text,
    this.sortOrder = 0,
    required this.createdAt,
  });

  final String id;
  final ReplyCategory category;
  final String text;
  final int sortOrder;
  final DateTime createdAt;

  factory PreparedReply.fromRow(Map<String, Object?> row) => PreparedReply(
        id: row['id'] as String,
        category: enumByName(ReplyCategory.values, row['category'], ReplyCategory.neutral),
        text: readString(row, 'text'),
        sortOrder: readInt(row, 'sort_order'),
        createdAt: intToDate(row['created_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'category': category.name,
        'text': text,
        'sort_order': sortOrder,
        'created_at': dateToInt(createdAt),
      };
}
