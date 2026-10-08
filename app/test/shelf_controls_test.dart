import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/catalogue_repository.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/screens/catalogue_search_screen.dart';
import 'package:readuo/screens/isbn_scanner_screen.dart';
import 'package:readuo/screens/shelf_details_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/main.dart';
import 'memory_preferences.dart';
import 'widget_test.dart' show FakeAuthService, user;
import 'manual_book_test.dart' show FakeBookRepository, testShelf, tapSaveBook;

void main() {
  testWidgets('speed dial exposes expansion and closes on background', (
    tester,
  ) async {
    final shelf = testShelf();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: ShelfDetailsScreen(
          ownerId: shelf.ownerId,
          shelf: shelf,
          bookRepository: FakeBookRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('add-book-button'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    final expanded = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.expanded == true,
    );
    expect(expanded, findsOneWidget);
    expect(find.byTooltip('Close add book menu'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-manual-choice')), findsNothing);
    expect(
      tester.widget<FloatingActionButton>(button).focusNode!.hasFocus,
      isTrue,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-manual-choice')), findsNothing);
    expect(find.byKey(const Key('shelf-add-dismiss')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'shelf filters cover all eight OR combinations and empty results',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shelf = testShelf();
      final books = FakeBookRepository(
        initialBooks: [
          for (final status in ReadingStatus.values)
            LibraryBook(
              id: status.name,
              ownerId: shelf.ownerId,
              shelfId: shelf.id,
              title: status.name,
              author: 'Reader',
              isbn: null,
              isOwned: true,
              readingStatus: status,
              coverUrl: null,
              createdAt: DateTime(2026),
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: ShelfDetailsScreen(
            ownerId: shelf.ownerId,
            shelf: shelf,
            bookRepository: books,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'All'), findsNothing);
      for (var combination = 0; combination < 8; combination++) {
        for (var index = 0; index < 3; index++) {
          final chip = tester.widget<FilterChip>(
            find.widgetWithText(FilterChip, ReadingStatus.values[index].label),
          );
          final selected = combination & (1 << index) != 0;
          if (chip.selected != selected) chip.onSelected!(selected);
          await tester.pumpAndSettle();
        }
        for (var index = 0; index < 3; index++) {
          expect(
            find.byKey(ValueKey(ReadingStatus.values[index].name)),
            combination == 0 || combination & (1 << index) != 0
                ? findsOneWidget
                : findsNothing,
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: ShelfDetailsScreen(
            ownerId: shelf.ownerId,
            shelf: shelf,
            bookRepository: FakeBookRepository(
              initialBooks: [
                LibraryBook(
                  id: 'only',
                  ownerId: shelf.ownerId,
                  shelfId: shelf.id,
                  title: 'Only reading',
                  author: 'Reader',
                  isbn: null,
                  isOwned: true,
                  readingStatus: ReadingStatus.reading,
                  coverUrl: null,
                  createdAt: DateTime(2026),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Finished'))
          .onSelected!(true);
      await tester.pumpAndSettle();
      expect(find.text('No books with this status.'), findsOneWidget);
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Finished'))
          .onSelected!(false);
      await tester.pumpAndSettle();
      expect(find.text('Only reading'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shelf add choices and header catalogue preserve exact destination',
    (tester) async {
      await runShelfControlsChecks(
        tester,
        capture: (stage) async {
          expect(tester.takeException(), isNull, reason: stage);
        },
        back: () async {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        },
      );
    },
  );
}

Future<void> runShelfControlsChecks(
  WidgetTester tester, {
  required Future<void> Function(String) capture,
  required Future<void> Function() back,
}) async {
  final shelf = testShelf(
    id: 'exact-destination',
    name: 'A very long shelf title for favourite weekend reading',
  );
  final books = FakeBookRepository();
  final catalogue = ShelfControlsCatalogue();
  useMemoryPreferences();
  await tester.pumpWidget(
    ReaduoApp(
      authService: FakeAuthService(
        current: user(uid: shelf.ownerId, displayName: 'Reader'),
      ),
      bookRepository: books,
      shelfRepository: ShelfControlsRepository(),
      catalogueRepository: catalogue,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('shelf-exact-destination')));
  await tester.pumpAndSettle();
  await capture('shelf-empty');
  expect(find.text('Scan into shelf'), findsNothing);
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  await capture('shelf-add-choices');
  expect(find.byType(BottomSheet), findsNothing);
  expect(
    tester.getBottomRight(find.byKey(const Key('shelf-manual-choice'))).dy,
    lessThan(tester.getTopLeft(find.byKey(const Key('add-book-button'))).dy),
  );
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('shelf-manual-choice')), findsNothing);
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  await tester.tapAt(const Offset(20, 230));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('shelf-manual-choice')), findsNothing);
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  await back();
  expect(find.byKey(const Key('shelf-manual-choice')), findsNothing);
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-friends')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-library')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('shelf-manual-choice')), findsNothing);
  await capture('shelf-speed-dial-collapsed');
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('scan-isbn-button')));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<IsbnScannerScreen>(find.byType(IsbnScannerScreen))
        .initialShelf!
        .id,
    shelf.id,
  );
  await capture('shelf-scan-destination');
  await back();
  expect(find.byKey(const Key('add-book-button')), findsOneWidget);
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('shelf-manual-choice')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('book-title-field')),
    'A manual book',
  );
  await tester.enterText(find.byKey(const Key('book-author-field')), 'Reader');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await capture('shelf-manual-destination');
  await tapSaveBook(tester);
  expect(books.lastShelfId, shelf.id);
  expect(books.createdCount, 1);
  await tester.tap(find.byKey(const Key('shelf-catalogue-button')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('shelf-catalogue-query')),
    'discard draft',
  );
  await capture('shelf-header-search');
  if (tester.view.viewInsets.bottom > 0) {
    await back();
    expect(find.byKey(const Key('shelf-catalogue-query')), findsOneWidget);
    await capture('shelf-search-keyboard-dismissed');
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await back();
  expect(find.byKey(const Key('shelf-catalogue-query')), findsNothing);
  expect(find.text(shelf.name), findsOneWidget);
  await tester.tap(find.byKey(const Key('shelf-catalogue-button')));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('shelf-catalogue-query')))
        .controller!
        .text,
    isEmpty,
  );
  await tester.enterText(
    find.byKey(const Key('shelf-catalogue-query')),
    'Catalogue book',
  );
  await tester.tap(find.byKey(const Key('shelf-catalogue-button')));
  await tester.pumpAndSettle();
  expect(catalogue.query, 'Catalogue book');
  expect(
    tester
        .widget<CatalogueSearchScreen>(find.byType(CatalogueSearchScreen))
        .initialShelf!
        .id,
    shelf.id,
  );
  await capture('shelf-catalogue-results');
  await tester.tap(find.byKey(const ValueKey('catalogue-work-shelf-work')));
  await tester.pumpAndSettle();
  await capture('shelf-catalogue-destination');
  final save = find.byKey(const Key('catalogue-save-button'));
  for (var attempt = 0; attempt < 5 && save.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
  expect(books.lastShelfId, shelf.id);
  expect(books.createdCount, 2);
  await back();
  await capture('shelf-books');
  expect(find.byKey(const Key('add-book-button')), findsOneWidget);
  final chip = find.widgetWithText(FilterChip, 'Finished');
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
  await capture('shelf-filter-no-results');
  expect(find.text('No books with this status.'), findsOneWidget);
  await tester.tap(chip);
  await tester.pumpAndSettle();
  await capture('shelf-filter-cleared');
  expect(find.text('No books with this status.'), findsNothing);
  final statusStrip = find.byWidgetPredicate(
    (widget) =>
        widget is SingleChildScrollView &&
        widget.scrollDirection == Axis.horizontal,
  );
  await tester.drag(statusStrip, const Offset(300, 0));
  await tester.pumpAndSettle();
  final shelfScroll = find.descendant(
    of: find.byType(ShelfDetailsScreen),
    matching: find.byType(CustomScrollView),
  );
  final position = tester
      .state<ScrollableState>(
        find
            .descendant(of: shelfScroll, matching: find.byType(Scrollable))
            .first,
      )
      .position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
  expect(
    tester.getBottomRight(find.byKey(const ValueKey('9780306406157'))).dy,
    lessThan(tester.getTopLeft(find.byKey(const Key('add-book-button'))).dy),
  );
  await capture('shelf-last-book-clear');
  expect(tester.takeException(), isNull);
}

class ShelfControlsRepository extends EmptyShelfRepository {
  @override
  Stream<List<Shelf>> watchShelves(String ownerId) => Stream.value([
    testShelf(id: 'unrelated', name: 'Unrelated first shelf'),
    testShelf(
      id: 'exact-destination',
      name: 'A very long shelf title for favourite weekend reading',
    ),
  ]);
}

class ShelfControlsCatalogue extends EmptyCatalogueRepository {
  String? query;
  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async {
    this.query = query;
    const edition = CatalogueEdition(
      id: 'shelf-edition',
      title: 'Catalogue book',
      author: 'Reader',
      isbn: '9780306406157',
      publisher: null,
      publishedYear: null,
      format: null,
      description: null,
      coverUrl: null,
      sourceUrl: 'https://openlibrary.org/books/OL1M',
      provider: CatalogueProvider.openLibrary,
    );
    return CatalogueSearchPage(
      items: [
        const CatalogueWork(
          id: 'shelf-work',
          title: 'Catalogue book',
          author: 'Reader',
          provider: CatalogueProvider.openLibrary,
          editionCount: 1,
          edition: edition,
        ),
      ],
      offset: offset,
      hasMore: false,
      provider: CatalogueProvider.openLibrary,
    );
  }
}
