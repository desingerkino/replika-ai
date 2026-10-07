import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/icons.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/pressable.dart';
import '../../core/design/adaptive.dart';
import '../../data/models/chat.dart';
import '../../design_system/glass_controls.dart';
import '../../design_system/glass_theme.dart';

/// Краски и формы «светлого жидкого стекла» экрана переписки.
class ChatGlass {
  const ChatGlass._();

  /// Фирменный градиент исходящих: #5667FF → #A078FF.
  static const LinearGradient outgoing = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5667FF), Color(0xFFA078FF)],
  );

  static const double radius = 22;
  static const double joined = 8;
  static const double tail = 7;
  static const double cardRadius = 24;

  /// Входящий пузырь: белое стекло 70 % (светлая тема) и 16 % (тёмная).
  static const Color incomingFillLight = Color(0xB3FFFFFF);
  static const Color incomingFillDark = Color(0x29FFFFFF);

  static Color incomingFill(BuildContext context) =>
      GlassTheme.of(context).dark ? incomingFillDark : incomingFillLight;

  static Color incomingBorder(BuildContext context) =>
      GlassTheme.of(context).dark ? const Color(0x33FFFFFF) : const Color(0xCCFFFFFF);

  static const Color outgoingText = Color(0xFFFFFFFF);
  static const Color outgoingMeta = Color(0xCCFFFFFF);

  /// Скругления: у последнего пузыря группы — маленький угол-«хвост».
  static BorderRadius bubbleRadius({
    required bool outgoing,
    required bool joinsPrevious,
    required bool joinsNext,
  }) {
    const round = Radius.circular(radius);
    final top = Radius.circular(joinsPrevious ? joined : radius);
    final bottom = Radius.circular(joinsNext ? joined : tail);
    return outgoing
        ? BorderRadius.only(topLeft: round, bottomLeft: round, topRight: top, bottomRight: bottom)
        : BorderRadius.only(topRight: round, bottomRight: round, topLeft: top, bottomLeft: bottom);
  }

  /// Заливка, кромка и мягкая тень пузыря.
  static BoxDecoration bubble(BuildContext context, {required bool outgoing, required BorderRadius radius}) {
    final glass = GlassTheme.of(context);
    if (outgoing) {
      return BoxDecoration(
        gradient: ChatGlass.outgoing,
        borderRadius: radius,
        border: Border.all(color: const Color(0x4DFFFFFF), width: 1),
        boxShadow: const [BoxShadow(color: Color(0x445667FF), blurRadius: 14, offset: Offset(0, 5))],
      );
    }
    return BoxDecoration(
      color: incomingFill(context),
      borderRadius: radius,
      border: Border.all(color: incomingBorder(context), width: 1),
      boxShadow: [BoxShadow(color: glass.shadow, blurRadius: 14, offset: const Offset(0, 4))],
    );
  }
}

/// Стеклянная шапка: назад, аватар, имя и статус, звонок, видео, «ещё».
class ChatGlassHeader extends StatelessWidget {
  const ChatGlassHeader({
    super.key,
    required this.peer,
    required this.typing,
    this.subtitle,
    this.onTitleTap,
    this.onCall,
    this.onVideo,
    this.onMore,
  });

  static const double side = 14;
  static const double avatarSize = 48;
  static const double buttonSize = 36;

  final ChatPeer peer;
  final bool typing;

  /// Вместо статуса собеседника (у группы — «3 участника»).
  final String? subtitle;
  final VoidCallback? onTitleTap;
  final VoidCallback? onCall;
  final VoidCallback? onVideo;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final status = typing ? 'печатает…' : (subtitle ?? peer.statusText.trim());
    final online = subtitle == null && !typing && peer.isOnline;
    final inPane = InDetailPane.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(side, 6, side, 8),
      child: Row(
        children: [
          if (!inPane) ...[
            GlassIconButton(
              icon: AppIcons.back,
              label: 'Назад',
              size: buttonSize,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Pressable(
              onTap: onTitleTap,
              tint: false,
              child: Row(
                children: [
                  Avatar(
                    name: peer.displayName,
                    size: avatarSize,
                    imagePath: peer.avatarPath,
                    tone: peer.avatarTone,
                    online: subtitle == null && peer.isOnline,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peer.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: glass.textPrimary,
                            fontSize: 15,
                            height: 20 / 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (status.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (online) ...[
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: GlassTheme.online,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: typing ? GlassTheme.accentBlue : glass.textSecondary,
                                    fontSize: 13.5,
                                    height: 18 / 13.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (onCall != null) ...[
            GlassIconButton(icon: AppIcons.callOutlined, label: 'Аудиозвонок', size: buttonSize, onPressed: onCall),
            const SizedBox(width: 6),
          ],
          if (onVideo != null) ...[
            GlassIconButton(icon: AppIcons.videoOutlined, label: 'Видеозвонок', size: buttonSize, onPressed: onVideo),
            const SizedBox(width: 6),
          ],
          GlassIconButton(icon: AppIcons.more, label: 'Ещё', size: buttonSize, onPressed: onMore),
        ],
      ),
    );
  }
}

/// Новая реплика появляется из размытия: прозрачность 0 → 1, размытие
/// 8 → 0 и сдвиг на 20 px снизу. Только для сообщений, пришедших после
/// открытия экрана; при «уменьшить движение» — без анимации.
class MessageEntrance extends StatefulWidget {
  const MessageEntrance({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  static const Duration duration = Duration(milliseconds: 380);
  static const double shift = 20;
  static const double maxBlur = 8;

  @override
  State<MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<MessageEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: MessageEntrance.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        if (t >= 1) return child!;
        final blur = MessageEntrance.maxBlur * (1 - t);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, MessageEntrance.shift * (1 - t)),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
