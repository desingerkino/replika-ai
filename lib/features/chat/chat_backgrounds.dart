import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/live_query.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../core/theme/app_theme_id.dart';
import '../../core/theme/theme_provider.dart';
import '../../data/db/tables.dart';
import '../../data/models/chat.dart';
import 'chat_wallpaper.dart';

/// Какой узор рисовать поверх цвета фона.
enum ChatPatternKind {
  /// Как в теме: узор, если стиль темы его включает.
  theme,
  none,
  doodle,
  dots,
}

/// Встроенный фон переписки. Хранится у чата строкой [id]
/// (chats.background); null — «Стандартный».
@immutable
class ChatBackground {
  const ChatBackground({
    required this.id,
    required this.name,
    this.brightness,
    this.color,
    this.pattern,
    this.kind = ChatPatternKind.none,
  });

  /// null — «Стандартный» (фон темы).
  final String? id;
  final String name;

  /// Светлый или тёмный фон независимо от темы: пузыри и подписи на нём
  /// берутся из светлого/тёмного варианта текущей темы — текст читается.
  final Brightness? brightness;

  /// Цвет фона; null — фон переписки темы.
  final Color? color;

  /// Цвет узора; null — цвет узора темы.
  final Color? pattern;
  final ChatPatternKind kind;
}

abstract final class ChatBackgrounds {
  static const ChatBackground standard =
      ChatBackground(id: null, name: 'Стандартный', kind: ChatPatternKind.theme);

  static const List<ChatBackground> all = [
    standard,
    ChatBackground(id: 'light', name: 'Светлый', brightness: Brightness.light, color: Color(0xFFEFF1F5)),
    ChatBackground(id: 'dark', name: 'Тёмный', brightness: Brightness.dark, color: Color(0xFF0F1620)),
    ChatBackground(id: 'minimal', name: 'Минималистичный'),
    ChatBackground(id: 'doodle', name: 'Узор', kind: ChatPatternKind.doodle),
    ChatBackground(id: 'dots', name: 'Точки', kind: ChatPatternKind.dots),
    ChatBackground(
      id: 'sky',
      name: 'Небо',
      brightness: Brightness.light,
      color: Color(0xFFDCEBFA),
      pattern: Color(0x2A1E6FD0),
      kind: ChatPatternKind.doodle,
    ),
    ChatBackground(
      id: 'mint',
      name: 'Мята',
      brightness: Brightness.light,
      color: Color(0xFFDDEFE3),
      pattern: Color(0x2A1A7A4C),
      kind: ChatPatternKind.doodle,
    ),
    ChatBackground(
      id: 'lavender',
      name: 'Лаванда',
      brightness: Brightness.light,
      color: Color(0xFFE8E4F8),
      pattern: Color(0x2A5B4BC4),
      kind: ChatPatternKind.dots,
    ),
    ChatBackground(
      id: 'night',
      name: 'Ночь',
      brightness: Brightness.dark,
      color: Color(0xFF111A2B),
      pattern: Color(0x1AFFFFFF),
      kind: ChatPatternKind.doodle,
    ),
  ];

  /// Фон по сохранённому id; неизвестный (старая версия, удалённый) —
  /// «Стандартный».
  static ChatBackground byId(String? id) {
    if (id == null) return standard;
    for (final background in all) {
      if (background.id == id) return background;
    }
    return standard;
  }
}

/// Тема для фона: если фон светлый/тёмный вопреки теме — тот же стиль
/// темы, но в нужной яркости.
ThemeData? themeForBackground(BuildContext context, ChatBackground background) {
  final wanted = background.brightness;
  if (wanted == null || Theme.of(context).brightness == wanted) return null;
  final provider = context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
  final id = provider?.notifier?.id ?? AppThemeId.replika;
  return AppTheme.build(id, wanted);
}

/// Слой фона без содержимого (для превью и самой переписки).
class ChatBackgroundPaint extends StatelessWidget {
  const ChatBackgroundPaint({super.key, required this.background, required this.child});

  final ChatBackground background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final color = background.color ?? (background.id == 'minimal' ? context.cs.surface : rc.chatBackground);
    final kind = switch (background.kind) {
      ChatPatternKind.theme => context.style.chatWallpaper ? ChatPatternKind.doodle : ChatPatternKind.none,
      final other => other,
    };
    final stroke = background.pattern ?? rc.chatPattern;
    switch (kind) {
      case ChatPatternKind.none:
      case ChatPatternKind.theme:
        return ColoredBox(color: color, child: child);
      case ChatPatternKind.doodle:
        return CustomPaint(
          painter: DoodlePainter(background: color, stroke: stroke),
          isComplex: true,
          child: RepaintBoundary(child: child),
        );
      case ChatPatternKind.dots:
        return CustomPaint(
          painter: DotsPainter(background: color, dot: stroke),
          isComplex: true,
          child: RepaintBoundary(child: child),
        );
    }
  }
}

/// Мягкий узор из точек разного размера.
class DotsPainter extends CustomPainter {
  const DotsPainter({required this.background, required this.dot});

  final Color background;
  final Color dot;

  static const double step = 22;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()..color = dot;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    var row = 0;
    for (var y = step / 2; y < size.height + step; y += step, row++) {
      final shift = row.isEven ? 0.0 : step / 2;
      var col = 0;
      for (var x = shift; x < size.width + step; x += step, col++) {
        final big = (row + col) % 3 == 0;
        canvas.drawCircle(Offset(x, y), big ? 2.2 : 1.3, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DotsPainter oldDelegate) => oldDelegate.background != background || oldDelegate.dot != dot;
}

/// Выбор фона чата: превью с пузырями, галочка у выбранного, фон
/// применяется сразу (переписка за экраном меняется вживую), «Сбросить» —
/// вернуть стандартный.
class ChatBackgroundScreen extends StatelessWidget {
  const ChatBackgroundScreen({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return LiveQuery<ChatHeader?>(
      tables: const {Tables.chats},
      queryKey: chatId,
      load: () => services.chats.header(chatId),
      builder: (context, snapshot) {
        final current = snapshot.data?.chat.background;
        final selected = ChatBackgrounds.byId(current);
        void apply(ChatBackground background) {
          HapticFeedback.selectionClick();
          services.chats.setBackground(chatId, background.id).catchError((Object error) {
            debugPrint('Фон чата не сохранён: $error');
          });
        }

        return Scaffold(
          appBar: ReplikaTopBar(
            leading: const BackIconButton(),
            title: Text('Фон чата', style: context.tt.titleMedium),
            actions: [
              if (selected.id != null)
                TextButton(
                  onPressed: () => apply(ChatBackgrounds.standard),
                  child: const Text('Сбросить'),
                ),
            ],
          ),
          body: GridView.builder(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xl),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: Space.l,
              crossAxisSpacing: Space.m,
              childAspectRatio: 0.56,
            ),
            itemCount: ChatBackgrounds.all.length,
            itemBuilder: (context, index) {
              final background = ChatBackgrounds.all[index];
              return _BackgroundTile(
                background: background,
                selected: background.id == selected.id,
                onTap: () => apply(background),
              );
            },
          ),
        );
      },
    );
  }
}

class _BackgroundTile extends StatelessWidget {
  const _BackgroundTile({required this.background, required this.selected, required this.onTap});

  final ChatBackground background;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final rc = context.rc;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Фон «${background.name}»',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: Motion.fast,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: selected ? cs.primary : rc.divider, width: selected ? 2.5 : 0.8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ChatWallpaper(background: background.id, child: const _MiniChat()),
                      if (selected)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: Icon(AppIcons.check, size: 15, color: cs.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.s),
            Text(
              background.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.bodySmall?.copyWith(
                color: selected ? cs.primary : rc.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Два пузыря в превью — видно, как читается переписка на фоне.
class _MiniChat extends StatelessWidget {
  const _MiniChat();

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    Widget bubble(bool out, double width) => Align(
          alignment: out ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: width,
            height: 18,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: out ? rc.bubbleOut : rc.bubbleIn,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(Space.s),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          bubble(false, 62),
          bubble(true, 54),
          bubble(false, 40),
          const SizedBox(height: Space.s),
        ],
      ),
    );
  }
}
