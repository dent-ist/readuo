import 'dart:async';
import 'memory_preferences.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/auth/auth_service.dart';
import 'package:readuo/profile/edit_profile_screen.dart';
import 'package:readuo/profile/profile_repository.dart';
import 'package:readuo/profile/profile_photo_draft.dart';
import 'p1_19_21_test.dart' show MemoryCache;
import 'package:readuo/profile/profile_widgets.dart';
import 'package:readuo/profile/support_repository.dart';
import 'package:readuo/profile/support_requests_screen.dart';
import 'package:readuo/profile/support_screens.dart';
import 'package:readuo/screens/account_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';

const reader = AuthUser(
  uid: 'reader',
  displayName: 'Maya',
  email: 'maya@example.test',
  photoUrl: null,
  providerIds: {'google.com'},
);

Widget app(Widget child) => MaterialApp(theme: ReaduoTheme.modern, home: child);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(useMemoryPreferences);
  testWidgets(
    'draft recovery blocks edits until loaded and retries storage failures',
    (tester) async {
      final storage = _DelayedDraftCache();
      final store = ProfilePhotoDraftStore(storage: storage);
      await store.write('reader', {'flow': 'edit', 'name': 'Recovered name'});
      await tester.pumpWidget(
        app(
          EditProfileScreen(
            uid: 'reader',
            name: 'Maya',
            photoUrl: null,
            repository: _Profiles(),
            draftStore: store,
          ),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      storage.readGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Retry draft recovery'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      storage.fail = false;
      await tester.tap(find.text('Retry draft recovery'));
      await tester.pumpAndSettle();
      expect(find.text('Recovered name'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
      await tester.enterText(find.byType(TextField), 'My new name');
      await tester.pumpAndSettle();
      expect(find.text('My new name'), findsOneWidget);
    },
  );
  testWidgets('avatar uses first and last grapheme initials', (tester) async {
    const cases = {
      'Maya Okonkwo': 'MO',
      '  maya  middle\t okonkwo  ': 'MO',
      'Maya': 'M',
      '   ': '?',
      'e\u0301lodie a\u0308nne': 'E\u0301A\u0308',
      '👩🏽‍💻 Reader': '👩🏽‍💻R',
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(app(ProfileAvatar(name: entry.key)));
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('edit profile keeps the canonical single initial', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const EditProfileScreen(
          uid: 'reader',
          name: 'Maya Okonkwo',
          photoUrl: null,
          repository: UnavailableProfileRepository(),
        ),
      ),
    );
    expect(
      find.descendant(of: find.byType(ProfileAvatar), matching: find.text('M')),
      findsOneWidget,
    );
    expect(find.text('MO'), findsNothing);
  });

  test('display names normalize and enforce empty/length boundaries', () {
    expect(validatedDisplayName('  Maya  '), 'Maya');
    expect(() => validatedDisplayName('   '), throwsA(isA<ProfileFailure>()));
    expect(
      () => validatedDisplayName('x' * 81),
      throwsA(isA<ProfileFailure>()),
    );
    expect(validatedDisplayName('x' * 80).length, 80);
  });

  test('photo validation rejects mislabeled and oversized payloads', () {
    expect(
      () => ProfilePhoto(
        Uint8List.fromList([255, 216, 255]),
        'image/jpeg',
      ).validate(),
      returnsNormally,
    );
    expect(
      () => ProfilePhoto(
        Uint8List.fromList([255, 216, 255]),
        'image/png',
      ).validate(),
      throwsA(isA<ProfileFailure>()),
    );
    expect(
      () =>
          ProfilePhoto(Uint8List(5 * 1024 * 1024 + 1), 'image/jpeg').validate(),
      throwsA(isA<ProfileFailure>()),
    );
    expect(
      () => ProfilePhoto(Uint8List(0), 'image/jpeg').validate(),
      throwsA(isA<ProfileFailure>()),
    );
  });

  test(
    'support validation trims and enforces bounds and stable identifiers',
    () {
      final draft = SupportDraft(
        subject: ' Help ',
        message: ' Details ',
        requestId: SupportDraft.newRequestId(),
      );
      draft.validate();
      expect(draft.subject, 'Help');
      expect(draft.message, 'Details');
      expect(
        () => SupportDraft(
          subject: 'x' * 121,
          message: 'Details',
          requestId: draft.requestId,
        ).validate(),
        throwsA(isA<ProfileFailure>()),
      );
      expect(
        () => SupportDraft(
          subject: 'Help',
          message: 'x' * 5001,
          requestId: draft.requestId,
        ).validate(),
        throwsA(isA<ProfileFailure>()),
      );
      expect(
        () => SupportDraft(
          subject: 'Help',
          message: 'Details',
          requestId: '../bad',
        ).validate(),
        throwsA(isA<ProfileFailure>()),
      );
    },
  );

  testWidgets('profile saves normalized name and updates visible identity', (
    tester,
  ) async {
    final repository = _Profiles();
    await tester.pumpWidget(
      app(
        AccountScreen(
          authService: _Auth(),
          user: reader,
          profileRepository: repository,
          bookCount: 3,
          friendCount: 2,
        ),
      ),
    );
    await tapVisible(tester, find.text('Edit profile'));
    await tester.enterText(find.byType(TextField), '  New name  ');
    await tapVisible(tester, find.text('Save profile'));
    expect(repository.names, ['New name']);
    expect(find.text('New name'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Shelves'), findsOneWidget);
  });

  testWidgets('empty name stays editable and does not call repository', (
    tester,
  ) async {
    final repository = _Profiles();
    await tester.pumpWidget(
      app(
        EditProfileScreen(
          uid: 'reader',
          name: 'Maya',
          photoUrl: null,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  ');
    await tapVisible(tester, find.text('Save profile'));
    expect(repository.names, isEmpty);
    expect(
      find.text('Enter a display name of 1–80 characters.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'unconfigured repository reports failure without pretending to save',
    (tester) async {
      await tester.pumpWidget(
        app(AccountScreen(authService: _Auth(), user: reader)),
      );
      await tapVisible(tester, find.text('Edit profile'));
      await tapVisible(tester, find.text('Save profile'));
      expect(
        find.text(
          'Profile editing is currently unavailable. Please try again later.',
        ),
        findsOneWidget,
      );
      expect(find.text('Profile updated'), findsNothing);
    },
  );

  testWidgets(
    'support rejects empty content then retries the identical draft',
    (tester) async {
      final repository = _Support()..fail = true;
      await tester.pumpWidget(
        app(SupportMessageScreen(repository: repository)),
      );
      await tapVisible(tester, find.text('Send message'));
      expect(repository.drafts, isEmpty);
      await tester.enterText(find.byType(TextField).at(0), ' Help ');
      await tester.enterText(find.byType(TextField).at(1), ' Problem details ');
      await tapVisible(tester, find.text('Send message'));
      expect(repository.drafts, hasLength(1));
      expect(find.text('Retry submission.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      await tapVisible(tester, find.text('Send message'));
      expect(repository.drafts, hasLength(2));
      expect(identical(repository.drafts[0], repository.drafts[1]), isTrue);
      expect(repository.drafts.first.subject, 'Help');
    },
  );

  testWidgets(
    'support disables submit until server result and confirms persistence',
    (tester) async {
      final repository = _Support()..pending = Completer<void>();
      await tester.pumpWidget(app(SupportScreen(repository: repository)));
      await tapVisible(tester, find.text('Contact support'));
      await tester.enterText(find.byType(TextField).at(0), 'Help');
      await tester.enterText(find.byType(TextField).at(1), 'Problem');
      await tester.tap(find.text('Send message'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Support request received.'), findsNothing);
      repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Help & support'), findsOneWidget);
      expect(find.text('Support request received.'), findsOneWidget);
    },
  );

  testWidgets(
    'sign out requires confirmation and cancellation retains session',
    (tester) async {
      final auth = _Auth();
      await tester.pumpWidget(
        app(AccountScreen(authService: auth, user: reader)),
      );
      await tapVisible(tester, find.byKey(const Key('sign-out-button')));
      expect(auth.signOuts, 0);
      await tapVisible(tester, find.text('Stay signed in'));
      expect(auth.signOuts, 0);
      await tapVisible(tester, find.byKey(const Key('sign-out-button')));
      await tapVisible(tester, find.byKey(const Key('confirm-sign-out')));
      expect(auth.signOuts, 1);
    },
  );

  testWidgets('sign out failure remains actionable without closing sheet', (
    tester,
  ) async {
    final auth = _Auth()..fail = true;
    await tester.pumpWidget(
      app(AccountScreen(authService: auth, user: reader)),
    );
    await tapVisible(tester, find.byKey(const Key('sign-out-button')));
    await tapVisible(tester, find.byKey(const Key('confirm-sign-out')));
    expect(find.text('Sign out failed.'), findsOneWidget);
    auth.fail = false;
    await tapVisible(tester, find.byKey(const Key('confirm-sign-out')));
    expect(auth.signOuts, 2);
    expect(find.text('Sign out of Readuo?'), findsNothing);
  });

  testWidgets('notifications and operator destinations call injected routes', (
    tester,
  ) async {
    var notifications = 0;
    var reports = 0;
    var support = 0;
    await tester.pumpWidget(
      app(
        AccountScreen(
          authService: _Auth(),
          user: reader,
          isModerator: true,
          onNotifications: () => notifications++,
          onModeration: () => reports++,
          onSupportQueue: () => support++,
        ),
      ),
    );
    await tapVisible(tester, find.text('Notifications'));
    await tapVisible(tester, find.text('Reports'));
    await tapVisible(tester, find.text('Support requests'));
    expect([notifications, reports, support], [1, 1, 1]);
  });

  testWidgets('operator queue resolves and reports failures', (tester) async {
    final repository = _Operator()..fail = true;
    await tester.pumpWidget(app(SupportRequestsScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Cannot sign in'), findsOneWidget);
    await tapVisible(tester, find.text('Mark resolved'));
    expect(
      find.text('Could not resolve this request. Please retry.'),
      findsOneWidget,
    );
    repository.fail = false;
    await tapVisible(tester, find.text('Mark resolved'));
    expect(repository.resolved, ['request', 'request']);
  });
}

class _DelayedDraftCache extends MemoryCache {
  final readGate = Completer<void>();
  bool fail = true;
  @override
  Future<String?> read(String key) async {
    await readGate.future;
    if (fail) throw StateError('local storage unavailable');
    return super.read(key);
  }
}

class _Profiles implements ProfileRepository {
  final List<String> names = [];
  @override
  Future<ProfileSaveResult> save({
    required String uid,
    required String displayName,
    ProfilePhoto? photo,
  }) async {
    names.add(displayName);
    return ProfileSaveResult(displayName, null);
  }
}

class _Support implements SupportRepository {
  final List<SupportDraft> drafts = [];
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> submit(SupportDraft draft) async {
    drafts.add(draft);
    if (fail) throw const ProfileFailure('Retry submission.');
    await pending?.future;
  }
}

class _Auth implements AuthService {
  int signOuts = 0;
  bool fail = false;
  @override
  Future<void> signOut() async {
    signOuts++;
    if (fail)
      throw const AuthFailure(AuthFailureKind.network, 'Sign out failed.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Operator implements SupportOperatorRepository {
  bool fail = false;
  final List<String> resolved = [];
  @override
  Stream<List<SupportRequest>> watchPending() => Stream.value([
    const SupportRequest(
      id: 'request',
      ownerId: 'reader',
      subject: 'Cannot sign in',
      message: 'Details',
      status: 'pending',
    ),
  ]);
  @override
  Future<void> resolve(String requestId) async {
    resolved.add(requestId);
    if (fail) throw const ProfileFailure('Permission denied.');
  }
}
