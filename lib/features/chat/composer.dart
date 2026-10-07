import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/design/widgets/pressable.dart';
import '../record/recording_bar.dart';
import '../record/voice_recording.dart';
import '../../design_system/glass_controls.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/glass_theme.dart';
import 'chat_glass.dart';
import 'emoji_sheet.dart';
import 'message_bubble.dart';

/// Поле ввода сообщения с кнопкой отправки.
class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.reply,
    this.onCancelReply,
    this.onAttach,
    this.voice,
    this.busy = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  /// Сообщение, на которое отвечают (показывается над полем ввода).
  final QuotedMessage? reply;
  final VoidCallback? onCancelReply;

  /// Скрепка: прикрепить фото, видео, аудио.
  final VoidCallback? onAttach;

  /// Голосовое: микрофон вместо кнопки отправки при пустом поле. Держишь —
  /// идёт запись, отпустил — отправка, вверх — фиксация, влево — отмена.
  final VoiceRecordingController? voice;

  /// Идёт добавление файла — тонкая полоса прогресса над полем.
  final bool busy;

  /// Высота стеклянной капсулы.
  static const double capsuleHeight = 60;
  static const double capsuleRadius = 30;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (reply != null) _ReplyBar(reply: reply!, onCancel: onCancelReply),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: ListenableBuilder(
              listenable: voice ?? _noVoice,
              builder: (context, _) {
                final recording = voice?.active ?? false;
                return GlassSurface(
                  radius: capsuleRadius,
                  strong: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: capsuleHeight),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (recording)
                            Expanded(child: RecordingBar(controller: voice!))
                          else ...[
                            if (onAttach != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: GlassIconButton(
                                  icon: AppIcons.plus,
                                  label: 'Прикрепить',
                                  size: 44,
                                  onPressed: busy ? null : onAttach,
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                                child: TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  minLines: 1,
                                  maxLines: 6,
                                  keyboardType: TextInputType.multiline,
                                  textCapitalization: TextCapitalization.sentences,
                                  cursorColor: GlassTheme.accentBlue,
                                  style: AppType.message.copyWith(color: glass.textPrimary, fontSize: 16, height: 21 / 16),
                                  decoration: InputDecoration.collapsed(
                                    hintText: 'Сообщение',
                                    hintStyle: AppType.message.copyWith(color: glass.textTertiary, fontSize: 16, height: 21 / 16),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: GlassIconButton(
                                icon: AppIcons.emoji,
                                label: 'Эмодзи',
                                size: 40,
                                onPressed: () => showEmojiSheet(context, controller),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          ValueListenableBuilder<TextEditingValue>(
                            // Ключ: кнопки справа не пересоздаются, когда строка записи
                            // заменяет поле ввода, — палец на микрофоне не теряется.
                            key: const ValueKey('composer-trailing'),
                            valueListenable: controller,
                            builder: (context, value, _) {
                              final hasText = value.text.trim().isNotEmpty;
                              final lockedRecording = voice?.locked ?? false;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (voice != null && !lockedRecording)
                                    _MicHoldButton(
                                      key: const ValueKey('composer-mic'),
                                      voice: voice!,
                                      enabled: !busy && !hasText,
                                    ),
                                  if (lockedRecording)
                                    SendButton(
                                      key: const ValueKey('composer-send-locked'),
                                      enabled: true,
                                      onPressed: voice!.sendLocked,
                                    )
                                  else
                                    SendButton(
                                      key: const ValueKey('composer-send'),
                                      enabled: hasText,
                                      onPressed: onSend,
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static final ValueNotifier<int> _noVoice = ValueNotifier<int>(0);
}

/// Микрофон-«держалка»: нажатие сразу начинает запись, подъём пальца
/// отправляет, движение вверх фиксирует, влево — отменяет. События ведутся
/// через Listener, поэтому палец можно уводить за пределы кнопки.
class _MicHoldButton extends StatefulWidget {
  const _MicHoldButton({super.key, required this.voice, required this.enabled});

  final VoiceRecordingController voice;
  final bool enabled;

  @override
  State<_MicHoldButton> createState() => _MicHoldButtonState();
}

class _MicHoldButtonState extends State<_MicHoldButton> {
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    final voice = widget.voice;
    final holding = voice.state == VoiceRecState.holding;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Записать голосовое. Удерживайте кнопку',
      excludeSemantics: true,
      onTap: widget.enabled ? () => voice.onProblem(voiceHoldHint) : null,
      child: SizedBox(
        width: 44,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (holding && voice.recording)
              Positioned(
                bottom: Sizes.minTouch + Space.xs,
                child: LockHint(progress: voice.lockProgress),
              ),
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: widget.enabled
                  ? (event) {
                      if (_pointer != null) return;
                      _pointer = event.pointer;
                      voice.press(event.position);
                    }
                  : null,
              onPointerMove: (event) {
                if (event.pointer == _pointer) voice.drag(event.position);
              },
              onPointerUp: (event) {
                if (event.pointer != _pointer) return;
                _pointer = null;
                voice.release();
              },
              onPointerCancel: (event) {
                if (event.pointer != _pointer) return;
                _pointer = null;
                voice.cancel();
              },
              child: Center(
                child: AnimatedScale(
                  scale: holding ? 1.25 : 1,
                  duration: reduceMotion ? Duration.zero : Motion.press,
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: widget.enabled ? 1 : 0.45,
                    duration: Motion.normal,
                    child: GlassSurface(
                      radius: 20,
                      gradient: holding ? ChatGlass.outgoing : null,
                      glow: holding ? GlassTheme.accentGlow.withValues(alpha: 0.4) : null,
                      child: SizedBox.square(
                        dimension: 40,
                        child: Icon(
                          AppIcons.microphone,
                          size: 22,
                          color: holding ? Colors.white : GlassTheme.of(context).textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка «Отправить». При нажатии коротко уменьшается (до 0.92) и стрелка
/// чуть сдвигается вверх, на отпускании возвращается: без отскока.
class SendButton extends StatelessWidget {
  const SendButton({super.key, required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _CircleButton(
      label: 'Отправить',
      icon: AppIcons.send,
      enabled: enabled,
      iconColor: Colors.white,
      onPressed: onPressed,
    );
  }
}

/// Круглая кнопка действия с откликом на нажатие (масштаб + сдвиг значка).
/// Цвет заливки меняется плавно, когда кнопка становится доступной.
class _CircleButton extends StatefulWidget {
  const _CircleButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.iconColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final Color iconColor;
  final VoidCallback? onPressed;


  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onPressed != null;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.press;
    final pressed = active && _pressed;
    return Semantics(
      button: true,
      enabled: active,
      label: widget.label,
      excludeSemantics: true,
      onTap: active ? widget.onPressed : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: active ? (_) => _setPressed(true) : null,
        onTapUp: active ? (_) => _setPressed(false) : null,
        onTapCancel: active ? () => _setPressed(false) : null,
        onTap: active ? widget.onPressed : null,
        // Область нажатия 48 px (Sizes.minTouch), сама кнопка — 44.
        child: Padding(
          padding: const EdgeInsets.all((Sizes.minTouch - Sizes.sendButton) / 2),
          child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : 0.6,
          duration: Motion.normal,
          child: AnimatedScale(
          scale: pressed ? 0.92 : 1,
          duration: duration,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: Motion.normal,
            curve: Motion.curve,
            width: Sizes.sendButton,
            height: Sizes.sendButton,
            decoration: BoxDecoration(
              gradient: ChatGlass.outgoing,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x66FFFFFF), width: 1),
              boxShadow: widget.enabled
                  ? const [BoxShadow(color: Color(0x665667FF), blurRadius: 12, offset: Offset(0, 4))]
                  : null,
            ),
            child: Center(
              child: AnimatedSlide(
                offset: pressed ? const Offset(0, -0.1) : Offset.zero,
                duration: duration,
                curve: Curves.easeOut,
                child: Icon(widget.icon, size: 22, color: widget.iconColor),
              ),
            ),
          ),
          ),
          ),
        ),
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.reply, this.onCancel});

  final QuotedMessage reply;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    const accent = GlassTheme.accentBlue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, Space.s, 20, 0),
      child: Row(
        children: [
          const Icon(AppIcons.reply, size: 22, color: accent),
          const SizedBox(width: Space.m),
          Container(width: 2, height: 34, color: accent),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ответ: ${reply.author}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelLarge?.copyWith(color: accent),
                ),
                Text(
                  reply.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodyMedium?.copyWith(color: glass.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить ответ',
            style: quietButtonStyle,
            onPressed: onCancel,
            icon: Icon(AppIcons.clear, color: glass.textSecondary),
          ),
        ],
      ),
    );
  }
}
