import 'package:flutter/widgets.dart';

/// Адаптивность по размеру доступного окна, а не по модели устройства.
///
/// Широкая раскладка (две панели) включается, когда окно не уже
/// [wideBreakpoint] и не ниже [minWideHeight]: iPad в обеих ориентациях и
/// широкое окно Split View; iPhone в ландшафте остаётся одноколоночным.
const double wideBreakpoint = 840;
const double minWideHeight = 480;

/// Ширина колонки со списками в двухпанельной раскладке.
const double listPaneWidth = 380;

/// Максимальная ширина переписки (пузыри не растягиваются на весь iPad).
const double chatContentMaxWidth = 720;

bool isWideWindow(Size size) => size.width >= wideBreakpoint && size.height >= minWideHeight;

/// Метка «этот экран показан в правой панели», а не отдельным окном:
/// стрелка «Назад» там не нужна.
class InDetailPane extends InheritedWidget {
  const InDetailPane({super.key, required super.child});

  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<InDetailPane>() != null;

  @override
  bool updateShouldNotify(InDetailPane oldWidget) => false;
}

/// Ограничивает ширину содержимого и центрирует его. На узком экране
/// ничего не меняет: ширина равна доступной.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = chatContentMaxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < maxWidth ? constraints.maxWidth : maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }
}
