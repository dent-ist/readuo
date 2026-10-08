import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/friends/friend_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/screens/my_library_screen.dart';
import 'package:readuo/screens/catalogue_search_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';
import 'memory_preferences.dart';
import 'widget_test.dart'
    show FakeAuthService, FakeShelfRepository, user, shelf;
import 'manual_book_test.dart' show FakeBookRepository;

void main() {
  setUp(useMemoryPreferences);
  for (final width in [390.0, 360.0]) {
    testWidgets('Library addition choices and four-tab navigation at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, width == 360 ? 640 : 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 360
          ? 1.3
          : 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await runLibraryAdditionChecks(tester);
    });
  }
}

Future<void> runLibraryAdditionChecks(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
  ThemeData? theme,
}) async {
  useMemoryPreferences();
  final reader = user(displayName: 'Reader');
  final target = shelf(id: 'quiet', ownerId: reader.uid, name: 'Quiet reads');
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? ReaduoTheme.modern,
      home: MyLibraryScreen(
        authService: FakeAuthService(current: reader),
        user: reader,
        shelfRepository: FakeShelfRepository(
          initialShelves: {
            reader.uid: [target],
          },
        ),
        bookRepository: FakeBookRepository(),
        bookLookupRepository: const EmptyBookLookupRepository(),
        friendRepository: const EmptyFriendRepository(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final nav = find.byType(ReaduoBottomNavigation);
  expect(nav, findsOneWidget);
  expect(find.byKey(const Key('bottom-scan-button')), findsNothing);
  final widths = ReaduoNavDestination.values
      .map(
        (destination) =>
            tester.getSize(find.byKey(Key('nav-${destination.name}'))).width,
      )
      .toList();
  for (final width in widths) {
    expect(width, closeTo(widths.first, .01));
  }
  expect(find.byKey(const Key('library-add-book-button')), findsNothing);
  expect(find.byKey(const Key('library-add-fab')), findsOneWidget);
  if (capture != null) await capture('library');
  Future<void> openMenu() async {
    await tester.tap(find.byKey(const Key('library-add-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-add-book-button')));
    await tester.pumpAndSettle();
    for (final label in ['Scan barcode', 'Search catalogue', 'Add manually']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
  }

  await openMenu();
  if (capture != null) await capture('library-add-books');
  await tester.tap(find.byKey(const Key('add-books-catalogue')));
  await tester.pumpAndSettle();
  expect(find.byType(CatalogueSearchScreen), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
  await openMenu();
  await tester.tap(find.byKey(const Key('add-books-manual')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('catalogue-title-field')), findsOneWidget);
  await tester.scrollUntilVisible(
    find.byKey(const Key('catalogue-shelf-picker')),
    180,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('catalogue-confirmation')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  expect(find.byKey(const Key('catalogue-shelf-picker')), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('shelf-quiet')),
    160,
    scrollable: find
        .descendant(
          of: find.byType(MyLibraryScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('shelf-quiet')));
  await tester.pumpAndSettle();
  if (capture != null) await capture('shelf');
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  for (final key in [
    'scan-isbn-button',
    'shelf-enter-isbn-choice',
    'shelf-catalogue-choice',
    'shelf-manual-choice',
  ]) {
    expect(find.byKey(Key(key)).hitTestable(), findsOneWidget);
  }
  if (capture != null) await capture('shelf-add-books');
  await tester.tap(find.byKey(const Key('shelf-catalogue-choice')));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<CatalogueSearchScreen>(find.byType(CatalogueSearchScreen))
        .initialShelf
        ?.id,
    target.id,
  );
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.byType(ReaduoBottomNavigation), findsOneWidget);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
