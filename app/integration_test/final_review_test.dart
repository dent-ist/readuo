import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:readuo/auth/auth_service.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';
import 'package:readuo/offline/offline_library_screens.dart';
import 'package:readuo/notifications/notification_client.dart';
import 'package:readuo/notifications/notification_screens.dart';
import 'package:readuo/notifications/notification.dart';
import 'package:readuo/screens/circle_screen.dart';
import 'package:readuo/screens/circle_post_composer_screen.dart';
import 'package:readuo/screens/manual_book_flow.dart';
import 'package:readuo/screens/friends_explore_screen.dart';
import 'package:readuo/circle/circle_repository.dart';
import 'package:readuo/circle/engagement_repository.dart';
import 'package:readuo/circle/photo_repository.dart';
import '../test/notifications_test.dart'
    show TestNotificationRepository, TestMessaging;
import '../test/p1_19_21_test.dart' as offline;
import 'package:readuo/moderation/moderation_repository.dart';
import 'package:readuo/moderation/moderation_screens.dart';
import '../test/moderation_test.dart' show FakeModerationRepository;
import 'package:readuo/friends/friend_repository.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/screens/library_books_screen.dart';
import 'package:readuo/screens/my_library_screen.dart';
import 'package:readuo/screens/book_details_screen.dart';
import 'package:readuo/screens/shelf_details_screen.dart';
import '../test/manual_book_test.dart' as manual;
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/screens/friends_screen.dart';
import 'package:readuo/screens/account_screen.dart';
import 'package:readuo/profile/support_screens.dart';
import 'package:readuo/profile/support_repository.dart';
import 'package:readuo/profile/edit_profile_screen.dart';
import 'package:readuo/profile/information_screen.dart';
import 'package:readuo/profile/profile_photo_sheet.dart';
import 'package:readuo/profile/profile_repository.dart';
import 'package:readuo/screens/login_screen.dart';
import 'package:readuo/screens/profile_setup_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import '../test/widget_test.dart'
    show FakeAuthService, FakeOnboardingRepository, FakeShelfRepository;
import '../test/profile_photo_draft_test.dart' show Picker;
import '../test/friends_test.dart' as friends;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const reader = AuthUser(
    uid: 'local-review-only',
    displayName: null,
    email: 'maya@example.test',
    photoUrl: null,
    providerIds: {'google.com'},
  );
  testWidgets('onboarding and profile Android render evidence', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    final renderFailures = <String>[];
    final capturedStates = <Map<String, Object?>>[];
    await binding.convertFlutterSurfaceToImage();
    Future<void> show(Widget screen, {bool settling = true}) async {
      if (screen is CircleScreen) {
        screen = Scaffold(
          body: screen,
          bottomNavigationBar: const ReaduoBottomNavigation(
            active: ReaduoNavDestination.circle,
          ),
        );
      }
      final navigator = GlobalKey<NavigatorState>();
      final root =
          screen is LoginScreen ||
          screen is FriendsScreen ||
          screen is MyLibraryScreen ||
          screen is ProfileSetupScreen;
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          navigatorKey: navigator,
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
          home: root ? screen : const Scaffold(),
        ),
      );
      if (!root)
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => screen),
        );
      if (settling) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    Future<void> capture(String name, {bool settling = true}) async {
      if (settling) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 500));
      }
      final error = tester.takeException();
      if (error != null) renderFailures.add('$name: $error');
      capturedStates.add({
        'id': name,
        'error': error?.toString(),
        'physicalWidth': tester.view.physicalSize.width,
        'physicalHeight': tester.view.physicalSize.height,
        'devicePixelRatio': tester.view.devicePixelRatio,
        'keyboardBottom': tester.view.viewInsets.bottom,
        'systemBottom': tester.view.viewPadding.bottom,
      });
      binding.reportData ??= {};
      binding.reportData!['reviewStates'] = capturedStates;
      await binding.takeScreenshot(
        '$name${const String.fromEnvironment('REVIEW_SUFFIX')}${error == null ? '' : '-FAILED'}',
      );
    }

    await show(
      LoginScreen(
        authService: FakeAuthService(
          signInFailure: const AuthFailure(
            AuthFailureKind.network,
            'Could not connect. Check your connection and try again.',
          ),
        ),
      ),
    );
    await capture('login');
    await tester.tap(find.text('Continue with Google'));
    await capture('login-error');
    final auth = FakeAuthService(current: reader);
    await show(
      ProfileSetupScreen(
        authService: auth,
        user: reader,
        onboardingRepository: FakeOnboardingRepository(),
        suggestedName: 'Maya',
        photoPicker: Picker(),
      ),
    );
    await capture('setup');
    if (!const bool.fromEnvironment('REVIEW_GUTTERS_ONLY')) {
      await tester.tap(find.byKey(const Key('display-name-field')));
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      for (
        var attempt = 0;
        attempt < 20 && tester.view.viewInsets.bottom == 0;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      expect(
        tester.view.viewInsets.bottom,
        greaterThan(0),
        reason: 'Keyboard screenshots require a real Android keyboard inset.',
      );
      await capture('setup-keyboard');
      await tester.scrollUntilVisible(
        find.byKey(const Key('save-profile-button')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await capture('setup-keyboard-actions');
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add a photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a photo'));
    await capture('profile-photo');
    await tester.tap(find.text('Photo access help'));
    await capture('profile-photo-access');
    await show(const ProfilePhotoAccessScreen());
    await capture('photo-access');
    await show(const InformationScreen(topic: 'terms'));
    await capture('terms');
    await show(const InformationScreen(topic: 'privacy'));
    await capture('privacy');
    await show(
      EditProfileScreen(
        uid: reader.uid,
        name: 'Maya',
        photoUrl: null,
        repository: const UnavailableProfileRepository(),
        photoPicker: Picker(),
      ),
    );
    await capture('edit-profile');
    await show(
      Scaffold(
        body: AccountScreen(
          authService: FakeAuthService(current: friends.testUser),
          user: friends.testUser,
          bookCount: 24,
          friendCount: 8,
        ),
        bottomNavigationBar: const ReaduoBottomNavigation(
          active: ReaduoNavDestination.profile,
        ),
      ),
    );
    await capture('profile');
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await capture('profile-bottom');
    await tester.tap(find.text('Sign out'));
    await capture('signout');
    await show(
      const AccountSignInScreen(name: 'Maya Okonkwo', provider: 'Google'),
    );
    await capture('account');
    await show(const SupportScreen());
    await capture('support');
    await show(
      const SupportMessageScreen(repository: UnavailableSupportRepository()),
    );
    await capture('support-message');
    final request = FriendRequestRecord(
      pairId: 'local-review-request',
      requesterId: friends.bailey.uid,
      recipientId: friends.testUser.uid,
      reader: friends.bailey,
      createdAt: DateTime(2026, 9, 27),
    );
    final repository = friends.FakeFriendRepository(
      friends: const [friends.bailey],
      incoming: [request],
      sent: [request],
      blocked: const [
        BlockedReader(uid: 'blocked', displayName: 'Jordan', photoUrl: null),
      ],
    );
    Widget friendHome(FriendRepository source) => FriendsScreen(
      authService: FakeAuthService(current: friends.testUser),
      repository: source,
      shelfRepository: const EmptyShelfRepository(),
      bookRepository: const EmptyBookRepository(),
      user: friends.testUser,
    );
    await show(friendHome(repository));
    await capture('friends');
    await show(friendHome(friends.FakeFriendRepository()));
    await capture('friends-empty');
    await show(
      EnterInviteCodeScreen(
        repository: repository,
        userId: friends.testUser.uid,
      ),
    );
    await capture('enter-code');
    await tester.enterText(
      find.byKey(const Key('invite-code-field')),
      'AAA000',
    );
    await tester.tap(find.byKey(const Key('find-friend-button')));
    await capture('invalid-code');
    await show(
      RequestPreviewScreen(
        repository: repository,
        userId: friends.testUser.uid,
        code: friends.bailey.inviteCode,
        result: const InviteLookupResult(
          InviteLookupKind.available,
          profile: friends.bailey,
        ),
      ),
    );
    await capture('request-preview');
    await tester.tap(find.byKey(const Key('send-friend-request-button')));
    await capture('request-sent');
    await show(
      FriendRequestsScreen(
        repository: repository,
        userId: friends.testUser.uid,
        incoming: true,
      ),
    );
    await capture('requests');
    await show(
      FriendRequestDetailScreen(
        repository: repository,
        userId: friends.testUser.uid,
        request: request,
        incoming: true,
      ),
    );
    await capture('request-detail');
    await show(
      FriendRequestsScreen(
        repository: repository,
        userId: friends.testUser.uid,
        incoming: false,
      ),
    );
    await capture('sent-requests');
    await show(
      BlockedReadersScreen(
        repository: repository,
        userId: friends.testUser.uid,
      ),
    );
    await capture('blocked-users');
    await tester.tap(find.text('Unblock'));
    await capture('unblock');
    Widget friendProfile() => FriendProfileScreen(
      repository: repository,
      shelfRepository: friends.SharedShelfRepository(),
      bookRepository: friends.SharedBookRepository(),
      userId: friends.testUser.uid,
      friend: friends.bailey,
    );
    await show(friendProfile());
    await capture('friend-profile');
    await tester.tap(find.byTooltip('Connection options'));
    await capture('profile-menu');
    await tester.tap(find.text('Remove friend'));
    await capture('remove-friend');
    await show(friendProfile());
    await tester.tap(find.byTooltip('Connection options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block this reader'));
    await capture('block-friend');
    const report = ModerationReport(
      id: 'report',
      kind: 'post',
      reason: 'Harassment or bullying',
      note: 'This comment was directed at me after I asked them to stop.',
      content: 'A reported post is displayed here for moderator review.',
    );
    final moderation = FakeModerationRepository()..reports = [report];
    await show(
      ReportScreen(
        repository: moderation,
        target: const ReportTarget(kind: 'post', id: 'local-fixture'),
        onDone: () {},
      ),
    );
    await capture('report');
    await show(ReportSentScreen(support: false, onDone: () {}, onBlock: () {}));
    await capture('report-sent');
    await show(ModerationScreen(repository: moderation));
    await capture('moderation');
    await show(ReportDetailScreen(repository: moderation, report: report));
    await capture('report-detail');
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Reviewed against community guidelines.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove content'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove content'));
    await capture('moderation-action');
    final draft = TextEditingController(
      text: 'Draft text stays here so it can be revised.',
    );
    addTearDown(draft.dispose);
    await show(
      ContentFilteredScreen(
        draftController: draft,
        onEdit: () {},
        onGuidelines: () {},
      ),
    );
    await capture('content-filtered');
    final shelf = Shelf(
      id: 'fiction',
      ownerId: friends.testUser.uid,
      name: 'Fiction',
      visibility: ShelfVisibility.friends,
      autoShareActivity: true,
      bookCount: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final destination = manual.testShelf(id: 'favorites', name: 'Favorites');
    final shelves = FakeShelfRepository(
      initialShelves: {
        friends.testUser.uid: [shelf, destination],
      },
    );
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
    final books = manual.FakeBookRepository(initialBooks: [book]);
    await show(
      MyLibraryScreen(
        authService: FakeAuthService(current: friends.testUser),
        shelfRepository: const EmptyShelfRepository(),
        bookRepository: const EmptyBookRepository(),
        bookLookupRepository: const EmptyBookLookupRepository(),
        friendRepository: repository,
        user: friends.testUser,
      ),
    );
    await capture('library-empty');
    await tester.tap(find.byKey(const Key('library-add-fab')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-create-bookshelf-button')));
    await capture('create-shelf');
    await show(
      LibraryBooksScreen(
        ownerId: friends.testUser.uid,
        bookRepository: books,
        onOpenBook: (_) {},
        onSearch: (_) async {},
        onAddBooks: () {},
      ),
    );
    await capture('library-books');
    await tester.ensureVisible(find.byKey(const Key('filter-finished')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-finished')));
    await capture('filter-empty');
    await tester.ensureVisible(find.byKey(const Key('filter-all')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-books-button')));
    await capture('sort-books');
    await show(
      LibrarySearchScreen(
        ownerId: friends.testUser.uid,
        initialQuery: 'Dune',
        bookRepository: books,
        shelfRepository: shelves,
        onOpenBook: (_) {},
        onOpenShelf: (_) {},
        onSearchCatalogue: () {},
      ),
    );
    await capture('search-results');
    await show(
      LibrarySearchScreen(
        ownerId: friends.testUser.uid,
        initialQuery: 'No matching book',
        bookRepository: books,
        shelfRepository: shelves,
        onOpenBook: (_) {},
        onOpenShelf: (_) {},
        onSearchCatalogue: () {},
      ),
    );
    await capture('search-empty');
    await show(
      ShelfDetailsScreen(
        ownerId: friends.testUser.uid,
        shelf: shelf,
        shelfRepository: shelves,
        bookRepository: books,
      ),
    );
    await capture('shelf');
    await show(
      ShelfDetailsScreen(
        ownerId: friends.testUser.uid,
        shelf: destination,
        shelfRepository: shelves,
        bookRepository: const EmptyBookRepository(),
      ),
    );
    await capture('shelf-empty');
    await show(
      ShelfSettingsScreen(
        ownerId: friends.testUser.uid,
        shelf: shelf,
        shelfRepository: shelves,
      ),
    );
    await capture('shelf-settings');
    await tester.ensureVisible(
      find.byKey(const Key('settings-visibility-private')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-visibility-private')));
    await tester.pumpAndSettle();
    await capture('private-confirm');
    await show(
      DeleteShelfScreen(
        ownerId: friends.testUser.uid,
        shelf: shelf,
        shelfRepository: shelves,
      ),
    );
    await capture('delete-shelf');
    await tester.ensureVisible(
      find.byKey(const Key('remove-shelf-and-books-choice')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-shelf-and-books-choice')));
    await capture('delete-shelf-confirm');
    await show(
      MoveAllBooksScreen(
        ownerId: friends.testUser.uid,
        sourceShelf: shelf,
        shelfRepository: shelves,
      ),
    );
    await capture('move-all');
    await show(
      BookDetailsScreen(
        ownerId: friends.testUser.uid,
        shelfId: shelf.id,
        bookId: book.id,
        shelfRepository: shelves,
        bookRepository: books,
      ),
    );
    await capture('book');
    await tester.scrollUntilVisible(
      find.byKey(const Key('change-reading-status-button')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('change-reading-status-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-reading-status-button')));
    await capture('reading-status');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-options-button')));
    await capture('book-menu');
    await tester.tap(find.byKey(const Key('manage-book-move')));
    await capture('move-book');
    await show(
      BookDetailsScreen(
        ownerId: friends.testUser.uid,
        shelfId: shelf.id,
        bookId: book.id,
        shelfRepository: shelves,
        bookRepository: books,
      ),
    );
    await tester.tap(find.byKey(const Key('book-options-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-book-remove')));
    await capture('remove-book');
    final savedBook = LibraryBook(
      id: 'saved',
      ownerId: book.ownerId,
      shelfId: book.shelfId,
      title: 'Piranesi',
      author: 'Susanna Clarke',
      isbn: null,
      isOwned: false,
      readingStatus: ReadingStatus.wantToRead,
      coverUrl: null,
      createdAt: DateTime(2026),
    );
    await show(
      BookDetailsScreen(
        ownerId: friends.testUser.uid,
        shelfId: shelf.id,
        bookId: savedBook.id,
        shelfRepository: shelves,
        bookRepository: manual.FakeBookRepository(initialBooks: [savedBook]),
      ),
    );
    await capture('saved-book');
    await show(
      MyLibraryScreen(
        authService: FakeAuthService(current: friends.testUser),
        shelfRepository: const EmptyShelfRepository(),
        bookRepository: const EmptyBookRepository(),
        bookLookupRepository: const EmptyBookLookupRepository(),
        friendRepository: const EmptyFriendRepository(),
        user: friends.testUser,
      ),
    );
    await tester.tap(find.byKey(const Key('explore-library-tab')));
    await capture('explore-empty');
    await show(
      FriendsExploreSearchScreen(
        viewerId: friends.testUser.uid,
        initialQuery: 'No matching book',
        friendRepository: repository,
        shelfRepository: const EmptyShelfRepository(),
        bookRepository: const EmptyBookRepository(),
        onOpenShelf: (_, __) async {},
        onOpenBook: (_, __, ___) async {},
        onPublic: (_) {},
      ),
    );
    await capture('explore-no-results');
    final sharedShelves = friends.SharedShelfRepository();
    final sharedBooks = friends.SharedBookRepository();
    await show(
      SharedShelfScreen(
        viewerId: friends.testUser.uid,
        friend: friends.bailey,
        shelf: sharedShelves.sharedShelf,
        friendRepository: repository,
        shelfRepository: sharedShelves,
        bookRepository: sharedBooks,
      ),
    );
    await capture('friend-shelf');
    await tester.tap(find.text('The Shared Book'));
    await capture('friend-book');
    await tester.ensureVisible(find.byKey(const Key('add-shared-book-button')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-shared-book-button')));
    await capture('save-shelf');
    await tester.ensureVisible(
      find.byKey(const Key('save-shared-book-button')),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-shared-book-button')));
    await capture('book-saved');
    await tester.tap(find.text('Keep exploring'));
    await tester.pumpAndSettle();
    sharedShelves.setSharedShelf(null);
    await capture('unavailable');
    await show(
      ManualBookFlow(
        ownerId: friends.testUser.uid,
        shelf: shelf,
        bookRepository: books,
        shelfRepository: shelves,
        existingBooks: [book],
        initialTitle: book.title,
        initialAuthor: book.author,
        pickPhoto: (_) async => null,
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('manual-next-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual-next-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-book-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-book-button')));
    await capture('manual-possible-duplicate');
    final offlineProbe = offline.Probe();
    final offlineController = await offline.loaded(
      offline.MemoryCache(),
      offlineProbe,
    );
    addTearDown(offlineController.dispose);
    offlineProbe.online = false;
    offlineController.networkChanged(false);
    await show(OfflineLibraryScreen(controller: offlineController));
    await capture('offline-library');
    await show(
      OfflineBookScreen(
        controller: offlineController,
        shelfId: offline.shelf.id,
        bookId: offline.book.id,
      ),
    );
    await capture('offline-book');
    await tester.ensureVisible(find.text('Change status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change status'));
    await capture('offline-action');
    final notifications = TestNotificationRepository();
    final messaging = TestMessaging();
    final client = NotificationClient(
      userId: 'local-review',
      installationId: 'local-review',
      repository: notifications,
      messaging: messaging,
      openDestination: (_, __) async => NotificationOpenResult.unavailable,
      onError: (_) {},
    );
    await show(NotificationsScreen(client: client, onSettings: () {}));
    await capture('notifications-empty');
    notifications.items['review'] = ReaduoNotification(
      id: 'review',
      recipientId: 'local-review',
      actorId: 'friend',
      actorName: 'Sarah Lin',
      type: NotificationType.like,
      targetId: 'local-post',
      createdAt: DateTime.now(),
    );
    for (final type in NotificationType.values.where(
      (type) => type != NotificationType.like,
    )) {
      notifications.items[type.name] = ReaduoNotification(
        id: type.name,
        recipientId: 'local-review',
        actorId: 'friend-${type.name}',
        actorName: type == NotificationType.friendRequest
            ? 'Tom Bergen'
            : type == NotificationType.requestAccepted
            ? 'Amara Reyes'
            : 'Jonas Kerr',
        type: type,
        targetId: 'local-${type.name}',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
    }
    await show(NotificationsScreen(client: client, onSettings: () {}));
    await capture('notifications');
    await show(
      NotificationSettingsScreen(
        userId: 'local-review',
        repository: notifications,
        openSettings: () async {},
      ),
    );
    await capture('notification-settings');
    await show(NotificationPermissionScreen(client: client, onDone: () {}));
    await capture('notification-permission');
    Widget circle(FriendRepository source) => CircleScreen(
      viewerId: friends.testUser.uid,
      friendRepository: source,
      shelfRepository: const EmptyShelfRepository(),
      bookRepository: const EmptyBookRepository(),
      circleRepository: const EmptyCircleRepository(),
      onInviteFriend: () {},
      onOpenLibrary: () {},
    );
    await show(circle(const EmptyFriendRepository()));
    await capture('circle-empty');
    await show(circle(const PendingFriends()), settling: false);
    await capture('feed-loading', settling: false);
    await show(circle(const FailedFriends()));
    await capture('network-error');
    final post = CirclePost(
      id: 'local-post',
      authorId: friends.bailey.uid,
      text: 'The quiet details stayed with me long after the final page.',
      attachment: null,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      updatedAt: null,
    );
    final postRepository = ReviewPosts(post);
    await show(
      CircleScreen(
        viewerId: friends.testUser.uid,
        friendRepository: repository,
        shelfRepository: const EmptyShelfRepository(),
        bookRepository: const EmptyBookRepository(),
        circleRepository: postRepository,
        onInviteFriend: () {},
        onOpenLibrary: () {},
      ),
    );
    await capture('circle');
    await tester.tap(
      find.byKey(const ValueKey('circle-report-post-local-post')),
    );
    await capture('post-menu');
    Widget postDetail(String commenter) => CirclePostDetailScreen(
      post: post,
      viewerId: friends.testUser.uid,
      displayName: friends.bailey.displayName,
      photoUrl: null,
      viewerDisplayName: 'Maya',
      viewerPhotoUrl: null,
      engagementRepository: ReviewComments(commenter),
      photoRepository: const EmptyCirclePhotoRepository(),
    );
    await show(postDetail('another-reader'));
    await capture('post');
    await tester.ensureVisible(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Comment options'));
    await capture('comment-menu');
    await show(postDetail(friends.testUser.uid));
    await tester.ensureVisible(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Comment options'));
    await capture('own-comment-menu');
    await tester.tap(find.text('Edit comment'));
    await capture('edit-comment');
    await show(postDetail(friends.testUser.uid));
    await tester.ensureVisible(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await capture('delete-comment');
    await show(
      CirclePostComposerScreen(
        ownerId: friends.testUser.uid,
        circleRepository: const FailedPosts(),
        bookRepository: books,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'A quiet Sunday with a good book.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('circle-submit-post')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await capture('save-error');
    expect(renderFailures, isEmpty);
  });
}

class PendingFriends extends EmptyFriendRepository {
  const PendingFriends();
  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) =>
      const Stream.empty();
}

class ReviewPosts extends EmptyCircleRepository {
  ReviewPosts(this.post);
  final CirclePost post;
  @override
  Stream<List<CirclePost>> watchPostsForAuthor({
    required String viewerId,
    required String authorId,
  }) => Stream.value(authorId == post.authorId ? [post] : []);
}

class FailedPosts extends EmptyCircleRepository {
  const FailedPosts();
  @override
  Future<void> publishPostDraft({
    required String authorId,
    required CirclePostDraft draft,
  }) async => throw const CircleFailure(
    'Your post wasn’t sent. Your draft is still here. Try again when your connection improves.',
  );
}

class ReviewComments extends EmptyCircleEngagementRepository {
  ReviewComments(this.author);
  final String author;
  @override
  Stream<List<CircleComment>> watchComments(CircleContentRef content) =>
      Stream.value([
        CircleComment(
          id: 'local-comment',
          authorId: author,
          authorDisplayName: 'Maya',
          authorPhotoUrl: null,
          text: 'This is next on my reading list.',
          createdAt: DateTime.now(),
          updatedAt: null,
        ),
      ]);
}

class FailedFriends extends EmptyFriendRepository {
  const FailedFriends();
  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) => Stream.error(
    const FriendFailure(
      'Could not connect. Check your connection and try again.',
    ),
  );
}
