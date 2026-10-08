import '../library/book.dart';
import '../library/shelf.dart';

class BookAdditionItem {
  const BookAdditionItem({required this.book, required this.shelf});
  final LibraryBook book;
  final Shelf shelf;
}

class BookAdditionPage {
  const BookAdditionPage({
    required this.items,
    this.nextCursor,
    this.watchPaths = const [],
  });
  final List<BookAdditionItem> items;
  final String? nextCursor;
  final List<String> watchPaths;
}
