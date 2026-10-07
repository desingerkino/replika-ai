import 'package:flutter/material.dart';

import '../context.dart';
import '../icons.dart';
import '../tokens.dart';

/// Поле поиска с кнопкой очистки.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return Container(
      // Рамка 1 px (как у поля сообщения): край поля читается и на белом,
      // и в тёмной теме; отступы уменьшены на её ширину.
      decoration: BoxDecoration(
        color: rc.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: rc.divider, width: Sizes.line),
      ),
      padding: const EdgeInsets.only(left: Space.m - Sizes.line),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 22, color: rc.textTertiary),
          const SizedBox(width: Space.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11 - Sizes.line),
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: context.tt.bodyLarge,
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: context.tt.bodyLarge?.copyWith(color: rc.textTertiary),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox(width: Space.m - Sizes.line);
              return IconButton(
                tooltip: 'Очистить',
                // Без Material-волны, область нажатия 48 px (по умолчанию).
                style: IconButton.styleFrom(splashFactory: NoSplash.splashFactory),
                icon: Icon(AppIcons.clear, size: 20, color: rc.textSecondary),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
