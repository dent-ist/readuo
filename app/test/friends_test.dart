import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/auth/auth_service.dart';
import 'package:readuo/friends/friend_repository.dart';
import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/screens/friends_screen.dart';
import 'package:readuo/screens/my_library_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';

const testUser = AuthUser(
  uid: 'owner-user',
  displayName: 'Alex Reader',
  email: 'private@example.com',
  photoUrl: null,
  providerIds: {'google.com'},
);

const ownerProfile = ReaderProfile(
  uid: 'owner-user',
  displayName: 'Alex Reader',
  photoUrl: null,
  inviteCode: 'ABC234',
);

const bailey = ReaderProfile(
  uid: 'other-user',
  displayName: 'Bailey Reader',
  photoUrl: null,
  inviteCode: 'XYZ789',
);

const caseyPublic = ReaderProfile(
  uid: 'casey-user',
  displayName: 'Casey Public',
  photoUrl: null,
  inviteCode: 'PUB456',
);

void main() {
  testWidgets('empty Friends state exposes both connection paths safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpFriends(tester, FakeFriendRepository());

    expect(find.text('Reading is better together'), findsOneWidget);
    expect(find.byKey(const Key('empty-invite-button')), findsOneWidget);
    expect(find.byKey(const Key('empty-enter-code-button')), findsOneWidget);
    expect(find.text('Friends'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Friends shows counts, real identities, and filters by name', (
    tester,
  ) async {
    final request = FriendRequestRecord(
      pairId: pairId(testUser.uid, bailey.uid),
      requesterId: bailey.uid,
      recipientId: testUser.uid,
      reader: bailey,
      createdAt: DateTime(2026, 9, 14),
    );
    final repository = FakeFriendRepository(
      friends: const [
        bailey,
        ReaderProfile(
          uid: 'casey-user',
          displayName: 'Casey Books',
          photoUrl: null,
          inviteCode: 'JKL456',
        ),
      ],
      incoming: [request],
      sent: [
        FriendRequestRecord(
          pairId: 'owner-user--third-user',
          requesterId: testUser.uid,
          recipientId: 'third-user',
          reader: const ReaderProfile(
            uid: 'third-user',
            displayName: 'Devon Pages',
            photoUrl: null,
            inviteCode: 'MNP678',
          ),
          createdAt: DateTime(2026, 9, 13),
        ),
      ],
    );
    await pumpFriends(tester, repository);

    expect(find.text('Your friends · 2'), findsOneWidget);
    expect(find.text('Bailey Reader'), findsOneWidget);
    expect(find.text('Casey Books'), findsOneWidget);
    expect(find.text('Requests · 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('friend-requests-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    await tester.tap(find.byKey(const Key('your-friends-tab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('friend-search-field')),
      'casey',
    );
    await tester.pump();
    expect(find.text('Casey Books'), findsOneWidget);
    expect(find.text('Bailey Reader'), findsNothing);
  });

  testWidgets('invite code flow distinguishes invalid and self codes', (
    tester,
  ) async {
    final repository = FakeFriendRepository(
      lookup: const InviteLookupResult(InviteLookupKind.self),
    );
    await pumpFriends(tester, repository);
    await tester.tap(find.byKey(const Key('empty-enter-code-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('invite-code-field')), '12');
    await tester.tap(find.byKey(const Key('find-friend-button')));
    await tester.pump();
    expect(find.text('Enter a 6-character friend code.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('invite-code-field')),
      'ABC-234',
    );
    await tester.tap(find.byKey(const Key('find-friend-button')));
    await tester.pumpAndSettle();
    expect(find.text('That is your own invite code.'), findsOneWidget);
    expect(repository.lastLookupCode, 'ABC234');
  });

  testWidgets('recipient accepts a pending request explicitly', (tester) async {
    final request = FriendRequestRecord(
      pairId: pairId(testUser.uid, bailey.uid),
      requesterId: bailey.uid,
      recipientId: testUser.uid,
      reader: bailey,
      createdAt: DateTime(2026, 9, 14),
    );
    final repository = FakeFriendRepository(incoming: [request]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: FriendRequestDetailScreen(
          repository: repository,
          userId: testUser.uid,
          request: request,
          incoming: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sent you a friend request.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('accept-request-button')));
    await tester.pumpAndSettle();
    expect(repository.acceptedPairId, request.pairId);
  });

  testWidgets('friend shelf is read-only and copied book uses safe defaults', (
    tester,
  ) async {
    final shelfRepository = SharedShelfRepository();
    final bookRepository = SharedBookRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: FriendProfileScreen(
          repository: FakeFriendRepository(friends: const [bailey]),
          shelfRepository: shelfRepository,
          bookRepository: bookRepository,
          userId: testUser.uid,
          friend: bailey,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shared reads'), findsOneWidget);

    await tester.tap(find.text('Shared reads'));
    await tester.pumpAndSettle();
    expect(find.text('Shared with friends'), findsOneWidget);
    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('Owned · Finished'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shared-book-shared-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-shared-book-state')), findsOneWidget);
    bookRepository.setSharedState(
      isOwned: false,
      readingStatus: ReadingStatus.reading,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('live-shared-book-state'))).data,
      'Not owned · Reading',
    );
    await tester.tap(find.byKey(const Key('add-shared-book-button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('copy-owned-switch')))
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('save-shared-book-button')));
    await tester.pumpAndSettle();
    expect(bookRepository.savedInput!.isOwned, isFalse);
    expect(bookRepository.savedInput!.readingStatus, ReadingStatus.wantToRead);
    expect(bookRepository.savedShelfId, 'mine');
    expect(find.text('On your reading list'), findsOneWidget);
    expect(
      tester
          .widget<SharedBookSavedScreen>(find.byType(SharedBookSavedScreen))
          .bookId,
      'saved-copy',
    );
    await tester.tap(find.text('Keep exploring'));
    await tester.pumpAndSettle();
    expect(find.byType(SharedBookSavedScreen), findsNothing);
  });

  testWidgets('shared shelf metadata updates live before access revokes', (
    tester,
  ) async {
    final shelfRepository = SharedShelfRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: FriendProfileScreen(
          repository: FakeFriendRepository(friends: const [bailey]),
          shelfRepository: shelfRepository,
          bookRepository: SharedBookRepository(),
          userId: testUser.uid,
          friend: bailey,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared reads'));
    await tester.pumpAndSettle();

    shelfRepository.setSharedShelf(
      shelfRepository.sharedShelf.copyWith(
        name: 'Renamed reads',
        visibility: ShelfVisibility.public,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Renamed reads'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);

    shelfRepository.setSharedShelf(null);
    await tester.pumpAndSettle();
    expect(find.text('Shelf unavailable'), findsOneWidget);
    expect(find.text('The Shared Book'), findsNothing);
  });

  testWidgets('friend removal dismisses an open remote book sheet', (
    tester,
  ) async {
    final friendRepository = RevocableFriendRepository();
    final shelfRepository = SharedShelfRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: FriendProfileScreen(
          repository: friendRepository,
          shelfRepository: shelfRepository,
          bookRepository: SharedBookRepository(),
          userId: testUser.uid,
          friend: bailey,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared reads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shared-book-shared-book')));
    await tester.pumpAndSettle();
    expect(find.text('Book details'), findsOneWidget);

    friendRepository.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('Book details'), findsNothing);
    expect(find.text('The Shared Book'), findsNothing);
  });

  testWidgets('private shelf revocation dismisses save and book sheets', (
    tester,
  ) async {
    final shelfRepository = SharedShelfRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: FriendProfileScreen(
          repository: FakeFriendRepository(friends: const [bailey]),
          shelfRepository: shelfRepository,
          bookRepository: SharedBookRepository(),
          userId: testUser.uid,
          friend: bailey,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared reads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shared-book-shared-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-shared-book-button')));
    await tester.pumpAndSettle();
    expect(find.text('Save to your library'), findsOneWidget);

    shelfRepository.setSharedShelf(null);
    await tester.pumpAndSettle();
    expect(find.text('Save to your library'), findsNothing);
    expect(find.text('Book details'), findsNothing);
    expect(find.byKey(const Key('save-shared-book-button')), findsNothing);
  });

  testWidgets('Friends Explore shows only owned books on accessible shelves', (
    tester,
  ) async {
    final shelfRepository = ExploreShelfRepository();
    final bookRepository = ExploreBookRepository();
    await pumpLibraryExplore(
      tester,
      friendRepository: RevocableFriendRepository(),
      shelfRepository: shelfRepository,
      bookRepository: bookRepository,
    );

    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('The Shared Book'), findsWidgets);
    expect(find.text('Saved but not owned'), findsNothing);
    expect(find.text('Private owned book'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('Friends Explore search preserves exact friend shelf and book', (
    tester,
  ) async {
    final shelfRepository = ExploreShelfRepository();
    final bookRepository = ExploreBookRepository();
    await pumpLibraryExplore(
      tester,
      friendRepository: RevocableFriendRepository(),
      shelfRepository: shelfRepository,
      bookRepository: bookRepository,
    );

    await tester.tap(find.byKey(const Key('library-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'Shared Book',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unified-explore')), findsOneWidget);
    expect(find.text('Bailey Reader'), findsOneWidget);

    await tester.tap(find.byKey(const Key('explore-book-shared-book')));
    await tester.pumpAndSettle();
    expect(find.text('Book details'), findsOneWidget);
    expect(
      find.text('Bailey Reader’s bookshelf\nShared reads · Friends'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('friend-book-see-more')), findsOneWidget);
  });

  testWidgets('Friends Explore revokes disconnected reader content live', (
    tester,
  ) async {
    final friendRepository = RevocableFriendRepository();
    await pumpLibraryExplore(
      tester,
      friendRepository: friendRepository,
      shelfRepository: ExploreShelfRepository(),
      bookRepository: ExploreBookRepository(),
    );
    expect(find.text('The Shared Book'), findsWidgets);

    friendRepository.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('The Shared Book'), findsNothing);
    expect(find.text('Nothing to explore yet'), findsOneWidget);
  });

  testWidgets('Friends Explore revokes shelf privacy and ownership live', (
    tester,
  ) async {
    final shelfRepository = ExploreShelfRepository();
    final bookRepository = ExploreBookRepository();
    await pumpLibraryExplore(
      tester,
      friendRepository: RevocableFriendRepository(),
      shelfRepository: shelfRepository,
      bookRepository: bookRepository,
    );
    expect(find.text('The Shared Book'), findsWidgets);

    bookRepository.revokeOwnership();
    await tester.pumpAndSettle();
    expect(find.text('The Shared Book'), findsNothing);
    expect(find.text('Nothing to explore yet'), findsOneWidget);

    bookRepository.restoreOwnership();
    await tester.pumpAndSettle();
    expect(find.text('The Shared Book'), findsWidgets);

    shelfRepository.makeSharedShelfPrivate();
    await tester.pumpAndSettle();
    expect(find.text('The Shared Book'), findsNothing);
    expect(find.text('Nothing to explore yet'), findsOneWidget);
  });

  testWidgets('Friends Explore retry replaces a failed live query', (
    tester,
  ) async {
    final friendRepository = RetryExploreFriendRepository();
    await pumpLibraryExplore(
      tester,
      friendRepository: friendRepository,
      shelfRepository: ExploreShelfRepository(),
      bookRepository: ExploreBookRepository(),
      settleAfterOpen: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Libraries couldn\u2019t be loaded.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('The Shared Book'), findsWidgets);
    expect(friendRepository.watchCount, 2);
  });

  testWidgets('Friends Explore duplicate ISBN never creates or resets entry', (
    tester,
  ) async {
    final shelfRepository = ExploreShelfRepository();
    final bookRepository = ExploreBookRepository(withExistingCopy: true);
    await pumpLibraryExplore(
      tester,
      friendRepository: RevocableFriendRepository(),
      shelfRepository: shelfRepository,
      bookRepository: bookRepository,
    );

    await tester.tap(find.byKey(const Key('explore-book-shared-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-shared-book-button')));
    await tester.pumpAndSettle();

    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.byKey(const Key('copy-book-existing')), findsOneWidget);
    expect(find.textContaining('as Reading'), findsOneWidget);
    expect(find.byKey(const Key('save-shared-book-button')), findsNothing);
    expect(bookRepository.savedInput, isNull);
  });

  testWidgets('Public Explore shows owned public books from multiple readers', (
    tester,
  ) async {
    final shelfRepository = PublicExploreShelfRepository();
    final bookRepository = PublicExploreBookRepository();
    await pumpLibraryExplore(
      tester,
      friendRepository: PublicExploreFriendRepository(),
      shelfRepository: shelfRepository,
      bookRepository: bookRepository,
    );

    await tester.pumpAndSettle();
    expect(find.text('Public Field Notes'), findsWidgets);
    expect(find.text('Public Quiet Futures'), findsWidgets);
    expect(find.text('Public saved only'), findsNothing);
    expect(
      find.byKey(const Key('explore-book-public-field-book')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const Key('unified-explore')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('explore-book-public-quiet-book')),
      findsOneWidget,
    );
  });

  testWidgets('Public Explore requires an exact ISBN identity match', (
    tester,
  ) async {
    await pumpLibraryExplore(
      tester,
      friendRepository: PublicExploreFriendRepository(),
      shelfRepository: PublicExploreShelfRepository(),
      bookRepository: PublicExploreBookRepository(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      '030640615',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unified-explore')), findsOneWidget);
    expect(find.text('No books found'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      '978-0-306-40615-7',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('explore-book-public-field-book')),
      findsOneWidget,
    );
  });

  testWidgets('Public Explore revokes retained detail and supports approval', (
    tester,
  ) async {
    final friendRepository = PublicExploreFriendRepository();
    final shelfRepository = PublicExploreShelfRepository();
    await pumpLibraryExplore(
      tester,
      friendRepository: friendRepository,
      shelfRepository: shelfRepository,
      bookRepository: PublicExploreBookRepository(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('explore-profile-other-user')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('public-reader-profile')), findsOneWidget);
    await tester.tap(find.byKey(const Key('public-send-friend-request')));
    await tester.pumpAndSettle();
    expect(find.text('Send friend request?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-public-friend-request')));
    await tester.pumpAndSettle();
    expect(friendRepository.sentRecipientId, bailey.uid);
    expect(find.text('Friend request sent for approval.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explore-book-public-field-book')));
    await tester.pumpAndSettle();
    expect(find.text('Public Field Notes'), findsWidgets);
    shelfRepository.revokeBaileyShelf();
    await tester.pumpAndSettle();
    expect(find.text('Public Field Notes'), findsNothing);
    expect(
      find.byKey(const Key('explore-book-public-field-book')),
      findsNothing,
    );
  });

  testWidgets('Public Explore labels partial results and retries directory', (
    tester,
  ) async {
    await pumpLibraryExplore(
      tester,
      friendRepository: PublicExploreFriendRepository(),
      shelfRepository: PartialPublicShelfRepository(),
      bookRepository: PublicExploreBookRepository(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Some libraries couldn\u2019t be loaded.'), findsOneWidget);
    expect(find.text('Public Field Notes'), findsWidgets);
    expect(find.text('Public Quiet Futures'), findsNothing);

    final retryRepository = RetryPublicShelfRepository();
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpLibraryExplore(
      tester,
      friendRepository: PublicExploreFriendRepository(),
      shelfRepository: retryRepository,
      bookRepository: PublicExploreBookRepository(),
      settleAfterOpen: false,
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Libraries couldn\u2019t be loaded.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Public Field Notes'), findsWidgets);
    expect(retryRepository.watchCount, 2);
  });

  testWidgets('Public Explore pagination restarts with a larger safe limit', (
    tester,
  ) async {
    final shelfRepository = PagingPublicShelfRepository();
    await pumpLibraryExplore(
      tester,
      friendRepository: PublicExploreFriendRepository(),
      shelfRepository: shelfRepository,
      bookRepository: PublicExploreBookRepository(),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('unified-explore')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(find.text('Public Quiet Futures'), findsNothing);
    expect(find.byKey(const Key('explore-load-more')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-load-more')));
    await tester.pumpAndSettle();
    expect(shelfRepository.requestedLimits, [20, 40]);
    expect(find.text('Public Quiet Futures'), findsWidgets);
    expect(find.byKey(const Key('explore-load-more')), findsNothing);
  });

  testWidgets('Public Explore duplicate ISBN never mutates the owned copy', (
    tester,
  ) async {
    final bookRepository = PublicExploreBookRepository(withExistingCopy: true);
    await pumpLibraryExplore(
      tester,
      friendRepository: PublicExploreFriendRepository(),
      shelfRepository: PublicExploreShelfRepository(),
      bookRepository: bookRepository,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explore-book-public-field-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-shared-book-button')));
    await tester.pumpAndSettle();
    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.byKey(const Key('save-shared-book-button')), findsNothing);
    expect(bookRepository.savedInput, isNull);
  });
}

Future<void> pumpLibraryExplore(
  WidgetTester tester, {
  required FriendRepository friendRepository,
  required ShelfRepository shelfRepository,
  required BookRepository bookRepository,
  bool settleAfterOpen = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: MyLibraryScreen(
        authService: const FakeAuthService(),
        shelfRepository: shelfRepository,
        bookRepository: bookRepository,
        bookLookupRepository: const EmptyBookLookupRepository(),
        friendRepository: friendRepository,
        user: testUser,
        showBottomNavigation: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('explore-library-tab')));
  if (settleAfterOpen) await tester.pumpAndSettle();
}

Future<void> pumpFriends(
  WidgetTester tester,
  FakeFriendRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: FriendsScreen(
        authService: const FakeAuthService(),
        repository: repository,
        shelfRepository: const EmptyShelfRepository(),
        bookRepository: const EmptyBookRepository(),
        user: testUser,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeFriendRepository implements FriendRepository {
  FakeFriendRepository({
    this.friends = const [],
    this.incoming = const [],
    this.sent = const [],
    this.blocked = const [],
    this.lookup = const InviteLookupResult(InviteLookupKind.unknown),
  });

  final List<ReaderProfile> friends;
  final List<FriendRequestRecord> incoming;
  final List<FriendRequestRecord> sent;
  final List<BlockedReader> blocked;
  final InviteLookupResult lookup;
  String? lastLookupCode;
  String? acceptedPairId;

  @override
  Future<ReaderProfile> ensureProfile(AuthUser user) async => ownerProfile;

  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) =>
      Stream.value(friends);

  @override
  Stream<List<FriendRequestRecord>> watchIncomingRequests(String userId) =>
      Stream.value(incoming);

  @override
  Stream<List<FriendRequestRecord>> watchSentRequests(String userId) =>
      Stream.value(sent);

  @override
  Stream<List<BlockedReader>> watchBlockedReaders(String userId) =>
      Stream.value(blocked);

  @override
  Future<InviteLookupResult> findByInviteCode({
    required String userId,
    required String code,
  }) async {
    lastLookupCode = code;
    return lookup;
  }

  @override
  Future<SendRequestOutcome> sendRequest({
    required String userId,
    required ReaderProfile recipient,
    required String inviteCode,
  }) async => SendRequestOutcome.sent;

  @override
  Future<void> acceptRequest({
    required String userId,
    required FriendRequestRecord request,
  }) async {
    acceptedPairId = request.pairId;
  }

  @override
  Future<void> declineRequest({
    required String userId,
    required FriendRequestRecord request,
  }) async {}

  @override
  Future<void> cancelRequest({
    required String userId,
    required FriendRequestRecord request,
  }) async {}

  @override
  Future<void> removeFriend({
    required String userId,
    required ReaderProfile friend,
  }) async {}

  @override
  Future<void> blockReader({
    required String userId,
    required ReaderProfile reader,
  }) async {}

  @override
  Future<void> unblockReader({
    required String userId,
    required String blockedUserId,
  }) async {}
}

class RevocableFriendRepository extends FakeFriendRepository {
  RevocableFriendRepository() : super(friends: const [bailey]);

  final StreamController<List<ReaderProfile>> _friendsController =
      StreamController<List<ReaderProfile>>.broadcast();

  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) async* {
    yield const [bailey];
    yield* _friendsController.stream;
  }

  void disconnect() => _friendsController.add(const []);
}

class RetryExploreFriendRepository extends FakeFriendRepository {
  int watchCount = 0;

  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) async* {
    watchCount += 1;
    if (watchCount == 1) {
      throw const FriendFailure('Libraries couldn\u2019t be loaded.');
    }
    yield const [bailey];
  }
}

class FakeAuthService implements AuthService {
  const FakeAuthService();

  @override
  AuthUser? get currentUser => testUser;

  @override
  Stream<AuthUser?> get userChanges => Stream.value(testUser);

  @override
  bool needsDisplayName(AuthUser user) => false;

  @override
  bool shouldStartFirstBookOnboarding(AuthUser user) => false;

  @override
  Future<AuthSignInResult> signIn(AuthProviderKind provider) async =>
      const AuthSignInResult(isNewUser: false);

  @override
  Future<void> signOut() async {}

  @override
  String? suggestedDisplayName(String uid) => null;

  @override
  Future<void> updateDisplayName(String displayName) async {}
}

class SharedShelfRepository implements ShelfRepository {
  final sharedShelf = Shelf(
    id: 'shared',
    ownerId: bailey.uid,
    name: 'Shared reads',
    visibility: ShelfVisibility.friends,
    autoShareActivity: true,
    bookCount: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final ownShelf = Shelf(
    id: 'mine',
    ownerId: testUser.uid,
    name: 'Want to read',
    visibility: ShelfVisibility.friends,
    autoShareActivity: true,
    bookCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final StreamController<Shelf?> _sharedShelfController =
      StreamController<Shelf?>.broadcast();

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) => Stream.value([ownShelf]);
  @override
  Stream<List<ShelfMutationOperation>> watchShelfOperations(String ownerId) =>
      Stream.value(const []);
  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) => Stream.value([sharedShelf]);
  @override
  Stream<Shelf?> watchSharedShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    yield sharedShelf;
    yield* _sharedShelfController.stream;
  }

  @override
  Future<Shelf> createShelf({
    required String ownerId,
    required CreateShelfInput input,
  }) async => sharedShelf;
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

  void setSharedShelf(Shelf? shelf) => _sharedShelfController.add(shelf);
}

class ExploreShelfRepository extends SharedShelfRepository {
  final StreamController<List<Shelf>> _exploreShelvesController =
      StreamController<List<Shelf>>.broadcast();

  final privateShelf = Shelf(
    id: 'private',
    ownerId: bailey.uid,
    name: 'Private notes',
    visibility: ShelfVisibility.private,
    autoShareActivity: false,
    bookCount: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) async* {
    yield [sharedShelf, privateShelf];
    yield* _exploreShelvesController.stream;
  }

  void makeSharedShelfPrivate() {
    _exploreShelvesController.add([
      Shelf(
        id: sharedShelf.id,
        ownerId: sharedShelf.ownerId,
        name: sharedShelf.name,
        visibility: ShelfVisibility.private,
        autoShareActivity: sharedShelf.autoShareActivity,
        bookCount: sharedShelf.bookCount,
        createdAt: sharedShelf.createdAt,
        updatedAt: sharedShelf.updatedAt,
      ),
      privateShelf,
    ]);
  }
}

class SharedBookRepository
    implements BookRepository, BookCreationReceiptSource {
  @override
  Future<String> createBookWithReceipt({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) async {
    await createBook(ownerId: ownerId, shelf: shelf, input: input);
    return 'saved-copy';
  }

  CreateBookInput? savedInput;
  String? savedShelfId;
  LibraryBook sharedBook = LibraryBook(
    id: 'shared-book',
    ownerId: bailey.uid,
    shelfId: 'shared',
    title: 'The Shared Book',
    author: 'A. Reader',
    isbn: null,
    isOwned: true,
    readingStatus: ReadingStatus.finished,
    coverUrl: null,
    createdAt: DateTime(2026),
  );
  final _sharedController = StreamController<List<LibraryBook>>.broadcast();

  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    yield [sharedBook];
    yield* _sharedController.stream;
  }

  void setSharedState({
    required bool isOwned,
    required ReadingStatus readingStatus,
  }) {
    sharedBook = LibraryBook(
      id: sharedBook.id,
      ownerId: sharedBook.ownerId,
      shelfId: sharedBook.shelfId,
      title: sharedBook.title,
      author: sharedBook.author,
      isbn: sharedBook.isbn,
      isOwned: isOwned,
      readingStatus: readingStatus,
      coverUrl: sharedBook.coverUrl,
      createdAt: sharedBook.createdAt,
    );
    _sharedController.add([sharedBook]);
  }

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) async {
    savedInput = input;
    savedShelfId = shelf.id;
  }

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) =>
      Stream.value(const []);
  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) => Stream.value(null);
  @override
  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  }) => Stream.value(const []);

  @override
  Future<void> updateReadingStatus({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required ReadingStatus readingStatus,
  }) async {}

  @override
  Future<void> updateOwnership({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required bool isOwned,
  }) async {}

  @override
  Future<void> moveBook({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
    required String bookId,
  }) async {}

  @override
  Future<void> removeBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required DateTime? expectedCreatedAt,
  }) async {}
}

class ExploreBookRepository extends SharedBookRepository {
  ExploreBookRepository({this.withExistingCopy = false}) {
    sharedBook = LibraryBook(
      id: 'shared-book',
      ownerId: bailey.uid,
      shelfId: 'shared',
      title: 'The Shared Book',
      author: 'A. Reader',
      isbn: '9780306406157',
      isOwned: true,
      readingStatus: ReadingStatus.finished,
      coverUrl: null,
      createdAt: DateTime(2026),
    );
  }

  final bool withExistingCopy;
  final StreamController<List<LibraryBook>> _exploreBooksController =
      StreamController<List<LibraryBook>>.broadcast();

  LibraryBook get notOwnedBook => LibraryBook(
    id: 'not-owned-book',
    ownerId: bailey.uid,
    shelfId: 'shared',
    title: 'Saved but not owned',
    author: 'A. Reader',
    isbn: '9780441172719',
    isOwned: false,
    readingStatus: ReadingStatus.wantToRead,
    coverUrl: null,
    createdAt: DateTime(2026),
  );

  LibraryBook get privateOwnedBook => LibraryBook(
    id: 'private-book',
    ownerId: bailey.uid,
    shelfId: 'private',
    title: 'Private owned book',
    author: 'A. Reader',
    isbn: '9780525559474',
    isOwned: true,
    readingStatus: ReadingStatus.wantToRead,
    coverUrl: null,
    createdAt: DateTime(2026),
  );

  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    if (shelfId == 'private') {
      yield [privateOwnedBook];
      return;
    }
    yield [sharedBook, notOwnedBook];
    yield* _exploreBooksController.stream;
  }

  void revokeOwnership() {
    sharedBook = LibraryBook(
      id: sharedBook.id,
      ownerId: sharedBook.ownerId,
      shelfId: sharedBook.shelfId,
      title: sharedBook.title,
      author: sharedBook.author,
      isbn: sharedBook.isbn,
      isOwned: false,
      readingStatus: sharedBook.readingStatus,
      coverUrl: sharedBook.coverUrl,
      createdAt: sharedBook.createdAt,
    );
    _exploreBooksController.add([sharedBook, notOwnedBook]);
  }

  void restoreOwnership() {
    sharedBook = LibraryBook(
      id: sharedBook.id,
      ownerId: sharedBook.ownerId,
      shelfId: sharedBook.shelfId,
      title: sharedBook.title,
      author: sharedBook.author,
      isbn: sharedBook.isbn,
      isOwned: true,
      readingStatus: sharedBook.readingStatus,
      coverUrl: sharedBook.coverUrl,
      createdAt: sharedBook.createdAt,
    );
    _exploreBooksController.add([sharedBook, notOwnedBook]);
  }

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) => Stream.value(
    withExistingCopy
        ? [
            LibraryBook(
              id: 'existing-book',
              ownerId: ownerId,
              shelfId: 'mine',
              title: 'My Shared Book',
              author: 'A. Reader',
              isbn: sharedBook.isbn,
              isOwned: false,
              readingStatus: ReadingStatus.reading,
              coverUrl: null,
              createdAt: DateTime(2025),
            ),
          ]
        : const [],
  );
}

class PublicExploreFriendRepository extends FakeFriendRepository
    implements PublicReaderQuerySource {
  String? sentRecipientId;

  @override
  Stream<ReaderProfile?> watchPublicReaderProfile({
    required String viewerId,
    required String readerId,
  }) => Stream.value(switch (readerId) {
    'other-user' => bailey,
    'casey-user' => caseyPublic,
    _ => null,
  });

  @override
  Future<SendRequestOutcome> sendRequest({
    required String userId,
    required ReaderProfile recipient,
    required String inviteCode,
  }) async {
    sentRecipientId = recipient.uid;
    return SendRequestOutcome.sent;
  }
}

class PublicExploreShelfRepository extends SharedShelfRepository
    implements PublicShelfQuerySource {
  final baileyShelf = Shelf(
    id: 'public-field',
    ownerId: bailey.uid,
    name: 'Field notes',
    visibility: ShelfVisibility.public,
    autoShareActivity: false,
    bookCount: 2,
    createdAt: DateTime(2026, 9, 2),
    updatedAt: DateTime(2026, 9, 2),
  );
  final caseyShelf = Shelf(
    id: 'public-quiet',
    ownerId: caseyPublic.uid,
    name: 'Quiet futures',
    visibility: ShelfVisibility.public,
    autoShareActivity: false,
    bookCount: 1,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );
  final _baileyShelfController = StreamController<Shelf?>.broadcast();

  @override
  Stream<PublicShelfReferencePage> watchPublicShelfReferencePage({
    required String viewerId,
    required int limit,
  }) {
    final references = [
      PublicShelfReference(ownerId: bailey.uid, shelfId: baileyShelf.id),
      PublicShelfReference(ownerId: caseyPublic.uid, shelfId: caseyShelf.id),
    ].take(limit).toList();
    return Stream.value(
      PublicShelfReferencePage(
        references: references,
        sourceCount: references.length,
        hasMore: false,
      ),
    );
  }

  @override
  Stream<Shelf?> watchPublicShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    if (shelfId == baileyShelf.id && ownerId == bailey.uid) {
      yield baileyShelf;
      yield* _baileyShelfController.stream;
      return;
    }
    if (shelfId == caseyShelf.id && ownerId == caseyPublic.uid) {
      yield caseyShelf;
      return;
    }
    yield null;
  }

  @override
  Stream<List<Shelf>> watchPublicShelvesByOwner({
    required String viewerId,
    required String ownerId,
  }) async* {
    if (ownerId == bailey.uid) {
      yield [baileyShelf];
      await for (final shelf in _baileyShelfController.stream) {
        yield shelf == null ? const [] : [shelf];
      }
      return;
    }
    if (ownerId == caseyPublic.uid) yield [caseyShelf];
  }

  void revokeBaileyShelf() => _baileyShelfController.add(null);
}

class PartialPublicShelfRepository extends PublicExploreShelfRepository {
  @override
  Stream<Shelf?> watchPublicShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) {
    if (ownerId == caseyPublic.uid) {
      return Stream.error(
        const ShelfFailure('This public shelf is unavailable.'),
      );
    }
    return super.watchPublicShelf(
      viewerId: viewerId,
      ownerId: ownerId,
      shelfId: shelfId,
    );
  }
}

class RetryPublicShelfRepository extends PublicExploreShelfRepository {
  int watchCount = 0;

  @override
  Stream<PublicShelfReferencePage> watchPublicShelfReferencePage({
    required String viewerId,
    required int limit,
  }) async* {
    watchCount += 1;
    if (watchCount == 1) {
      throw const ShelfFailure('Libraries couldn\u2019t be loaded.');
    }
    yield* super.watchPublicShelfReferencePage(
      viewerId: viewerId,
      limit: limit,
    );
  }
}

class PagingPublicShelfRepository extends PublicExploreShelfRepository {
  final List<int> requestedLimits = [];

  @override
  Stream<PublicShelfReferencePage> watchPublicShelfReferencePage({
    required String viewerId,
    required int limit,
  }) {
    requestedLimits.add(limit);
    final sourceReferences = <PublicShelfReference>[
      PublicShelfReference(ownerId: viewerId, shelfId: 'viewer-public'),
      PublicShelfReference(ownerId: bailey.uid, shelfId: baileyShelf.id),
      for (var index = 2; index < 20; index += 1)
        PublicShelfReference(
          ownerId: bailey.uid,
          shelfId: 'stale-public-$index',
        ),
      PublicShelfReference(ownerId: caseyPublic.uid, shelfId: caseyShelf.id),
    ];
    final sourcePage = sourceReferences.take(limit).toList();
    return Stream.value(
      PublicShelfReferencePage(
        references: sourcePage
            .where((reference) => reference.ownerId != viewerId)
            .toList(),
        sourceCount: sourcePage.length,
        hasMore: sourceReferences.length > limit,
      ),
    );
  }
}

class PublicExploreBookRepository extends SharedBookRepository {
  PublicExploreBookRepository({this.withExistingCopy = false});

  final bool withExistingCopy;

  final publicFieldBook = LibraryBook(
    id: 'public-field-book',
    ownerId: bailey.uid,
    shelfId: 'public-field',
    title: 'Public Field Notes',
    author: 'R. Explorer',
    isbn: '9780306406157',
    isOwned: true,
    readingStatus: ReadingStatus.reading,
    coverUrl: null,
    createdAt: DateTime(2026),
  );
  final publicSavedOnly = LibraryBook(
    id: 'public-saved-only',
    ownerId: bailey.uid,
    shelfId: 'public-field',
    title: 'Public saved only',
    author: 'R. Explorer',
    isbn: '9780441172719',
    isOwned: false,
    readingStatus: ReadingStatus.wantToRead,
    coverUrl: null,
    createdAt: DateTime(2026),
  );
  final publicQuietBook = LibraryBook(
    id: 'public-quiet-book',
    ownerId: caseyPublic.uid,
    shelfId: 'public-quiet',
    title: 'Public Quiet Futures',
    author: 'C. Reader',
    isbn: '9780525559474',
    isOwned: true,
    readingStatus: ReadingStatus.finished,
    coverUrl: null,
    createdAt: DateTime(2026),
  );

  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) => Stream.value(switch (shelfId) {
    'public-field' => [publicFieldBook, publicSavedOnly],
    'public-quiet' => [publicQuietBook],
    _ => const <LibraryBook>[],
  });

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) => Stream.value(
    withExistingCopy
        ? [
            LibraryBook(
              id: 'owned-copy',
              ownerId: ownerId,
              shelfId: 'mine',
              title: 'My Public Field Notes',
              author: publicFieldBook.author,
              isbn: publicFieldBook.isbn,
              isOwned: false,
              readingStatus: ReadingStatus.reading,
              coverUrl: null,
              createdAt: DateTime(2025),
            ),
          ]
        : const [],
  );
}
