import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/book_repository.dart';
import 'book_information.dart';

class CircleBookMetadata extends StatefulWidget {
  const CircleBookMetadata({
    required this.repository,
    required this.ownerId,
    required this.shelfId,
    required this.bookId,
    required this.onOpen,
    this.showDescription = true,
    super.key,
  });
  final BookRepository repository;
  final String ownerId;
  final String shelfId;
  final String bookId;
  final ValueChanged<LibraryBook> onOpen;
  final bool showDescription;

  @override
  State<CircleBookMetadata> createState() => _CircleBookMetadataState();
}

class _CircleBookMetadataState extends State<CircleBookMetadata> {
  late var _book = _watch();
  Stream<LibraryBook?> _watch() => widget.repository.watchBook(
    ownerId: widget.ownerId,
    shelfId: widget.shelfId,
    bookId: widget.bookId,
  );

  @override
  void didUpdateWidget(covariant CircleBookMetadata oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.ownerId != widget.ownerId ||
        oldWidget.shelfId != widget.shelfId ||
        oldWidget.bookId != widget.bookId)
      _book = _watch();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<LibraryBook?>(
    key: ValueKey(_book),
    stream: _book,
    builder: (context, snapshot) {
      final book = snapshot.data;
      if (snapshot.hasError || book == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          if (widget.showDescription)
            BookEditionMetadata(book: book)
          else
            Text(
              [
                if (book.publisher.trim().isNotEmpty) book.publisher,
                if (book.publishedYear.trim().isNotEmpty) book.publishedYear,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (widget.showDescription)
            BookDescription(book: book, compact: true),
          TextButton(
            onPressed: () => widget.onOpen(book),
            child: const Text('Book details ›'),
          ),
        ],
      );
    },
  );
}
