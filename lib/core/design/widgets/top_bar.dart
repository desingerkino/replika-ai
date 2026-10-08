import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../context.dart';
import '../icons.dart';
import '../tokens.dart';
import '../adaptive.dart';

/// Верхняя панель экрана. Своя, а не AppBar: полный контроль над видом.
class ReplikaTopBar extends StatelessWidget implements PreferredSizeWidget {
  const ReplikaTopBar({
    super.key,
    this.leading,
    required this.title,
    this.actions = const [],
  });

  final Widget? leading;
  final Widget title;
  final List<Widget> actions;

  /// Для Scaffold это верхний предел: реальная высота — по содержимому
  /// (минимум 56). При крупном системном шрифте панель растёт, а не
  /// выпускает текст наружу.
  @override
  Size get preferredSize => const Size.fromHeight(Sizes.topBar * 2.5);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cs.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.topBar),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.rc.divider, width: 0.6)),
          ),
          padding: EdgeInsets.only(
            left: leading == null ? Space.l : Space.xs,
            right: Space.xs,
            top: Space.xs,
            bottom: Space.xs,
          ),
          child: Row(
            children: [
              if (leading != null) leading!,
              Expanded(child: title),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка «Назад».
class BackIconButton extends StatelessWidget {
  const BackIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    // В правой панели широкого экрана возвращаться некуда.
    if (InDetailPane.of(context)) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Назад',
      icon: const Icon(AppIcons.back),
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}

/// Крупный заголовок раздела («Чаты», «Контакты»).
/// Удержание заголовка ([onTitleHold]) ничем не выдаёт себя в кадре.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.onTitleHold,
  });

  final String title;
  final List<Widget> actions;

  /// Скрытое действие: удерживать заголовок 2 секунды.
  final VoidCallback? onTitleHold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l + 4, Space.m, Space.s, Space.s),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            Expanded(
              child: _hold(
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: context.tt.headlineSmall?.copyWith(
                      fontSize: 34,
                      height: 41 / 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }

  Widget _hold(Widget child) {
    final action = onTitleHold;
    if (action == null) return child;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: const Duration(seconds: 2)),
          (recognizer) => recognizer.onLongPress = action,
        ),
      },
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }
}
