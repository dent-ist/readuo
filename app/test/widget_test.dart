import 'library_navigation_helpers.dart';
import 'dart:async';
import 'memory_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/auth/auth_service.dart';
import 'package:readuo/friends/friend_repository.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/main.dart';
import 'package:readuo/onboarding/onboarding_repository.dart';
import 'package:readuo/screens/account_screen.dart';
import 'package:readuo/screens/friends_screen.dart';
import 'package:readuo/screens/login_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';

void main() {
  setUp(useMemoryPreferences);
  testWidgets('shows Google auth and defers Apple setup', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Apple sign-in coming later'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('apple-sign-in-button')))
          .onPressed,
      isNull,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('new Google user begins durable first-book onboarding', (
    tester,
  ) async {
    final auth = FakeAuthService(
      signInUser: user(displayName: null),
      suggestedNameValue: 'Provider Name',
    );
    final onboarding = FakeOnboardingRepository();
    await tester.pumpWidget(
      ReaduoApp(authService: auth, onboardingRepository: onboarding),
    );
    await tester.pumpAndSettle();

    await tapGoogle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Make yourself at home'), findsOneWidget);
    expect(find.text('Provider Name'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('display-name-field')),
      'Reader One',
    );
    await tester.tap(find.byKey(const Key('save-profile-button')));
    await tester.pumpAndSettle();

    expect(find.text('Your library starts here'), findsOneWidget);
    expect(find.text('Make room for your first book'), findsOneWidget);
    expect(find.text('Scan my first book'), findsOneWidget);
    expect(find.text('Search for a book instead'), findsOneWidget);
    expect(find.text('Add a book manually'), findsOneWidget);
    expect(find.text('I’ll do this later'), findsOneWidget);
    expect(auth.savedDisplayName, 'Reader One');
    expect(
      onboarding.statuses['firebase-uid-123'],
      FirstBookOnboardingStatus.pending,
    );
    expect(onboarding.beginOwnerIds, ['firebase-uid-123']);
  });

  testWidgets('existing user without onboarding state bypasses first book', (
    tester,
  ) async {
    final auth = FakeAuthService(current: user(displayName: 'Existing Reader'));
    final onboarding = FakeOnboardingRepository();

    await tester.pumpWidget(
      ReaduoApp(authService: auth, onboardingRepository: onboarding),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Library'), findsOneWidget);
    expect(find.byKey(const Key('first-book-onboarding')), findsNothing);
  });

  testWidgets(
    'skipping first-book setup retries and stays skipped on restart',
    (tester) async {
      final currentUser = user(displayName: 'Skip Reader');
      final auth = FakeAuthService(current: currentUser);
      final onboarding = FakeOnboardingRepository(
        statuses: {currentUser.uid: FirstBookOnboardingStatus.pending},
        skipFailuresRemaining: 1,
      );

      await tester.pumpWidget(
        ReaduoApp(authService: auth, onboardingRepository: onboarding),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('first-book-skip')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('first-book-onboarding')), findsOneWidget);
      expect(
        find.text('Could not save this choice. Please retry.'),
        findsOneWidget,
      );
      expect(
        onboarding.statuses[currentUser.uid],
        FirstBookOnboardingStatus.pending,
      );

      await tester.tap(find.byKey(const Key('first-book-retry')));
      await tester.pumpAndSettle();
      expect(find.text('My Library'), findsOneWidget);
      expect(
        onboarding.statuses[currentUser.uid],
        FirstBookOnboardingStatus.skipped,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ReaduoApp(authService: auth, onboardingRepository: onboarding),
      );
      await tester.pumpAndSettle();
      expect(find.text('My Library'), findsOneWidget);
      expect(find.byKey(const Key('first-book-onboarding')), findsNothing);
    },
  );

  testWidgets('first-book state remains isolated between signed-in users', (
    tester,
  ) async {
    final firstUser = user(displayName: 'First Reader', uid: 'first-user');
    final secondUser = user(displayName: 'Second Reader', uid: 'second-user');
    final auth = FakeAuthService(current: firstUser);
    final onboarding = FakeOnboardingRepository(
      statuses: {
        firstUser.uid: FirstBookOnboardingStatus.pending,
        secondUser.uid: FirstBookOnboardingStatus.completed,
      },
    );

    await tester.pumpWidget(
      ReaduoApp(authService: auth, onboardingRepository: onboarding),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('first-book-onboarding')), findsOneWidget);

    auth.switchUser(secondUser);
    await tester.pumpAndSettle();
    expect(find.text('My Library'), findsOneWidget);
    expect(find.byKey(const Key('first-book-onboarding')), findsNothing);

    auth.switchUser(firstUser);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('first-book-onboarding')), findsOneWidget);
  });

  testWidgets(
    'manual first-book save preserves draft on failure and completes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final currentUser = user(displayName: 'Manual Reader');
      final auth = FakeAuthService(current: currentUser);
      final onboarding = FakeOnboardingRepository(
        statuses: {currentUser.uid: FirstBookOnboardingStatus.pending},
      );
      final shelves = FakeShelfRepository();
      final books = _OnboardingBookRepository(createFailuresRemaining: 1);

      await tester.pumpWidget(
        ReaduoApp(
          authService: auth,
          onboardingRepository: onboarding,
          shelfRepository: shelves,
          bookRepository: books,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('first-book-manual')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('catalogue-title-field')),
        'Draft Book',
      );
      await tester.enterText(
        find.byKey(const Key('catalogue-author-field')),
        'Draft Author',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalogue-create-shelf')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('shelf-name-field')),
        'First shelf',
      );
      await tester.ensureVisible(find.byKey(const Key('save-shelf-button')));
      await tester.tap(find.byKey(const Key('save-shelf-button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('catalogue-save-button')),
      );
      await tester.tap(find.byKey(const Key('catalogue-save-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save this book. Please retry.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('catalogue-title-field')))
            .controller!
            .text,
        'Draft Book',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('catalogue-author-field')))
            .controller!
            .text,
        'Draft Author',
      );

      await tester.tap(find.byKey(const Key('catalogue-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('My Library'), findsOneWidget);
      expect(
        onboarding.statuses[currentUser.uid],
        FirstBookOnboardingStatus.completed,
      );
      expect(books.savedOwnerId, currentUser.uid);
      expect(books.savedShelfId, 'shelf-1');
      expect(books.savedInput?.title, 'Draft Book');
      expect(books.savedInput?.author, 'Draft Author');
    },
  );

  testWidgets('empty display name is rejected', (tester) async {
    final auth = FakeAuthService(current: user(displayName: null));
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-profile-button')));
    await tester.pump();

    expect(
      find.text('Enter a display name of 1–80 characters to continue.'),
      findsOneWidget,
    );
    expect(auth.savedDisplayName, isNull);
  });

  testWidgets('existing session restores and signs out', (tester) async {
    final auth = FakeAuthService(current: user(displayName: 'Restored Reader'));
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();

    expect(find.text('My Library'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Restored Reader'), findsOneWidget);
    await confirmProfileSignOut(tester);
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(auth.signOutCount, 1);
  });

  testWidgets('deep Friends Profile logout clears every authenticated route', (
    tester,
  ) async {
    final auth = FakeAuthService(current: user(displayName: 'First Reader'));
    await tester.pumpWidget(
      ReaduoApp(
        authService: auth,
        friendRepository: NavigationFriendRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-friends')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-profile')));
    await tester.pumpAndSettle();
    expect(find.text('First Reader'), findsOneWidget);

    await confirmProfileSignOut(tester);
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Friends'), findsNothing);
    expect(find.text('First Reader'), findsNothing);
  });

  testWidgets('shelf Profile logout cannot reveal the old shelf with Back', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Shelf Reader');
    final auth = FakeAuthService(current: currentUser);
    final shelves = FakeShelfRepository(
      initialShelves: {
        currentUser.uid: [
          shelf(
            id: 'private-stack',
            ownerId: currentUser.uid,
            name: 'Old shelf',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(authService: auth, shelfRepository: shelves),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shelf-private-stack')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-profile')));
    await tester.pumpAndSettle();
    await confirmProfileSignOut(tester);
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Old shelf'), findsNothing);
  });

  testWidgets(
    'external session loss clears friend detail and next-user state',
    (tester) async {
      final firstUser = user(displayName: 'First Reader', uid: 'first-user');
      final secondUser = user(displayName: 'Second Reader', uid: 'second-user');
      final auth = FakeAuthService(current: firstUser);
      final shelves = FakeShelfRepository(
        initialShelves: {
          firstUser.uid: [
            shelf(id: 'first', ownerId: firstUser.uid, name: 'First shelf'),
          ],
          secondUser.uid: [
            shelf(id: 'second', ownerId: secondUser.uid, name: 'Second shelf'),
          ],
        },
      );
      await tester.pumpWidget(
        ReaduoApp(
          authService: auth,
          shelfRepository: shelves,
          friendRepository: NavigationFriendRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-friends')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bailey Reader'));
      await tester.pumpAndSettle();
      expect(find.text('Reader profile'), findsOneWidget);

      auth.expireSession();
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Bailey Reader'), findsNothing);

      auth.switchUser(secondUser);
      await tester.pumpAndSettle();
      expect(find.text('Second shelf'), findsOneWidget);
      expect(find.text('First shelf'), findsNothing);
      expect(find.text('Bailey Reader'), findsNothing);
    },
  );

  testWidgets('external session loss dismisses authenticated modal', (
    tester,
  ) async {
    final auth = FakeAuthService(current: user(displayName: 'Reader'));
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library-add-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-create-bookshelf-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-name-field')), findsOneWidget);

    auth.expireSession();
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const Key('shelf-name-field')), findsNothing);
  });

  testWidgets(
    'same-user refresh preserves route and Back while UID switch resets',
    (tester) async {
      final firstUser = user(displayName: 'First Reader', uid: 'first-user');
      final secondUser = user(displayName: 'Second Reader', uid: 'second-user');
      final auth = FakeAuthService(current: firstUser);
      final shelves = FakeShelfRepository(
        initialShelves: {
          firstUser.uid: [
            shelf(id: 'first', ownerId: firstUser.uid, name: 'First shelf'),
          ],
          secondUser.uid: [
            shelf(id: 'second', ownerId: secondUser.uid, name: 'Second shelf'),
          ],
        },
      );
      await tester.pumpWidget(
        ReaduoApp(authService: auth, shelfRepository: shelves),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shelf-first')));
      await tester.pumpAndSettle();

      auth.switchUser(
        user(displayName: 'Refreshed Reader', uid: firstUser.uid),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-book-button')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('My Library'), findsOneWidget);
      expect(find.text('First shelf'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shelf-first')));
      await tester.pumpAndSettle();
      auth.switchUser(secondUser);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-book-button')), findsNothing);
      expect(find.text('Second shelf'), findsOneWidget);
      expect(find.text('First shelf'), findsNothing);
    },
  );

  testWidgets('sign-out failure stays retryable on Account', (tester) async {
    final auth = FakeAuthService(
      current: user(displayName: 'Retry Reader'),
      signOutFailuresRemaining: 1,
    );
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Retry Reader'), findsOneWidget);
    await openProfileSignOutConfirmation(tester);
    expect(auth.signOutCount, 0);
    expect(auth.currentUser?.displayName, 'Retry Reader');
    await tester.tap(find.byKey(const Key('confirm-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Could not sign out. Please try again.'), findsOneWidget);
    expect(find.text('Sign out of Readuo?'), findsOneWidget);
    expect(auth.currentUser?.displayName, 'Retry Reader');
    expect(auth.signOutCount, 1);

    await tester.tap(find.byKey(const Key('confirm-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(auth.signOutCount, 2);
  });

  testWidgets('cancellation stays signed out without an error banner', (
    tester,
  ) async {
    final auth = FakeAuthService(
      signInFailure: const AuthFailure(
        AuthFailureKind.cancelled,
        'Sign-in was canceled.',
      ),
    );
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();

    await tapGoogle(tester);
    await tester.pump();

    expect(find.text('Sign-in canceled.'), findsOneWidget);
    expect(find.byKey(const Key('auth-error')), findsNothing);
  });

  testWidgets('account conflict explains the non-merging policy', (
    tester,
  ) async {
    final auth = FakeAuthService(
      signInFailure: const AuthFailure(
        AuthFailureKind.accountConflict,
        'An account already exists for this email through another provider. '
        'Sign in with that provider first. Readuo never links accounts '
        'automatically.',
      ),
    );
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();

    await tapGoogle(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-error')), findsOneWidget);
    expect(
      find.textContaining('never links accounts automatically'),
      findsOneWidget,
    );
  });

  testWidgets('provider buttons disable while Google sign-in is pending', (
    tester,
  ) async {
    final completer = Completer<AuthSignInResult>();
    final auth = FakeAuthService(signInCompleter: completer);
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();

    await tapGoogle(tester);
    await tester.pump();

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('google-sign-in-button')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const AuthSignInResult(isNewUser: false));
    await tester.pumpAndSettle();
  });

  testWidgets('portrait login fits without scrolling above Android insets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in const [
      Size(360, 640),
      Size(360, 800),
      Size(390, 844),
      Size(412, 915),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        loginHarness(
          FakeAuthService(),
          size: size,
          padding: const EdgeInsets.only(top: 24, bottom: 48),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('login-scroll-view')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, 0, reason: '$size');
      expect(
        find.byKey(const Key('google-sign-in-button')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Privacy notice').hitTestable(), findsOneWidget);
      final googleTop = tester
          .getTopLeft(find.byKey(const Key('google-sign-in-button')))
          .dy;
      await tester.drag(
        find.byKey(const Key('login-scroll-view')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const Key('google-sign-in-button'))).dy,
        googleTop,
        reason: '$size',
      );
    }
  });

  testWidgets('genuine-overflow login remains scrollable', (tester) async {
    tester.view.physicalSize = const Size(320, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuthService();

    await tester.pumpWidget(
      loginHarness(
        auth,
        size: const Size(320, 500),
        padding: const EdgeInsets.only(top: 24, bottom: 48),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('login-scroll-view')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.ensureVisible(find.text('Privacy notice'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy notice').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a Friends shelf with automatic sharing on by default', (
    tester,
  ) async {
    final auth = FakeAuthService(current: user(displayName: 'Reader'));
    final shelves = FakeShelfRepository();
    await tester.pumpWidget(
      ReaduoApp(authService: auth, shelfRepository: shelves),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library-add-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-create-bookshelf-button')));
    await tester.pumpAndSettle();

    final visibilityTiles = tester
        .widgetList<RadioListTile<ShelfVisibility>>(
          find.byType(RadioListTile<ShelfVisibility>),
        )
        .toList();
    final autoShare = tester.widget<SwitchListTile>(
      find.byKey(const Key('auto-share-switch')),
    );
    expect(visibilityTiles.map((tile) => tile.value), [
      ShelfVisibility.private,
      ShelfVisibility.friends,
      ShelfVisibility.public,
    ]);
    expect(
      tester
          .widget<RadioGroup<ShelfVisibility>>(
            find.byType(RadioGroup<ShelfVisibility>),
          )
          .groupValue,
      ShelfVisibility.friends,
    );
    expect(autoShare.value, isTrue);

    await tester.enterText(
      find.byKey(const Key('shelf-name-field')),
      'Want to read',
    );
    await tester.ensureVisible(find.byKey(const Key('save-shelf-button')));
    await tester.tap(find.byKey(const Key('save-shelf-button')));
    await tester.pumpAndSettle();

    expect(shelves.lastOwnerId, auth.currentUser!.uid);
    expect(shelves.lastInput!.visibility, ShelfVisibility.friends);
    expect(shelves.lastInput!.autoShareActivity, isTrue);
    expect(find.text('Want to read'), findsWidgets);
  });

  testWidgets('private shelf disables and clears automatic sharing', (
    tester,
  ) async {
    final auth = FakeAuthService(current: user(displayName: 'Reader'));
    final shelves = FakeShelfRepository();
    await tester.pumpWidget(
      ReaduoApp(authService: auth, shelfRepository: shelves),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-add-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-create-bookshelf-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Private'));
    await tester.pump();
    final autoShare = tester.widget<SwitchListTile>(
      find.byKey(const Key('auto-share-switch')),
    );
    expect(autoShare.value, isFalse);
    expect(autoShare.onChanged, isNull);
    expect(find.text('Private shelves keep activity private.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('shelf-name-field')),
      'Personal notes',
    );
    await tester.ensureVisible(find.byKey(const Key('save-shelf-button')));
    await tester.tap(find.byKey(const Key('save-shelf-button')));
    await tester.pumpAndSettle();

    expect(shelves.lastInput!.visibility, ShelfVisibility.private);
    expect(shelves.lastInput!.autoShareActivity, isFalse);
  });

  testWidgets('requires a shelf name before saving', (tester) async {
    final auth = FakeAuthService(current: user(displayName: 'Reader'));
    final shelves = FakeShelfRepository();
    await tester.pumpWidget(
      ReaduoApp(authService: auth, shelfRepository: shelves),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-add-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-create-bookshelf-button')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('save-shelf-button')));
    await tester.tap(find.byKey(const Key('save-shelf-button')));
    await tester.pump();

    expect(find.text('Enter a shelf name.'), findsOneWidget);
    expect(shelves.lastInput, isNull);
  });

  testWidgets('switching accounts never shows the previous user shelves', (
    tester,
  ) async {
    final firstUser = user(displayName: 'First', uid: 'first-user');
    final secondUser = user(displayName: 'Second', uid: 'second-user');
    final auth = FakeAuthService(current: firstUser);
    final shelves = FakeShelfRepository(
      initialShelves: {
        firstUser.uid: [
          shelf(id: 'first', ownerId: firstUser.uid, name: 'First shelf'),
        ],
        secondUser.uid: [
          shelf(id: 'second', ownerId: secondUser.uid, name: 'Second shelf'),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(authService: auth, shelfRepository: shelves),
    );
    await tester.pumpAndSettle();
    expect(find.text('First shelf'), findsOneWidget);
    expect(find.text('Second shelf'), findsNothing);

    auth.switchUser(secondUser);
    await tester.pumpAndSettle();

    expect(find.text('First shelf'), findsNothing);
    expect(find.text('Second shelf'), findsOneWidget);
  });

  testWidgets('owned shelf opens its book list and empty state', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Reader');
    final auth = FakeAuthService(current: currentUser);
    final shelves = FakeShelfRepository(
      initialShelves: {
        currentUser.uid: [
          shelf(
            id: 'owned-shelf',
            ownerId: currentUser.uid,
            name: 'Owned shelf',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(authService: auth, shelfRepository: shelves),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shelf-owned-shelf')));
    await tester.pumpAndSettle();

    expect(find.text('Owned shelf'), findsOneWidget);
    expect(find.text('This shelf is empty'), findsOneWidget);
    expect(find.byKey(const Key('add-book-button')), findsOneWidget);
  });

  testWidgets('shelf settings edit metadata without changing book count', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Reader');
    final original = shelf(
      id: 'editable',
      ownerId: currentUser.uid,
      name: 'Weekend reads',
      bookCount: 7,
    );
    final auth = FakeAuthService(current: currentUser);
    final shelves = FakeShelfRepository(
      initialShelves: {
        currentUser.uid: [original],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(authService: auth, shelfRepository: shelves),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-editable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shelf settings'));
    await tester.pumpAndSettle();

    expect(find.text('Shelf settings'), findsOneWidget);
    expect(
      tester
          .widgetList<RadioListTile<ShelfVisibility>>(
            find.byType(RadioListTile<ShelfVisibility>),
          )
          .map((tile) => tile.value),
      [
        ShelfVisibility.friends,
        ShelfVisibility.private,
        ShelfVisibility.public,
      ],
    );
    await tester.enterText(
      find.byKey(const Key('settings-shelf-name-field')),
      'Field notes',
    );
    await tester.enterText(
      find.byKey(const Key('settings-shelf-description-field')),
      'Books for the road',
    );
    await tester.tap(find.byKey(const Key('settings-visibility-public')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-auto-share-switch')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-shelf-settings-button')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('save-shelf-settings-button')));
    await tester.pumpAndSettle();

    expect(shelves.lastUpdateOwnerId, currentUser.uid);
    expect(shelves.lastUpdateShelfId, original.id);
    expect(shelves.lastUpdateInput!.name, 'Field notes');
    expect(shelves.lastUpdateInput!.description, 'Books for the road');
    expect(shelves.lastUpdateInput!.visibility, ShelfVisibility.public);
    expect(shelves.lastUpdateInput!.autoShareActivity, isFalse);
    expect(shelves.shelfFor(currentUser.uid, original.id).bookCount, 7);
    expect(find.text('Field notes'), findsOneWidget);
    expect(find.text('Books for the road'), findsOneWidget);
    expect(find.textContaining('Automatic activity off'), findsOneWidget);
  });

  testWidgets(
    'making a shelf Private requires confirmation and forces sharing off',
    (tester) async {
      final currentUser = user(displayName: 'Reader');
      final shelves = FakeShelfRepository(
        initialShelves: {
          currentUser.uid: [
            shelf(id: 'shared', ownerId: currentUser.uid, name: 'Shared shelf'),
          ],
        },
      );
      await tester.pumpWidget(
        ReaduoApp(
          authService: FakeAuthService(current: currentUser),
          shelfRepository: shelves,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shelf-shared')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shelf-settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shelf settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-visibility-private')));
      await tester.pumpAndSettle();
      expect(find.text('Make this shelf private?'), findsOneWidget);
      expect(
        find.text('Automatic posting will be turned off.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('keep-shelf-visibility-button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<ShelfVisibility>>(
              find.byType(RadioGroup<ShelfVisibility>),
            )
            .groupValue,
        ShelfVisibility.friends,
      );

      await tester.tap(find.byKey(const Key('settings-visibility-private')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-private-shelf-button')));
      await tester.pumpAndSettle();
      final shareSwitch = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings-auto-share-switch')),
      );
      expect(shareSwitch.value, isFalse);
      expect(shareSwitch.onChanged, isNull);
      expect(
        find.text('Private shelves never post to Circle.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('save-shelf-settings-button')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('save-shelf-settings-button')));
      await tester.pumpAndSettle();
      expect(shelves.lastUpdateInput!.visibility, ShelfVisibility.private);
      expect(shelves.lastUpdateInput!.autoShareActivity, isFalse);
    },
  );

  testWidgets('shelf settings failure remains retryable', (tester) async {
    final currentUser = user(displayName: 'Reader');
    final shelves = FakeShelfRepository(
      updateFailuresRemaining: 1,
      initialShelves: {
        currentUser.uid: [
          shelf(id: 'retry', ownerId: currentUser.uid, name: 'Retry shelf'),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: shelves,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-retry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shelf settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings-shelf-name-field')),
      'Retry succeeded',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-shelf-settings-button')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(
      find.byKey(const Key('save-shelf-settings-button')),
    );
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.byKey(const Key('save-shelf-settings-button')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-shelf-error')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('save-shelf-settings-button')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(
      find.byKey(const Key('save-shelf-settings-button')),
    );
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.byKey(const Key('save-shelf-settings-button')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Retry succeeded'), findsOneWidget);
    expect(shelves.updateAttempts, 2);
  });

  testWidgets('moves every book count then deletes the source shelf', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Reader');
    final shelves = FakeShelfRepository(
      initialShelves: {
        currentUser.uid: [
          shelf(
            id: 'source',
            ownerId: currentUser.uid,
            name: 'Source shelf',
            bookCount: 2,
          ),
          shelf(
            id: 'destination',
            ownerId: currentUser.uid,
            name: 'Destination shelf',
            visibility: ShelfVisibility.private,
            autoShareActivity: false,
            bookCount: 3,
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: shelves,
      ),
    );
    await tester.pumpAndSettle();
    await openDeleteShelfFlow(tester, 'source');

    expect(
      find.text('What would you like to do with the books?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('move-all-choice')));
    await tester.pumpAndSettle();
    expect(find.text('Move books first'), findsOneWidget);
    expect(find.byKey(const Key('move-destination-source')), findsNothing);
    expect(find.text('3 books · Private'), findsOneWidget);
    await tester.tap(find.byKey(const Key('move-all-books-button')));
    await tester.pumpAndSettle();

    expect(shelves.lastMoveSourceId, 'source');
    expect(shelves.lastMoveDestinationId, 'destination');
    expect(find.text('Source shelf'), findsNothing);
    expect(shelves.shelfFor(currentUser.uid, 'destination').bookCount, 5);
  });

  testWidgets(
    'remove confirmation cancels and failed removal stays retryable',
    (tester) async {
      final currentUser = user(displayName: 'Reader');
      final shelves = FakeShelfRepository(
        mutationFailuresRemaining: 1,
        initialShelves: {
          currentUser.uid: [
            shelf(
              id: 'remove',
              ownerId: currentUser.uid,
              name: 'Remove me',
              bookCount: 2,
            ),
          ],
        },
      );
      await tester.pumpWidget(
        ReaduoApp(
          authService: FakeAuthService(current: currentUser),
          shelfRepository: shelves,
        ),
      );
      await tester.pumpAndSettle();
      await openDeleteShelfFlow(tester, 'remove');

      await tester.tap(find.byKey(const Key('remove-shelf-and-books-choice')));
      await tester.pumpAndSettle();
      expect(find.text('Remove shelf and 2 books?'), findsOneWidget);
      expect(find.textContaining('This cannot be undone.'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('cancel-confirm-delete-shelf-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete shelf'), findsOneWidget);
      expect(find.text('Remove me'), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove-shelf-and-books-choice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete-shelf-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-shelf-error')), findsOneWidget);
      expect(find.text('Remove me'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-delete-shelf-button')));
      await tester.pumpAndSettle();

      expect(shelves.deleteAttempts, 2);
      expect(shelves.lastDeleteShelfId, 'remove');
      expect(find.text('Remove me'), findsNothing);
    },
  );

  testWidgets('empty shelf removal is guarded against double submit', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Reader');
    final completer = Completer<void>();
    final shelves = FakeShelfRepository(
      mutationCompleter: completer,
      initialShelves: {
        currentUser.uid: [
          shelf(
            id: 'empty-delete',
            ownerId: currentUser.uid,
            name: 'Empty shelf',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: shelves,
      ),
    );
    await tester.pumpAndSettle();
    await openDeleteShelfFlow(tester, 'empty-delete');
    await tester.tap(find.byKey(const Key('remove-shelf-and-books-choice')));
    await tester.pumpAndSettle();
    expect(find.text('Remove shelf and 0 books?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-shelf-button')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-delete-shelf-button')),
          )
          .onPressed,
      isNull,
    );
    expect(shelves.deleteAttempts, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Empty shelf'), findsNothing);
    expect(shelves.deleteAttempts, 1);
  });

  testWidgets('removed move destination disables submission safely', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Reader');
    final shelves = FakeShelfRepository(
      initialShelves: {
        currentUser.uid: [
          shelf(
            id: 'source-live',
            ownerId: currentUser.uid,
            name: 'Source live',
            bookCount: 1,
          ),
          shelf(
            id: 'target-live',
            ownerId: currentUser.uid,
            name: 'Target live',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: shelves,
      ),
    );
    await tester.pumpAndSettle();
    await openDeleteShelfFlow(tester, 'source-live');
    await tester.tap(find.byKey(const Key('move-all-choice')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('move-all-books-button')))
          .onPressed,
      isNotNull,
    );

    shelves.removeShelfForTest(currentUser.uid, 'target-live');
    await tester.pumpAndSettle();
    expect(
      find.text('Create another shelf before moving these books.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('move-all-books-button')))
          .onPressed,
      isNull,
    );
    expect(shelves.moveAttempts, 0);
  });

  testWidgets('pending shelf move is named and resumes its saved destination', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Reader');
    final shelves = FakeShelfRepository(
      initialShelves: {
        currentUser.uid: [
          shelf(
            id: 'paused-source',
            ownerId: currentUser.uid,
            name: 'Paused source',
            bookCount: 2,
            mutationOperationId: 'paused-source',
          ),
          shelf(
            id: 'saved-target',
            ownerId: currentUser.uid,
            name: 'Saved target',
            bookCount: 4,
            mutationOperationId: 'paused-source',
          ),
        ],
      },
      initialOperations: {
        currentUser.uid: const [
          ShelfMutationOperation(
            id: 'paused-source',
            ownerId: 'test-user',
            sourceShelfId: 'paused-source',
            destinationShelfId: 'saved-target',
            mode: ShelfMutationMode.move,
            totalCount: 5,
            processedCount: 3,
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: shelves,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shelf change paused'), findsOneWidget);
    expect(
      find.text('Continue moving 2 books from Paused source to Saved target.'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('resume-shelf-operation-paused-source')),
    );
    await tester.pumpAndSettle();
    expect(shelves.resumeAttempts, 1);
    expect(shelves.lastMoveSourceId, 'paused-source');
    expect(shelves.lastMoveDestinationId, 'saved-target');
  });

  testWidgets('locked shelf explains pending work and disables mutations', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Reader');
    final shelves = FakeShelfRepository(
      initialShelves: {
        currentUser.uid: [
          shelf(
            id: 'locked',
            ownerId: currentUser.uid,
            name: 'Locked shelf',
            mutationOperationId: 'source-operation',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: shelves,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-locked')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Shelf change in progress. Return to Library to continue the confirmed action.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FloatingActionButton>(
            find.byKey(const Key('add-book-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('shelf-catalogue-button')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('bottom-scan-button')), findsNothing);
  });

  testWidgets('authenticated tabs retain one stationary navigation element', (
    tester,
  ) async {
    final auth = FakeAuthService(current: user(displayName: 'Tab Reader'));
    final shelves = FakeShelfRepository(
      initialShelves: {
        auth.currentUser!.uid: [
          shelf(
            id: 'query-shelf',
            ownerId: auth.currentUser!.uid,
            name: 'Query shelf',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(
        authService: auth,
        shelfRepository: shelves,
        friendRepository: NavigationFriendRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final navigation = find.byKey(const Key('authenticated-bottom-navigation'));
    final initialElement = tester.element(navigation);
    final initialRect = tester.getRect(navigation);
    await tester.tap(find.byKey(const Key('library-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('library-search-field')),
      'preserved query',
    );
    final librarySearchEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('library-search-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(librarySearchEditable.focusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('nav-friends')));
    await tester.pumpAndSettle();
    expect(tester.element(navigation), same(initialElement));
    expect(tester.getRect(navigation), initialRect);
    expect(
      tester.widget<ReaduoBottomNavigation>(navigation).active,
      ReaduoNavDestination.friends,
    );
    expect(librarySearchEditable.focusNode.hasFocus, isFalse);

    await tester.tap(find.byKey(const Key('nav-profile')));
    await tester.pumpAndSettle();
    expect(tester.element(navigation), same(initialElement));
    expect(tester.getRect(navigation), initialRect);
    expect(
      tester.widget<ReaduoBottomNavigation>(navigation).active,
      ReaduoNavDestination.profile,
    );

    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pumpAndSettle();
    expect(find.text('preserved query'), findsOneWidget);
    expect(navigation, findsOneWidget);
    expect(tester.element(navigation), same(initialElement));
  });

  testWidgets(
    'four navigation destinations reach scanning only through Library',
    (tester) async {
      final currentUser = user(displayName: 'Scanner Reader');
      final shelves = FakeShelfRepository(
        initialShelves: {
          currentUser.uid: [
            shelf(
              id: 'central-shelf',
              ownerId: currentUser.uid,
              name: 'Central shelf',
            ),
          ],
        },
      );
      await tester.pumpWidget(
        ReaduoApp(
          authService: FakeAuthService(current: currentUser),
          shelfRepository: shelves,
          friendRepository: NavigationFriendRepository(),
        ),
      );
      await tester.pumpAndSettle();

      for (final destination in [
        ReaduoNavDestination.library,
        ReaduoNavDestination.friends,
        ReaduoNavDestination.profile,
      ]) {
        if (destination != ReaduoNavDestination.library) {
          await tester.tap(find.byKey(Key('nav-${destination.name}')));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const Key('bottom-scan-button')), findsNothing);
        await openLibraryScanner(tester);
        expect(find.byKey(const Key('scanner-permission-continue')), findsNothing);
        await tester.pumpAndSettle();
        expect(find.text('Choose a shelf'), findsOneWidget);
        expect(find.byType(ReaduoBottomNavigation), findsNothing);
        await tester.tap(
          find.byKey(const Key('scanner-destination-central-shelf')),
        );
        await tester.pump();
        expect(find.text('Scan a book'), findsOneWidget);
        expect(find.text('Adding to “Central shelf”'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ReaduoBottomNavigation>(
                find.byKey(const Key('authenticated-bottom-navigation')),
              )
              .active,
          ReaduoNavDestination.library,
        );
      }
    },
  );

  testWidgets(
    'duplicate detail returns to scanner and nested sign-out clears it',
    (tester) async {
      final currentUser = user(displayName: 'Scanner Reader');
      final auth = FakeAuthService(current: currentUser);
      final source = shelf(
        id: 'central-shelf',
        ownerId: currentUser.uid,
        name: 'Central shelf',
      );
      final destination = shelf(
        id: 'other-shelf',
        ownerId: currentUser.uid,
        name: 'Other shelf',
      );
      final existing = LibraryBook(
        id: 'nested-book',
        ownerId: currentUser.uid,
        shelfId: source.id,
        title: 'Nested book',
        author: 'Route Tester',
        isbn: '9780306406157',
        isOwned: true,
        readingStatus: ReadingStatus.reading,
        coverUrl: null,
        createdAt: DateTime(2026),
      );
      await tester.pumpWidget(
        ReaduoApp(
          authService: auth,
          shelfRepository: FakeShelfRepository(
            initialShelves: {
              currentUser.uid: [source, destination],
            },
          ),
          bookRepository: _NavigationBookRepository(existing),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-profile')));
      await tester.pumpAndSettle();

      Future<void> openDuplicate() async {
        await openLibraryScanner(tester);
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('scanner-destination-central-shelf')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('scanner-enter-isbn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('scan-manual-isbn-field')),
          '9780306406157',
        );
        await tester.tap(find.byKey(const Key('lookup-isbn-button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('scanner-duplicate-title')),
          findsOneWidget,
        );
      }

      await openDuplicate();
      await tester.tap(find.byKey(const Key('scanner-view-existing')));
      await tester.pumpAndSettle();
      expect(find.text('Book details'), findsOneWidget);
      expect(find.byType(ReaduoBottomNavigation), findsOneWidget);
      expect(
        tester
            .widget<ReaduoBottomNavigation>(
              find.byKey(const Key('authenticated-bottom-navigation')),
            )
            .active,
        ReaduoNavDestination.library,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scanner-duplicate-title')), findsOneWidget);
      expect(find.byType(ReaduoBottomNavigation), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaduoBottomNavigation>(
              find.byKey(const Key('authenticated-bottom-navigation')),
            )
            .active,
        ReaduoNavDestination.library,
      );

      await openDuplicate();
      await tester.tap(find.byKey(const Key('scanner-view-existing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-options-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manage-book-move')));
      await tester.pumpAndSettle();
      expect(find.text('Move to a shelf'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-profile')));
      await tester.pumpAndSettle();
      await confirmProfileSignOut(tester);
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Book details'), findsNothing);
      expect(find.byKey(const Key('scanner-duplicate-title')), findsNothing);
    },
  );

  testWidgets('Done scanning returns the selected shelf to Library', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Batch Reader');
    final target = shelf(
      id: 'batch-shelf',
      ownerId: currentUser.uid,
      name: 'Batch shelf',
    );
    final books = _SavingNavigationBookRepository();
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: FakeShelfRepository(
          initialShelves: {
            currentUser.uid: [target],
          },
        ),
        bookRepository: books,
        bookLookupRepository: const _ImmediateScannerLookup(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-profile')));
    await tester.pumpAndSettle();
    await openLibraryScanner(tester);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scanner-destination-batch-shelf')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scanner-enter-isbn')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scan-manual-isbn-field')),
      '9780306406157',
    );
    await tester.tap(find.byKey(const Key('lookup-isbn-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('lookup-save-another-button')),
    );
    await tester.tap(find.byKey(const Key('lookup-save-another-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-scanner')));
    await tester.pumpAndSettle();

    expect(books.savedShelfId, target.id);
    expect(find.byKey(const Key('add-book-button')), findsOneWidget);
    expect(
      tester
          .widget<ReaduoBottomNavigation>(
            find.byKey(const Key('authenticated-bottom-navigation')),
          )
          .active,
      ReaduoNavDestination.library,
    );
  });

  testWidgets(
    'sign-out disposes a pending scanner lookup and its late result',
    (tester) async {
      final currentUser = user(displayName: 'Scanner Reader');
      final auth = FakeAuthService(current: currentUser);
      final pendingLookup = _PendingScannerLookup();
      await tester.pumpWidget(
        ReaduoApp(
          authService: auth,
          shelfRepository: FakeShelfRepository(
            initialShelves: {
              currentUser.uid: [
                shelf(
                  id: 'scanner-shelf',
                  ownerId: currentUser.uid,
                  name: 'Scanner shelf',
                ),
              ],
            },
          ),
          bookLookupRepository: pendingLookup,
        ),
      );
      await tester.pumpAndSettle();
      await openLibraryScanner(tester);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('scanner-destination-scanner-shelf')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('scanner-enter-isbn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('scan-manual-isbn-field')),
        '9780306406157',
      );
      await tester.tap(find.byKey(const Key('lookup-isbn-button')));
      await tester.pump();
      expect(find.byKey(const Key('isbn-lookup-progress')), findsOneWidget);

      auth.expireSession();
      await tester.pumpAndSettle();
      pendingLookup.complete();
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Book found'), findsNothing);
    },
  );

  testWidgets('tab switches do not stack routes and Back returns to Library', (
    tester,
  ) async {
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: user(displayName: 'Reader')),
        friendRepository: NavigationFriendRepository(),
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 3; index += 1) {
      await tester.tap(find.byKey(const Key('nav-friends')));
      await tester.pumpAndSettle();
    }
    expect(find.byType(FriendsScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('My Library'), findsOneWidget);
    expect(
      tester
          .widget<ReaduoBottomNavigation>(
            find.byKey(const Key('authenticated-bottom-navigation')),
          )
          .active,
      ReaduoNavDestination.library,
    );
  });

  testWidgets('shelf uses the shell bar and fullscreen settings hide it', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Reader');
    final shelves = FakeShelfRepository(
      initialShelves: {
        currentUser.uid: [
          shelf(
            id: 'shell-shelf',
            ownerId: currentUser.uid,
            name: 'Shell shelf',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: shelves,
      ),
    );
    await tester.pumpAndSettle();
    final navigation = find.byKey(const Key('authenticated-bottom-navigation'));
    final navigationElement = tester.element(navigation);

    await tester.tap(find.byKey(const Key('shelf-shell-shelf')));
    await tester.pumpAndSettle();
    expect(navigation, findsOneWidget);
    expect(tester.element(navigation), same(navigationElement));
    expect(find.byType(ReaduoBottomNavigation), findsOneWidget);

    await tester.tap(find.byKey(const Key('shelf-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shelf settings'));
    await tester.pumpAndSettle();
    expect(find.text('Shelf settings'), findsOneWidget);
    expect(navigation, findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navigation, findsOneWidget);

    await openLibraryScanner(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scanner-permission-continue')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Scan a book'), findsOneWidget);
    expect(find.text('Adding to “Shell shelf”'), findsOneWidget);
    expect(navigation, findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navigation, findsOneWidget);
  });

  testWidgets('shelf scanner cancels to A and Done switches exactly to B', (
    tester,
  ) async {
    final currentUser = user(displayName: 'Shelf Scanner');
    final shelfA = shelf(
      id: 'shelf-a',
      ownerId: currentUser.uid,
      name: 'Shelf A',
    );
    final shelfB = shelf(
      id: 'shelf-b',
      ownerId: currentUser.uid,
      name: 'Shelf B',
    );
    final books = _SavingNavigationBookRepository();
    await tester.pumpWidget(
      ReaduoApp(
        authService: FakeAuthService(current: currentUser),
        shelfRepository: FakeShelfRepository(
          initialShelves: {
            currentUser.uid: [shelfA, shelfB],
          },
        ),
        bookRepository: books,
        bookLookupRepository: const _ImmediateScannerLookup(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-shelf-a')));
    await tester.pumpAndSettle();

    Future<void> openScannerAndChooseB() async {
      await openLibraryScanner(tester);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scanner-shelf-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scanner-sheet-shelf-shelf-b')));
      await tester.pumpAndSettle();
      expect(find.text('Adding to “Shelf B”'), findsOneWidget);
    }

    await openScannerAndChooseB();
    await tester.tap(find.byKey(const Key('close-scanner')));
    await tester.pumpAndSettle();
    expect(find.text('Shelf A'), findsOneWidget);

    await openScannerAndChooseB();
    await tester.tap(find.byKey(const Key('scanner-enter-isbn')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scan-manual-isbn-field')),
      '9780306406157',
    );
    await tester.tap(find.byKey(const Key('lookup-isbn-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('lookup-save-another-button')),
    );
    await tester.tap(find.byKey(const Key('lookup-save-another-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-scanner')));
    await tester.pumpAndSettle();

    expect(books.savedShelfId, shelfB.id);
    expect(find.text('Shelf B'), findsOneWidget);
    expect(find.byType(ReaduoBottomNavigation), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('My Library'), findsOneWidget);
  });

  testWidgets('same-UID refresh updates Profile without resetting its tab', (
    tester,
  ) async {
    final first = user(displayName: 'Before refresh');
    final auth = FakeAuthService(current: first);
    await tester.pumpWidget(ReaduoApp(authService: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Before refresh'), findsOneWidget);

    auth.switchUser(user(displayName: 'After refresh', uid: first.uid));
    await tester.pumpAndSettle();
    expect(find.text('After refresh'), findsOneWidget);
    expect(find.text('Before refresh'), findsNothing);
    expect(
      tester
          .widget<ReaduoBottomNavigation>(
            find.byKey(const Key('authenticated-bottom-navigation')),
          )
          .active,
      ReaduoNavDestination.profile,
    );
  });
}

Future<void> openProfileSignOutConfirmation(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('sign-out-button')),
    250,
    scrollable: find
        .descendant(
          of: find.byType(AccountScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.byKey(const Key('sign-out-button')));
  await tester.pumpAndSettle();
  expect(find.text('Sign out of Readuo?'), findsOneWidget);
  expect(find.text('Stay signed in'), findsOneWidget);
  expect(find.text('Continue with Google'), findsNothing);
}

Future<void> confirmProfileSignOut(WidgetTester tester) async {
  await openProfileSignOutConfirmation(tester);
  await tester.tap(find.byKey(const Key('confirm-sign-out')));
  await tester.pumpAndSettle();
}

Future<void> openDeleteShelfFlow(WidgetTester tester, String shelfId) async {
  await tester.tap(find.byKey(Key('shelf-$shelfId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('shelf-settings-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Shelf settings'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('delete-shelf-button')),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const Key('delete-shelf-button')));
  await tester.pumpAndSettle();
}

Widget loginHarness(
  AuthService authService, {
  required Size size,
  required EdgeInsets padding,
}) {
  return MaterialApp(
    theme: ReaduoTheme.modern,
    home: MediaQuery(
      data: MediaQueryData(size: size, padding: padding, viewPadding: padding),
      child: LoginScreen(authService: authService),
    ),
  );
}

Future<void> tapGoogle(WidgetTester tester) async {
  final button = find.byKey(const Key('google-sign-in-button'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

AuthUser user({required String? displayName, String uid = 'firebase-uid-123'}) {
  return AuthUser(
    uid: uid,
    displayName: displayName,
    email: 'reader@example.com',
    photoUrl: null,
    providerIds: const {'google.com'},
  );
}

class FakeAuthService implements AuthService {
  FakeAuthService({
    AuthUser? current,
    this.signInUser,
    this.suggestedNameValue,
    this.signInFailure,
    this.signInCompleter,
    this.signOutFailuresRemaining = 0,
  }) : _current = current;

  final AuthUser? signInUser;
  final String? suggestedNameValue;
  final AuthFailure? signInFailure;
  final Completer<AuthSignInResult>? signInCompleter;
  int signOutFailuresRemaining;
  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();
  AuthUser? _current;
  String? savedDisplayName;
  int signOutCount = 0;

  @override
  AuthUser? get currentUser => _current;

  @override
  bool needsDisplayName(AuthUser user) => !user.hasDisplayName;

  @override
  bool shouldStartFirstBookOnboarding(AuthUser user) => !user.hasDisplayName;

  @override
  Stream<AuthUser?> get userChanges async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  String? suggestedDisplayName(String uid) => suggestedNameValue;

  @override
  Future<AuthSignInResult> signIn(AuthProviderKind provider) async {
    if (signInFailure != null) throw signInFailure!;
    if (signInCompleter != null) return signInCompleter!.future;
    _current = signInUser ?? user(displayName: 'Existing Reader');
    _controller.add(_current);
    return AuthSignInResult(isNewUser: !_current!.hasDisplayName);
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    savedDisplayName = displayName;
    _current = AuthUser(
      uid: _current!.uid,
      displayName: displayName,
      email: _current!.email,
      photoUrl: _current!.photoUrl,
      providerIds: _current!.providerIds,
    );
    _controller.add(_current);
  }

  @override
  Future<void> signOut() async {
    signOutCount += 1;
    if (signOutFailuresRemaining > 0) {
      signOutFailuresRemaining -= 1;
      throw const AuthFailure(
        AuthFailureKind.network,
        'Could not sign out. Please try again.',
      );
    }
    _current = null;
    _controller.add(null);
  }

  void expireSession() {
    _current = null;
    _controller.add(null);
  }

  void switchUser(AuthUser user) {
    _current = user;
    _controller.add(user);
  }
}

class FakeOnboardingRepository implements OnboardingRepository {
  FakeOnboardingRepository({
    Map<String, FirstBookOnboardingStatus> statuses = const {},
    this.loadFailuresRemaining = 0,
    this.beginFailuresRemaining = 0,
    this.skipFailuresRemaining = 0,
    this.completeFailuresRemaining = 0,
  }) : statuses = Map.of(statuses);

  final Map<String, FirstBookOnboardingStatus> statuses;
  final List<String> beginOwnerIds = [];
  int loadFailuresRemaining;
  int beginFailuresRemaining;
  int skipFailuresRemaining;
  int completeFailuresRemaining;

  @override
  Future<FirstBookOnboardingStatus> loadFirstBookStatus(String ownerId) async {
    if (loadFailuresRemaining > 0) {
      loadFailuresRemaining -= 1;
      throw const OnboardingFailure(
        'Could not restore first-book setup. Please retry.',
      );
    }
    return statuses[ownerId] ?? FirstBookOnboardingStatus.notStarted;
  }

  @override
  Future<void> beginFirstBook(String ownerId) async {
    beginOwnerIds.add(ownerId);
    if (beginFailuresRemaining > 0) {
      beginFailuresRemaining -= 1;
      throw const OnboardingFailure(
        'Could not start first-book setup. Please retry.',
      );
    }
    statuses.putIfAbsent(ownerId, () => FirstBookOnboardingStatus.pending);
  }

  @override
  Future<void> skipFirstBook(String ownerId) async {
    if (skipFailuresRemaining > 0) {
      skipFailuresRemaining -= 1;
      throw const OnboardingFailure(
        'Could not save this choice. Please retry.',
      );
    }
    statuses[ownerId] = FirstBookOnboardingStatus.skipped;
  }

  @override
  Future<void> completeFirstBook(String ownerId) async {
    if (completeFailuresRemaining > 0) {
      completeFailuresRemaining -= 1;
      throw const OnboardingFailure(
        'Your book is safe, but setup could not finish. Retry.',
      );
    }
    statuses[ownerId] = FirstBookOnboardingStatus.completed;
  }
}

class _OnboardingBookRepository extends EmptyBookRepository {
  _OnboardingBookRepository({this.createFailuresRemaining = 0});

  final Map<String, List<LibraryBook>> _books = {};
  final Map<String, StreamController<List<LibraryBook>>> _controllers = {};
  int createFailuresRemaining;
  String? savedOwnerId;
  String? savedShelfId;
  CreateBookInput? savedInput;

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) async* {
    yield List.unmodifiable(_books[ownerId] ?? const []);
    yield* _controllers
        .putIfAbsent(ownerId, StreamController<List<LibraryBook>>.broadcast)
        .stream;
  }

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) async {
    if (createFailuresRemaining > 0) {
      createFailuresRemaining -= 1;
      throw const BookFailure('Could not save this book. Please retry.');
    }
    savedOwnerId = ownerId;
    savedShelfId = shelf.id;
    savedInput = input;
    final ownerBooks = _books.putIfAbsent(ownerId, () => []);
    ownerBooks.add(
      LibraryBook(
        id: 'book-${ownerBooks.length + 1}',
        ownerId: ownerId,
        shelfId: shelf.id,
        title: input.title,
        author: input.author,
        isbn: input.normalizedIsbn,
        isOwned: input.isOwned,
        readingStatus: input.readingStatus,
        coverUrl: input.coverUrl,
        createdAt: DateTime(2026),
      ),
    );
    _controllers[ownerId]?.add(List.unmodifiable(ownerBooks));
  }
}

class NavigationFriendRepository extends EmptyFriendRepository {
  @override
  Future<ReaderProfile> ensureProfile(AuthUser user) async => ReaderProfile(
    uid: user.uid,
    displayName: user.displayName!,
    photoUrl: user.photoUrl,
    inviteCode: 'ABC234',
  );

  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) =>
      Stream.value(const [
        ReaderProfile(
          uid: 'bailey-user',
          displayName: 'Bailey Reader',
          photoUrl: null,
          inviteCode: 'XYZ789',
        ),
      ]);
}

class _PendingScannerLookup implements BookLookupRepository {
  final _completer = Completer<BookLookupResult>();

  void complete() => _completer.complete(
    const BookLookupResult(
      isbn: '9780306406157',
      title: 'Late result',
      author: 'Ignored Author',
      publisher: null,
      publishedYear: null,
      description: null,
      coverUrl: null,
      sourceUrl: 'https://openlibrary.org/isbn/9780306406157',
    ),
  );

  @override
  Future<BookLookupResult> lookup(String isbnInput) => _completer.future;
}

class _ImmediateScannerLookup implements BookLookupRepository {
  const _ImmediateScannerLookup();

  @override
  Future<BookLookupResult> lookup(String isbnInput) async =>
      const BookLookupResult(
        isbn: '9780306406157',
        title: 'Batch book',
        author: 'Route Tester',
        publisher: null,
        publishedYear: null,
        description: null,
        coverUrl: null,
        sourceUrl: 'https://openlibrary.org/isbn/9780306406157',
      );
}

class _SavingNavigationBookRepository extends EmptyBookRepository {
  String? savedShelfId;

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) async {
    savedShelfId = shelf.id;
  }
}

class _NavigationBookRepository extends EmptyBookRepository {
  const _NavigationBookRepository(this.book);

  final LibraryBook book;

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) =>
      Stream.value([book]);

  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) => Stream.value(
    ownerId == book.ownerId && shelfId == book.shelfId && bookId == book.id
        ? book
        : null,
  );

  @override
  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  }) => Stream.value(
    ownerId == book.ownerId && shelfId == book.shelfId ? [book] : const [],
  );
}

Shelf shelf({
  required String id,
  required String ownerId,
  required String name,
  ShelfVisibility visibility = ShelfVisibility.friends,
  bool autoShareActivity = true,
  int bookCount = 0,
  String? mutationOperationId,
}) {
  return Shelf(
    id: id,
    ownerId: ownerId,
    name: name,
    visibility: visibility,
    autoShareActivity: autoShareActivity,
    bookCount: bookCount,
    mutationOperationId: mutationOperationId,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

class FakeShelfRepository implements ShelfRepository {
  FakeShelfRepository({
    Map<String, List<Shelf>> initialShelves = const {},
    Map<String, List<ShelfMutationOperation>> initialOperations = const {},
    this.updateFailuresRemaining = 0,
    this.mutationFailuresRemaining = 0,
    this.mutationCompleter,
  }) : _shelves = initialShelves.map(
         (ownerId, shelves) => MapEntry(ownerId, List.of(shelves)),
       ),
       _operations = initialOperations.map(
         (ownerId, operations) => MapEntry(ownerId, List.of(operations)),
       );

  final Map<String, List<Shelf>> _shelves;
  final Map<String, List<ShelfMutationOperation>> _operations;
  final Map<String, StreamController<List<Shelf>>> _controllers = {};
  String? lastOwnerId;
  CreateShelfInput? lastInput;
  String? lastUpdateOwnerId;
  String? lastUpdateShelfId;
  UpdateShelfInput? lastUpdateInput;
  int updateFailuresRemaining;
  int updateAttempts = 0;
  int mutationFailuresRemaining;
  final Completer<void>? mutationCompleter;
  int moveAttempts = 0;
  int deleteAttempts = 0;
  int resumeAttempts = 0;
  String? lastMoveSourceId;
  String? lastMoveDestinationId;
  String? lastDeleteShelfId;

  Shelf shelfFor(String ownerId, String shelfId) =>
      _shelves[ownerId]!.singleWhere((shelf) => shelf.id == shelfId);

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) async* {
    yield List.unmodifiable(_shelves[ownerId] ?? const []);
    yield* _controllers
        .putIfAbsent(ownerId, StreamController<List<Shelf>>.broadcast)
        .stream;
  }

  @override
  Stream<List<ShelfMutationOperation>> watchShelfOperations(String ownerId) =>
      Stream.value(List.unmodifiable(_operations[ownerId] ?? const []));

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
  }) async* {
    final matches = (_shelves[ownerId] ?? const <Shelf>[]).where(
      (shelf) => shelf.id == shelfId,
    );
    yield matches.isEmpty ? null : matches.first;
  }

  @override
  Future<Shelf> createShelf({
    required String ownerId,
    required CreateShelfInput input,
  }) async {
    lastOwnerId = ownerId;
    lastInput = input;
    final ownerShelves = _shelves.putIfAbsent(ownerId, () => []);
    final created = shelf(
      id: 'shelf-${ownerShelves.length + 1}',
      ownerId: ownerId,
      name: input.name.trim(),
      visibility: input.visibility,
      autoShareActivity: input.autoShareActivity,
    );
    ownerShelves.add(created);
    _controllers
        .putIfAbsent(ownerId, StreamController<List<Shelf>>.broadcast)
        .add(List.unmodifiable(ownerShelves));
    return created;
  }

  @override
  Future<void> updateShelf({
    required String ownerId,
    required String shelfId,
    required UpdateShelfInput input,
  }) async {
    updateAttempts += 1;
    if (updateFailuresRemaining > 0) {
      updateFailuresRemaining -= 1;
      throw const ShelfFailure('Could not update the shelf. Please retry.');
    }
    lastUpdateOwnerId = ownerId;
    lastUpdateShelfId = shelfId;
    lastUpdateInput = input;
    final ownerShelves = _shelves[ownerId] ?? [];
    final index = ownerShelves.indexWhere((shelf) => shelf.id == shelfId);
    if (index < 0) throw const ShelfFailure('Shelf not found.');
    ownerShelves[index] = ownerShelves[index].copyWith(
      name: input.name.trim(),
      description: input.description.trim(),
      visibility: input.visibility,
      autoShareActivity: input.autoShareActivity,
    );
    _controllers
        .putIfAbsent(ownerId, StreamController<List<Shelf>>.broadcast)
        .add(List.unmodifiable(ownerShelves));
  }

  @override
  Future<void> moveAllBooksAndDeleteShelf({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
  }) async {
    moveAttempts += 1;
    await mutationCompleter?.future;
    if (mutationFailuresRemaining > 0) {
      mutationFailuresRemaining -= 1;
      throw const ShelfFailure('The library changed. Please retry.');
    }
    final ownerShelves = _shelves[ownerId] ?? [];
    final sourceIndex = ownerShelves.indexWhere(
      (shelf) => shelf.id == sourceShelfId,
    );
    final destinationIndex = ownerShelves.indexWhere(
      (shelf) => shelf.id == destinationShelfId,
    );
    if (sourceIndex < 0 || destinationIndex < 0) {
      throw const ShelfFailure('Shelf not found.');
    }
    lastMoveSourceId = sourceShelfId;
    lastMoveDestinationId = destinationShelfId;
    final source = ownerShelves[sourceIndex];
    final destination = ownerShelves[destinationIndex];
    ownerShelves[destinationIndex] = Shelf(
      id: destination.id,
      ownerId: destination.ownerId,
      name: destination.name,
      description: destination.description,
      visibility: destination.visibility,
      autoShareActivity: destination.autoShareActivity,
      bookCount: destination.bookCount + source.bookCount,
      createdAt: destination.createdAt,
      updatedAt: destination.updatedAt,
    );
    ownerShelves.removeWhere((shelf) => shelf.id == sourceShelfId);
    _emit(ownerId);
  }

  @override
  Future<void> deleteShelfAndBooks({
    required String ownerId,
    required String shelfId,
  }) async {
    deleteAttempts += 1;
    await mutationCompleter?.future;
    if (mutationFailuresRemaining > 0) {
      mutationFailuresRemaining -= 1;
      throw const ShelfFailure('The library changed. Please retry.');
    }
    lastDeleteShelfId = shelfId;
    (_shelves[ownerId] ?? []).removeWhere((shelf) => shelf.id == shelfId);
    _emit(ownerId);
  }

  @override
  Future<void> resumeShelfOperation({
    required String ownerId,
    required String sourceShelfId,
  }) async {
    resumeAttempts += 1;
    final operation = (_operations[ownerId] ?? []).singleWhere(
      (item) => item.sourceShelfId == sourceShelfId,
    );
    if (operation.mode == ShelfMutationMode.move) {
      await moveAllBooksAndDeleteShelf(
        ownerId: ownerId,
        sourceShelfId: sourceShelfId,
        destinationShelfId: operation.destinationShelfId!,
      );
    } else {
      await deleteShelfAndBooks(ownerId: ownerId, shelfId: sourceShelfId);
    }
    (_operations[ownerId] ?? []).remove(operation);
  }

  void _emit(String ownerId) {
    _controllers
        .putIfAbsent(ownerId, StreamController<List<Shelf>>.broadcast)
        .add(List.unmodifiable(_shelves[ownerId] ?? const []));
  }

  void removeShelfForTest(String ownerId, String shelfId) {
    (_shelves[ownerId] ?? []).removeWhere((shelf) => shelf.id == shelfId);
    _emit(ownerId);
  }
}
