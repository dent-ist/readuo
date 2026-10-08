import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/readuo_theme.dart';

class ReaduoTabHeader extends AppBar {
  ReaduoTabHeader({
    required BuildContext context,
    required String title,
    List<ReaduoTabHeaderAction> actions = const [],
    super.key,
  }) : super(
         automaticallyImplyLeading: false,
         centerTitle: false,
         backgroundColor: ReaduoColors.background,
         surfaceTintColor: Colors.transparent,
         elevation: 0,
         scrolledUnderElevation: 0,
         titleSpacing: 16,
         toolbarHeight: _height(context, title, actions),
         title: DefaultTextStyle(
           style: titleStyle,
           child: Text(
             title,
             softWrap: true,
             style: titleStyle,
             textScaler: MediaQuery.textScalerOf(context),
           ),
         ),
         actionsPadding: const EdgeInsetsDirectional.only(end: 16),
         actions: actions,
       );

  static const titleStyle = TextStyle(
    fontSize: 28,
    height: 1.2,
    letterSpacing: -.5,
    fontWeight: FontWeight.w800,
    color: ReaduoColors.ink,
  );

  static double _height(
    BuildContext context,
    String title,
    List<ReaduoTabHeaderAction> actions,
  ) {
    final width =
        MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal -
        32 -
        actions.fold<double>(
          0,
          (width, action) => width + action.width(context),
        ) -
        (actions.isEmpty ? 0 : 16);
    final painter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: math.max(1, width));
    final height = math.max(64.0, painter.height + 24);
    painter.dispose();
    return height;
  }
}

class ReaduoTabHeaderAction extends StatelessWidget {
  const ReaduoTabHeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.label,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;

  double width(BuildContext context) {
    if (label == null) return 48;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final result = painter.width + 64;
    painter.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width(context),
    height: 48,
    child: label != null
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Tooltip(
              message: tooltip,
              child: FilledButton.icon(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: const StadiumBorder(),
                ),
                icon: Icon(icon, size: 18),
                label: Text(label!),
              ),
            ),
          )
        : IconButton.outlined(
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              foregroundColor: ReaduoColors.muted,
              side: const BorderSide(color: ReaduoColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(icon, size: 22),
          ),
  );
}
