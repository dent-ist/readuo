import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/notifications/notification.dart';
import 'package:readuo/notifications/notification_client.dart';
import 'package:readuo/notifications/notification_presentation.dart';
import 'package:readuo/notifications/notification_screens.dart';
import 'package:readuo/screens/shelf_details_screen.dart';
import 'package:readuo/screens/circle_screen.dart';
import 'package:readuo/main.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_tab_activity.dart';

import 'manual_book_test.dart' show FakeBookRepository, testShelf;
import 'notification_messaging_test.dart' show TestPreferences;
import 'notifications_test.dart' show TestMessaging, TestNotificationRepository;
import 'phone_feedback_test.dart'
    show PhoneCircleRepository, PhoneFriendRepository;
import 'widget_test.dart' show FakeAuthService, FakeShelfRepository, user;
import 'memory_preferences.dart';

class ExperienceRepository extends TestNotificationRepository {
  Completer<ReaduoNotification?>? pendingRead;
  @override
  Future<ReaduoNotification?> getNotification(String userId, String id) async =>
      pendingRead == null
      ? super.getNotification(userId, id)
      : pendingRead!.future;
  @override
  Future<NotificationPreferences> getPreferences(String userId) async =>
      NotificationPreferences.fromMap({
        for (final entry in values.entries) entry.key.name: entry.value,
      });
}

ReaduoNotification experienceNotice(String id, {String recipient = 'owner'}) =>
    ReaduoNotification(
      id: id,
      recipientId: recipient,
      actorId: 'friend',
      actorName: 'Private friend',
      type: NotificationType.comment,
      targetId: 'post',
      commentId: id,
      preview: 'Private text',
      createdAt: DateTime.now(),
    );

void main() {
  test(
    'transient foreground failure permits redelivery rather than losing the event',
    () async {
      final repository = ExperienceRepository()..failRead = true;
      repository.items['retry'] = experienceNotice('retry');
      var shown = 0;
      final client = NotificationClient(
        userId: 'owner',
        installationId: 'install',
        repository: repository,
        messaging: TestMessaging(),
        openDestination: (_, _) async => NotificationOpenResult.opened,
        onError: (_) {},
        canPresent: () => true,
        destinationAvailable: (_) async => true,
        onForeground: (_) => shown++,
      );
      await client.presentForeground(
        const NotificationEnvelope('retry', 'owner'),
      );
      expect(shown, 0);
      repository.failRead = false;
      await client.presentForeground(
        const NotificationEnvelope('retry', 'owner'),
      );
      expect(shown, 1);
      await client.dispose();
    },
  );

  testWidgets(
    'root modal does not count obscured nested conversation as visible',
    (tester) async {
      final root = GlobalKey<NavigatorState>();
      const destination = NotificationDestination(
        NotificationDestinationKind.post,
        'post',
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: root,
          home: Builder(
            builder: (context) => NotificationRouteVisibility(
              visible: ModalRoute.of(context)?.isCurrent ?? false,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const NotificationDestinationMarker(
                    destination: destination,
                    child: Scaffold(body: Text('Conversation')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(NotificationDestinationMarker.isViewing(destination), true);
      unawaited(
        root.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Root modal')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(NotificationDestinationMarker.isViewing(destination), false);
      root.currentState!.pop();
      await tester.pumpAndSettle();
      expect(NotificationDestinationMarker.isViewing(destination), true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'foreground validates recipient, source, preferences and deduplicates',
    () async {
      final repository = ExperienceRepository();
      final shown = <String>[];
      var allowed = true;
      var viewing = false;
      final client = NotificationClient(
        userId: 'owner',
        installationId: 'install',
        repository: repository,
        messaging: TestMessaging(),
        openDestination: (_, _) async => NotificationOpenResult.opened,
        onError: (_) {},
        canPresent: () => true,
        destinationAvailable: (_) async => allowed,
        isViewing: (_) => viewing,
        onForeground: (item) => shown.add(item.id),
      );
      for (final id in [
        'valid',
        'wrong',
        'revoked',
        'muted',
        'viewed',
        'forged',
      ])
        repository.items[id] = experienceNotice(id);
      await client.presentForeground(
        const NotificationEnvelope('wrong', 'someone-else'),
      );
      repository.items['forged'] = experienceNotice(
        'forged',
        recipient: 'someone-else',
      );
      await client.presentForeground(
        const NotificationEnvelope('forged', 'owner'),
      );
      allowed = false;
      await client.presentForeground(
        const NotificationEnvelope('revoked', 'owner'),
      );
      allowed = true;
      repository.values[NotificationType.comment] = false;
      await client.presentForeground(
        const NotificationEnvelope('muted', 'owner'),
      );
      repository.values[NotificationType.comment] = true;
      viewing = true;
      await client.presentForeground(
        const NotificationEnvelope('viewed', 'owner'),
      );
      viewing = false;
      await client.presentForeground(
        const NotificationEnvelope('valid', 'owner'),
      );
      await client.presentForeground(
        const NotificationEnvelope('valid', 'owner'),
      );
      expect(shown, ['valid']);
      await client.dispose();
    },
  );

  test(
    'late foreground work is discarded on pause/resume and signout',
    () async {
      for (final stop in [false, true]) {
        final repository = ExperienceRepository()..pendingRead = Completer();
        var shown = 0;
        final client = NotificationClient(
          userId: 'owner',
          installationId: 'install',
          repository: repository,
          messaging: TestMessaging(),
          openDestination: (_, _) async => NotificationOpenResult.opened,
          onError: (_) {},
          canPresent: () => true,
          destinationAvailable: (_) async => true,
          onForeground: (_) => shown++,
        );
        final pending = client.presentForeground(
          const NotificationEnvelope('late', 'owner'),
        );
        if (stop)
          await client.beforeSignOut();
        else
          client.invalidateForeground();
        repository.pendingRead!.complete(experienceNotice('late'));
        await pending;
        expect(shown, 0);
        await client.dispose();
      }
    },
  );

  test('malformed foreground payload is ignored', () {
    for (final data in <Map<String, dynamic>>[
      {},
      {'notificationId': 'id'},
      {'notificationId': '../id', 'recipientId': 'owner'},
      {'notificationId': 'id', 'recipientId': 3},
    ]) {
      expect(NotificationEnvelope.fromData(data), isNull);
    }
    expect(
      NotificationEnvelope.fromData({
        'notificationId': 'id',
        'recipientId': 'owner',
      })?.recipientId,
      'owner',
    );
  });

  test(
    'first connection rationale is once per account and never prompts on denial',
    () async {
      final store = TestPreferences();
      final opportunity = NotificationPermissionOpportunity(store, 'owner');
      Future<bool> claim(
        int count, {
        bool current = true,
        NotificationPermission permission =
            NotificationPermission.notDetermined,
      }) => opportunity.claim(
        friendCount: count,
        permission: permission,
        isCurrent: () => current,
      );
      expect(await claim(0), false);
      expect(await claim(1, current: false), false);
      expect(await claim(1), true);
      expect(await claim(2), false);
      expect(
        await NotificationPermissionOpportunity(store, 'owner').claim(
          friendCount: 1,
          permission: NotificationPermission.notDetermined,
          isCurrent: () => true,
        ),
        false,
      );
      expect(
        await NotificationPermissionOpportunity(store, 'other').claim(
          friendCount: 1,
          permission: NotificationPermission.notDetermined,
          isCurrent: () => true,
        ),
        true,
      );
      expect(
        await NotificationPermissionOpportunity(store, 'denied').claim(
          friendCount: 1,
          permission: NotificationPermission.denied,
          isCurrent: () => true,
        ),
        false,
      );
      await opportunity.clear();
      expect(
        store.values.containsKey('readuo.notifications.friendRationale.owner'),
        false,
      );
      expect(store.values['readuo.notifications.friendRationale.other'], true);
    },
  );

  testWidgets(
    'visible conversation suppresses all its comment events but not hidden tabs or routes',
    (tester) async {
      const destination = NotificationDestination(
        NotificationDestinationKind.post,
        'post',
      );
      final active = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (context, value, _) => ReaduoTabActivity(
              active: value,
              child: const NotificationDestinationMarker(
                destination: destination,
                child: Scaffold(body: Text('Post')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        NotificationDestinationMarker.isViewing(
          const NotificationDestination(
            NotificationDestinationKind.post,
            'post',
            commentId: 'new',
          ),
        ),
        true,
      );
      expect(
        NotificationDestinationMarker.isViewing(
          const NotificationDestination(
            NotificationDestinationKind.post,
            'other',
          ),
        ),
        false,
      );
      active.value = false;
      await tester.pump();
      expect(NotificationDestinationMarker.isViewing(destination), false);
      active.value = true;
      await tester.pump();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(NotificationDestinationMarker.isViewing(destination), false);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(NotificationDestinationMarker.isViewing(destination), true);
      await tester.pumpWidget(const SizedBox.shrink());
      active.dispose();
    },
  );

  testWidgets(
    'notification explanation, quiet banner and labeled shelf action',
    (tester) async {
      await runNotificationExperienceChecks(tester);
    },
  );
}

Future<void> runNotificationExperienceChecks(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  final messaging = TestMessaging();
  final repository = ExperienceRepository();
  var opened = 0;
  final client = NotificationClient(
    userId: 'owner',
    installationId: 'install',
    repository: repository,
    messaging: messaging,
    openDestination: (_, _) async {
      opened++;
      return NotificationOpenResult.opened;
    },
    onError: (_) {},
  );
  Future<void> show(Widget child) async {
    await tester.pumpWidget(
      MaterialApp(theme: ReaduoTheme.modern, home: child),
    );
    await tester.pumpAndSettle();
  }

  var deferred = false;
  await show(
    NotificationPermissionScreen(client: client, onDone: () => deferred = true),
  );
  expect(messaging.requests, 0);
  if (capture != null) await capture('notification-first-connection');
  await tester.tap(find.text('Not now'));
  expect(deferred, true);
  await tester.tap(find.text('Enable notifications'));
  await tester.pumpAndSettle();
  expect(messaging.requests, 1);
  if (capture != null) await capture('notification-denied');
  await tester.ensureVisible(find.text('Phone notification settings'));
  await tester.pumpAndSettle();
  if (capture != null) await capture('notification-denied-settings');
  await tester.tap(find.text('Phone notification settings'));
  expect(messaging.settings, 1);
  var settingsOpened = false;
  await show(
    NotificationSettingsScreen(
      userId: 'owner',
      repository: repository,
      openSettings: () async => settingsOpened = true,
      enableLabel: 'Enable notifications',
    ),
  );
  await tester.ensureVisible(find.text('Enable notifications'));
  await tester.pumpAndSettle();
  if (capture != null) await capture('notification-profile-enable');
  await tester.tap(find.text('Enable notifications'));
  expect(settingsOpened, true);
  repository.items['tap'] = experienceNotice('tap');
  useMemoryPreferences();
  await tester.pumpWidget(
    ReaduoApp(
      authService: FakeAuthService(current: user(displayName: 'Reader')),
      shelfRepository: FakeShelfRepository(),
      circleRepository: PhoneCircleRepository(),
      friendRepository: PhoneFriendRepository(),
    ),
  );
  await tester.pumpAndSettle();
  final overlay = NotificationBannerOverlay();
  await tester.tap(find.byKey(const Key('nav-circle')));
  await tester.pumpAndSettle();
  final circleContext = tester.element(find.byType(CircleScreen));
  overlay.show(circleContext, () => unawaited(client.open('tap')));
  await tester.pumpAndSettle();
  expect(find.text('Private friend'), findsNothing);
  expect(find.text('Private text'), findsNothing);
  if (capture != null) await capture('notification-quiet-banner');
  await tester.tap(find.text('New activity in your circle. Tap to view.'));
  await tester.pumpAndSettle();
  expect(opened, 1);
  expect(find.byType(QuietNotificationBanner), findsNothing);
  overlay.show(circleContext, () {});
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-profile')));
  await tester.pumpAndSettle();
  expect(find.text('Edit profile'), findsOneWidget);
  await tester.tap(find.byTooltip('Dismiss notification'));
  await tester.pumpAndSettle();
  expect(find.byType(QuietNotificationBanner), findsNothing);
  overlay.dismiss();
  final shelf = testShelf();
  await show(
    ShelfDetailsScreen(
      ownerId: shelf.ownerId,
      shelf: shelf,
      bookRepository: FakeBookRepository(),
    ),
  );
  expect(
    tester
        .widget<FloatingActionButton>(find.byKey(const Key('add-book-button')))
        .isExtended,
    isTrue,
  );
  expect(find.text('Add book'), findsNothing);
  if (capture != null) await capture('shelf-round-book-plus');
  await tester.tap(find.byKey(const Key('add-book-button')));
  await tester.pumpAndSettle();
  expect(find.text('Scan barcode'), findsOneWidget);
  expect(find.byKey(const Key('shelf-manual-choice')), findsOneWidget);
  if (capture != null) await capture('shelf-round-speed-dial');
  await tester.tap(find.byTooltip('Close add book menu').last);
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await client.dispose();
  expect(tester.takeException(), isNull);
}
