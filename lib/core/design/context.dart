import 'package:flutter/material.dart';

import '../theme/app_style.dart';
import 'colors.dart';

extension ThemeContext on BuildContext {
  ReplikaColors get rc => Theme.of(this).extension<ReplikaColors>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;

  /// Формы и раскладки текущей темы. Тема без AppStyle (например,
  /// операторская) получает фирменный стиль «Реплики».
  AppStyle get style => Theme.of(this).extension<AppStyle>() ?? AppStyle.replika;
}
