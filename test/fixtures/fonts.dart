// Настоящие шрифты приложения в тестах-снимках (по умолчанию тесты рисуют
// текст квадратиками тестового шрифта).
import 'dart:convert';

import 'package:flutter/services.dart';

/// Загружает все шрифты из манифеста сборки: Inter, значки Replika и Material.
Future<void> loadAppFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
