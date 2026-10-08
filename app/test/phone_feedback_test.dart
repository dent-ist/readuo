import 'library_navigation_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/circle/circle_repository.dart';
import 'package:readuo/main.dart';
import 'package:readuo/friends/friend_repository.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';
import 'package:readuo/screens/friends_explore_screen.dart';
import 'package:readuo/screens/friends_screen.dart';
import 'memory_preferences.dart';
import 'widget_test.dart'
    show
        FakeAuthService,
        FakeShelfRepository,
        NavigationFriendRepository,
        user,
        shelf;

void main() {
  setUp(useMemoryPreferences);
  testWidgets(
    'four-tab swipes, header actions and scanner Back preserve navigation',
    (tester) async {
      final platformCalls = <MethodCall>[];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await runPhoneNavigationChecks(
        tester,
        capture: (_) async {},
        nativeBack: () async {
          final updates = platformCalls.where(
            (call) => call.method == 'SystemNavigator.setFrameworkHandlesBack',
          );
          expect(updates, isNotEmpty);
          expect(updates.last.arguments, true);
          await tester.binding.handlePopRoute();
        },
      );
      expect(
        platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
        isEmpty,
      );
      await tester.tap(find.byKey(const Key('nav-friends')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('friend-search-field'));
      await tester.scrollUntilVisible(
        search,
        -350,
        scrollable: find
            .descendant(
              of: find.byType(FriendsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(search, 'Bailey');
      await tester.drag(search, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaduoBottomNavigation>(
              find.byKey(const Key('authenticated-bottom-navigation')),
            )
            .active,
        ReaduoNavDestination.friends,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.dragFrom(const Offset(8, 400), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaduoBottomNavigation>(
              find.byKey(const Key('authenticated-bottom-navigation')),
            )
            .active,
        ReaduoNavDestination.friends,
      );
      await tester.tap(find.byKey(const Key('nav-profile')));
      await tester.tap(find.byKey(const Key('nav-circle')));
      await tester.tap(find.byKey(const Key('nav-friends')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, 'Bailey');
    },
  );
  testWidgets('Explore returns to the same live My Library repeatedly', (
    tester,
  ) async {
    final reader = user(displayName: 'Reader');
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: reader),
        shelfRepository: FakeShelfRepository(
          initialShelves: {
            reader.uid: [
              shelf(
                id: 'phone-shelf',
                ownerId: reader.uid,
                name: 'Phone shelf',
              ),
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.tap(find.text('Explore').first);
      await tester.pumpAndSettle();
      expect(find.byType(ExploreBody), findsOneWidget);
      await tester.tap(find.text('My Library').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('shelf-phone-shelf')), findsOneWidget);
    }
  });
}

Future<void> runPhoneNavigationChecks(
  WidgetTester tester, {
  required Future<void> Function(String) capture,
  required Future<void> Function() nativeBack,
}) async {
  useMemoryPreferences();
  final reader = user(displayName: 'Reader');
  await tester.pumpWidget(
    ReaduoApp(
      authService: FakeAuthService(current: reader),
      friendRepository: PhoneFriendRepository(),
      circleRepository: PhoneCircleRepository(),
      shelfRepository: FakeShelfRepository(
        initialShelves: {
          reader.uid: [
            shelf(id: 'phone-shelf', ownerId: reader.uid, name: 'Phone shelf'),
          ],
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  ReaduoNavDestination active() => tester
      .widget<ReaduoBottomNavigation>(
        find.byKey(const Key('authenticated-bottom-navigation')),
      )
      .active;
  Future<void> select(String tab) async {
    await tester.tap(find.byKey(Key('nav-$tab')));
    await tester.pumpAndSettle();
  }

  Future<void> swipe(double direction) async {
    final size = tester.getSize(find.byKey(const Key('main-tab-pages')));
    await tester.dragFrom(
      Offset(size.width / 2, size.height * .7),
      Offset(direction * size.width * .75, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  await select('circle');
  await capture('phone-circle');
  expect(find.byType(FloatingActionButton), findsOneWidget);
  expect(find.text('Friends only · newest first'), findsNothing);
  expect(find.byKey(const Key('circle-thought-composer')), findsOneWidget);
  await tester.scrollUntilVisible(
    find.byKey(const Key('circle-refresh')),
    350,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('circle-feed-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  expect(
    tester.getRect(find.byKey(const Key('circle-refresh'))).bottom,
    lessThan(
      tester
          .getRect(find.byKey(const Key('authenticated-bottom-navigation')))
          .top,
    ),
  );
  await capture('phone-circle-bottom');
  for (final destination in ReaduoNavDestination.values.skip(1)) {
    await swipe(-1);
    expect(active(), destination);
    await capture('phone-${destination.name}');
  }
  for (final destination in ReaduoNavDestination.values.reversed.skip(1)) {
    await swipe(1);
    expect(active(), destination);
  }
  await tester.tap(find.byKey(const Key('circle-thought-composer')));
  await tester.pumpAndSettle();
  await capture('phone-compose');
  await tester.enterText(
    find.byKey(const Key('circle-post-text')),
    'Keep this draft while navigating back.',
  );
  await capture('phone-compose-keyboard');
  final composeScroll = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byKey(const Key('circle-new-post')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  composeScroll.position.jumpTo(composeScroll.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('circle-submit-post')));
  await tester.pumpAndSettle();
  expect(
    tester.getRect(find.byKey(const Key('circle-submit-post'))).bottom,
    lessThanOrEqualTo(
      (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
          tester.view.devicePixelRatio,
    ),
  );
  await capture('phone-compose-keyboard-action');
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  await nativeBack();
  await tester.pumpAndSettle();
  await capture('phone-after-draft-back');
  expect(find.text('Discard draft?'), findsOneWidget);
  await capture('phone-discard-dialog');
  await nativeBack();
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('circle-new-post')), findsOneWidget);
  expect(find.text('Discard draft?'), findsNothing);
  await nativeBack();
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('circle-discard-draft')));
  await tester.pumpAndSettle();
  for (final destination in ReaduoNavDestination.values) {
    await select(destination.name);
    await openLibraryScanner(tester);
    await tester.pumpAndSettle();
    await capture('phone-scanner-from-${destination.name}');
    await nativeBack();
    await tester.pumpAndSettle();
    expect(active(), ReaduoNavDestination.library);
    await capture('phone-back-to-${destination.name}');
  }
  await select('friends');
  await tester.tap(find.byKey(const Key('invite-friend-button')));
  await tester.pumpAndSettle();
  await capture('phone-invite');
  await nativeBack();
  await tester.pumpAndSettle();
  expect(active(), ReaduoNavDestination.friends);
  await tester.enterText(
    find.byKey(const Key('friend-search-field')),
    'Reader',
  );
  await capture('phone-friends-keyboard');
  expect(
    tester.getRect(find.byKey(const Key('invite-friend-button'))).bottom,
    lessThanOrEqualTo(
      (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
          tester.view.devicePixelRatio,
    ),
  );
  await tester.enterText(find.byKey(const Key('friend-search-field')), '');
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  await tester.scrollUntilVisible(
    find.text('Reader 12'),
    300,
    scrollable: find
        .descendant(
          of: find.byType(FriendsScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  expect(
    tester.getRect(find.text('Reader 12')).bottom,
    lessThan(
      tester
          .getRect(find.byKey(const Key('authenticated-bottom-navigation')))
          .top,
    ),
  );
  await capture('phone-friends-bottom');
  await select('profile');
  await openLibraryScanner(tester);
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('scanner-destination-phone-shelf')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('scanner-enter-isbn')));
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await capture('phone-scanner-manual-entry');
  await nativeBack();
  await tester.pumpAndSettle();
  expect(active(), ReaduoNavDestination.library);
  await select('library');
  for (var attempt = 0; attempt < 3; attempt++) {
    await tester.tap(find.text('Explore').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Library').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-phone-shelf')), findsOneWidget);
  }
  await tester.tap(find.byKey(const Key('shelf-phone-shelf')));
  await tester.pumpAndSettle();
  await capture('phone-shelf');
  final statusStrip = find.byWidgetPredicate(
    (widget) =>
        widget is SingleChildScrollView &&
        widget.scrollDirection == Axis.horizontal,
  );
  await tester.ensureVisible(statusStrip);
  await tester.pumpAndSettle();
  await tester.drag(statusStrip, const Offset(-230, 0));
  await tester.pumpAndSettle();
  expect(active(), ReaduoNavDestination.library);
  await capture('phone-shelf-status-strip');
  await select('friends');
  await select('library');
  expect(find.byKey(const Key('add-book-button')), findsOneWidget);
  await openLibraryScanner(tester);
  await tester.pumpAndSettle();
  await capture('phone-shelf-scanner');
  await nativeBack();
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('add-book-button')), findsOneWidget);
  await capture('phone-back-to-shelf');
  expect(tester.takeException(), isNull);
}

class PhoneCircleRepository extends EmptyCircleRepository {
  @override
  Stream<List<CirclePost>> watchPostsForAuthor({
    required String viewerId,
    required String authorId,
  }) => Stream.value([
    for (var index = 0; authorId == 'bailey-user' && index < 8; index++)
      CirclePost(
        id: 'phone-post-$index',
        authorId: authorId,
        text:
            'A quiet chapter and a good cup of coffee. What are you reading today?',
        attachment: null,
        createdAt: DateTime(2026, 9, 27),
        updatedAt: DateTime(2026, 9, 27),
      ),
  ]);
}

class PhoneFriendRepository extends NavigationFriendRepository {
  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) async* {
    final original = await super.watchFriends(userId).first;
    yield [
      ...original,
      for (var index = 2; index <= 12; index++)
        ReaderProfile(
          uid: 'phone-reader-$index',
          displayName: 'Reader $index',
          photoUrl: null,
          inviteCode: 'TEST$index',
        ),
    ];
  }
}
