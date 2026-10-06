import 'dart:async';

import 'package:flutter/material.dart';

import '../context.dart';
import '../icons.dart';
import '../tokens.dart';

/// Пустое состояние экрана.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final tt = context.tt;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: rc.surfaceMuted, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: rc.textTertiary),
            ),
            const SizedBox(height: Space.l),
            Text(title, style: tt.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Space.xs + 2),
              Text(
                message!,
                style: tt.bodyMedium?.copyWith(color: rc.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Space.xl - 4),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Ошибка загрузки с кнопкой повтора.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: AppIcons.error,
      title: 'Что-то пошло не так',
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.retry, size: 20),
              label: const Text('Повторить'),
            ),
    );
  }
}

/// Загрузка. Индикатор появляется с задержкой, чтобы быстрые чтения
/// из базы не вызывали мигание.
class LoadingState extends StatefulWidget {
  const LoadingState({super.key});

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.expand();
    return const Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}
