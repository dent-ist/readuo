import 'package:flutter/material.dart';

import '../library/book.dart';
import '../theme/readuo_theme.dart';
import 'book_cover_image.dart';
import 'book_information.dart';
import 'generated_book_cover.dart';

class LibrarySearchResult extends StatelessWidget {
  const LibrarySearchResult({
    required this.book,
    required this.shelfName,
    required this.onTap,
    super.key,
  });
  final LibraryBook book;
  final String shelfName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            height: 168,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: book.coverUrl == null
                  ? GeneratedBookCover(title: book.title, author: book.author)
                  : BookCoverImage(
                      book.coverUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => GeneratedBookCover(
                        title: book.title,
                        author: book.author,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(book.author),
                const SizedBox(height: 8),
                Text(
                  book.readingStatus.label,
                  style: const TextStyle(color: ReaduoColors.accent),
                ),
                const SizedBox(height: 8),
                Text(shelfName, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                BookDescription(book: book, compact: true),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
