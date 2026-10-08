import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/book.dart';
import '../theme/readuo_theme.dart';

class BookDescription extends StatelessWidget {
  const BookDescription({required this.book, this.compact = false, super.key});
  final LibraryBook book;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final description = book.description.trim();
    if (compact && description.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Text(
            'Description',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          description.isEmpty
              ? 'No description is available for this edition.'
              : description,
          key: compact ? null : const Key('book-description'),
          maxLines: compact ? 3 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style: const TextStyle(fontSize: 15, height: 1.45),
        ),
      ],
    );
  }
}

class BookEditionMetadata extends StatelessWidget {
  const BookEditionMetadata({required this.book, super.key});
  final LibraryBook book;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (book.publisher.trim().isNotEmpty)
        Text(book.publisher, style: Theme.of(context).textTheme.bodySmall),
      if (book.publishedYear.trim().isNotEmpty)
        Text(
          'Published ${book.publishedYear}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
}

class BookIsbnRow extends StatelessWidget {
  const BookIsbnRow({required this.book, super.key});
  final LibraryBook book;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: ReaduoColors.line),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            book.isbn == null ? 'ISBN not available' : 'ISBN ${book.isbn}',
            key: const Key('book-details-isbn'),
          ),
        ),
        if (book.isbn != null)
          IconButton(
            tooltip: 'Copy ISBN',
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: book.isbn!));
              if (context.mounted)
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('ISBN copied')));
            },
          )
        else
          const SizedBox(height: 48),
      ],
    ),
  );
}
