import 'package:flutter/widgets.dart';

/// Базовая палитра бренда «Реплика».
/// Синий — основной цвет, вольфрам (тёплый свет ламп на площадке) —
/// редкий акцент. Никаких неоновых и «стеклянных» эффектов.
abstract final class Palette {
  static const Color brand = Color(0xFF3D5CFF);
  static const Color brandDeep = Color(0xFF2B44D1);
  static const Color brandBright = Color(0xFF7C93FF);
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
  static const double chatRowMinHeight = 76;
  static const double avatarList = 56;
  static const double avatarHeader = 38;
  static const double avatarContact = 44;
  static const double bubbleMaxWidthFactor = 0.78;

  /// Предел ширины пузыря на широких экранах (iPad).
  static const double bubbleMaxWidthCap = 520;
  static const double sendButton = 44;
  static const double minTouch = 48;

  /// Плавающая нижняя панель вкладок (узкий экран).
  static const double tabBar = 64;
  static const double tabBarSideMargin = 16;
  static const double tabBarMinBottomMargin = 12;

  /// Сколько места под панелью вкладок должен оставлять прокручиваемый
  /// контент, чтобы последняя строка не пряталась за ней.
  static const double tabBarContentInset = tabBar + 24;

  /// Прикреплённая нижняя панель (тема Telegram).
  static const double dockedTabBar = 64;
}

/// Длительности и кривые анимаций.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
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

/// Спокойные тона аватаров-инициалов (светлая подложка, тёмные буквы).
/// Индексы совпадают с [AvatarTones], чтобы выбранный контакту тон
/// сохранял свой оттенок.
abstract final class AvatarTints {
  static const List<(Color, Color)> light = [
    (Color(0xFFDFE5FF), Color(0xFF2F49CC)),
    (Color(0xFFFFE5D4), Color(0xFFB8501A)),
    (Color(0xFFEADFFF), Color(0xFF6035C5)),
    (Color(0xFFD8F1E2), Color(0xFF1B7F4B)),
    (Color(0xFFFFDCE8), Color(0xFFB81D56)),
    (Color(0xFFEEF0D0), Color(0xFF5F6318)),
    (Color(0xFFD3EFEF), Color(0xFF0F7377)),
    (Color(0xFFFFEFC9), Color(0xFF8A5A00)),
  ];

  static const List<(Color, Color)> dark = [
    (Color(0xFF232C5C), Color(0xFFB4C1FF)),
    (Color(0xFF4A2A17), Color(0xFFFFB48A)),
    (Color(0xFF32245C), Color(0xFFCDB8FF)),
    (Color(0xFF173A28), Color(0xFF7FD8A6)),
    (Color(0xFF4B1C2E), Color(0xFFFF9DBB)),
    (Color(0xFF3A3B17), Color(0xFFD6D98A)),
    (Color(0xFF143B3D), Color(0xFF7FD3D6)),
    (Color(0xFF4A3610), Color(0xFFFFD27F)),
  ];

  /// (подложка, буквы) для индекса тона.
  static (Color, Color) at(int index, Brightness brightness) {
    final list = brightness == Brightness.dark ? dark : light;
    return list[index.abs() % list.length];
  }
}
