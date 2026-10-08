import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/screens/isbn_scanner_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';

void main() {
  testWidgets('repeated scan callbacks start only one lookup', (tester) async {
    final lookup = FakeLookupRepository();
    await pumpScanner(tester, lookup: lookup);

    await tester.tap(find.byKey(const Key('fake-scan-twice')));
    await tester.pumpAndSettle();

    expect(lookup.calls, 1);
    expect(find.text('Book found'), findsOneWidget);
  });

  testWidgets('manual ISBN entry validates before catalogue lookup', (
    tester,
  ) async {
    final lookup = FakeLookupRepository();
    await pumpScanner(tester, lookup: lookup);

    await tester.tap(find.byKey(const Key('scanner-enter-isbn')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scan-manual-isbn-field')),
      '9780306406158',
    );
    await tester.tap(find.byKey(const Key('lookup-isbn-button')));
    await tester.pump();

    expect(find.text('Enter a valid ISBN-10 or ISBN-13.'), findsOneWidget);
    expect(lookup.calls, 0);
  });

  testWidgets('camera opens immediately without a Continue screen', (
    tester,
  ) async {
    final lifecycle = ScannerLifecycleProbe();
    await pumpScanner(
      tester,
      scannerBuilder: (_, onCode) =>
          LifecycleScanner(lifecycle: lifecycle, onCode: onCode),
    );
    expect(find.byKey(const Key('scanner-permission-continue')), findsNothing);
    expect(lifecycle.mounts, 1);
  });

  testWidgets('direct ISBN entry repeats without opening the camera', (
    tester,
  ) async {
    final lifecycle = ScannerLifecycleProbe();
    final books = FakeScannedBookRepository();
    await pumpScanner(
      tester,
      books: books,
      startWithManualIsbn: true,
      scannerBuilder: (_, onCode) =>
          LifecycleScanner(lifecycle: lifecycle, onCode: onCode),
    );
    for (var i = 0; i < 2; i++) {
      final field = find.byKey(const Key('scan-manual-isbn-field'));
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, '9780306406157');
      await tester.tap(find.byKey(const Key('lookup-isbn-button')));
      await tester.pumpAndSettle();
      expect(find.text('Add & Enter Another'), findsOneWidget);
      expect(find.text('Add & Finish'), findsOneWidget);
      final add = find.byKey(const Key('lookup-save-another-button'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
    }
    expect(books.inputs, hasLength(2));
    expect(books.lastShelfId, 'target-shelf');
    expect(lifecycle.mounts, 0);
  });

  testWidgets('cancelled lookup ignores a stale result', (tester) async {
    final pending = Completer<BookLookupResult>();
    final lookup = FakeLookupRepository(pending: pending);
    await pumpScanner(tester, lookup: lookup);

    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cancel-isbn-lookup')));
    await tester.pump();

    pending.complete(testLookupResult());
    await tester.pumpAndSettle();
    expect(find.text('Book found'), findsNothing);
    expect(find.byKey(const Key('fake-scan-once')), findsOneWidget);
  });

  testWidgets('friend and locked shelves never become destinations', (
    tester,
  ) async {
    final shelves = FakeShelfRepository([
      testShelf(id: 'friend', ownerId: 'friend-user', name: 'Friend shelf'),
      testShelf(id: 'locked', mutationOperationId: 'operation'),
      testShelf(id: 'mine', name: 'My shelf'),
    ]);
    await pumpScanner(tester, shelves: shelves, initialShelf: null);

    expect(find.text('Where should books go?'), findsOneWidget);
    expect(find.text('My shelf'), findsOneWidget);
    expect(find.text('Friend shelf'), findsNothing);
    expect(find.byKey(const Key('scanner-destination-locked')), findsNothing);
  });

  testWidgets(
    'new shelf callback selects exact shelf and null preserves picker',
    (tester) async {
      final shelves = FakeShelfRepository(const []);
      var createCalls = 0;
      await pumpScanner(
        tester,
        shelves: shelves,
        initialShelf: null,
        onCreateShelf: () async {
          createCalls += 1;
          return createCalls == 1
              ? null
              : testShelf(id: 'new', name: 'Exact new');
        },
      );

      await tester.tap(find.byKey(const Key('scanner-create-first-shelf')));
      await tester.pumpAndSettle();
      expect(find.text('Create your first shelf'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scanner-create-first-shelf')));
      await tester.pumpAndSettle();
      expect(find.text('Adding to “Exact new”'), findsOneWidget);
    },
  );

  testWidgets('save and scan another retains shelf and resets book defaults', (
    tester,
  ) async {
    final books = FakeScannedBookRepository();
    await pumpScanner(tester, books: books);
    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scanner-book-details')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lookup-owned-switch')));
    await tester.tap(find.byKey(const Key('lookup-owned-switch')));
    await tester.ensureVisible(find.byKey(const Key('lookup-status-reading')));
    await tester.tap(find.byKey(const Key('lookup-status-reading')));
    await tester.ensureVisible(
      find.byKey(const Key('lookup-save-another-button')),
    );
    await tester.tap(find.byKey(const Key('lookup-save-another-button')));
    await tester.pumpAndSettle();

    expect(books.inputs, hasLength(1));
    expect(books.lastShelfId, 'target-shelf');
    expect(books.inputs.single.isOwned, isFalse);
    expect(books.inputs.single.readingStatus, ReadingStatus.reading);
    expect(find.byKey(const Key('fake-scan-once')), findsOneWidget);
    expect(find.text('Adding to “Scanned books”'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lookup-save-button')));
    await tester.tap(find.byKey(const Key('lookup-save-button')));
    await tester.pumpAndSettle();
    expect(books.inputs, hasLength(2));
    expect(books.inputs.last.isOwned, isTrue);
    expect(books.inputs.last.readingStatus, ReadingStatus.wantToRead);
    expect(books.activityBatchIds, hasLength(2));
    expect(books.activityBatchIds.toSet(), hasLength(1));
  });

  testWidgets('save failure preserves draft and can retry', (tester) async {
    final books = FakeScannedBookRepository(saveFailures: 1);
    await pumpScanner(
      tester,
      books: books,
      lookup: FakeLookupRepository(
        result: testLookupResult(title: '', author: ''),
      ),
    );
    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lookup-title-field')),
      'Edited title',
    );
    await tester.enterText(
      find.byKey(const Key('lookup-author-field')),
      'Edited author',
    );
    await tester.ensureVisible(
      find.byKey(const Key('lookup-save-another-button')),
    );
    await tester.tap(find.byKey(const Key('lookup-save-another-button')));
    await tester.pumpAndSettle();

    expect(find.text('Save failed. Retry.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('lookup-title-field')))
          .controller!
          .text,
      'Edited title',
    );
    await tester.ensureVisible(
      find.byKey(const Key('lookup-save-another-button')),
    );
    await tester.tap(find.byKey(const Key('lookup-save-another-button')));
    await tester.pumpAndSettle();
    expect(books.inputs.single.title, 'Edited title');
  });

  testWidgets('destination invalidation preserves current confirmation draft', (
    tester,
  ) async {
    final shelves = FakeShelfRepository([testShelf()]);
    await pumpScanner(
      tester,
      shelves: shelves,
      initialShelf: testShelf(),
      lookup: FakeLookupRepository(
        result: testLookupResult(title: '', author: 'Draft author'),
      ),
    );
    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lookup-title-field')),
      'Keep me',
    );

    shelves.emit([
      testShelf(mutationOperationId: 'operation'),
      testShelf(id: 'other', name: 'Other shelf'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Where should books go?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scanner-destination-other')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('lookup-title-field')))
          .controller!
          .text,
      'Keep me',
    );
    expect(find.text('Other shelf'), findsOneWidget);

    shelves.emit([testShelf()]);
    await tester.pumpAndSettle();
    expect(find.text('Where should books go?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scanner-destination-target-shelf')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('lookup-title-field')))
          .controller!
          .text,
      'Keep me',
    );
  });

  testWidgets(
    'duplicate shows exact location and supports view move and scan',
    (tester) async {
      final duplicate = testBook();
      final books = FakeScannedBookRepository(initialBooks: [duplicate]);
      await pumpScanner(
        tester,
        books: books,
        shelves: FakeShelfRepository([
          testShelf(id: 'source', name: 'Existing shelf'),
          testShelf(),
        ]),
        initialShelf: testShelf(),
      );

      await tester.tap(find.byKey(const Key('fake-scan-once')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scanner-duplicate-title')), findsOneWidget);
      expect(
        find.textContaining('Existing shelf · Reading · Owned'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('scanner-view-existing')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('scanner-move-existing')));
      await tester.pumpAndSettle();
      tester
          .widget<ListTile>(
            find.byKey(const Key('scanner-sheet-shelf-target-shelf')),
          )
          .onTap!();
      await tester.pumpAndSettle();
      expect(books.movedBookId, duplicate.id);
      expect(find.byKey(const Key('fake-scan-once')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const Key('fake-scan-once')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('scanner-scan-another-duplicate')),
      );
      await tester.tap(find.byKey(const Key('scanner-scan-another-duplicate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-scan-once')), findsOneWidget);
    },
  );

  testWidgets('lookup failure preserves manual and catalogue alternatives', (
    tester,
  ) async {
    final lookup = FakeLookupRepository(
      failure: const BookLookupFailure(
        BookLookupFailureKind.notFound,
        'No Open Library or Google Books match was found for this ISBN.',
      ),
    );
    Shelf? manualShelf;
    IsbnManualSeed? manualSeed;
    Shelf? catalogueShelf;
    String? catalogueQuery;
    await pumpScanner(
      tester,
      lookup: lookup,
      onManualAdd: (shelf, seed) async {
        manualShelf = shelf;
        manualSeed = seed;
      },
      onCatalogue: (shelf, query) async {
        catalogueShelf = shelf;
        catalogueQuery = query;
      },
    );
    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('lookup-failure-manual-add')));
    await tester.pump();
    await tester.tap(find.text('Search catalogue'));
    expect(manualShelf?.id, 'target-shelf');
    expect(manualSeed?.isbn, '9780306406157');
    expect(manualSeed?.title, isEmpty);
    expect(manualSeed?.author, isEmpty);
    expect(catalogueShelf?.id, 'target-shelf');
    expect(catalogueQuery, '9780306406157');
  });

  testWidgets('lookup failure survives shelf updates and shelf stream errors', (
    tester,
  ) async {
    final shelves = FakeShelfRepository([testShelf()]);
    await pumpScanner(
      tester,
      shelves: shelves,
      initialShelf: testShelf(),
      lookup: FakeLookupRepository(
        failure: const BookLookupFailure(
          BookLookupFailureKind.service,
          'Catalogue service is unavailable.',
        ),
      ),
      onManualAdd: (_, _) async {},
      onCatalogue: (_, _) async {},
    );
    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pumpAndSettle();

    shelves.emit([testShelf(name: 'Renamed shelf')]);
    await tester.pumpAndSettle();
    expect(find.text('Catalogue service is unavailable.'), findsOneWidget);
    expect(find.text('Retry lookup'), findsOneWidget);
    expect(find.byKey(const Key('lookup-failure-manual-add')), findsOneWidget);
    expect(
      find.byKey(const Key('lookup-failure-search-catalogue')),
      findsOneWidget,
    );

    shelves.fail();
    await tester.pumpAndSettle();
    expect(find.text('Choose a shelf'), findsOneWidget);
    expect(find.byKey(const Key('scanner-destination-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('covered routes dispose camera and reject queued detections', (
    tester,
  ) async {
    final lookup = FakeLookupRepository();
    final lifecycle = ScannerLifecycleProbe();
    final catalogue = Completer<void>();
    await pumpScanner(
      tester,
      lookup: lookup,
      scannerBuilder: (_, onCode) =>
          LifecycleScanner(lifecycle: lifecycle, onCode: onCode),
      onCatalogue: (_, _) => catalogue.future,
    );
    expect(lifecycle.mounts, 1);
    final queuedDetection = lifecycle.latestDetection!;

    await tester.tap(find.byKey(const Key('scanner-shelf-selector')));
    await tester.pump();
    expect(lifecycle.disposals, 1);
    queuedDetection('9780306406157');
    await tester.pump();
    expect(lookup.calls, 0);
    tester
        .widget<ListTile>(
          find.byKey(const Key('scanner-sheet-shelf-target-shelf')),
        )
        .onTap!();
    await tester.pumpAndSettle();
    expect(lifecycle.mounts, 2);

    final secondQueuedDetection = lifecycle.latestDetection!;
    await tester.tap(find.byKey(const Key('scanner-search-catalogue')));
    await tester.pump();
    expect(lifecycle.disposals, 2);
    secondQueuedDetection('9780306406157');
    await tester.pump();
    expect(lookup.calls, 0);
    catalogue.complete();
    await tester.pumpAndSettle();
    expect(lifecycle.mounts, 3);
  });

  testWidgets('pending duplicate save disables conflicts and uses snapshot', (
    tester,
  ) async {
    final lookup = FakeLookupRepository();
    final books = PendingSaveBookRepository(
      failure: const DuplicateIsbnFailure(
        title: 'Existing title',
        shelfName: 'Existing shelf',
      ),
    );
    ValueChanged<String>? staleDetection;
    await pumpScanner(
      tester,
      lookup: lookup,
      books: books,
      onCreateShelf: () async => testShelf(id: 'created'),
      scannerBuilder: (_, onCode) {
        staleDetection = onCode;
        return FilledButton(
          key: const Key('fake-scan-once'),
          onPressed: () => onCode('9780306406157'),
          child: const Text('Scan once'),
        );
      },
    );
    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scanner-book-details')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('lookup-save-another-button')),
    );
    await tester.tap(find.byKey(const Key('lookup-save-another-button')));
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('scanner-wrong-book')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('scanner-shelf-selector')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('scanner-create-shelf')))
          .onPressed,
      isNull,
    );
    staleDetection!('0-306-40615-2');
    staleDetection!('9780306406157');
    expect(lookup.calls, 1);

    books.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scanner-duplicate-title')), findsOneWidget);
    expect(books.attempts, 1);
    expect(books.lastInput!.normalizedIsbn, '9780306406157');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending generic save preserves confirmation for retry', (
    tester,
  ) async {
    final books = PendingSaveBookRepository(
      failure: const BookFailure('Offline. Retry the same book.'),
    );
    await pumpScanner(tester, books: books);
    await tester.tap(find.byKey(const Key('fake-scan-once')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lookup-save-button')));
    await tester.tap(find.byKey(const Key('lookup-save-button')));
    await tester.pump();
    books.complete();
    await tester.pumpAndSettle();

    expect(find.text('Offline. Retry the same book.'), findsOneWidget);
    expect(find.text('A Book'), findsWidgets);
    expect(find.byKey(const Key('lookup-save-button')), findsOneWidget);
  });

  testWidgets('large live shelf picker scrolls and rejects a stale row', (
    tester,
  ) async {
    final shelves = FakeShelfRepository([
      for (var index = 0; index < 14; index += 1)
        testShelf(id: 'shelf-$index', name: 'Shelf $index'),
    ]);
    await pumpScanner(
      tester,
      shelves: shelves,
      initialShelf: shelves.current.first,
      size: const Size(360, 640),
      viewPadding: const EdgeInsets.only(bottom: 48),
    );
    await tester.tap(find.byKey(const Key('scanner-shelf-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scanner-shelf-choice-list')), findsOneWidget);
    final shelfScrollable = find
        .descendant(
          of: find.byKey(const Key('scanner-shelf-choice-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('scanner-sheet-shelf-shelf-13')),
      180,
      scrollable: shelfScrollable,
    );
    expect(tester.takeException(), isNull);

    final staleTap = tester
        .widget<ListTile>(find.byKey(const Key('scanner-sheet-shelf-shelf-13')))
        .onTap!;
    shelves.emit(
      shelves.current.where((shelf) => shelf.id != 'shelf-13').toList(),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scanner-sheet-shelf-shelf-13')), findsNothing);
    staleTap();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'That shelf changed before selection. Choose an available shelf.',
      ),
      findsOneWidget,
    );
    expect(find.text('Adding to “Shelf 0”'), findsOneWidget);
  });
}

Future<void> pumpScanner(
  WidgetTester tester, {
  FakeLookupRepository? lookup,
  FakeScannedBookRepository? books,
  FakeShelfRepository? shelves,
  Shelf? initialShelf,
  Future<Shelf?> Function()? onCreateShelf,
  Future<void> Function(Shelf, IsbnManualSeed)? onManualAdd,
  Future<void> Function(Shelf, String)? onCatalogue,
  Future<void> Function(LibraryBook)? onViewExisting,
  IsbnScannerBuilder? scannerBuilder,
  Size? size,
  EdgeInsets? viewPadding,
  bool startWithManualIsbn = false,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final destination = initialShelf ?? testShelf();
  final shelfRepository = shelves ?? FakeShelfRepository([destination]);
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(size: size, padding: viewPadding, viewPadding: viewPadding),
        child: child!,
      ),
      home: IsbnScannerScreen(
        ownerId: 'owner-user',
        startWithManualIsbn: startWithManualIsbn,
        shelfRepository: shelfRepository,
        bookRepository: books ?? FakeScannedBookRepository(),
        lookupRepository: lookup ?? FakeLookupRepository(),
        initialShelf: initialShelf == null && shelves != null
            ? null
            : destination,
        onCreateShelf: onCreateShelf,
        onOpenManualAdd: onManualAdd,
        onSearchCatalogue: onCatalogue,
        onViewExisting: onViewExisting ?? (_) async {},
        scannerBuilder:
            scannerBuilder ??
            (_, onCode) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  key: const Key('fake-scan-once'),
                  onPressed: () => onCode('0-306-40615-2'),
                  child: const Text('Scan once'),
                ),
                FilledButton(
                  key: const Key('fake-scan-twice'),
                  onPressed: () {
                    onCode('0-306-40615-2');
                    onCode('9780306406157');
                  },
                  child: const Text('Scan twice'),
                ),
              ],
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Shelf testShelf({
  String id = 'target-shelf',
  String ownerId = 'owner-user',
  String name = 'Scanned books',
  String? mutationOperationId,
}) => Shelf(
  id: id,
  ownerId: ownerId,
  name: name,
  visibility: ShelfVisibility.private,
  autoShareActivity: false,
  bookCount: 0,
  mutationOperationId: mutationOperationId,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

LibraryBook testBook() => LibraryBook(
  id: 'existing-book',
  ownerId: 'owner-user',
  shelfId: 'source',
  title: 'Existing title',
  author: 'Existing author',
  isbn: '9780306406157',
  isOwned: true,
  readingStatus: ReadingStatus.reading,
  coverUrl: null,
  createdAt: DateTime(2026),
);

BookLookupResult testLookupResult({
  String title = 'A Book',
  String author = 'An Author',
}) => BookLookupResult(
  isbn: '9780306406157',
  title: title,
  author: author,
  publisher: 'Example Press',
  publishedYear: 1981,
  description: 'Description',
  coverUrl: null,
  sourceUrl: 'https://openlibrary.org/isbn/9780306406157',
);

class FakeLookupRepository implements BookLookupRepository {
  FakeLookupRepository({this.pending, this.failure, BookLookupResult? result})
    : result = result ?? testLookupResult();
  final Completer<BookLookupResult>? pending;
  final BookLookupFailure? failure;
  final BookLookupResult result;
  int calls = 0;

  @override
  Future<BookLookupResult> lookup(String isbnInput) async {
    calls += 1;
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return result;
  }
}

class FakeShelfRepository implements ShelfRepository {
  FakeShelfRepository(this.current);
  List<Shelf> current;
  final _changes = StreamController<List<Shelf>>.broadcast();

  void emit(List<Shelf> shelves) {
    current = shelves;
    _changes.add(shelves);
  }

  void fail() => _changes.addError(StateError('offline'));

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) async* {
    yield current;
    yield* _changes.stream;
  }

  @override
  Stream<List<ShelfMutationOperation>> watchShelfOperations(String ownerId) =>
      Stream.value(const []);

  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) => Stream.value(const []);

  @override
  Stream<Shelf?> watchSharedShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) => Stream.value(null);

  @override
  Future<Shelf> createShelf({
    required String ownerId,
    required CreateShelfInput input,
  }) => throw UnimplementedError();

  @override
  Future<void> updateShelf({
    required String ownerId,
    required String shelfId,
    required UpdateShelfInput input,
  }) => throw UnimplementedError();

  @override
  Future<void> moveAllBooksAndDeleteShelf({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteShelfAndBooks({
    required String ownerId,
    required String shelfId,
  }) => throw UnimplementedError();

  @override
  Future<void> resumeShelfOperation({
    required String ownerId,
    required String sourceShelfId,
  }) => throw UnimplementedError();
}

class FakeScannedBookRepository
    implements BookRepository, ActivityBookMutationSource {
  FakeScannedBookRepository({
    this.initialBooks = const [],
    this.saveFailures = 0,
  });
  final List<LibraryBook> initialBooks;
  int saveFailures;
  final List<CreateBookInput> inputs = [];
  final List<String> activityBatchIds = [];
  String? lastShelfId;
  String? movedBookId;

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) =>
      Stream.value(initialBooks);

  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) => Stream.value(null);

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) => _save(shelf: shelf, input: input);

  @override
  Future<void> createBookWithActivityBatch({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
    required String activityBatchId,
  }) async {
    activityBatchIds.add(activityBatchId);
    await _save(shelf: shelf, input: input);
  }

  Future<void> _save({
    required Shelf shelf,
    required CreateBookInput input,
  }) async {
    if (saveFailures > 0) {
      saveFailures -= 1;
      throw const BookFailure('Save failed. Retry.');
    }
    inputs.add(input);
    lastShelfId = shelf.id;
  }

  @override
  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  }) => Stream.value(const []);

  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) => Stream.value(const []);

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
  }) async {
    movedBookId = bookId;
  }

  @override
  Future<void> removeBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required DateTime? expectedCreatedAt,
  }) async {}
}

class PendingSaveBookRepository extends FakeScannedBookRepository {
  PendingSaveBookRepository({required this.failure});
  final BookFailure failure;
  final _pending = Completer<void>();
  int attempts = 0;
  CreateBookInput? lastInput;

  void complete() => _pending.complete();

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) async {
    attempts += 1;
    lastInput = input;
    await _pending.future;
    throw failure;
  }

  @override
  Future<void> createBookWithActivityBatch({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
    required String activityBatchId,
  }) => createBook(ownerId: ownerId, shelf: shelf, input: input);
}

class ScannerLifecycleProbe {
  int mounts = 0;
  int disposals = 0;
  ValueChanged<String>? latestDetection;
}

class LifecycleScanner extends StatefulWidget {
  const LifecycleScanner({
    required this.lifecycle,
    required this.onCode,
    super.key,
  });
  final ScannerLifecycleProbe lifecycle;
  final ValueChanged<String> onCode;

  @override
  State<LifecycleScanner> createState() => _LifecycleScannerState();
}

class _LifecycleScannerState extends State<LifecycleScanner> {
  @override
  void initState() {
    super.initState();
    widget.lifecycle.mounts += 1;
    widget.lifecycle.latestDetection = widget.onCode;
  }

  @override
  void dispose() {
    widget.lifecycle.disposals += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Center(child: Text('Lifecycle scanner')),
  );
}
