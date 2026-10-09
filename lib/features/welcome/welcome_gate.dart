import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../data/repositories/settings_repository.dart';
import '../shell/home_shell.dart';
import 'welcome_screen.dart';

/// Показывает приветствие при первом запуске, затем — главный экран.
class WelcomeGate extends StatefulWidget {
  const WelcomeGate({super.key});

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  bool? _seen;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading || _seen != null) return;
    _loading = true;
    _load();
  }

  Future<void> _load() async {
    var seen = true; // при сбое чтения не блокируем вход в приложение
    try {
      seen = await Services.read(context).settings.getValue(SettingKeys.welcomeSeen) == '1';
    } catch (error) {
      debugPrint('Флаг приветствия не прочитан: $error');
    }
    if (mounted) setState(() => _seen = seen);
  }

  Future<void> _start() async {
    setState(() => _seen = true);
    try {
      await Services.read(context).settings.setValue(SettingKeys.welcomeSeen, '1');
    } catch (error) {
      debugPrint('Флаг приветствия не сохранён: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) return Scaffold(backgroundColor: Theme.of(context).colorScheme.surface);
    if (seen) return const HomeShell();
    return WelcomeScreen(onStart: _start);
  }
}
