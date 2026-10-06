import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/startup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Приложение рисуется под прозрачными системными панелями.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const StartupApp());
}
