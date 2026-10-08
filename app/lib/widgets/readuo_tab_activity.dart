import 'package:flutter/widgets.dart';

class ReaduoTabActivity extends InheritedWidget {
  const ReaduoTabActivity({
    required this.active,
    required super.child,
    super.key,
  });

  final bool active;

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaduoTabActivity>()?.active ??
      true;

  @override
  bool updateShouldNotify(ReaduoTabActivity oldWidget) =>
      active != oldWidget.active;
}
