import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/brand/brand.dart';
import '../core/design/context.dart';
import '../core/design/icons.dart';
import '../core/design/theme.dart';
import '../core/theme/app_theme_id.dart';
import '../features/splash/splash_screen.dart';
import '../core/design/tokens.dart';
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
      // Заставка показывается хотя бы до конца своей анимации появления.
      final opened = AppServices.open();
      await Future.wait<Object?>([opened, Future<void>.delayed(const Duration(milliseconds: 1100))]);
      final services = await opened;
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      child: services != null
          ? ReplikaApp(key: const ValueKey('app'), services: services)
          : _startup(),
    );
  }

  Widget _startup() {
    return MaterialApp(
      key: const ValueKey('startup'),
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppThemeId.fallback, Brightness.light),
      darkTheme: AppTheme.build(AppThemeId.fallback, Brightness.dark),
      themeMode: ThemeMode.system,
      locale: appLocale,
      supportedLocales: const [appLocale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _error == null
          ? const SplashScreen()
          : _StartupError(error: _error!, retrying: _opening, onRetry: _retry),
    );
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
