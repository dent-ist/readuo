import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/main.dart';
import 'package:readuo/screens/account_screen.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';

import 'circle_test.dart' show runCircleEdgeChecks;
import 'isbn_scanner_test.dart' as scanner;
import 'memory_preferences.dart';
import 'phone_feedback_test.dart'
    show PhoneCircleRepository, PhoneFriendRepository;
import 'widget_test.dart'
    show FakeAuthService, FakeShelfRepository, user, shelf;

void main() {
  for (final small in [false, true]) {
    testWidgets(
      'approved five screens, live counts and filters ${small ? 'small' : 'normal'}',
      (tester) async {
        tester.view.physicalSize = small
            ? const Size(360, 640)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = small ? 1.3 : 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await runApprovedRedesignChecks(tester, capture: (_) async {});
      },
    );
  }
}

Future<void> runApprovedRedesignChecks(
  WidgetTester tester, {
  required Future<void> Function(String) capture,
}) async {
  useMemoryPreferences();
  await runCircleEdgeChecks(tester, capture: capture);
  await tester.pumpWidget(const SizedBox.shrink());
  final reader = user(displayName: 'Maya Okonkwo');
  final shelves = [
    shelf(
      id: 'weekend',
      ownerId: reader.uid,
      name: 'Weekend reads',
      bookCount: 3,
    ),
    shelf(
      id: 'personal',
      ownerId: reader.uid,
      name: 'Personal',
      bookCount: 3,
      visibility: ShelfVisibility.private,
      autoShareActivity: false,
    ),
    shelf(id: 'empty', ownerId: reader.uid, name: 'Next chapter'),
  ];
  final books = _DesignBooks([
    for (var index = 0; index < 6; index++)
      LibraryBook(
        id: 'book-$index',
        ownerId: reader.uid,
        shelfId: index < 3 ? 'weekend' : 'personal',
        title: [
          'Piranesi',
          'Dune',
          'The Midnight Library',
          'Small Beautiful Lives',
          'The Quiet Things',
          'A Brighter Tomorrow',
        ][index],
        author: [
          'Susanna Clarke',
          'Frank Herbert',
          'Matt Haig',
          'River North',
          'Maya Okonkwo',
          'Alex Reader',
        ][index],
        isbn: null,
        isOwned: true,
        readingStatus: ReadingStatus.values[index % 3],
        coverUrl: null,
        createdAt: DateTime(2026),
        description:
            'Sample edition description for layout testing. A thoughtful story about memory, belonging, and the unexpected connections between people.\n\nThis second paragraph checks that the full description remains readable below the cover and that longer text can scroll without hiding the actions.',
        publisher: 'Sample publisher',
        publishedYear: '2024',
      ),
    LibraryBook(
      id: 'shared-book',
      ownerId: 'bailey-user',
      shelfId: 'shared',
      title: 'Piranesi',
      author: 'Susanna Clarke',
      isbn: null,
      isOwned: true,
      readingStatus: ReadingStatus.reading,
      coverUrl: null,
      createdAt: DateTime(2026),
    ),
  ]);
  await tester.pumpWidget(
    ReaduoApp(
      authService: FakeAuthService(current: reader),
      shelfRepository: _DesignShelves(
        initialShelves: {
          reader.uid: shelves,
          'bailey-user': [
            shelf(
              id: 'shared',
              ownerId: 'bailey-user',
              name: 'Shared reading',
              bookCount: 1,
            ),
          ],
        },
      ),
      bookRepository: books,
      friendRepository: PhoneFriendRepository(),
      circleRepository: PhoneCircleRepository(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-library')));
  await tester.pumpAndSettle();
  expect(find.text('Scan'), findsNothing);
  expect(find.byKey(const Key('library-add-book-button')), findsNothing);
  expect(find.byKey(const Key('library-add-fab')), findsOneWidget);
  expect(find.text('6 books · 3 shelves'), findsOneWidget);
  await capture('library-overview');
  expect(find.byKey(const Key('library-search-field')), findsNothing);
  await tester.tap(find.byKey(const Key('library-search-button')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('library-search-field')),
    'Piranesi',
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('library-shelf-carousel')), findsNothing);
  expect(find.text('1 book found'), findsOneWidget);
  await capture('library-search-expanded');
  await tester.tap(find.byKey(const Key('library-book-weekend-book-0')));
  await tester.pumpAndSettle();
  expect(find.text('Book details'), findsOneWidget);
  expect(find.text('Write a review').evaluate().length, lessThanOrEqualTo(1));
  await capture('book-details-rich');
  await tester.scrollUntilVisible(
    find.byKey(const Key('book-description')),
    150,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('book-details-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await capture('book-description');
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('clear-library-search')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('library-shelf-carousel')), findsOneWidget);
  await tester.tap(find.byKey(const Key('cancel-library-search')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('library-search-field')), findsNothing);
  await tester.scrollUntilVisible(
    find.byKey(const Key('library-status-reading')),
    160,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await Scrollable.ensureVisible(
    tester.element(find.byKey(const Key('library-status-reading'))),
    alignment: .5,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('library-status-reading')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('library-book-weekend-book-0')), findsNothing);
  expect(find.byKey(const Key('library-book-weekend-book-1')), findsOneWidget);
  await capture('library-reading-filter');
  await tester.tap(find.byKey(const Key('library-search-button')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('library-search-field')),
    'Piranesi',
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('library-book-weekend-book-0')), findsOneWidget);
  await tester.tap(find.byKey(const Key('cancel-library-search')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('library-status-reading')),
    150,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  expect(
    tester
        .widget<ChoiceChip>(find.byKey(const Key('library-status-reading')))
        .selected,
    isTrue,
  );
  await tester.tap(find.byKey(const Key('nav-profile')));
  await tester.pumpAndSettle();
  final profile = tester.widget<AccountScreen>(find.byType(AccountScreen));
  expect(profile.bookCount, 6);
  expect(profile.shelfCount, 3);
  expect(profile.friendCount, 12);
  await capture('profile-overview');
  await tester.scrollUntilVisible(
    find.text('Community guidelines'),
    160,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await capture('profile-support');
  await tester.tap(find.byKey(const Key('nav-friends')));
  await tester.pumpAndSettle();
  expect(find.text('Reading Piranesi'), findsOneWidget);
  await capture('friends-overview');
  await tester.tap(find.byKey(const Key('friend-requests-tab')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('received-requests-card')), findsOneWidget);
  expect(find.byKey(const Key('sent-requests-card')), findsOneWidget);
  await capture('friends-requests');
  await tester.tap(find.byKey(const Key('nav-library')));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<ChoiceChip>(find.byKey(const Key('library-status-reading')))
        .selected,
    isTrue,
  );
  await tester.scrollUntilVisible(
    find.byKey(const Key('library-shelf-carousel')),
    -160,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const Key('library-shelf-carousel')),
    const Offset(-240, 0),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('shelf-empty')).hitTestable(), findsOneWidget);
  await tester.tap(find.byKey(const Key('library-add-fab')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('library-add-book-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('add-books-scan')));
  await tester.pumpAndSettle();
  expect(find.byType(ReaduoBottomNavigation), findsNothing);
  expect(find.text('Where should books go?'), findsOneWidget);
  await tester.pumpWidget(const SizedBox.shrink());
  final scannedBooks = scanner.FakeScannedBookRepository();
  await scanner.pumpScanner(
    tester,
    books: scannedBooks,
    lookup: scanner.FakeLookupRepository(
      result: scanner.testLookupResult(
        title: 'Piranesi',
        author: 'Susanna Clarke',
      ),
    ),
    onCatalogue: (_, _) async {},
  );
  await tester.tap(find.byKey(const Key('fake-scan-once')));
  await tester.pumpAndSettle();
  expect(scannedBooks.inputs, isEmpty);
  expect(find.text('Match found. Confirm below.'), findsOneWidget);
  final visibility = tester.widget<Chip>(
    find.byKey(const Key('scanner-shelf-visibility')),
  );
  expect(visibility.onDeleted, isNull);
  await capture('scanner-confirmation');
  await tester.ensureVisible(
    find.byKey(const Key('scanner-confirmation-scan-again')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('scanner-confirmation-scan-again')));
  await tester.pumpAndSettle();
  expect(scannedBooks.inputs, isEmpty);
  await tester.tap(find.byKey(const Key('fake-scan-once')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('scanner-book-details')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('scanner-book-details')));
  await tester.pumpAndSettle();
  for (final status in ReadingStatus.values) {
    expect(
      find.byKey(ValueKey('lookup-status-${status.name}')),
      findsOneWidget,
    );
  }
  await tester.ensureVisible(find.byKey(const Key('lookup-status-reading')));
  await tester.pumpAndSettle();
  await capture('scanner-book-details');
  await tester.tap(find.byKey(const Key('lookup-status-reading')));
  await tester.ensureVisible(find.byKey(const Key('lookup-save-button')));
  await tester.pumpAndSettle();
  expect(
    tester.getRect(find.byKey(const Key('lookup-save-button'))).bottom,
    lessThanOrEqualTo(
      (tester.view.physicalSize.height - tester.view.viewPadding.bottom) /
          tester.view.devicePixelRatio,
    ),
  );
  await tester.tap(find.byKey(const Key('lookup-save-button')));
  await tester.pumpAndSettle();
  expect(scannedBooks.inputs.single.readingStatus, ReadingStatus.reading);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

class _DesignShelves extends FakeShelfRepository {
  _DesignShelves({required super.initialShelves});
  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) => watchShelves(ownerId).map(
    (shelves) => shelves
        .where(
          (shelf) =>
              shelf.ownerId == ownerId &&
              shelf.visibility != ShelfVisibility.private,
        )
        .toList(),
  );
}

class _DesignBooks extends EmptyBookRepository {
  _DesignBooks(this.books);
  final List<LibraryBook> books;
  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) => Stream.value(
    books
        .where(
          (book) =>
              book.ownerId == ownerId &&
              book.shelfId == shelfId &&
              book.id == bookId,
        )
        .firstOrNull,
  );
  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) => watchBooks(ownerId: ownerId, shelfId: shelfId);
  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) =>
      Stream.value(books.where((book) => book.ownerId == ownerId).toList());
  @override
  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  }) => Stream.value(
    books
        .where((book) => book.ownerId == ownerId && book.shelfId == shelfId)
        .toList(),
  );
}
