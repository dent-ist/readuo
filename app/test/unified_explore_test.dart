import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/friends/friend_repository.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/main.dart';
import 'package:readuo/screens/friends_explore_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';
import 'package:readuo/widgets/readuo_section_tabs.dart';
import 'friends_test.dart' as fixtures;
import 'widget_test.dart'
    show FakeAuthService, FakeShelfRepository, user, shelf;

void main() {
  for (final width in [390.0, 360.0]) {
    testWidgets('unified Explore empty, search, and grouped copies at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, width == 360 ? 640 : 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await runUnifiedExploreChecks(tester);
    });
  }

  testWidgets(
    'switching between My Library and Explore preserves tab alignment',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final reader = user(displayName: 'Reader');
      await tester.pumpWidget(
        ReaduoApp(
          authService: FakeAuthService(current: reader),
          shelfRepository: FakeShelfRepository(
            initialShelves: {
              reader.uid: [
                shelf(
                  id: 'shelf-1',
                  ownerId: reader.uid,
                  name: 'My Bookshelf',
                ),
              ],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-library')));
      await tester.pumpAndSettle();

      final myLibraryTabsRect = tester.getRect(find.byType(ReaduoSectionTabs));
      expect(myLibraryTabsRect.left, 16.0);
      expect(myLibraryTabsRect.right, 390.0 - 16.0);

      await tester.tap(find.text('Explore').first);
      await tester.pumpAndSettle();

      final exploreTabsRect = tester.getRect(find.byType(ReaduoSectionTabs));
      expect(exploreTabsRect.left, myLibraryTabsRect.left);
      expect(exploreTabsRect.right, myLibraryTabsRect.right);
      expect(exploreTabsRect.width, myLibraryTabsRect.width);
      expect(exploreTabsRect.top, myLibraryTabsRect.top);
      expect(exploreTabsRect.bottom, myLibraryTabsRect.bottom);

      await tester.tap(find.text('My Library').first);
      await tester.pumpAndSettle();

      final backTabsRect = tester.getRect(find.byType(ReaduoSectionTabs));
      expect(backTabsRect.left, myLibraryTabsRect.left);
      expect(backTabsRect.right, myLibraryTabsRect.right);
      expect(backTabsRect, myLibraryTabsRect);
    },
  );
}

Future<void> runUnifiedExploreChecks(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  String? openedOwner;
  bool? openedFriend;
  Future<void> pump({bool empty = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey(empty),
        debugShowCheckedModeBanner: false,
        theme: ReaduoTheme.modern,
        home: Scaffold(
          appBar: AppBar(title: const Text('Library')),
          bottomNavigationBar: const ReaduoBottomNavigation(),
          body: ExploreBody(
            searchMode: true,
            viewerId: 'viewer',
            friendRepository: empty
                ? const EmptyFriendRepository()
                : _Friends(),
            shelfRepository: empty ? const EmptyShelfRepository() : _Shelves(),
            bookRepository: empty ? const EmptyBookRepository() : _Books(),
            onMyLibrary: () {},
            onOpenProfile: (_, _) async {},
            onOpenShelf: (_, _, _) async {},
            onOpenBook: (reader, shelf, book, isFriend) async {
              openedOwner = reader.uid;
              openedFriend = isFriend;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  await pump(empty: true);
  expect(find.text('Nothing to explore yet'), findsOneWidget);
  expect(find.byType(FilledButton), findsNothing);
  expect(find.text('Public'), findsNothing);
  expect(find.byKey(const Key('explore-public-filter')), findsNothing);
  if (capture != null) await capture('empty');
  await pump();
  expect(find.byType(ExpansionTile), findsOneWidget);
  expect(find.text('In 2 libraries'), findsOneWidget);
  expect(find.text('Includes a friend'), findsOneWidget);
  expect(find.text('Public saved only'), findsNothing);
  if (capture != null) await capture('grouped');
  final search = find.byKey(const Key('explore-search-field'));
  await tester.enterText(search, 'quiet futures');
  await tester.pumpAndSettle();
  expect(
    find.byType(ExpansionTile),
    findsOneWidget,
    reason: 'Search matches shelf names across both sources.',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
  final copies = find.byWidgetPredicate(
    (widget) => widget.key.toString().contains('explore-copy-'),
  );
  expect(
    copies,
    findsNWidgets(2),
    reason: 'A friend’s public copy appears only once.',
  );
  if (capture != null) await capture('copies');
  final publicCopy = find.byKey(
    ValueKey(
      'explore-copy-${fixtures.caseyPublic.uid}/public-quiet/public-quiet-book',
    ),
  );
  await tester.ensureVisible(publicCopy);
  await tester.pumpAndSettle();
  await tester.tap(publicCopy);
  await tester.pumpAndSettle();
  expect(openedOwner, fixtures.caseyPublic.uid);
  expect(openedFriend, isFalse);
  final friendCopy = find.byKey(
    ValueKey(
      'explore-copy-${fixtures.bailey.uid}/public-field/public-field-book',
    ),
  );
  await tester.ensureVisible(friendCopy);
  await tester.pumpAndSettle();
  await tester.tap(friendCopy);
  await tester.pumpAndSettle();
  expect(openedOwner, fixtures.bailey.uid);
  expect(openedFriend, isTrue);
  await tester.ensureVisible(search);
  await tester.pumpAndSettle();
  await tester.tap(search);
  await tester.pumpAndSettle();
  await tester.enterText(search, 'nothing matches this');
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  expect(find.text('No books found'), findsOneWidget);
  expect(find.byType(ExpansionTile), findsNothing);
  if (capture != null) await capture('no-results');
  await tester.tap(find.byTooltip('Clear search'));
  await tester.pumpAndSettle();
  expect(find.byType(ExpansionTile), findsOneWidget);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

class _Friends extends fixtures.PublicExploreFriendRepository {
  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) =>
      Stream.value([fixtures.bailey]);
}

class _Shelves extends fixtures.PublicExploreShelfRepository {
  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) => Stream.value(ownerId == fixtures.bailey.uid ? [baileyShelf] : []);
}

class _Books extends fixtures.PublicExploreBookRepository {
  @override
  LibraryBook get publicQuietBook => LibraryBook(
    id: 'public-quiet-book',
    ownerId: fixtures.caseyPublic.uid,
    shelfId: 'public-quiet',
    title: 'Public Field Notes',
    author: 'R. Explorer',
    isbn: '9780306406157',
    isOwned: true,
    readingStatus: ReadingStatus.finished,
    coverUrl: null,
    createdAt: DateTime(2026),
  );
}
