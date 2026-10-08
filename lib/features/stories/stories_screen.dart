import 'package:flutter/material.dart';

import '../../core/design/context.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';

/// Вкладка «Истории»: пока заглушка без данных.
class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.cs.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const ScreenHeader(title: 'Истории'),
            Expanded(
              child: EmptyState(
                icon: Icons.motion_photos_on_outlined,
                title: 'Историй пока нет',
                message: 'Здесь появятся истории ваших контактов.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
