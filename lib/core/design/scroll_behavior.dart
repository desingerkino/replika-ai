import 'package:flutter/material.dart';

/// Прокрутка как в iOS на обеих платформах: пружинящий край и никакого
/// «свечения» Android. Списки прокручиваются, даже если короче экрана, —
/// так работает «потяните, чтобы обновить».
class ReplikaScrollBehavior extends MaterialScrollBehavior {
  const ReplikaScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
