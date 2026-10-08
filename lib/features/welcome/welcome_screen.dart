import 'package:flutter/material.dart';

import '../../core/brand/logo.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';

/// Экран приветствия при первом запуске. Авторизации нет: кнопка
/// «Начать» просто открывает приложение.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  ReplikaLogo(size: 96, onDark: dark),
                  const SizedBox(height: Space.xl),
                  Text(
                    'Добро пожаловать в Replika',
                    textAlign: TextAlign.center,
                    style: tt.headlineSmall?.copyWith(
                      fontSize: 28,
                      height: 34 / 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: Space.m),
                  Text(
                    'Общайтесь, создавайте истории и оставайтесь на связи',
                    textAlign: TextAlign.center,
                    style: tt.bodyLarge?.copyWith(color: rc.textSecondary),
                  ),
                  const Spacer(flex: 4),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: onStart,
                      style: FilledButton.styleFrom(
                        backgroundColor: dark ? Palette.white : Palette.ink,
                        foregroundColor: dark ? Palette.ink : Palette.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Начать'),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
