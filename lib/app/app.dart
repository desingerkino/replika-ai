import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/brand/brand.dart';
import '../core/design/theme.dart';
import '../features/welcome/welcome_gate.dart';
import '../features/kino/fake_status_bar.dart';
import 'hidden_gestures.dart';
import 'navigator.dart';
import 'services.dart';

const Locale appLocale = Locale('ru', 'RU');

class ReplikaApp extends StatelessWidget {
  const ReplikaApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Services(
      services: services,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: services.themeMode,
        builder: (context, mode, _) => MaterialApp(
          title: Brand.name,
          debugShowCheckedModeBanner: false,
          navigatorKey: AppNavigator.key,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          locale: appLocale,
          supportedLocales: const [appLocale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppTheme.overlayStyle(Theme.of(context).brightness),
            child: HiddenGestures(
              onNext: services.appInput.next,
              onPrevious: services.appInput.previous,
              onOperator: AppNavigator.openOperator,
              child: KinoFrame(child: child ?? const SizedBox.shrink()),
            ),
          ),
          home: const WelcomeGate(),
        ),
      ),
    );
  }
}
