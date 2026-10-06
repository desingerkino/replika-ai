import 'package:flutter/material.dart';

/// Типографическая шкала. Шрифт — системный: в кадре приложение должно
/// выглядеть родным для конкретного телефона, и ничего не грузится из сети.
abstract final class AppType {
  static TextTheme textTheme({required Color primary, required Color secondary}) {
    return TextTheme(
      headlineSmall: TextStyle(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: primary),
      titleLarge: TextStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: primary),
      titleMedium: TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: primary),
      titleSmall: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600, letterSpacing: 0, color: primary),
      bodyLarge: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w400, letterSpacing: 0, color: primary),
      bodyMedium: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w400, letterSpacing: 0, color: primary),
      bodySmall: TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400, letterSpacing: 0, color: secondary),
      labelLarge: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600, letterSpacing: 0, color: primary),
      labelMedium: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: secondary),
      labelSmall: TextStyle(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: secondary),
    );
  }

  /// Текст сообщения.
  static const TextStyle message = TextStyle(
    fontSize: 16,
    height: 21 / 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Фиксированная высота строки сообщения: строка с временем
  /// не «проседает», даже если в ней нет текста.
  static const StrutStyle messageStrut = StrutStyle(
    fontSize: 16,
    height: 21 / 16,
    forceStrutHeight: true,
  );

  /// Время и статус внутри пузыря — цифры одинаковой ширины.
  static const TextStyle meta = TextStyle(
    fontSize: 11.5,
    height: 14 / 11.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
