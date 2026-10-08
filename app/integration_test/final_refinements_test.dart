import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:readuo/circle/circle_repository.dart';
import 'package:readuo/friends/friend_repository.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/screens/book_details_screen.dart';
import 'package:readuo/screens/circle_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';
import '../test/friends_test.dart' as friends;
import '../test/manual_book_test.dart' as manual;
import '../test/widget_test.dart' show FakeShelfRepository;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('final book guidance and Circle spacing', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    final states = <Map<String, Object?>>[];
    await binding.convertFlutterSurfaceToImage();
    Future<void> show(Widget screen) async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          theme: ReaduoTheme.modern,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                double.parse(
                  const String.fromEnvironment(
                    'REVIEW_TEXT_SCALE',
                    defaultValue: '1',
                  ),
                ),
              ),
            ),
            child: child!,
          ),
          home: screen,
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> capture(String id) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      states.add({
        'id': id,
        'error': null,
        'physicalWidth': tester.view.physicalSize.width,
        'physicalHeight': tester.view.physicalSize.height,
        'devicePixelRatio': tester.view.devicePixelRatio,
        'keyboardBottom': tester.view.viewInsets.bottom,
        'systemBottom': tester.view.viewPadding.bottom,
      });
      binding.reportData ??= {};
      binding.reportData!['reviewStates'] = states;
      binding.reportData!['reviewBatch'] = 'refinements';
      await binding.takeScreenshot(
        '$id${const String.fromEnvironment('REVIEW_SUFFIX')}',
      );
    }

    final shelf = manual.testShelf(id: 'fiction', name: 'Fiction');
    final book = LibraryBook(
      id: 'dune',
      ownerId: friends.testUser.uid,
      shelfId: shelf.id,
      title: 'Dune',
      author: 'Frank Herbert',
      isbn: null,
      isOwned: true,
      readingStatus: ReadingStatus.reading,
      coverUrl: null,
      createdAt: DateTime(2026),
    );
    await show(
      BookDetailsScreen(
        ownerId: friends.testUser.uid,
        shelfId: shelf.id,
        bookId: book.id,
        shelfRepository: FakeShelfRepository(
          initialShelves: {
            friends.testUser.uid: [shelf],
          },
        ),
        bookRepository: manual.FakeBookRepository(initialBooks: [book]),
      ),
    );
    await capture('book');
    await tester.scrollUntilVisible(
      find.byKey(const Key('book-ownership-toggle')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await capture('book-guidance');
    expect(
      find.text(
        'Ownership is separate from reading status. Turning it off removes this book from social discovery.',
      ),
      findsOneWidget,
    );
    await show(
      Scaffold(
        body: CircleScreen(
          viewerId: friends.testUser.uid,
          friendRepository: const EmptyFriendRepository(),
          shelfRepository: const EmptyShelfRepository(),
          bookRepository: const EmptyBookRepository(),
          circleRepository: const EmptyCircleRepository(),
          onInviteFriend: () {},
          onOpenLibrary: () {},
        ),
        bottomNavigationBar: const ReaduoBottomNavigation(
          active: ReaduoNavDestination.circle,
        ),
      ),
    );
    await capture('circle-empty');
    await tester.ensureVisible(find.byKey(const Key('circle-visit-library')));
    await tester.pumpAndSettle();
    await capture('circle-empty-actions');
    expect(
      find.byKey(const Key('circle-visit-library')).hitTestable(),
      findsOneWidget,
    );
  });
}
