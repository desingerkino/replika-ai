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
                padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: Sizes.sendButton + 2),
                        decoration: BoxDecoration(
                          color: rc.surfaceMuted,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Эмодзи',
                              onPressed: () => _insertEmoji(context),
                              icon: Icon(Icons.sentiment_satisfied_alt_outlined, color: rc.textSecondary),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
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
                                    hintStyle: AppType.message.copyWith(color: rc.textSecondary),
                                  ),
                                ),
                              ),
                            ),
                            if (onAttach != null)
                              IconButton(
                                tooltip: 'Прикрепить',
                                onPressed: busy ? null : onAttach,
                                icon: Transform.rotate(
                                  angle: 0.6,
                                  child: Icon(Icons.attach_file_rounded, color: rc.textSecondary),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) {
                        final hasText = value.text.trim().isNotEmpty;
                        return AnimatedSwitcher(
                          duration: Motion.normal,
                          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                          child: !hasText && onVoice != null
                              ? Semantics(
                                  key: const ValueKey('mic'),
                                  button: true,
                                  label: 'Записать голосовое',
                                  child: SizedBox(
                                    width: Sizes.sendButton + 2,
                                    height: Sizes.sendButton + 2,
                                    child: Material(
                                      color: cs.primary,
                                      shape: const CircleBorder(),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: busy ? null : onVoice,
                                        child: Icon(Icons.mic_rounded, color: cs.onPrimary, size: 24),
                                      ),
                                    ),
                                  ),
                                )
                              : SendButton(key: const ValueKey('send'), enabled: hasText, onPressed: onSend),
                        );
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

  /// Быстрая вставка эмодзи в текст (полный набор — на системной клавиатуре).
  Future<void> _insertEmoji(BuildContext context) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in composerEmoji)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(e),
                  child: SizedBox.square(dimension: 46, child: Center(child: Text(e, style: const TextStyle(fontSize: 26)))),
                ),
            ],
          ),
        ),
      ),
    );
    if (emoji == null) return;
    final value = controller.value;
    final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(selection.start, selection.end, emoji);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: selection.start + emoji.length),
    );
    focusNode.requestFocus();
  }
}

/// Частые эмодзи для быстрой вставки.
const List<String> composerEmoji = [
  '😀', '😂', '🥹', '😍', '😘', '😊', '😉', '😎', '🤔', '😮', '😢', '😭',
  '😡', '🥳', '😴', '🙄', '👍', '👎', '👏', '🙏', '💪', '🤝', '❤️', '🔥',
  '✨', '🎉', '💯', '👀', '🎬', '📞', '🌹', '☕',
];

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
        width: Sizes.sendButton + 2,
        height: Sizes.sendButton + 2,
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
