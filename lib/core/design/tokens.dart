import 'package:flutter/widgets.dart';

/// Базовая палитра бренда «Реплика».
/// Петроль — основной цвет, вольфрам (тёплый свет ламп на площадке) —
/// редкий акцент. Никаких неоновых и «стеклянных» эффектов.
abstract final class Palette {
  static const Color petrol = Color(0xFF155E75);
  static const Color petrolDeep = Color(0xFF0E4658);
  static const Color petrolBright = Color(0xFF3E9BB5);

  /// Основной синий интерфейса («Чистый воздух»). Петроль остаётся цветом
  /// логотипа (core/brand/logo.dart).
  static const Color blue = Color(0xFF1F6FA8);
  static const Color blueBright = Color(0xFF5AA9DE);
  static const Color tungsten = Color(0xFFE3A13B);
  static const Color ink = Color(0xFF15202B);
  static const Color white = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF2F9E6E);
  static const Color warning = Color(0xFFD08A1E);
  static const Color danger = Color(0xFFC8372D);
}

/// Палитра операторской панели. Панель всегда тёмная: на площадке
/// светлый экран даёт блики и отвлекает.
abstract final class OperatorPalette {
  static const Color background = Color(0xFF14191E);
  static const Color surface = Color(0xFF1C2329);
  static const Color line = Color(0xFF2B343C);
  static const Color text = Color(0xFFE7ECEF);
  static const Color textDim = Color(0xFF8C98A2);

  /// «В эфире» — как лампа tally на камере.
  static const Color live = Color(0xFFE5382E);
  static const Color standby = Color(0xFFF0A43A);
  static const Color ready = Color(0xFF3FB27F);
}

/// Шкала отступов.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Радиусы скругления.
abstract final class Radii {
  static const double bubble = 18;
  static const double joined = 6;
  static const double tail = 4;
  static const double card = 14;
  static const double control = 12;
  static const double sheet = 22;
  static const double pill = 999;
}

/// Размеры элементов.
abstract final class Sizes {
  static const double topBar = 56;
  static const double chatRowMinHeight = 72;
  static const double avatarList = 52;
  static const double avatarHeader = 38;
  static const double avatarContact = 44;
  static const double bubbleMaxWidthFactor = 0.78;

  /// Предел ширины пузыря на широких экранах (iPad).
  static const double bubbleMaxWidthCap = 520;
  static const double sendButton = 44;
  static const double minTouch = 48;

  /// Линии интерфейса (разделители, рамки): не тоньше 1 px, иначе в крупном
  /// плане они пропадают или дают муар.
  static const double line = 1;

  /// Рамка удалённого сообщения.
  static const double lineStrong = 1.5;
}

/// Длительности и кривые анимаций.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  /// Нажатие кнопки (отправить, микрофон): быстро, без отскока.
  static const Duration press = Duration(milliseconds: 100);

  /// Смена микрофона и «отправить».
  static const Duration swap = Duration(milliseconds: 160);
  static const Curve curve = Curves.easeOutCubic;
}

/// Приглушённые тона аватаров-инициалов.
abstract final class AvatarTones {
  static const List<Color> all = [
    Color(0xFF5F87A0),
    Color(0xFF9A7454),
    Color(0xFF7A6798),
    Color(0xFF5B8A68),
    Color(0xFFA35A68),
    Color(0xFF848A4A),
    Color(0xFF4C7A8A),
    Color(0xFFAE7842),
  ];

  static Color at(int index) => all[index.abs() % all.length];

  /// Стабильный тон по строке (не зависит от запуска приложения).
  static int indexForKey(String key) {
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % all.length;
  }

  static Color forKey(String key) => all[indexForKey(key)];
}
