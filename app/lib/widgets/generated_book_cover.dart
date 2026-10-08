import 'package:flutter/material.dart';

class GeneratedBookCover extends StatelessWidget {
  const GeneratedBookCover({required this.title, this.author = '', super.key});
  final String title;
  final String author;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 65;
      final colors = [
        const Color(0xFF184B61),
        const Color(0xFFAB5834),
        const Color(0xFF33385E),
        const Color(0xFF416071),
      ];
      final color =
          colors[title.codeUnits.fold<int>(0, (sum, value) => sum + value) %
              colors.length];
      return Container(
        padding: EdgeInsets.all(compact ? 5 : 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: .85)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: RichText(
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  text: title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 7 : 12,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            if (author.isNotEmpty)
              RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  text: author,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 5 : 8,
                    height: 1.1,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
