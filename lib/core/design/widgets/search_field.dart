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
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    return Container(
      constraints: const BoxConstraints(minHeight: 38),
      decoration: BoxDecoration(
        color: rc.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      padding: const EdgeInsets.only(left: Space.m),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 18, color: rc.textTertiary),
          const SizedBox(width: Space.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
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
              if (value.text.isEmpty) return const SizedBox(width: Space.m);
              return IconButton(
                tooltip: 'Очистить',
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
