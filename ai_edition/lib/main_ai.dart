import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai/llamadart_provider.dart';
import 'ai/qwen_auto_reply_engine.dart';
import 'app/auto_reply.dart';
import 'app/startup.dart';

/// Вход «Реплика AI»: то же приложение, что lib/main.dart, плюс локальный
/// ИИ-собеседник (по умолчанию выключен: Настройки → Дополнения).
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  AutoReplyController.engine = LocalAutoReplyEngine(LlamadartLocalLlmProvider());
  runApp(const StartupApp());
}
