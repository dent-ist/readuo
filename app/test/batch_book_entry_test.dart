import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/screens/isbn_scanner_screen.dart';
import 'package:readuo/screens/shelf_details_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'isbn_scanner_test.dart' show FakeShelfRepository, FakeLookupRepository;
import 'manual_book_test.dart' show FakeBookRepository, testShelf;
import 'memory_preferences.dart';

void main() {
  for (final width in [390.0, 360.0]) {
    testWidgets('shelf menu and repeated manual entry at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, width == 360 ? 640 : 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await runBatchBookEntryChecks(tester);
    });
  }
}

Future<void> runBatchBookEntryChecks(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  useMemoryPreferences();
  final shelf = testShelf(name: 'Quiet reads');
  final books = FakeBookRepository();
  final shelves = FakeShelfRepository([shelf]);
  Future<void> tap(String key) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final button = find.byKey(Key(key));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ReaduoTheme.modern,
      home: ShelfDetailsScreen(
        ownerId: shelf.ownerId,
        shelf: shelf,
        shelfRepository: shelves,
        bookRepository: books,
        bookLookupRepository: FakeLookupRepository(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final fab = tester.widget<FloatingActionButton>(
    find.byKey(const Key('add-book-button')),
  );
  expect(fab.isExtended, isFalse);
  expect(fab.shape, isA<CircleBorder>());
  if (capture != null) await capture('shelf');
  await tap('add-book-button');
  for (final label in [
    'Scan ISBN',
    'Enter ISBN',
    'Search Catalogue',
    'Add Manually',
  ]) {
    expect(find.text(label).hitTestable(), findsOneWidget);
  }
  if (capture != null) await capture('shelf-menu');
  await tap('shelf-enter-isbn-choice');
  expect(find.byType(CameraIsbnScanner), findsNothing);
  if (capture != null) await capture('enter-isbn');
  await tester.enterText(
    find.byKey(const Key('scan-manual-isbn-field')),
    '9780306406157',
  );
  await tap('lookup-isbn-button');
  if (capture != null) await capture('isbn-confirmation');
  await tap('lookup-save-another-button');
  expect(books.createdCount, 1);
  expect(find.byType(CameraIsbnScanner), findsNothing);
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('scan-manual-isbn-field')))
        .controller!
        .text,
    isEmpty,
  );
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tap('add-book-button');
  await tap('shelf-manual-choice');
  for (var i = 0; i < 2; i++) {
    final title = find.byKey(const Key('book-title-field'));
    expect(tester.widget<TextFormField>(title).controller!.text, isEmpty);
    await tester.enterText(title, 'Manual book ${i + 1}');
    await tester.enterText(
      find.byKey(const Key('book-author-field')),
      'A Reader',
    );
    await tap('manual-next-button');
    expect(find.text('Quiet reads'), findsWidgets);
    if (i == 0 && capture != null) await capture('manual-confirmation');
    await tap(i == 0 ? 'save-book-another-button' : 'save-book-button');
    if (i == 0 && capture != null) await capture('manual-next-entry');
  }
  expect(books.createdCount, 3);
  expect(books.lastShelfId, shelf.id);
  expect(find.byType(ShelfDetailsScreen), findsOneWidget);
  expect(find.byKey(const Key('book-title-field')), findsNothing);
  expect(tester.takeException(), isNull);

  // Drive recognized barcodes through the real scanner flow with a camera fixture.
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ReaduoTheme.modern,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('open-batch-scanner'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => IsbnScannerScreen(
                    ownerId: shelf.ownerId,
                    initialShelf: shelf,
                    shelfRepository: shelves,
                    bookRepository: FakeBookRepository(),
                    lookupRepository: _BatchLookup(),
                    scannerBuilder: (_, onCode) => Center(
                      child: FilledButton(
                        key: const Key('recognize-barcode'),
                        onPressed: () => onCode('9780156012195'),
                        child: const Text('Recognize sample barcode'),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Scan ISBN'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tap('open-batch-scanner');
  await tap('recognize-barcode');
  expect(find.text('Add & Scan Next'), findsOneWidget);
  if (capture != null) await capture('scan-confirmation');
  await tap('lookup-save-another-button');
  expect(
    find.byKey(const Key('recognize-barcode')).hitTestable(),
    findsOneWidget,
  );
  expect(find.byKey(const Key('scanner-scan-next')), findsNothing);
  await tap('recognize-barcode');
  // The repository rejects duplicate ISBNs without leaving the flow.
  await tap('lookup-save-another-button');
  expect(find.byKey(const Key('scanner-duplicate-title')), findsOneWidget);
  await tap('scanner-scan-another-duplicate');
  expect(find.byKey(const Key('recognize-barcode')), findsOneWidget);
  await tap('close-scanner');
  expect(find.byKey(const Key('open-batch-scanner')), findsOneWidget);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

class _BatchLookup implements BookLookupRepository {
  @override
  Future<BookLookupResult> lookup(String isbnInput) async => BookLookupResult(
    isbn: isbnInput,
    title: 'The Little Prince',
    author: 'Antoine de Saint-Exupéry',
    publisher: null,
    publishedYear: null,
    description: null,
    coverUrl: null,
    sourceUrl: '',
  );
}
