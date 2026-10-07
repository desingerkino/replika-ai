import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/brand/brand.dart';
import '../core/design/context.dart';
import '../core/design/icons.dart';
import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../features/splash/splash_screen.dart';
import 'app.dart';
import 'services.dart';

/// Запуск: открытие базы и демо-данных. Если открыть не удалось —
/// экран ошибки с повтором, а не «белый экран».
class StartupApp extends StatefulWidget {
  const StartupApp({super.key});

  @override
  State<StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<StartupApp> {
  AppServices? _services;
  Object? _error;
  bool _opening = false;

  /// Стартовый экран доиграл полосу загрузки.
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    _opening = true;
    _load();
  }

  Future<void> _retry() async {
    if (_opening) return;
    setState(() => _opening = true);
    await _load();
  }

  Future<void> _load() async {
    try {
      final services = await AppServices.open();
      if (!mounted) return;
      setState(() {
        _services = services;
        _opening = false;
      });
    } catch (error, stack) {
      debugPrint('Ошибка запуска: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _error = error;
        _opening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    // Приложение открывается, когда и данные готовы, и стартовый экран
    // закончил; переход — плавное перекрытие, без вспышки.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Оба слоя на весь экран (выше MaterialApp нет Directionality, поэтому
      // выравнивание задано явно).
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      child: services != null && _splashDone
          ? KeyedSubtree(key: const ValueKey('app'), child: ReplikaApp(services: services))
          : KeyedSubtree(
              key: const ValueKey('startup'),
              child: MaterialApp(
                title: Brand.name,
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: ThemeMode.system,
                locale: appLocale,
                supportedLocales: const [appLocale],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: _error == null
                    ? SplashScreen(onFinished: _onSplashFinished)
                    : _StartupError(error: _error!, retrying: _opening, onRetry: _retry),
              ),
            ),
    );
  }

  void _onSplashFinished() {
    if (!mounted || _splashDone) return;
    setState(() => _splashDone = true);
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({
    required this.error,
    required this.retrying,
    required this.onRetry,
  });

  final Object error;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.xl),
          children: [
            const SizedBox(height: Space.xxxl),
            Icon(AppIcons.error, size: 48, color: rc.danger),
            const SizedBox(height: Space.l),
            Text('Не удалось открыть данные приложения', style: tt.titleLarge),
            const SizedBox(height: Space.s),
            Text(
              'Переписки и настройки хранятся на этом телефоне. Попробуйте '
              'ещё раз; если ошибка повторится, перезапустите приложение.',
              style: tt.bodyMedium?.copyWith(color: rc.textSecondary),
            ),
            const SizedBox(height: Space.xl),
            FilledButton.icon(
              onPressed: retrying ? null : onRetry,
              icon: const Icon(AppIcons.retry),
              label: Text(retrying ? 'Открываю…' : 'Повторить'),
            ),
            const SizedBox(height: Space.xl),
            Text('Технические подробности для разработчика:', style: tt.labelMedium),
            const SizedBox(height: Space.xs),
            SelectableText(
              error.toString(),
              style: tt.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
