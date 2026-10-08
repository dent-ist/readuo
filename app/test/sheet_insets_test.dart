import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/screens/my_library_screen.dart';
import 'package:readuo/screens/shelf_details_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';

void main() {
  testWidgets('create shelf action stays above Android navigation inset', (
    tester,
  ) async {
    await pumpInsetSheet(
      tester,
      viewPadding: const EdgeInsets.only(bottom: 48),
      viewInsets: EdgeInsets.zero,
    );

    await tester.ensureVisible(find.byKey(const Key('save-shelf-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('save-shelf-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getBottomRight(find.byKey(const Key('save-shelf-button'))).dy,
      lessThanOrEqualTo(512),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('create shelf action stays reachable above keyboard', (
    tester,
  ) async {
    await pumpInsetSheet(
      tester,
      viewPadding: const EdgeInsets.only(bottom: 32),
      viewInsets: const EdgeInsets.only(bottom: 220),
    );

    await tester.ensureVisible(find.byKey(const Key('save-shelf-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('save-shelf-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getBottomRight(find.byKey(const Key('save-shelf-button'))).dy,
      lessThanOrEqualTo(340),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shelf settings action stays above Android navigation inset', (
    tester,
  ) async {
    await pumpSettingsScreen(
      tester,
      viewPadding: const EdgeInsets.only(bottom: 48),
      viewInsets: EdgeInsets.zero,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('save-shelf-settings-button')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('save-shelf-settings-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester
          .getBottomRight(find.byKey(const Key('save-shelf-settings-button')))
          .dy,
      lessThanOrEqualTo(512),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'private confirmation actions stay above Android navigation inset',
    (tester) async {
      await pumpSettingsScreen(
        tester,
        viewPadding: const EdgeInsets.only(bottom: 48),
        viewInsets: EdgeInsets.zero,
      );

      await tester.tap(find.byKey(const Key('settings-visibility-private')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('confirm-private-shelf-button')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('keep-shelf-visibility-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('keep-shelf-visibility-button')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester
            .getBottomRight(
              find.byKey(const Key('keep-shelf-visibility-button')),
            )
            .dy,
        lessThanOrEqualTo(512),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('delete confirmation stays reachable above Android inset', (
    tester,
  ) async {
    const source = Shelf(
      id: 'source',
      ownerId: 'owner-user',
      name: 'Weekend reads',
      visibility: ShelfVisibility.friends,
      autoShareActivity: true,
      bookCount: 3,
      createdAt: null,
      updatedAt: null,
    );
    await pumpDeletionScreen(tester, source);

    await tester.tap(find.byKey(const Key('remove-shelf-and-books-choice')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('cancel-confirm-delete-shelf-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('confirm-delete-shelf-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cancel-confirm-delete-shelf-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester
          .getBottomRight(
            find.byKey(const Key('cancel-confirm-delete-shelf-button')),
          )
          .dy,
      lessThanOrEqualTo(512),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('move-all action stays reachable above Android inset', (
    tester,
  ) async {
    const source = Shelf(
      id: 'source',
      ownerId: 'owner-user',
      name: 'Weekend reads',
      visibility: ShelfVisibility.friends,
      autoShareActivity: true,
      bookCount: 3,
      createdAt: null,
      updatedAt: null,
    );
    const destination = Shelf(
      id: 'destination',
      ownerId: 'owner-user',
      name: 'Private stack',
      visibility: ShelfVisibility.private,
      autoShareActivity: false,
      bookCount: 2,
      createdAt: null,
      updatedAt: null,
    );
    await pumpDeletionScreen(
      tester,
      source,
      shelves: const [source, destination],
    );
    await tester.tap(find.byKey(const Key('move-all-choice')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('move-all-books-button')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('move-all-books-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getBottomRight(find.byKey(const Key('move-all-books-button'))).dy,
      lessThanOrEqualTo(512),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> pumpDeletionScreen(
  WidgetTester tester,
  Shelf source, {
  List<Shelf>? shelves,
}) async {
  tester.view.physicalSize = const Size(360, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final viewPadding = const EdgeInsets.only(bottom: 48);
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: const Size(360, 560),
          padding: viewPadding,
          viewPadding: viewPadding,
        ),
        child: child!,
      ),
      home: DeleteShelfScreen(
        ownerId: 'owner-user',
        shelf: source,
        shelfRepository: TestShelfRepository(shelves: shelves ?? [source]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpInsetSheet(
  WidgetTester tester, {
  required EdgeInsets viewPadding,
  required EdgeInsets viewInsets,
}) async {
  tester.view.physicalSize = const Size(360, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 560),
          padding: viewPadding,
          viewPadding: viewPadding,
          viewInsets: viewInsets,
        ),
        child: const Scaffold(
          body: CreateShelfSheet(
            ownerId: 'owner-user',
            shelfRepository: TestShelfRepository(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpSettingsScreen(
  WidgetTester tester, {
  required EdgeInsets viewPadding,
  required EdgeInsets viewInsets,
}) async {
  tester.view.physicalSize = const Size(360, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 560),
          padding: viewPadding,
          viewPadding: viewPadding,
          viewInsets: viewInsets,
        ),
        child: const ShelfSettingsScreen(
          ownerId: 'owner-user',
          shelf: Shelf(
            id: 'shelf-id',
            ownerId: 'owner-user',
            name: 'Shared shelf',
            description: 'A shelf shared with friends',
            visibility: ShelfVisibility.friends,
            autoShareActivity: true,
            bookCount: 3,
            createdAt: null,
            updatedAt: null,
          ),
          shelfRepository: TestShelfRepository(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class TestShelfRepository implements ShelfRepository {
  const TestShelfRepository({this.shelves = const []});

  final List<Shelf> shelves;

  @override
  Future<Shelf> createShelf({
    required String ownerId,
    required CreateShelfInput input,
  }) async => shelves.first;

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) => Stream.value(shelves);

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
  Future<void> updateShelf({
    required String ownerId,
    required String shelfId,
    required UpdateShelfInput input,
  }) async {}

  @override
  Future<void> moveAllBooksAndDeleteShelf({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
  }) async {}

  @override
  Future<void> deleteShelfAndBooks({
    required String ownerId,
    required String shelfId,
  }) async {}

  @override
  Future<void> resumeShelfOperation({
    required String ownerId,
    required String sourceShelfId,
  }) async {}
}
