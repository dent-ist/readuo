import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/screens/shelf_details_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';

void main() {
  testWidgets('manual add is preselected, defaults owned, and persists', (
    tester,
  ) async {
    final repository = FakeBookRepository();
    final selectedShelf = testShelf(id: 'reading', name: 'Current reads');
    await pumpShelf(tester, repository, selectedShelf);

    expect(find.text('This shelf is empty'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-book-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-manual-choice')));
    await tester.pumpAndSettle();

    expect(find.text('Add a book'), findsOneWidget);
    expect(find.byKey(const Key('add-cover-photo')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('book-title-field')),
      'The Little Prince',
    );
    await tester.enterText(
      find.byKey(const Key('book-author-field')),
      'Antoine de Saint-Exupéry',
    );
    await tester.enterText(
      find.byKey(const Key('book-isbn-field')),
      '0-15-601219-7',
    );
    await tapSaveBook(tester);
    await tester.pumpAndSettle();

    expect(repository.lastShelfId, selectedShelf.id);
    expect(repository.lastOwnerId, selectedShelf.ownerId);
    expect(repository.lastInput!.isOwned, isTrue);
    expect(repository.lastInput!.readingStatus, ReadingStatus.wantToRead);
    expect(repository.lastInput!.normalizedIsbn, '9780156012195');
    expect(find.text('The Little Prince'), findsOneWidget);
    expect(find.text('Want to read'), findsWidgets);
    expect(find.text('Owned'), findsOneWidget);
  });

  testWidgets('manual add validates required fields and ISBN checksum', (
    tester,
  ) async {
    final repository = FakeBookRepository();
    await pumpShelf(tester, repository, testShelf());
    await tester.tap(find.byKey(const Key('add-book-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-manual-choice')));
    await tester.pumpAndSettle();

    await tapSaveBook(tester);
    await tester.pump();
    expect(find.text('Enter a book title.'), findsOneWidget);
    expect(find.text('Enter an author.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('book-title-field')), 'Book');
    await tester.enterText(
      find.byKey(const Key('book-author-field')),
      'Author',
    );
    await tester.enterText(
      find.byKey(const Key('book-isbn-field')),
      '9780306406158',
    );
    await tapSaveBook(tester);
    await tester.pump();
    expect(find.text('Enter a valid ISBN-10 or ISBN-13.'), findsOneWidget);
    expect(repository.lastInput, isNull);
  });

  testWidgets('duplicate ISBN reports the existing title and shelf', (
    tester,
  ) async {
    final repository = FakeBookRepository(
      isbnLocations: const {
        '9780306406157': ('Existing edition', 'Finished books'),
      },
    );
    await pumpShelf(tester, repository, testShelf());
    await tester.tap(find.byKey(const Key('add-book-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-manual-choice')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('book-title-field')),
      'Duplicate',
    );
    await tester.enterText(
      find.byKey(const Key('book-author-field')),
      'Author',
    );
    await tester.enterText(
      find.byKey(const Key('book-isbn-field')),
      '0306406152',
    );
    await tapSaveBook(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This ISBN is already saved as “Existing edition” on “Finished books”.',
      ),
      findsOneWidget,
    );
    expect(find.text('Duplicate'), findsNWidgets(2));
    expect(repository.createdCount, 0);
  });

  testWidgets('same-title books without ISBN remain distinct copies', (
    tester,
  ) async {
    final existing = LibraryBook(
      id: 'first-copy',
      ownerId: 'owner-user',
      shelfId: 'shelf-one',
      title: 'Shared title',
      author: 'First Author',
      isbn: null,
      isOwned: true,
      readingStatus: ReadingStatus.finished,
      coverUrl: null,
      createdAt: DateTime(2026),
    );
    final repository = FakeBookRepository(initialBooks: [existing]);
    await pumpShelf(tester, repository, testShelf());
    await tester.tap(find.byKey(const Key('add-book-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-manual-choice')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('book-title-field')),
      'Shared title',
    );
    await tester.enterText(
      find.byKey(const Key('book-author-field')),
      'Second Author',
    );
    expect(find.byKey(const Key('same-title-warning')), findsOneWidget);
    await tapSaveBook(tester);
    await tester.pumpAndSettle();

    expect(find.text('Shared title'), findsNWidgets(2));
    expect(repository.createdCount, 1);
  });
}

Future<void> pumpShelf(
  WidgetTester tester,
  FakeBookRepository repository,
  Shelf shelf,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: ShelfDetailsScreen(
        ownerId: shelf.ownerId,
        shelf: shelf,
        bookRepository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapSaveBook(WidgetTester tester) async {
  if (tester.testTextInput.isRegistered) tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final next = find.byKey(const Key('manual-next-button'));
  if (next.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      next,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(next);
    await tester.pumpAndSettle();
  }
  final button = find.byKey(const Key('save-book-button'));
  if (button.evaluate().isEmpty) return;
  await tester.scrollUntilVisible(
    button,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  final separate = find.text('Add as a separate entry');
  if (separate.evaluate().isNotEmpty) {
    await tester.tap(separate);
    await tester.pumpAndSettle();
  }
}

Shelf testShelf({String id = 'shelf-one', String name = 'My shelf'}) {
  return Shelf(
    id: id,
    ownerId: 'owner-user',
    name: name,
    visibility: ShelfVisibility.private,
    autoShareActivity: false,
    bookCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

class FakeBookRepository implements BookRepository {
  FakeBookRepository({
    List<LibraryBook> initialBooks = const [],
    Map<String, (String, String)> isbnLocations = const {},
  }) : _books = List.of(initialBooks),
       _isbnLocations = Map.of(isbnLocations);

  final List<LibraryBook> _books;
  final Map<String, (String, String)> _isbnLocations;
  final StreamController<List<LibraryBook>> _controller =
      StreamController<List<LibraryBook>>.broadcast();
  String? lastOwnerId;
  String? lastShelfId;
  CreateBookInput? lastInput;
  int createdCount = 0;

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) => Stream.value(
    List.unmodifiable(_books.where((book) => book.ownerId == ownerId)),
  );

  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) => Stream.value(
    _books.cast<LibraryBook?>().firstWhere(
      (book) =>
          book?.ownerId == ownerId &&
          book?.shelfId == shelfId &&
          book?.id == bookId,
      orElse: () => null,
    ),
  );

  @override
  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  }) async* {
    yield List.unmodifiable(
      _books.where(
        (book) => book.ownerId == ownerId && book.shelfId == shelfId,
      ),
    );
    yield* _controller.stream.map(
      (books) => List.unmodifiable(
        books.where(
          (book) => book.ownerId == ownerId && book.shelfId == shelfId,
        ),
      ),
    );
  }

  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) => Stream.value(const []);

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) async {
    lastOwnerId = ownerId;
    lastShelfId = shelf.id;
    lastInput = input;
    final isbn = input.normalizedIsbn;
    final existing = isbn == null ? null : _isbnLocations[isbn];
    if (existing != null) {
      throw DuplicateIsbnFailure(title: existing.$1, shelfName: existing.$2);
    }
    createdCount += 1;
    final book = LibraryBook(
      id: isbn ?? 'copy-$createdCount',
      ownerId: ownerId,
      shelfId: shelf.id,
      title: input.title.trim(),
      author: input.author.trim(),
      isbn: isbn,
      isOwned: input.isOwned,
      readingStatus: input.readingStatus,
      coverUrl: null,
      createdAt: DateTime.now(),
    );
    _books.add(book);
    if (isbn != null) _isbnLocations[isbn] = (book.title, shelf.name);
    _controller.add(List.unmodifiable(_books));
  }

  @override
  Future<void> updateReadingStatus({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required ReadingStatus readingStatus,
  }) async {}

  @override
  Future<void> updateOwnership({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required bool isOwned,
  }) async {}

  @override
  Future<void> moveBook({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
    required String bookId,
  }) async {}

  @override
  Future<void> removeBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required DateTime? expectedCreatedAt,
  }) async {}
}
