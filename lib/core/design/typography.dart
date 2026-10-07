import 'package:flutter/material.dart';

/// Типографическая шкала. Шрифт — Inter (SIL OFL 1.1), лежит в приложении
/// файлами assets/fonts: ничего не грузится из сети, а кадр одинаков на
/// iPhone и Android. Размеры подобраны для съёмки: в крупном плане
/// мелкий текст (время, подписи) не должен теряться.
abstract final class AppType {
  /// Единственное семейство интерфейса. Подключено в pubspec.yaml (fonts).
  static const String fontFamily = 'Inter';

  static TextTheme textTheme({required Color primary, required Color secondary}) {
    return TextTheme(
      headlineSmall: TextStyle(fontFamily: fontFamily, fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: primary),
      titleLarge: TextStyle(fontFamily: fontFamily, fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: primary),
      titleMedium: TextStyle(fontFamily: fontFamily, fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: primary),
      titleSmall: TextStyle(fontFamily: fontFamily, fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600, letterSpacing: 0, color: primary),
      bodyLarge: TextStyle(fontFamily: fontFamily, fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w400, letterSpacing: 0, color: primary),
      bodyMedium: TextStyle(fontFamily: fontFamily, fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w400, letterSpacing: 0, color: primary),
      bodySmall: TextStyle(fontFamily: fontFamily, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400, letterSpacing: 0, color: secondary),
      labelLarge: TextStyle(fontFamily: fontFamily, fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600, letterSpacing: 0, color: primary),
      // Подписи и время в списках: было 12 / 11, для камеры — 13 / 12.
      labelMedium: TextStyle(fontFamily: fontFamily, fontSize: 13, height: 17 / 13, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: secondary),
      labelSmall: TextStyle(fontFamily: fontFamily, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: secondary),
    );
  }

  /// Текст сообщения (было 16).
  static const TextStyle message = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 21 / 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// Фиксированная высота строки сообщения: строка с временем
  /// не «проседает», даже если в ней нет текста.
  static const StrutStyle messageStrut = StrutStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 21 / 16,
    forceStrutHeight: true,
  );

  /// Время и статус внутри пузыря — цифры одинаковой ширины (было 11.5).
  static const TextStyle meta = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 15 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
