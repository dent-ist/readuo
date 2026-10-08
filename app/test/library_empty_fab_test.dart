import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/main.dart';
import 'package:readuo/widgets/readuo_tab_header.dart';
import 'memory_preferences.dart';
import 'widget_test.dart' show FakeAuthService, FakeShelfRepository, user;

void main() {
  for (final width in [390.0, 360.0]) {
    testWidgets('empty Library FAB responds to bookshelf creation at $width', (
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
      await runEmptyLibraryFabChecks(tester);
    });
  }
}

Future<void> runEmptyLibraryFabChecks(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  useMemoryPreferences();
  final reader = user(displayName: 'Reader');
  final repository = FakeShelfRepository();
  await tester.pumpWidget(
    ReaduoApp(
      authService: FakeAuthService(current: reader),
      shelfRepository: repository,
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Your library is empty'), findsOneWidget);
  expect(find.text('My Library'), findsOneWidget);
  expect(find.text('Explore'), findsOneWidget);
  final header = find.byType(ReaduoTabHeader);
  expect(
    find.descendant(of: header, matching: find.byType(ReaduoTabHeaderAction)),
    findsOneWidget,
  );
  expect(find.byKey(const Key('library-search-button')), findsOneWidget);
  final guidance = find.byKey(const Key('empty-library-guidance'));
  expect(
    find.descendant(
      of: guidance,
      matching: find.byWidgetPredicate(
        (w) => w is ButtonStyleButton || w is IconButton,
      ),
    ),
    findsNothing,
  );
  expect(find.byKey(const Key('library-add-book-button')), findsNothing);
  if (capture != null) await capture('empty-library');
  final fab = find.byKey(const Key('library-add-fab'));
  final add = find.byKey(const Key('library-add-book-button'));
  await tester.tap(fab);
  await tester.pumpAndSettle();
  expect(tester.widget<ElevatedButton>(add).onPressed, isNull);
  expect(find.text('Create Bookshelf').hitTestable(), findsOneWidget);
  if (capture != null) await capture('empty-library-menu');
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(add, findsNothing);
  expect(find.text('Your library is empty'), findsOneWidget);
  await tester.tap(fab);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('library-create-bookshelf-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('library-add-dismiss')), findsNothing);
  await tester.enterText(
    find.byKey(const Key('shelf-name-field')),
    'Favourites',
  );
  await tester.ensureVisible(find.byKey(const Key('save-shelf-button')));
  await tester.tap(find.byKey(const Key('save-shelf-button')));
  await tester.pumpAndSettle();
  expect(find.text('Your library is empty'), findsNothing);
  await tester.tap(fab);
  await tester.pumpAndSettle();
  expect(tester.widget<ElevatedButton>(add).onPressed, isNotNull);
  if (capture != null) await capture('library-menu-with-bookshelf');
  repository.removeShelfForTest(reader.uid, 'shelf-1');
  await tester.pumpAndSettle();
  expect(tester.widget<ElevatedButton>(add).onPressed, isNull);
  await tester.tap(find.byKey(const Key('nav-circle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-library')));
  await tester.pumpAndSettle();
  expect(add, findsNothing);
  await tester.tap(fab);
  await tester.pumpAndSettle();
  await tester.tapAt(
    tester.getTopLeft(find.byKey(const Key('library-add-dismiss'))) +
        const Offset(10, 100),
  );
  await tester.pumpAndSettle();
  expect(add, findsNothing);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
