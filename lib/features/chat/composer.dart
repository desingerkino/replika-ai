import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/design/widgets/pressable.dart';
import '../record/recording_bar.dart';
import '../record/voice_recording.dart';
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

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    return Material(
      color: cs.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: rc.divider, width: Sizes.line)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) const LinearProgressIndicator(minHeight: 2),
              if (reply != null) _ReplyBar(reply: reply!, onCancel: onCancelReply),
              ListenableBuilder(
                listenable: voice ?? _noVoice,
                builder: (context, _) => Padding(
            padding: EdgeInsets.fromLTRB(onAttach == null ? Space.m : Space.xs, Space.s - 2, Space.s - 2, Space.s - 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (voice?.active ?? false)
                  Expanded(child: RecordingBar(controller: voice!))
                else ...[
                if (onAttach != null)
                  IconButton(
                    tooltip: 'Прикрепить',
                    style: quietButtonStyle,
                    onPressed: busy ? null : onAttach,
                    icon: Icon(AppIcons.attachment, color: rc.textSecondary),
                  ),
                Expanded(
                  // 2 px сверху и снизу: поле на одной линии с 48-пиксельной областью кнопки.
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: (Sizes.minTouch - Sizes.sendButton) / 2),
                    child: Container(
                    constraints: const BoxConstraints(minHeight: Sizes.sendButton),
                    // Рамка 1 px: край поля читается в крупном плане; отступы
                    // уменьшены на её ширину, размер поля прежний.
                    padding: const EdgeInsets.symmetric(horizontal: Space.l - Sizes.line, vertical: 11 - Sizes.line),
                    decoration: BoxDecoration(
                      color: rc.surfaceMuted,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: rc.divider, width: Sizes.line),
                    ),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppType.message.copyWith(color: rc.textPrimary),
                      decoration: InputDecoration.collapsed(
                        hintText: 'Сообщение',
                        hintStyle: AppType.message.copyWith(color: rc.textTertiary),
                      ),
                    ),
                    ),
                  ),
                ),
                ],
                const SizedBox(width: Space.s - 2),
                ValueListenableBuilder<TextEditingValue>(
                  // Ключ: кнопка справа не пересоздаётся, когда строка записи
                  // заменяет поле ввода, — палец на микрофоне не теряется.
                  key: const ValueKey('composer-trailing'),
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    final showMic = !hasText && voice != null;
                    final lockedRecording = voice?.locked ?? false;
                    final reduceMotion = MediaQuery.disableAnimationsOf(context);
                    // Микрофон и «отправить» сменяют друг друга плавно:
                    // короткое затухание с лёгким масштабом.
                    return AnimatedSwitcher(
                      duration: reduceMotion ? Duration.zero : Motion.swap,
                      reverseDuration: reduceMotion ? Duration.zero : Motion.swap,
                      switchInCurve: Motion.curve,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
                          child: child,
                        ),
                      ),
                      child: lockedRecording
                          ? SendButton(
                              key: const ValueKey('composer-send-locked'),
                              enabled: true,
                              onPressed: voice!.sendLocked,
                            )
                          : showMic
                              ? _MicHoldButton(
                                  key: const ValueKey('composer-mic'),
                                  voice: voice!,
                                  enabled: !busy,
                                )
                              : SendButton(
                                  key: const ValueKey('composer-send'),
                                  enabled: hasText,
                                  onPressed: onSend,
                                ),
                    );
                  },
                ),
              ],
            ),
                ),
              ),
            ],
          ),
        ),
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
    final cs = context.cs;
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
        width: Sizes.minTouch,
        height: Sizes.minTouch,
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
                  child: Container(
                    width: Sizes.sendButton,
                    height: Sizes.sendButton,
                    decoration: BoxDecoration(
                      color: widget.enabled ? cs.primary : context.rc.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(AppIcons.microphone, size: 22, color: cs.onPrimary),
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
    final rc = context.rc;
    final cs = context.cs;
    return _CircleButton(
      label: 'Отправить',
      icon: AppIcons.send,
      enabled: enabled,
      fill: enabled ? cs.primary : rc.surfaceMuted,
      iconColor: enabled ? cs.onPrimary : rc.textTertiary,
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
    required this.fill,
    required this.iconColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final Color fill;
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
          child: AnimatedScale(
          scale: pressed ? 0.92 : 1,
          duration: duration,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: Motion.normal,
            curve: Motion.curve,
            width: Sizes.sendButton,
            height: Sizes.sendButton,
            decoration: BoxDecoration(color: widget.fill, shape: BoxShape.circle),
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
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.reply, this.onCancel});

  final QuotedMessage reply;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, 0),
      child: Row(
        children: [
          Icon(AppIcons.reply, size: 22, color: cs.primary),
          const SizedBox(width: Space.m),
          Container(width: 2, height: 34, color: cs.primary),
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
                  style: context.tt.labelLarge?.copyWith(color: cs.primary),
                ),
                Text(
                  reply.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodyMedium?.copyWith(color: rc.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить ответ',
            style: quietButtonStyle,
            onPressed: onCancel,
            icon: Icon(AppIcons.clear, color: rc.textSecondary),
          ),
        ],
      ),
    );
  }
}
