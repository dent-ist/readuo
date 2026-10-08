import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/auth/auth_service.dart';
import 'package:readuo/circle/review_repository.dart';
import 'package:readuo/friends/friend_repository.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/main.dart';
import 'package:readuo/screens/book_details_screen.dart';
import 'package:readuo/screens/my_library_screen.dart';
import 'package:readuo/screens/shelf_details_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';

void main() {
  const ownerId = 'owner';
  final firstBook = book(
    id: 'first',
    title: 'First saved title',
    author: 'First Author',
    isbn: '9780306406157',
  );
  final secondBook = book(
    id: 'second',
    title: 'The actual selected book',
    author: 'Selected Author',
    isbn: '9780140328721',
    isOwned: false,
    readingStatus: ReadingStatus.reading,
  );

  testWidgets(
    'library preview and shelf grid open the exact selected identity',
    (tester) async {
      final books = MemoryBookRepository([firstBook, secondBook]);
      final shelves = MemoryShelfRepository([testShelf()]);
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: MyLibraryScreen(
            authService: const TestAuthService(),
            shelfRepository: shelves,
            bookRepository: books,
            bookLookupRepository: const EmptyBookLookupRepository(),
            friendRepository: const EmptyFriendRepository(),
            user: TestAuthService.user,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final secondPreview = find.byKey(
        const Key('library-book-shelf-one-second'),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(secondPreview);
      await tester.pumpAndSettle();
      expect(find.text('The actual selected book'), findsOneWidget);
      expect(find.text('Selected Author'), findsOneWidget);
      expect(find.text('ISBN 9780140328721'), findsOneWidget);
      expect(books.lastWatchedBookId, 'second');
      final selectedShelfRow = find.byKey(const Key('book-shelf-row'));
      await tester.scrollUntilVisible(selectedShelfRow, 250);
      await tester.tap(selectedShelfRow);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-book-button')), findsOneWidget);
      expect(find.text('Living room'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Book details'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('write-review-button')),
        250,
      );
      await tester.drag(
        find.byKey(const Key('book-details-scroll')),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Share a written review with your friends. A star rating is optional.',
        ),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      final shelfCard = find.byKey(const Key('shelf-shelf-one'));
      await tester.drag(find.byType(ListView).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.tap(shelfCard);
      await tester.pumpAndSettle();
      final firstTile = find.byKey(const Key('shelf-book-first'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(firstTile);
      await tester.pumpAndSettle();
      expect(find.text('First saved title'), findsOneWidget);
      expect(find.text('ISBN 9780306406157'), findsOneWidget);
      expect(books.lastWatchedBookId, 'first');
      final firstShelfRow = find.byKey(const Key('book-shelf-row'));
      await tester.scrollUntilVisible(firstShelfRow, 250);
      await tester.tap(firstShelfRow);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-book-button')), findsOneWidget);
    },
  );

  testWidgets('shell bar persists across book detail tab actions and Back', (
    tester,
  ) async {
    final books = MemoryBookRepository([firstBook]);
    await tester.pumpWidget(
      ReaduoApp(
        authService: const TestAuthService(),
        shelfRepository: MemoryShelfRepository([testShelf()]),
        bookRepository: books,
      ),
    );
    await tester.pumpAndSettle();
    final navigation = find.byKey(const Key('authenticated-bottom-navigation'));
    final navigationElement = tester.element(navigation);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-book-shelf-one-first')));
    await tester.pumpAndSettle();

    expect(find.text('Book details'), findsOneWidget);
    expect(find.byType(ReaduoBottomNavigation), findsOneWidget);
    expect(tester.element(navigation), same(navigationElement));
    await tester.tap(find.byKey(const Key('nav-friends')));
    await tester.pumpAndSettle();
    expect(find.text('Book details'), findsNothing);
    expect(tester.element(navigation), same(navigationElement));
    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pumpAndSettle();
    expect(find.text('Book details'), findsOneWidget);
    expect(tester.element(navigation), same(navigationElement));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Book details'), findsNothing);
    expect(
      tester.widget<ReaduoBottomNavigation>(navigation).active,
      ReaduoNavDestination.library,
    );
  });

  testWidgets('status and ownership update independently and stream live', (
    tester,
  ) async {
    final books = MemoryBookRepository([firstBook]);
    await pumpDetails(tester, books: books);

    final ownershipToggle = find.byKey(const Key('book-ownership-toggle'));
    await tester.scrollUntilVisible(ownershipToggle, 300);
    await Scrollable.ensureVisible(
      tester.element(ownershipToggle),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(ownershipToggle);
    await tester.pumpAndSettle();
    expect(books.current('first')!.isOwned, false);
    expect(books.current('first')!.readingStatus, ReadingStatus.wantToRead);

    await tester.scrollUntilVisible(
      find.byKey(const Key('change-reading-status-button')),
      -200,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('change-reading-status-button'))),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-reading-status-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reading-status-finished')));
    await tester.tap(find.byKey(const Key('save-reading-status-button')));
    await tester.pumpAndSettle();

    expect(books.current('first')!.readingStatus, ReadingStatus.finished);
    expect(books.current('first')!.isOwned, false);
    await tester.drag(
      find.byKey(const Key('book-details-scroll')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Not owned'), findsOneWidget);
  });

  testWidgets('failed status and ownership edits retain drafts for retry', (
    tester,
  ) async {
    final books = MemoryBookRepository(
      [firstBook],
      statusFailuresRemaining: 1,
      ownershipFailuresRemaining: 1,
    );
    await pumpDetails(tester, books: books);

    final ownershipToggle = find.byKey(const Key('book-ownership-toggle'));
    await tester.scrollUntilVisible(ownershipToggle, 300);
    await Scrollable.ensureVisible(
      tester.element(ownershipToggle),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(ownershipToggle);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('book-ownership-toggle')),
          )
          .value,
      false,
    );
    expect(find.text('Retry ownership change'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('Retry ownership change')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry ownership change'));
    await tester.pumpAndSettle();
    expect(books.current('first')!.isOwned, false);

    await tester.scrollUntilVisible(
      find.byKey(const Key('change-reading-status-button')),
      -200,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('change-reading-status-button'))),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-reading-status-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reading-status-finished')));
    await tester.tap(find.byKey(const Key('save-reading-status-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reading-status-error')), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<ReadingStatus>>(
            find.byType(RadioGroup<ReadingStatus>),
          )
          .groupValue,
      ReadingStatus.finished,
    );
    await tester.tap(find.byKey(const Key('save-reading-status-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reading-status-error')), findsNothing);
    expect(books.current('first')!.readingStatus, ReadingStatus.finished);
  });

  testWidgets('moves one exact book and retains the destination after retry', (
    tester,
  ) async {
    final shelves = MemoryShelfRepository([
      testShelf(),
      testShelf(
        id: 'destination',
        name: 'Finished favorites',
        bookCount: 3,
        visibility: ShelfVisibility.private,
      ),
    ]);
    final books = MemoryBookRepository(
      [firstBook],
      moveFailuresRemaining: 1,
      onMoved: shelves.applyMove,
    );
    var createShelfCalls = 0;
    await pumpDetails(
      tester,
      books: books,
      shelves: shelves,
      onCreateShelf: () async {
        createShelfCalls += 1;
      },
    );

    await tester.tap(find.byKey(const Key('book-options-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to another shelf'));
    await tester.pumpAndSettle();

    expect(find.text('Move to a shelf'), findsOneWidget);
    expect(find.text('Living room'), findsNothing);
    expect(find.text('Finished favorites'), findsOneWidget);
    expect(find.text('3 books · Private'), findsOneWidget);
    expect(
      find.byKey(const Key('create-book-move-shelf-button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('create-book-move-shelf-button')));
    expect(createShelfCalls, 1);

    await tester.tap(find.byKey(const Key('move-book-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('move-book-error')), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'destination',
    );
    await tester.tap(find.byKey(const Key('move-book-button')));
    await tester.pumpAndSettle();

    final moved = books.current('first')!;
    expect(moved.shelfId, 'destination');
    expect(moved.id, firstBook.id);
    expect(moved.isbn, firstBook.isbn);
    expect(moved.isOwned, firstBook.isOwned);
    expect(moved.readingStatus, firstBook.readingStatus);
    expect(moved.createdAt, firstBook.createdAt);
    expect(books.lastMoveSourceId, 'shelf-one');
    expect(books.lastMoveDestinationId, 'destination');
    expect(find.text('On Finished favorites'), findsOneWidget);
    expect(shelves.current('shelf-one')!.bookCount, 1);
    expect(shelves.current('destination')!.bookCount, 4);
    expect(shelves.current('shelf-one')!.visibility, ShelfVisibility.friends);
    expect(shelves.current('destination')!.visibility, ShelfVisibility.private);
  });

  testWidgets(
    'remove confirmation cancels safely, retries, and unwinds one detail route',
    (tester) async {
      final shelves = MemoryShelfRepository([testShelf()]);
      final books = MemoryBookRepository(
        [firstBook, secondBook],
        removeFailuresRemaining: 1,
        onRemoved: shelves.applyRemoval,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open-book-details'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BookDetailsScreen(
                        ownerId: ownerId,
                        shelfId: 'shelf-one',
                        bookId: 'first',
                        shelfRepository: shelves,
                        bookRepository: books,
                        showBottomNavigation: false,
                      ),
                    ),
                  ),
                  child: const Text('Open details'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-book-details')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book-options-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manage-book-remove')));
      await tester.pumpAndSettle();
      final removeSheet = find.byKey(const Key('remove-book-sheet'));
      expect(find.text('Remove from your library?'), findsOneWidget);
      expect(
        find.descendant(
          of: removeSheet,
          matching: find.text('First saved title'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: removeSheet, matching: find.text('First Author')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: removeSheet,
          matching: find.text('ISBN 9780306406157'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('keep-book-button')));
      await tester.pumpAndSettle();
      expect(books.current('first'), isNotNull);
      expect(shelves.current('shelf-one')!.bookCount, 2);
      expect(find.text('Book details'), findsOneWidget);

      await tester.tap(find.byKey(const Key('book-options-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manage-book-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-book-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('remove-book-error')), findsOneWidget);
      expect(books.current('first'), isNotNull);
      expect(shelves.current('shelf-one')!.bookCount, 2);

      await tester.tap(find.byKey(const Key('remove-book-button')));
      await tester.pumpAndSettle();
      expect(find.text('Book details'), findsNothing);
      expect(find.byKey(const Key('open-book-details')), findsOneWidget);
      expect(books.current('first'), isNull);
      expect(books.current('second'), same(secondBook));
      expect(shelves.current('shelf-one')!.bookCount, 1);
      expect(books.lastRemovedShelfId, 'shelf-one');
      expect(books.lastRemovalExpectedCreatedAt, firstBook.createdAt);
    },
  );

  testWidgets('locked shelf explains the operation and disables both edits', (
    tester,
  ) async {
    final books = MemoryBookRepository([firstBook]);
    final shelves = MemoryShelfRepository([testShelf()]);
    await pumpDetails(tester, books: books, shelves: shelves);
    shelves.lock();
    await tester.pumpAndSettle();

    expect(find.textContaining('Book edits are paused'), findsOneWidget);
    expect(find.text('Return to Library to continue'), findsOneWidget);
    final statusButton = find.byKey(const Key('change-reading-status-button'));
    await tester.scrollUntilVisible(statusButton, 300);
    expect(tester.widget<OutlinedButton>(statusButton).onPressed, isNull);
    final ownershipToggle = find.byKey(const Key('book-ownership-toggle'));
    await tester.scrollUntilVisible(ownershipToggle, 200);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('book-ownership-toggle')),
          )
          .onChanged,
      isNull,
    );
  });

  testWidgets('deleted or moved source becomes a missing state', (
    tester,
  ) async {
    final books = MemoryBookRepository([firstBook]);
    await pumpDetails(tester, books: books);
    books.remove('first');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missing-book-message')), findsOneWidget);
    expect(
      find.textContaining('may have moved or been removed'),
      findsOneWidget,
    );
  });

  testWidgets('shelf status filter reacts to a streamed detail update', (
    tester,
  ) async {
    final books = MemoryBookRepository([firstBook]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: ShelfDetailsScreen(
          ownerId: ownerId,
          shelf: testShelf(),
          shelfRepository: MemoryShelfRepository([testShelf()]),
          bookRepository: books,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Want to read').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-book-first')), findsOneWidget);

    await books.updateReadingStatus(
      ownerId: ownerId,
      shelfId: 'shelf-one',
      bookId: 'first',
      readingStatus: ReadingStatus.finished,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-book-first')), findsNothing);
    expect(find.text('No books with this status.'), findsOneWidget);
  });

  testWidgets(
    'book details renders, edits, and confirms deletion of a review',
    (tester) async {
      final books = MemoryBookRepository([firstBook]);
      final review = CircleReview(
        id: circleReviewId(ownerId, firstBook.id),
        authorId: ownerId,
        shelfId: firstBook.shelfId,
        bookId: firstBook.id,
        bookCreatedAt: firstBook.createdAt!,
        title: firstBook.title,
        bookAuthor: firstBook.author,
        coverUrl: null,
        text: 'My exact-edition review.',
        rating: 4,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final reviews = _ReviewRepositoryFake(review);
      await pumpDetails(tester, books: books, reviews: reviews);

      await tester.scrollUntilVisible(
        find.byKey(const Key('own-book-review')),
        250,
      );
      expect(find.text('My exact-edition review.'), findsOneWidget);
      expect(find.text('Edit review'), findsOneWidget);
      await tester.tap(find.byKey(const Key('write-review-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('circle-edit-review')), findsOneWidget);
      expect(find.text('My exact-edition review.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('delete-review-button')),
        250,
      );
      await tester.tap(find.byKey(const Key('delete-review-button')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this review?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-delete-review')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own-book-review')), findsNothing);
      expect(reviews.deletedReviewId, review.id);
    },
  );
}

Future<void> pumpDetails(
  WidgetTester tester, {
  required MemoryBookRepository books,
  MemoryShelfRepository? shelves,
  ReviewRepository reviews = const EmptyReviewRepository(),
  Future<void> Function()? onCreateShelf,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: BookDetailsScreen(
        ownerId: 'owner',
        shelfId: 'shelf-one',
        bookId: 'first',
        shelfRepository: shelves ?? MemoryShelfRepository([testShelf()]),
        bookRepository: books,
        reviewRepository: reviews,
        onCreateShelf: onCreateShelf,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ReviewRepositoryFake implements ReviewRepository {
  _ReviewRepositoryFake(this.review);

  CircleReview? review;
  String? deletedReviewId;
  final _controller = StreamController<CircleReview?>.broadcast();

  @override
  Stream<CircleReview?> watchReview({
    required String viewerId,
    required String authorId,
    required String bookId,
  }) async* {
    yield review;
    yield* _controller.stream;
  }

  @override
  Future<CircleReviewDraft?> loadDraft({
    required String ownerId,
    required String reviewId,
  }) async => null;

  @override
  Future<void> saveDraft({
    required String ownerId,
    required CircleReviewDraft draft,
  }) async {}

  @override
  Future<void> clearDraft({
    required String ownerId,
    required String reviewId,
  }) async {}

  @override
  Future<void> publishDraft({
    required String authorId,
    required CircleReviewDraft draft,
  }) async {}

  @override
  Future<void> deleteReview({
    required String authorId,
    required String reviewId,
  }) async {
    deletedReviewId = reviewId;
    review = null;
    _controller.add(null);
  }

  @override
  Stream<List<CircleReview>> watchReviewsForAuthor({
    required String viewerId,
    required String authorId,
  }) => Stream.value(review == null ? const [] : [review!]);
}

LibraryBook book({
  required String id,
  required String title,
  required String author,
  String? isbn,
  bool isOwned = true,
  ReadingStatus readingStatus = ReadingStatus.wantToRead,
  String shelfId = 'shelf-one',
}) => LibraryBook(
  id: id,
  ownerId: 'owner',
  shelfId: shelfId,
  title: title,
  author: author,
  isbn: isbn,
  isOwned: isOwned,
  readingStatus: readingStatus,
  coverUrl: null,
  createdAt: DateTime(2026),
);

Shelf testShelf({
  String id = 'shelf-one',
  String name = 'Living room',
  int bookCount = 2,
  ShelfVisibility visibility = ShelfVisibility.friends,
  String? mutationOperationId,
}) => Shelf(
  id: id,
  ownerId: 'owner',
  name: name,
  visibility: visibility,
  autoShareActivity: visibility != ShelfVisibility.private,
  bookCount: bookCount,
  mutationOperationId: mutationOperationId,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class MemoryShelfRepository extends EmptyShelfRepository {
  MemoryShelfRepository(List<Shelf> shelves) : _shelves = List.of(shelves);

  List<Shelf> _shelves;
  final _controller = StreamController<List<Shelf>>.broadcast();

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) async* {
    yield List.unmodifiable(_shelves);
    yield* _controller.stream;
  }

  void lock() {
    _shelves = [testShelf(mutationOperationId: 'operation-one')];
    _controller.add(List.unmodifiable(_shelves));
  }

  Shelf? current(String shelfId) {
    for (final shelf in _shelves) {
      if (shelf.id == shelfId) return shelf;
    }
    return null;
  }

  void applyMove(String sourceShelfId, String destinationShelfId) {
    _shelves = _shelves.map((shelf) {
      if (shelf.id == sourceShelfId) {
        return _copyShelf(shelf, bookCount: shelf.bookCount - 1);
      }
      if (shelf.id == destinationShelfId) {
        return _copyShelf(shelf, bookCount: shelf.bookCount + 1);
      }
      return shelf;
    }).toList();
    _controller.add(List.unmodifiable(_shelves));
  }

  void applyRemoval(String shelfId) {
    _shelves = _shelves.map((shelf) {
      return shelf.id == shelfId
          ? _copyShelf(shelf, bookCount: shelf.bookCount - 1)
          : shelf;
    }).toList();
    _controller.add(List.unmodifiable(_shelves));
  }

  Shelf _copyShelf(Shelf shelf, {required int bookCount}) => Shelf(
    id: shelf.id,
    ownerId: shelf.ownerId,
    name: shelf.name,
    description: shelf.description,
    visibility: shelf.visibility,
    autoShareActivity: shelf.autoShareActivity,
    bookCount: bookCount,
    mutationOperationId: shelf.mutationOperationId,
    createdAt: shelf.createdAt,
    updatedAt: shelf.updatedAt,
  );
}

class MemoryBookRepository extends EmptyBookRepository {
  MemoryBookRepository(
    List<LibraryBook> books, {
    this.statusFailuresRemaining = 0,
    this.ownershipFailuresRemaining = 0,
    this.moveFailuresRemaining = 0,
    this.removeFailuresRemaining = 0,
    this.onMoved,
    this.onRemoved,
  }) : _books = List.of(books);

  final List<LibraryBook> _books;
  final _controller = StreamController<List<LibraryBook>>.broadcast();
  int statusFailuresRemaining;
  int ownershipFailuresRemaining;
  int moveFailuresRemaining;
  int removeFailuresRemaining;
  final void Function(String sourceShelfId, String destinationShelfId)? onMoved;
  final void Function(String shelfId)? onRemoved;
  String? lastWatchedBookId;
  String? lastMoveSourceId;
  String? lastMoveDestinationId;
  String? lastRemovedShelfId;
  DateTime? lastRemovalExpectedCreatedAt;

  LibraryBook? current(String bookId) {
    for (final book in _books) {
      if (book.id == bookId) return book;
    }
    return null;
  }

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) async* {
    yield _forOwner(ownerId);
    yield* _controller.stream.map(
      (books) => books.where((book) => book.ownerId == ownerId).toList(),
    );
  }

  @override
  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  }) async* {
    yield _forShelf(ownerId, shelfId);
    yield* _controller.stream.map(
      (books) => books
          .where((book) => book.ownerId == ownerId && book.shelfId == shelfId)
          .toList(),
    );
  }

  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) async* {
    lastWatchedBookId = bookId;
    yield _find(ownerId, shelfId, bookId);
    yield* _controller.stream.map((_) => _find(ownerId, shelfId, bookId));
  }

  @override
  Future<void> updateReadingStatus({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required ReadingStatus readingStatus,
  }) async {
    if (statusFailuresRemaining > 0) {
      statusFailuresRemaining -= 1;
      throw const BookFailure('Could not update status. Please retry.');
    }
    final existing = _required(ownerId, shelfId, bookId);
    _replace(existing, readingStatus: readingStatus);
  }

  @override
  Future<void> updateOwnership({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required bool isOwned,
  }) async {
    if (ownershipFailuresRemaining > 0) {
      ownershipFailuresRemaining -= 1;
      throw const BookFailure('Could not update ownership. Please retry.');
    }
    final existing = _required(ownerId, shelfId, bookId);
    _replace(existing, isOwned: isOwned);
  }

  @override
  Future<void> moveBook({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
    required String bookId,
  }) async {
    if (moveFailuresRemaining > 0) {
      moveFailuresRemaining -= 1;
      throw const BookFailure('Could not move this book. Please retry.');
    }
    final existing = _required(ownerId, sourceShelfId, bookId);
    if (_find(ownerId, destinationShelfId, bookId) != null) {
      throw const BookFailure('The destination already contains this book.');
    }
    lastMoveSourceId = sourceShelfId;
    lastMoveDestinationId = destinationShelfId;
    final index = _books.indexOf(existing);
    _books[index] = LibraryBook(
      id: existing.id,
      ownerId: existing.ownerId,
      shelfId: destinationShelfId,
      title: existing.title,
      author: existing.author,
      isbn: existing.isbn,
      isOwned: existing.isOwned,
      readingStatus: existing.readingStatus,
      coverUrl: existing.coverUrl,
      createdAt: existing.createdAt,
    );
    onMoved?.call(sourceShelfId, destinationShelfId);
    _controller.add(List.unmodifiable(_books));
  }

  @override
  Future<void> removeBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required DateTime? expectedCreatedAt,
  }) async {
    if (removeFailuresRemaining > 0) {
      removeFailuresRemaining -= 1;
      throw const BookFailure('Could not remove this book. Please retry.');
    }
    final existing = _required(ownerId, shelfId, bookId);
    if (existing.createdAt != expectedCreatedAt) {
      throw const BookFailure('This saved entry changed after confirmation.');
    }
    lastRemovedShelfId = shelfId;
    lastRemovalExpectedCreatedAt = expectedCreatedAt;
    _books.remove(existing);
    onRemoved?.call(shelfId);
    _controller.add(List.unmodifiable(_books));
  }

  void remove(String bookId) {
    _books.removeWhere((book) => book.id == bookId);
    _controller.add(List.unmodifiable(_books));
  }

  LibraryBook _required(String ownerId, String shelfId, String bookId) {
    final existing = _find(ownerId, shelfId, bookId);
    if (existing == null) {
      throw const BookFailure('This saved book is no longer on this shelf.');
    }
    return existing;
  }

  LibraryBook? _find(String ownerId, String shelfId, String bookId) {
    for (final book in _books) {
      if (book.ownerId == ownerId &&
          book.shelfId == shelfId &&
          book.id == bookId) {
        return book;
      }
    }
    return null;
  }

  List<LibraryBook> _forOwner(String ownerId) =>
      _books.where((book) => book.ownerId == ownerId).toList();

  List<LibraryBook> _forShelf(String ownerId, String shelfId) => _books
      .where((book) => book.ownerId == ownerId && book.shelfId == shelfId)
      .toList();

  void _replace(
    LibraryBook existing, {
    ReadingStatus? readingStatus,
    bool? isOwned,
  }) {
    final index = _books.indexOf(existing);
    _books[index] = LibraryBook(
      id: existing.id,
      ownerId: existing.ownerId,
      shelfId: existing.shelfId,
      title: existing.title,
      author: existing.author,
      isbn: existing.isbn,
      isOwned: isOwned ?? existing.isOwned,
      readingStatus: readingStatus ?? existing.readingStatus,
      coverUrl: existing.coverUrl,
      createdAt: existing.createdAt,
    );
    _controller.add(List.unmodifiable(_books));
  }
}

class TestAuthService implements AuthService {
  const TestAuthService();

  static const user = AuthUser(
    uid: 'owner',
    displayName: 'Owner',
    email: null,
    photoUrl: null,
    providerIds: {},
  );

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> get userChanges => Stream.value(user);

  @override
  bool needsDisplayName(AuthUser user) => false;

  @override
  bool shouldStartFirstBookOnboarding(AuthUser user) => false;

  @override
  Future<AuthSignInResult> signIn(AuthProviderKind provider) async =>
      const AuthSignInResult(isNewUser: false);

  @override
  Future<void> signOut() async {}

  @override
  String? suggestedDisplayName(String uid) => null;

  @override
  Future<void> updateDisplayName(String displayName) async {}
}
