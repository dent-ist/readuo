import 'library_navigation_helpers.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/auth/auth_service.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/main.dart';
import 'package:readuo/screens/account_screen.dart';
import 'package:readuo/screens/library_books_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';

void main() {
  test('library matching normalizes text and ISBN-10/13 editions', () {
    final isbnBook = _book(
      id: 'isbn',
      title: '  A   Distant   Shore ',
      author: 'MAYA Okonkwo',
      isbn: '9780306406157',
    );
    final manualBook = _book(
      id: 'manual',
      title: 'No ISBN Story',
      author: 'River North',
      isbn: null,
    );
    final numberedTitle = _book(
      id: 'numbered',
      title: 'Book 1',
      author: 'Another Writer',
      isbn: '9781984000008',
    );

    expect(
      libraryBookMatches(isbnBook, normalizeLibraryText(' distant shore ')),
      isTrue,
    );
    expect(
      libraryBookMatches(isbnBook, normalizeLibraryText('maya   okonkwo')),
      isTrue,
    );
    expect(
      libraryBookMatches(isbnBook, normalizeLibraryText('0-306-40615-2')),
      isTrue,
    );
    expect(
      libraryBookMatches(isbnBook, normalizeLibraryText('978 0 306 40615 7')),
      isTrue,
    );
    expect(
      libraryBookMatches(isbnBook, normalizeLibraryText('ISBN: 0-306-40615-2')),
      isTrue,
    );
    expect(libraryBookMatches(isbnBook, normalizeLibraryText('40615')), isTrue);
    expect(
      libraryBookMatches(isbnBook, normalizeLibraryText('Book 1')),
      isFalse,
    );
    expect(
      libraryBookMatches(isbnBook, normalizeLibraryText('1984 Orwell')),
      isFalse,
    );
    expect(
      libraryBookMatches(numberedTitle, normalizeLibraryText('Book 1')),
      isTrue,
    );
    expect(
      libraryBookMatches(manualBook, normalizeLibraryText('NO isbn')),
      isTrue,
    );
    expect(
      libraryBookMatches(manualBook, normalizeLibraryText('9780306406157')),
      isFalse,
    );
    expect(
      libraryBookMatches(manualBook, normalizeLibraryText('1984 Orwell')),
      isFalse,
    );
  });

  test('library sorting is deterministic for equal title and author keys', () {
    final books =
        [
          _book(
            id: 'b',
            shelfId: 'two',
            title: 'Dune',
            author: 'Frank Herbert',
          ),
          _book(
            id: 'a',
            shelfId: 'one',
            title: ' dune ',
            author: 'Frank Herbert',
          ),
          _book(id: 'c', title: 'Dune Messiah', author: 'Frank Herbert'),
        ]..sort(
          (left, right) =>
              compareLibraryBooks(left, right, LibraryBookSort.title),
        );

    expect(books.map((book) => book.id), ['a', 'b', 'c']);
  });

  testWidgets('all books filters, sorts, searches, and opens exact entries', (
    tester,
  ) async {
    final books = _LiveBookRepository([
      _book(
        id: 'newest',
        title: 'Dune Messiah',
        author: 'Frank Herbert',
        status: ReadingStatus.wantToRead,
        createdAt: DateTime.utc(2026, 4, 4),
      ),
      _book(
        id: 'edition-two',
        title: 'Dune',
        author: 'Frank Herbert',
        isbn: '9780441172719',
        isOwned: false,
        status: ReadingStatus.reading,
        createdAt: DateTime.utc(2026, 4, 3),
      ),
      _book(
        id: 'edition-one',
        title: 'Dune',
        author: 'Frank Herbert',
        isbn: '9780593099322',
        status: ReadingStatus.reading,
        createdAt: DateTime.utc(2026, 4, 2),
      ),
      _book(
        id: 'manual',
        title: 'A Manual Book',
        author: 'Zed Writer',
        isbn: null,
        createdAt: DateTime.utc(2026, 4, 1),
      ),
    ]);
    LibraryBook? opened;
    String? searched;
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: LibraryBooksScreen(
          ownerId: 'owner',
          bookRepository: books,
          onOpenBook: (book) => opened = book,
          onSearch: (query) async => searched = query,
          onAddBooks: () {},
          showBottomNavigation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4 books'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('all-books-one-newest'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('all-books-one-edition-two')))
            .dy,
      ),
    );

    await tester.tap(find.byKey(const Key('filter-reading')));
    await tester.pumpAndSettle();
    expect(find.text('2 reading'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter-reading')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('filter-reading')))
          .selected,
      isFalse,
    );
    expect(find.text('A Manual Book'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter-reading')));
    await tester.pumpAndSettle();
    expect(find.text('Not owned'), findsOneWidget);
    expect(find.text('A Manual Book'), findsNothing);

    await tester.tap(find.byKey(const Key('sort-books-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-title')));
    await tester.tap(find.byKey(const Key('apply-book-sort')));
    await tester.pumpAndSettle();
    expect(find.text('Title · A to Z'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('all-books-one-edition-one'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('all-books-one-edition-two')))
            .dy,
      ),
    );

    await tester.tap(find.byKey(const Key('all-books-one-edition-two')));
    expect(opened?.id, 'edition-two');
    expect(opened?.isbn, '9780441172719');

    final searchField = find.descendant(
      of: find.byKey(const Key('all-books-search-field')),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, '  DUNE  ');
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('submit-library-search')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('submit-library-search')));
    await tester.pumpAndSettle();
    expect(searched, 'DUNE');

    await tester.tap(find.byKey(const Key('filter-finished')));
    await tester.pumpAndSettle();
    expect(find.text('No books in this status'), findsOneWidget);
    await tester.tap(find.text('Show all books'));
    await tester.pumpAndSettle();
    expect(find.text('4 books'), findsOneWidget);
  });

  testWidgets('library search stays live and links exact containing shelves', (
    tester,
  ) async {
    final firstShelf = _shelf(id: 'one', name: 'Living room', count: 1);
    final secondShelf = _shelf(id: 'two', name: 'Personal', count: 2);
    final shelves = _LiveShelfRepository([firstShelf, secondShelf]);
    final firstEdition = _book(
      id: 'first-edition',
      shelfId: 'one',
      title: 'Dune',
      author: 'Frank Herbert',
      isbn: '9780306406157',
    );
    final secondEdition = _book(
      id: 'second-edition',
      shelfId: 'two',
      title: 'Dune',
      author: 'Frank Herbert',
      isbn: '9780441172719',
      isOwned: false,
    );
    final manual = _book(
      id: 'manual',
      shelfId: 'two',
      title: 'No ISBN Story',
      author: 'River North',
      isbn: null,
    );
    final books = _LiveBookRepository([firstEdition, secondEdition, manual]);
    LibraryBook? openedBook;
    Shelf? openedShelf;
    var catalogueAttempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: LibrarySearchScreen(
          ownerId: 'owner',
          initialQuery: 'DUNE',
          bookRepository: books,
          shelfRepository: shelves,
          onOpenBook: (book) => openedBook = book,
          onOpenShelf: (shelf) => openedShelf = shelf,
          onSearchCatalogue: () => catalogueAttempts += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 books · Owned and saved entries'), findsOneWidget);
    expect(find.byKey(const Key('search-shelf-one')), findsOneWidget);
    expect(find.byKey(const Key('search-shelf-two')), findsOneWidget);
    await tester.tap(find.byKey(const Key('search-book-two-second-edition')));
    expect(openedBook?.id, 'second-edition');
    await tester.tap(find.byKey(const Key('search-shelf-one')));
    expect(openedShelf?.id, 'one');

    books.replace([
      _copyBook(firstEdition, shelfId: 'two'),
      _copyBook(secondEdition, status: ReadingStatus.finished, isOwned: true),
      manual,
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-shelf-one')), findsNothing);
    expect(find.byKey(const Key('search-shelf-two')), findsOneWidget);
    expect(find.text('3 books'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);

    books.replace([_copyBook(firstEdition, shelfId: 'two'), manual]);
    await tester.pumpAndSettle();
    expect(find.text('1 book · Owned and saved entries'), findsOneWidget);
    expect(
      find.byKey(const Key('search-book-two-first-edition')),
      findsOneWidget,
    );

    final searchField = find.descendant(
      of: find.byKey(const Key('library-search-results-field')),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, '0-306-40615-2');
    await tester.tap(find.byKey(const Key('submit-library-search')));
    await tester.pumpAndSettle();
    expect(find.text('1 book · Owned and saved entries'), findsOneWidget);

    await tester.enterText(searchField, '  NO   isbn  ');
    await tester.tap(find.byKey(const Key('submit-library-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-book-two-manual')), findsOneWidget);

    await tester.enterText(searchField, 'missing title');
    await tester.tap(find.byKey(const Key('submit-library-search')));
    await tester.pumpAndSettle();
    expect(find.text('No matches in your library'), findsOneWidget);
    await tester.tap(find.text('Search catalogue'));
    expect(catalogueAttempts, 1);
  });

  testWidgets('all-books route resets when switching root tabs', (
    tester,
  ) async {
    final auth = _TestAuthService();
    final shelves = _LiveShelfRepository([
      _shelf(id: 'one', name: 'Living room', count: 8),
    ]);
    final books = _LiveBookRepository([
      for (var index = 0; index < 8; index += 1)
        _book(
          id: 'book-$index',
          title: 'Book ${String.fromCharCode(72 - index)}',
          author: 'Author ${index + 1}',
          status: index.isEven
              ? ReadingStatus.reading
              : ReadingStatus.wantToRead,
          createdAt: DateTime.utc(2026, 5, index + 1),
        ),
    ]);
    await tester.pumpWidget(
      ReaduoApp(
        authService: auth,
        shelfRepository: shelves,
        bookRepository: books,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('view-all-books')),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('view-all-books'))),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-all-books')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-reading')));
    await tester.tap(find.byKey(const Key('sort-books-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-author')));
    await tester.tap(find.byKey(const Key('apply-book-sort')));
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('all-library-books-list'));
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-friends')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('all-books-result-count')), findsNothing);
    expect(find.byKey(const Key('view-all-books')), findsOneWidget);
    expect(find.byType(ReaduoBottomNavigation), findsOneWidget);
  });

  testWidgets(
    'search book and shelf children reuse one shell bar and restore search',
    (tester) async {
      final shelf = _shelf(id: 'one', name: 'Living room', count: 1);
      await tester.pumpWidget(
        ReaduoApp(
          authService: _TestAuthService(),
          shelfRepository: _LiveShelfRepository([shelf]),
          bookRepository: _LiveBookRepository([
            _book(id: 'dune', title: 'Dune', author: 'Frank Herbert'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('library-search-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('library-search-field')),
        'Dune',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('view-all-books')));
      await tester.pumpAndSettle();
      final navigation = find.byKey(
        const Key('authenticated-bottom-navigation'),
      );
      expect(find.text('Search my library'), findsOneWidget);
      expect(navigation, findsNothing);

      await tester.tap(find.byKey(const Key('search-book-one-dune')));
      await tester.pumpAndSettle();
      expect(find.text('Book details'), findsOneWidget);
      expect(navigation, findsOneWidget);
      expect(find.byType(ReaduoBottomNavigation), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Search my library'), findsOneWidget);
      expect(navigation, findsNothing);

      await tester.tap(find.byKey(const Key('search-shelf-one')));
      await tester.pumpAndSettle();
      expect(find.text('Living room'), findsWidgets);
      expect(navigation, findsOneWidget);
      expect(find.byType(ReaduoBottomNavigation), findsOneWidget);

      await tester.tap(find.byKey(const Key('shelf-settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shelf settings'));
      await tester.pumpAndSettle();
      expect(find.text('Shelf settings'), findsOneWidget);
      expect(navigation, findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(navigation, findsOneWidget);

      await openLibraryScanner(tester);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('scanner-permission-continue')),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan a book'), findsOneWidget);
      expect(navigation, findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(navigation, findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Search my library'), findsOneWidget);
      expect(navigation, findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsWidgets);
      expect(navigation, findsOneWidget);
    },
  );

  testWidgets(
    'signing out from a nested search destination clears all routes',
    (tester) async {
      final auth = _TestAuthService();
      await tester.pumpWidget(
        ReaduoApp(
          authService: auth,
          shelfRepository: _LiveShelfRepository([
            _shelf(id: 'one', name: 'Living room', count: 1),
          ]),
          bookRepository: _LiveBookRepository([
            _book(id: 'dune', title: 'Dune', author: 'Frank Herbert'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-search-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('library-search-field')),
        'Dune',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('view-all-books')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-book-one-dune')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-profile')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('sign-out-button')),
        250,
        scrollable: find
            .descendant(
              of: find.byType(AccountScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('sign-out-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-sign-out')));
      await tester.pumpAndSettle();

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Search my library'), findsNothing);
      expect(find.text('Book details'), findsNothing);
      expect(find.byType(ReaduoBottomNavigation), findsNothing);
    },
  );

  testWidgets('UID switch discards all-books state and isolates entries', (
    tester,
  ) async {
    const secondUser = AuthUser(
      uid: 'second-owner',
      displayName: 'Second Reader',
      email: null,
      photoUrl: null,
      providerIds: {'google.com'},
    );
    final auth = _TestAuthService();
    final shelves = _LiveShelfRepository([
      _shelf(id: 'one', name: 'First shelf', count: 1),
      _shelf(
        id: 'second',
        name: 'Second shelf',
        count: 1,
        ownerId: secondUser.uid,
      ),
    ]);
    final books = _LiveBookRepository([
      _book(id: 'first-private', title: 'First private book'),
      _book(
        id: 'second-private',
        ownerId: secondUser.uid,
        shelfId: 'second',
        title: 'Second private book',
      ),
    ]);
    await tester.pumpWidget(
      ReaduoApp(
        authService: auth,
        shelfRepository: shelves,
        bookRepository: books,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('view-all-books')),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('view-all-books'))),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-all-books')));
    await tester.pumpAndSettle();
    expect(find.text('First private book'), findsOneWidget);
    expect(find.text('Second private book'), findsNothing);

    auth.switchUser(secondUser);
    await tester.pumpAndSettle();

    expect(find.byType(LibraryBooksScreen), findsNothing);
    expect(find.text('First shelf'), findsNothing);
    expect(find.text('Second shelf'), findsOneWidget);
    expect(find.text('First private book'), findsNothing);
  });

  testWidgets('empty library guides bookshelf creation through its FAB', (
    tester,
  ) async {
    await tester.pumpWidget(
      ReaduoApp(
        authService: _TestAuthService(),
        shelfRepository: _LiveShelfRepository([]),
        bookRepository: _LiveBookRepository([]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.byKey(const Key('library-search-button')), findsOneWidget);
    expect(find.byKey(const Key('empty-library-scan')), findsNothing);
    expect(find.byKey(const Key('empty-library-catalogue')), findsNothing);
    expect(find.byKey(const Key('create-shelf-button')), findsNothing);
    expect(find.byKey(const Key('library-add-book-button')), findsNothing);
    await tester.tap(find.byKey(const Key('library-add-fab')));
    await tester.pumpAndSettle();
    expect(find.text('Create Bookshelf'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('library-add-book-button')),
          )
          .onPressed,
      isNull,
    );
  });
}

LibraryBook _book({
  required String id,
  String ownerId = 'owner',
  String shelfId = 'one',
  String title = 'Title',
  String author = 'Author',
  String? isbn,
  bool isOwned = true,
  ReadingStatus status = ReadingStatus.wantToRead,
  DateTime? createdAt,
}) {
  return LibraryBook(
    id: id,
    ownerId: ownerId,
    shelfId: shelfId,
    title: title,
    author: author,
    isbn: isbn,
    isOwned: isOwned,
    readingStatus: status,
    coverUrl: null,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  );
}

LibraryBook _copyBook(
  LibraryBook book, {
  String? shelfId,
  ReadingStatus? status,
  bool? isOwned,
}) {
  return LibraryBook(
    id: book.id,
    ownerId: book.ownerId,
    shelfId: shelfId ?? book.shelfId,
    title: book.title,
    author: book.author,
    isbn: book.isbn,
    isOwned: isOwned ?? book.isOwned,
    readingStatus: status ?? book.readingStatus,
    coverUrl: book.coverUrl,
    createdAt: book.createdAt,
  );
}

Shelf _shelf({
  required String id,
  required String name,
  required int count,
  String ownerId = 'owner',
}) {
  return Shelf(
    id: id,
    ownerId: ownerId,
    name: name,
    description: null,
    visibility: ShelfVisibility.friends,
    autoShareActivity: true,
    bookCount: count,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

class _LiveBookRepository extends EmptyBookRepository {
  _LiveBookRepository(List<LibraryBook> books) : _books = List.of(books);

  List<LibraryBook> _books;
  final _controller = StreamController<List<LibraryBook>>.broadcast();

  List<LibraryBook> get current => List.unmodifiable(_books);

  void replace(List<LibraryBook> books) {
    _books = List.of(books);
    _controller.add(List.unmodifiable(_books));
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
    yield _find(ownerId, shelfId, bookId);
    yield* _controller.stream.map((_) => _find(ownerId, shelfId, bookId));
  }

  List<LibraryBook> _forOwner(String ownerId) =>
      _books.where((book) => book.ownerId == ownerId).toList();

  List<LibraryBook> _forShelf(String ownerId, String shelfId) => _books
      .where((book) => book.ownerId == ownerId && book.shelfId == shelfId)
      .toList();

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
}

class _LiveShelfRepository extends EmptyShelfRepository {
  _LiveShelfRepository(this._shelves);

  final List<Shelf> _shelves;

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) async* {
    yield _shelves.where((shelf) => shelf.ownerId == ownerId).toList();
  }

  @override
  Stream<List<ShelfMutationOperation>> watchShelfOperations(
    String ownerId,
  ) async* {
    yield const [];
  }
}

class _TestAuthService implements AuthService {
  _TestAuthService() : _currentUser = user;

  static const user = AuthUser(
    uid: 'owner',
    displayName: 'Reader',
    email: null,
    photoUrl: null,
    providerIds: {'google.com'},
  );
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;

  void switchUser(AuthUser user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Stream<AuthUser?> get userChanges async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  bool needsDisplayName(AuthUser user) => false;

  @override
  bool shouldStartFirstBookOnboarding(AuthUser user) => false;

  @override
  String? suggestedDisplayName(String uid) => null;

  @override
  Future<AuthSignInResult> signIn(AuthProviderKind provider) async {
    return const AuthSignInResult(isNewUser: false);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  @override
  Future<void> updateDisplayName(String displayName) async {}
}
