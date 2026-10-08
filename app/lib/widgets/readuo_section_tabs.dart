import 'package:flutter/material.dart';

import '../theme/readuo_theme.dart';

class ReaduoSectionTabs extends StatelessWidget {
  const ReaduoSectionTabs({
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.tabKeys,
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<Key?>? tabKeys;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: ReaduoColors.line)),
    ),
    child: Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Semantics(
              selected: selected == index,
              button: true,
              child: InkWell(
                key: tabKeys?[index],
                onTap: () => onSelected(index),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected == index
                            ? ReaduoColors.accent
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected == index
                          ? ReaduoColors.accent
                          : ReaduoColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
