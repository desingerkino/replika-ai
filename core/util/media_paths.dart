import 'dart:io';

/// Пути к файлам медиатеки.
///
/// В базе лежат абсолютные пути. На Android папка приложения постоянна, а на
/// iOS путь к контейнеру приложения может измениться (переустановка,
/// восстановление из копии, обновление через Xcode), и сохранённые пути
/// перестанут открываться. Поэтому при чтении путь, которого нет на диске,
/// заново привязывается к текущей папке медиатеки по имени файла.
abstract final class MediaPaths {
  static String? _root;

  /// Текущая папка медиатеки; вызывается один раз при запуске.
  static void configure(String root) => _root = root;

  /// Не подменять пути (папка приложения неизвестна).
  static void reset() => _root = null;

  static String resolve(String stored) {
    final root = _root;
    if (root == null || stored.isEmpty || stored.startsWith(root)) return stored;
    if (File(stored).existsSync()) return stored;
    final sep = Platform.pathSeparator;
    final marker = '${sep}media$sep';
    final index = stored.lastIndexOf(marker);
    if (index < 0) return stored;
    final candidate = '$root$sep${stored.substring(index + marker.length)}';
    return File(candidate).existsSync() ? candidate : stored;
  }

  static String? resolveOrNull(String? stored) => stored == null ? null : resolve(stored);
}
