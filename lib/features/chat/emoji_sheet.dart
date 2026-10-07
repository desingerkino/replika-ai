import 'package:flutter/material.dart';

import '../../design_system/glass_surface.dart';
import '../../design_system/glass_theme.dart';

/// Набор эмодзи для быстрого ввода (без внешних пакетов).
const List<String> quickEmoji = [
  '😊', '😂', '🥹', '😍', '😘', '😉', '😎', '🤔',
  '😅', '😢', '😡', '🙄', '😴', '🤗', '🥳', '😇',
  '👍', '👎', '🙏', '👏', '🙌', '💪', '👌', '✌️',
  '❤️', '🔥', '✨', '🎉', '💯', '👀', '🎬', '📸',
];

/// Вставляет [emoji] в позицию курсора.
void insertEmoji(TextEditingController controller, String emoji) {
  final value = controller.value;
  final text = value.text;
  final selection = value.selection;
  final start = selection.isValid ? selection.start : text.length;
  final end = selection.isValid ? selection.end : text.length;
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, emoji),
    selection: TextSelection.collapsed(offset: start + emoji.length),
  );
}

/// Стеклянная панель с эмодзи; выбор вставляется в поле ввода.
Future<void> showEmojiSheet(BuildContext context, TextEditingController controller) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x33000000),
    builder: (context) {
      final glass = GlassTheme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: GlassSurface(
            radius: 28,
            strong: true,
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (final emoji in quickEmoji)
                  InkResponse(
                    radius: 24,
                    onTap: () {
                      insertEmoji(controller, emoji);
                      Navigator.of(context).pop();
                    },
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: Center(
                        child: Text(
                          emoji,
                          style: TextStyle(fontSize: 26, color: glass.textPrimary),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
