import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
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
    this.onVoice,
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

  /// Микрофон: записать голосовое (вместо кнопки отправки при пустом поле).
  final VoidCallback? onVoice;

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
          border: Border(top: BorderSide(color: rc.divider, width: 0.6)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) const LinearProgressIndicator(minHeight: 2),
              if (reply != null) _ReplyBar(reply: reply!, onCancel: onCancelReply),
              Padding(
            padding: EdgeInsets.fromLTRB(onAttach == null ? Space.m : Space.xs, Space.s, Space.s, Space.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (onAttach != null)
                  IconButton(
                    tooltip: 'Прикрепить',
                    onPressed: busy ? null : onAttach,
                    icon: Icon(Icons.attach_file_rounded, color: rc.textSecondary),
                  ),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: Sizes.sendButton),
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 11),
                    decoration: BoxDecoration(
                      color: rc.surfaceMuted,
                      borderRadius: BorderRadius.circular(22),
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
                const SizedBox(width: Space.s),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    if (!hasText && onVoice != null) {
                      return Semantics(
                        button: true,
                        label: 'Записать голосовое',
                        child: SizedBox(
                          width: Sizes.sendButton,
                          height: Sizes.sendButton,
                          child: Material(
                            color: cs.primary,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: busy ? null : onVoice,
                              child: Icon(Icons.mic_rounded, color: cs.onPrimary, size: 22),
                            ),
                          ),
                        ),
                      );
                    }
                    return SendButton(enabled: hasText, onPressed: onSend);
                  },
                ),
              ],
            ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SendButton extends StatelessWidget {
  const SendButton({super.key, required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Отправить',
      child: AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.curve,
        width: Sizes.sendButton,
        height: Sizes.sendButton,
        decoration: BoxDecoration(
          color: enabled ? cs.primary : rc.surfaceMuted,
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Icon(
                AppIcons.send,
                size: 22,
                color: enabled ? cs.onPrimary : rc.textTertiary,
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
            onPressed: onCancel,
            icon: Icon(AppIcons.clear, color: rc.textSecondary),
          ),
        ],
      ),
    );
  }
}
