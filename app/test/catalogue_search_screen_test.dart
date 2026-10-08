import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/catalogue_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/screens/catalogue_search_screen.dart';

void main() {
  testWidgets('search result confirms selected edition and saves to shelf', (
    tester,
  ) async {
    final books = _RecordingBookRepository();
    await tester.pumpWidget(
      _app(
        repository: _DirectCatalogue(isbn: '9780306406157'),
        books: books,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'A Book',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalogue-results')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('catalogue-work-work')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalogue-confirmation')), findsOneWidget);
    expect(find.text('ISBN 9780306406157'), findsOneWidget);
    await _tapSave(tester);

    expect(books.inputs, hasLength(1));
    expect(books.inputs.single.normalizedIsbn, '9780306406157');
    expect(books.shelfIds, ['shelf-1']);
    expect(find.text('Book saved to “Reading”.'), findsOneWidget);
  });

  testWidgets('no-ISBN result requires explicit manual confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(repository: _DirectCatalogue(isbn: null)));

    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'Archive Notes',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No ISBN — manual entry'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('catalogue-work-work')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalogue-manual-warning')), findsOneWidget);
    expect(find.text('ISBN not provided'), findsOneWidget);
  });

  testWidgets('duplicate save error keeps confirmation draft', (tester) async {
    final books = _RecordingBookRepository(
      failure: const DuplicateIsbnFailure(
        title: 'Existing Book',
        shelfName: 'Reading',
      ),
    );
    await tester.pumpWidget(
      _app(
        repository: _DirectCatalogue(isbn: '9780306406157'),
        books: books,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'A Book',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalogue-work-work')));
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(
      find.text('This ISBN is already saved as “Existing Book” on “Reading”.'),
      findsOneWidget,
    );
    expect(find.text('A Book'), findsOneWidget);
    expect(find.byKey(const Key('catalogue-confirmation')), findsOneWidget);
  });

  testWidgets('work result requires selecting a specific ISBN edition', (
    tester,
  ) async {
    final books = _RecordingBookRepository();
    await tester.pumpWidget(_app(repository: _WorkCatalogue(), books: books));
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'A Book',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalogue-work-work')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalogue-editions')), findsOneWidget);
    expect(find.text('ISBN 9780306406157'), findsOneWidget);
    expect(find.text('ISBN 9780140328721'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('catalogue-edition-edition-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalogue-save-button')));
    await tester.pumpAndSettle();

    expect(books.inputs.single.normalizedIsbn, '9780140328721');
  });

  testWidgets('new shelf is auto-selected without losing the draft', (
    tester,
  ) async {
    final shelves = _MutableShelfRepository();
    final books = _RecordingBookRepository();
    await tester.pumpWidget(
      _app(
        repository: _DirectCatalogue(isbn: null),
        books: books,
        shelves: shelves,
        initialShelf: null,
        onCreateShelf: () async {
          shelves.add(_shelf);
          return _shelf;
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'A Book',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalogue-work-work')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('catalogue-title-field')),
      'My retained title',
    );

    await tester.tap(find.byKey(const Key('catalogue-create-shelf')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('catalogue-title-field')))
          .controller!
          .text,
      'My retained title',
    );
    expect(find.text('Reading'), findsOneWidget);
    await _tapSave(tester);
    expect(books.shelfIds, ['shelf-1']);
    expect(books.inputs.single.title, 'My retained title');
  });

  testWidgets('a stale search response cannot replace the latest results', (
    tester,
  ) async {
    final repository = _DeferredCatalogue();
    await tester.pumpWidget(_app(repository: repository));

    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'first',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'second',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    repository.complete('second', 'Latest result');
    await tester.pumpAndSettle();
    repository.complete('first', 'Stale result');
    await tester.pumpAndSettle();

    expect(find.text('Latest result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
  });

  testWidgets('clearing search invalidates a pending response', (tester) async {
    final repository = _DeferredCatalogue();
    await tester.pumpWidget(_app(repository: repository));
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'first',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    await tester.enterText(find.byKey(const Key('catalogue-query-field')), '');
    await tester.pump();
    repository.complete('first', 'Late result');
    await tester.pumpAndSettle();

    expect(find.text('Find your next addition'), findsOneWidget);
    expect(find.text('Late result'), findsNothing);
  });

  testWidgets('no-results uses canonical accent mark and secondary action', (
    tester,
  ) async {
    await tester.pumpWidget(_app(repository: const _EmptyCatalogue()));
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'Unknown title',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();

    expect(find.text('No catalogue matches'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('catalogue-empty-mark'))),
      const Size.square(72),
    );
    expect(find.widgetWithText(OutlinedButton, 'Add manually'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add manually'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Enter an ISBN'), findsOneWidget);
  });

  testWidgets('edition Back restores exact work continuation offset', (
    tester,
  ) async {
    final repository = _PagingCatalogue();
    await tester.pumpWidget(_app(repository: repository));
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'books',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalogue-work-work-0')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catalogue-results')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalogue-load-more')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('catalogue-results')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('catalogue-load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalogue-load-more')));
    await tester.pumpAndSettle();

    expect(repository.searchOffsets, [0, 8]);
    expect(repository.searchProviders.last, CatalogueProvider.openLibrary);
    expect(find.text('Book 8'), findsOneWidget);
  });

  testWidgets(
    'opening a work cancels pending continuation and retries prior offset',
    (tester) async {
      final repository = _PendingWorkContinuationCatalogue();
      await tester.pumpWidget(_app(repository: repository));
      await tester.enterText(
        find.byKey(const Key('catalogue-query-field')),
        'books',
      );
      await tester.tap(find.byKey(const Key('catalogue-search-button')));
      await tester.pumpAndSettle();
      final resultsScrollable = find.descendant(
        of: find.byKey(const Key('catalogue-results')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('catalogue-load-more')),
        300,
        scrollable: resultsScrollable,
      );

      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('catalogue-load-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalogue-load-more')));
      await tester.pump();
      tester.state<ScrollableState>(resultsScrollable).position.jumpTo(0);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('catalogue-work-work-0')));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final restoredScrollable = find.descendant(
        of: find.byKey(const Key('catalogue-results')),
        matching: find.byType(Scrollable),
      );
      final restoredPosition = tester
          .state<ScrollableState>(restoredScrollable)
          .position;
      restoredPosition.jumpTo(restoredPosition.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('catalogue-load-more')),
            )
            .onPressed,
        isNotNull,
      );

      repository.completeStaleContinuation();
      await tester.pumpAndSettle();
      expect(find.text('Late book'), findsNothing);
      restoredPosition.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Book 0'), findsOneWidget);
      restoredPosition.jumpTo(restoredPosition.maxScrollExtent);
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('catalogue-load-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalogue-load-more')));
      await tester.pumpAndSettle();

      expect(repository.searchOffsets, [0, 8, 8]);
      expect(repository.searchProviders.skip(1), [
        CatalogueProvider.openLibrary,
        CatalogueProvider.openLibrary,
      ]);
      expect(find.text('Book 8'), findsOneWidget);
    },
  );

  testWidgets('failed work continuation retains results and retries offset', (
    tester,
  ) async {
    final repository = _PagingCatalogue(failFirstContinuation: true);
    await tester.pumpWidget(_app(repository: repository));
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'books',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();
    final resultsScrollable = find.descendant(
      of: find.byKey(const Key('catalogue-results')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalogue-load-more')),
      300,
      scrollable: resultsScrollable,
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('catalogue-load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalogue-load-more')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalogue-work-continuation-error')),
      findsOneWidget,
    );
    expect(find.text('Retry loading matches'), findsOneWidget);
    tester.state<ScrollableState>(resultsScrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Book 0'), findsOneWidget);
    final position = tester.state<ScrollableState>(resultsScrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('catalogue-load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalogue-load-more')));
    await tester.pumpAndSettle();

    expect(repository.searchOffsets, [0, 8, 8]);
    expect(find.text('Book 8'), findsOneWidget);
  });

  testWidgets('new search invalidates an in-flight edition continuation', (
    tester,
  ) async {
    final repository = _EditionDeferredCatalogue();
    await tester.pumpWidget(_app(repository: repository));
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'first',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalogue-work-work')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalogue-editions-load-more')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'second',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    repository.completeMore();
    await tester.pumpAndSettle();

    expect(find.text('Second result'), findsOneWidget);
    expect(find.text('Late edition'), findsNothing);
  });

  testWidgets('cancelled shelf creation never selects an unrelated shelf', (
    tester,
  ) async {
    final shelves = _MutableShelfRepository();
    final books = _RecordingBookRepository();
    await tester.pumpWidget(
      _app(
        repository: _DirectCatalogue(isbn: null),
        books: books,
        shelves: shelves,
        initialShelf: null,
        onCreateShelf: () async {
          shelves.add(_unrelatedShelf);
          return null;
        },
      ),
    );
    await _openDirectResult(tester);
    await tester.tap(find.byKey(const Key('catalogue-create-shelf')));
    await tester.pumpAndSettle();
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.text('Choose a shelf before saving.'), findsOneWidget);
    expect(books.inputs, isEmpty);
  });

  testWidgets('multiple shelf arrivals select only the returned shelf', (
    tester,
  ) async {
    final shelves = _MutableShelfRepository();
    final books = _RecordingBookRepository();
    await tester.pumpWidget(
      _app(
        repository: _DirectCatalogue(isbn: null),
        books: books,
        shelves: shelves,
        initialShelf: null,
        onCreateShelf: () async {
          shelves.add(_unrelatedShelf);
          shelves.add(_shelf);
          return _shelf;
        },
      ),
    );
    await _openDirectResult(tester);
    await tester.tap(find.byKey(const Key('catalogue-create-shelf')));
    await tester.pumpAndSettle();
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(books.shelfIds, ['shelf-1']);
  });

  testWidgets('confirmation remains scrollable with keyboard insets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(repository: _DirectCatalogue(isbn: null)));
    await tester.enterText(
      find.byKey(const Key('catalogue-query-field')),
      'A Book',
    );
    await tester.tap(find.byKey(const Key('catalogue-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalogue-work-work')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catalogue-title-field')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('catalogue-save-button'))).height,
      greaterThanOrEqualTo(48),
    );
  });
}

Future<void> _openDirectResult(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('catalogue-query-field')),
    'A Book',
  );
  await tester.tap(find.byKey(const Key('catalogue-search-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('catalogue-work-work')));
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  final saveButton = find.byKey(const Key('catalogue-save-button'));
  for (
    var attempt = 0;
    attempt < 5 && saveButton.evaluate().isEmpty;
    attempt++
  ) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
  }
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}

Widget _app({
  required CatalogueRepository repository,
  BookRepository? books,
  ShelfRepository? shelves,
  Shelf? initialShelf = _shelf,
  Future<Shelf?> Function()? onCreateShelf,
}) {
  return MaterialApp(
    home: CatalogueSearchScreen(
      ownerId: 'owner',
      catalogueRepository: repository,
      shelfRepository: shelves ?? _ShelfRepository(),
      bookRepository: books ?? _RecordingBookRepository(),
      initialShelf: initialShelf,
      onCreateShelf: onCreateShelf,
    ),
  );
}

const _shelf = Shelf(
  id: 'shelf-1',
  ownerId: 'owner',
  name: 'Reading',
  visibility: ShelfVisibility.private,
  autoShareActivity: false,
  bookCount: 0,
  createdAt: null,
  updatedAt: null,
);

const _unrelatedShelf = Shelf(
  id: 'unrelated',
  ownerId: 'owner',
  name: 'Unrelated',
  visibility: ShelfVisibility.private,
  autoShareActivity: false,
  bookCount: 0,
  createdAt: null,
  updatedAt: null,
);

class _ShelfRepository extends EmptyShelfRepository {
  @override
  Stream<List<Shelf>> watchShelves(String ownerId) => Stream.value([_shelf]);
}

class _MutableShelfRepository extends EmptyShelfRepository {
  final List<Shelf> _items = [];
  final StreamController<List<Shelf>> _controller =
      StreamController<List<Shelf>>.broadcast();

  void add(Shelf shelf) {
    _items.add(shelf);
    _controller.add([..._items]);
  }

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) async* {
    yield [..._items];
    yield* _controller.stream;
  }
}

class _RecordingBookRepository extends EmptyBookRepository {
  _RecordingBookRepository({this.failure});

  final BookFailure? failure;
  final List<CreateBookInput> inputs = [];
  final List<String> shelfIds = [];

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) async {
    inputs.add(input);
    shelfIds.add(shelf.id);
    if (failure != null) throw failure!;
  }
}

class _DirectCatalogue implements CatalogueRepository {
  _DirectCatalogue({required this.isbn});

  final String? isbn;

  CatalogueEdition get edition => CatalogueEdition(
    id: 'edition',
    title: 'A Book',
    author: 'An Author',
    isbn: isbn,
    publisher: 'Press',
    publishedYear: 1981,
    format: 'Hardcover',
    description: null,
    coverUrl: null,
    sourceUrl: 'https://openlibrary.org/books/OL1M',
    provider: CatalogueProvider.openLibrary,
  );

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async => CatalogueSearchPage(
    items: [
      CatalogueWork(
        id: 'work',
        title: edition.title,
        author: edition.author,
        provider: edition.provider,
        editionCount: 1,
        edition: edition,
      ),
    ],
    offset: offset,
    hasMore: false,
    provider: CatalogueProvider.openLibrary,
  );

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) async =>
      CatalogueEditionPage(items: [edition], offset: offset, hasMore: false);
}

class _EmptyCatalogue implements CatalogueRepository {
  const _EmptyCatalogue();

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async => const CatalogueSearchPage(
    items: [],
    offset: 0,
    hasMore: false,
    provider: CatalogueProvider.openLibrary,
  );

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) async => const CatalogueEditionPage(items: [], offset: 0, hasMore: false);
}

class _WorkCatalogue implements CatalogueRepository {
  CatalogueEdition _edition(String id, String isbn) => CatalogueEdition(
    id: id,
    title: 'A Book',
    author: 'An Author',
    isbn: isbn,
    publisher: null,
    publishedYear: null,
    format: null,
    description: null,
    coverUrl: null,
    sourceUrl: 'https://openlibrary.org/books/$id',
    provider: CatalogueProvider.openLibrary,
  );

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async => const CatalogueSearchPage(
    items: [
      CatalogueWork(
        id: 'work',
        title: 'A Book',
        author: 'An Author',
        provider: CatalogueProvider.openLibrary,
        editionCount: 2,
      ),
    ],
    offset: 0,
    hasMore: false,
    provider: CatalogueProvider.openLibrary,
  );

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) async => CatalogueEditionPage(
    items: [
      _edition('edition-1', '9780306406157'),
      _edition('edition-2', '9780140328721'),
    ],
    offset: 0,
    hasMore: false,
  );
}

class _PagingCatalogue implements CatalogueRepository {
  _PagingCatalogue({this.failFirstContinuation = false});

  final bool failFirstContinuation;
  final List<int> searchOffsets = [];
  final List<CatalogueProvider?> searchProviders = [];
  bool _failedContinuation = false;

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async {
    searchOffsets.add(offset);
    searchProviders.add(provider);
    if (offset > 0 && failFirstContinuation && !_failedContinuation) {
      _failedContinuation = true;
      throw const CatalogueFailure(
        CatalogueFailureKind.network,
        'Could not load the next page.',
      );
    }
    final count = offset == 0 ? 8 : 1;
    return CatalogueSearchPage(
      items: [
        for (var index = 0; index < count; index += 1)
          CatalogueWork(
            id: 'work-${offset + index}',
            title: 'Book ${offset + index}',
            author: 'Author',
            provider: CatalogueProvider.openLibrary,
            editionCount: 1,
          ),
      ],
      offset: offset,
      hasMore: offset == 0,
      provider: CatalogueProvider.openLibrary,
    );
  }

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) async => CatalogueEditionPage(
    items: [
      CatalogueEdition(
        id: 'edition-${work.id}',
        title: work.title,
        author: work.author,
        isbn: '9780306406157',
        publisher: null,
        publishedYear: null,
        format: null,
        description: null,
        coverUrl: null,
        sourceUrl: 'https://openlibrary.org/books/OL1M',
        provider: CatalogueProvider.openLibrary,
      ),
    ],
    offset: offset,
    hasMore: false,
  );
}

class _PendingWorkContinuationCatalogue implements CatalogueRepository {
  final Completer<CatalogueSearchPage> _staleContinuation =
      Completer<CatalogueSearchPage>();
  final List<int> searchOffsets = [];
  final List<CatalogueProvider?> searchProviders = [];
  var _continuationCalls = 0;

  void completeStaleContinuation() => _staleContinuation.complete(
    const CatalogueSearchPage(
      items: [
        CatalogueWork(
          id: 'late',
          title: 'Late book',
          author: 'Late author',
          provider: CatalogueProvider.openLibrary,
          editionCount: 1,
        ),
      ],
      offset: 8,
      hasMore: false,
      provider: CatalogueProvider.openLibrary,
    ),
  );

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) {
    searchOffsets.add(offset);
    searchProviders.add(provider);
    if (offset == 0) {
      return Future.value(
        CatalogueSearchPage(
          items: [
            for (var index = 0; index < 8; index += 1)
              CatalogueWork(
                id: 'work-$index',
                title: 'Book $index',
                author: 'Author',
                provider: CatalogueProvider.openLibrary,
                editionCount: 1,
              ),
          ],
          offset: 0,
          hasMore: true,
          provider: CatalogueProvider.openLibrary,
        ),
      );
    }
    _continuationCalls += 1;
    if (_continuationCalls == 1) return _staleContinuation.future;
    return Future.value(
      const CatalogueSearchPage(
        items: [
          CatalogueWork(
            id: 'work-8',
            title: 'Book 8',
            author: 'Author',
            provider: CatalogueProvider.openLibrary,
            editionCount: 1,
          ),
        ],
        offset: 8,
        hasMore: false,
        provider: CatalogueProvider.openLibrary,
      ),
    );
  }

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) async => CatalogueEditionPage(
    items: [
      CatalogueEdition(
        id: 'edition-${work.id}',
        title: work.title,
        author: work.author,
        isbn: '9780306406157',
        publisher: null,
        publishedYear: null,
        format: null,
        description: null,
        coverUrl: null,
        sourceUrl: 'https://openlibrary.org/books/OL1M',
        provider: CatalogueProvider.openLibrary,
      ),
    ],
    offset: offset,
    hasMore: false,
  );
}

class _EditionDeferredCatalogue implements CatalogueRepository {
  final Completer<CatalogueEditionPage> _more =
      Completer<CatalogueEditionPage>();

  void completeMore() => _more.complete(
    const CatalogueEditionPage(
      items: [
        CatalogueEdition(
          id: 'late',
          title: 'Late edition',
          author: 'Author',
          isbn: '9780140328721',
          publisher: null,
          publishedYear: null,
          format: null,
          description: null,
          coverUrl: null,
          sourceUrl: 'https://openlibrary.org/books/late',
          provider: CatalogueProvider.openLibrary,
        ),
      ],
      offset: 20,
      hasMore: false,
    ),
  );

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async => CatalogueSearchPage(
    items: [
      CatalogueWork(
        id: query == 'second' ? 'second' : 'work',
        title: query == 'second' ? 'Second result' : 'First result',
        author: 'Author',
        provider: CatalogueProvider.openLibrary,
        editionCount: 2,
      ),
    ],
    offset: 0,
    hasMore: false,
    provider: CatalogueProvider.openLibrary,
  );

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) {
    if (offset > 0) return _more.future;
    return Future.value(
      const CatalogueEditionPage(
        items: [
          CatalogueEdition(
            id: 'first',
            title: 'First edition',
            author: 'Author',
            isbn: '9780306406157',
            publisher: null,
            publishedYear: null,
            format: null,
            description: null,
            coverUrl: null,
            sourceUrl: 'https://openlibrary.org/books/first',
            provider: CatalogueProvider.openLibrary,
          ),
        ],
        offset: 0,
        hasMore: true,
      ),
    );
  }
}

class _DeferredCatalogue implements CatalogueRepository {
  final Map<String, Completer<CatalogueSearchPage>> _completers = {};

  void complete(String query, String title) {
    _completers[query]!.complete(
      CatalogueSearchPage(
        items: [
          CatalogueWork(
            id: title,
            title: title,
            author: 'Author',
            provider: CatalogueProvider.openLibrary,
            editionCount: 1,
          ),
        ],
        offset: 0,
        hasMore: false,
        provider: CatalogueProvider.openLibrary,
      ),
    );
  }

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) => (_completers[query] ??= Completer<CatalogueSearchPage>()).future;

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) async => const CatalogueEditionPage(items: [], offset: 0, hasMore: false);
}
