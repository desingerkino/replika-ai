import 'package:flutter/material.dart';

import 'colors.dart';

extension ThemeContext on BuildContext {
  ReplikaColors get rc => Theme.of(this).extension<ReplikaColors>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}
