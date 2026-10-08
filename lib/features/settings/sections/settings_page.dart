import 'package:flutter/material.dart';

import '../../../core/design/context.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/form.dart';
import '../../../core/design/widgets/top_bar.dart';

/// Страница раздела настроек: шапка с «Назад» и список.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ReplikaTopBar(
        leading: const BackIconButton(),
        title: Text(title, style: context.tt.titleMedium),
      ),
      body: ListView(
        padding: listPadding(context, const EdgeInsets.only(bottom: Space.xl)),
        children: children,
      ),
    );
  }
}

/// Пояснение мелким текстом под группой настроек.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l + 4, Space.s, Space.l + 4, 0),
      child: Text(text, style: context.tt.bodySmall?.copyWith(color: context.rc.textSecondary)),
    );
  }
}
