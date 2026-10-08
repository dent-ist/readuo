import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/notifications/notification.dart';
import 'package:readuo/notifications/notification_client.dart';
import 'package:readuo/notifications/notification_repository.dart';
import 'package:readuo/notifications/notification_screens.dart';
import 'package:readuo/theme/readuo_theme.dart';

class TestNotificationRepository extends EmptyNotificationRepository {
  final preferences = StreamController<NotificationPreferences>.broadcast();
  final Map<String, ReaduoNotification> items = {};
  final Map<NotificationType, bool> values = {};
  final List<String> calls = [];
  bool failWrites = false;
  bool failRemoval = false;
  Completer<void>? pendingRemoval;
  bool failRead = false;
  Completer<void>? pendingToken;

  @override
  Stream<List<ReaduoNotification>> watchNotifications(String userId) =>
      Stream.value(items.values.toList());
  @override
  Future<ReaduoNotification?> getNotification(String userId, String id) async {
    if (failRead) throw StateError('offline');
    return items[id];
  }

  @override
  Stream<NotificationPreferences> watchPreferences(String userId) async* {
    yield NotificationPreferences.fromMap({
      for (final entry in values.entries) entry.key.name: entry.value,
    });
    yield* preferences.stream;
  }

  @override
  Future<void> setPreference(
    String userId,
    NotificationType type,
    bool enabled,
  ) async {
    if (failWrites) throw StateError('offline');
    values[type] = enabled;
    preferences.add(
      NotificationPreferences.fromMap({
        for (final entry in values.entries) entry.key.name: entry.value,
      }),
    );
  }

  @override
  Future<void> markRead(String userId, String id) async {
    calls.add('read:$id');
  }

  @override
  Future<void> saveToken(
    String userId,
    String installationId,
    String token,
  ) async {
    calls.add('save:$userId:$installationId:$token');
    await pendingToken?.future;
  }

  @override
  Future<void> removeToken(String userId, String installationId) async {
    await pendingRemoval?.future;
    if (failRemoval) throw StateError('offline');
    calls.add('remove:$userId:$installationId');
  }
}

class TestMessaging implements NotificationMessaging {
  NotificationPermission status = NotificationPermission.notDetermined;
  NotificationPermission response = NotificationPermission.denied;
  final refresh = StreamController<String>.broadcast();
  final opened = StreamController<String>.broadcast();
  int requests = 0;
  int deletes = 0;
  int settings = 0;
  String? initial;
  bool failDelete = false;
  bool failGetToken = false;
  int initialReads = 0;
  Completer<String?>? pendingGetToken;
  @override
  Future<NotificationPermission> permission() async => status;
  @override
  Future<NotificationPermission> requestPermission() async {
    requests++;
    return status = response;
  }

  @override
  Future<String?> getToken() async {
    if (failGetToken) throw StateError('offline');
    return pendingGetToken == null ? 'token' : await pendingGetToken!.future;
  }

  @override
  Future<void> deleteToken() async {
    deletes++;
    if (failDelete) throw StateError('offline');
  }

  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Stream<String> get openedNotificationIds => opened.stream;
  @override
  Future<String?> initialNotificationId() async {
    initialReads++;
    return initial;
  }

  @override
  Future<void> openSettings() async {
    settings++;
  }
}

ReaduoNotification fixture(
  NotificationType type, {
  String recipient = 'owner',
}) => ReaduoNotification(
  id: type.name,
  recipientId: recipient,
  actorId: 'actor',
  actorName: switch (type) {
    NotificationType.friendRequest => 'Priya Shah',
    NotificationType.requestAccepted => 'Tom',
    NotificationType.comment => 'Amara',
    NotificationType.like => 'Sarah',
    NotificationType.booksAdded => 'Kenny Kim',
  },
  type: type,
  targetId: 'exact-${type.name}',
  isReview: type == NotificationType.like,
  commentId: type == NotificationType.comment ? 'exact-comment' : null,
  preview: type == NotificationType.comment
      ? '“This looks like a perfect Sunday.”'
      : type == NotificationType.like
      ? 'Sea of Tranquility'
      : '',
  createdAt: DateTime.now().subtract(switch (type) {
    NotificationType.friendRequest => Duration.zero,
    NotificationType.requestAccepted => const Duration(hours: 1),
    NotificationType.comment => const Duration(hours: 2),
    NotificationType.like => const Duration(days: 1),
    NotificationType.booksAdded => const Duration(hours: 3),
  }),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (const bool.fromEnvironment('NOTIFICATION_SCREENSHOTS')) {
      const fontPath = String.fromEnvironment('NOTIFICATION_FONT');
      final loader = FontLoader('Roboto')
        ..addFont(
          File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  late TestNotificationRepository repository;
  late TestMessaging messaging;
  late NotificationClient client;
  late List<NotificationDestination> destinations;
  late List<Object> errors;
  setUp(() {
    repository = TestNotificationRepository();
    messaging = TestMessaging();
    destinations = [];
    errors = [];
    client = NotificationClient(
      userId: 'owner',
      installationId: 'installation',
      repository: repository,
      messaging: messaging,
      openDestination: (recipient, destination) async {
        destinations.add(destination);
        return NotificationOpenResult.opened;
      },
      onError: errors.add,
    );
  });
  tearDown(() async {
    await client.dispose();
    await repository.preferences.close();
    await messaging.refresh.close();
    await messaging.opened.close();
  });

  test(
    'failed startup retries without duplicate listeners or token invalidation',
    () async {
      messaging.status = NotificationPermission.granted;
      messaging.failGetToken = true;
      await expectLater(client.start(), throwsStateError);
      messaging.failGetToken = false;
      await Future.wait([client.start(), client.start()]);
      repository.items['like'] = fixture(NotificationType.like);
      messaging.opened.add('like');
      messaging.refresh.add('rotated');
      await Future<void>.delayed(Duration.zero);
      expect(destinations, hasLength(1));
      expect(
        repository.calls.where((call) => call.endsWith(':rotated')),
        hasLength(1),
      );
      expect(messaging.deletes, 1);
      expect(messaging.initialReads, 1);
    },
  );
  test('failed startup token invalidation can be retried', () async {
    messaging.failDelete = true;
    await expectLater(client.start(), throwsStateError);
    messaging.failDelete = false;
    await client.start();
    expect(messaging.deletes, 2);
  });
  test(
    'cold-start ID survives a failed server read and is consumed once',
    () async {
      messaging.initial = 'like';
      repository.items['like'] = fixture(NotificationType.like);
      repository.failRead = true;
      await expectLater(client.start(), throwsStateError);
      repository.failRead = false;
      await client.start();
      await client.start();
      expect(messaging.initialReads, 1);
      expect(destinations, hasLength(1));
    },
  );
  test(
    'pending remote unregister is bounded and does not block signout',
    () async {
      repository.pendingRemoval = Completer<void>();
      final bounded = NotificationClient(
        userId: 'owner',
        installationId: 'installation',
        repository: repository,
        messaging: messaging,
        openDestination: (_, _) async => NotificationOpenResult.unavailable,
        onError: errors.add,
        cleanupTimeout: const Duration(milliseconds: 10),
      );
      await bounded.beforeSignOut();
      expect(messaging.deletes, 1);
      expect(bounded.isActive, isFalse);
      expect(errors, hasLength(1));
      repository.pendingRemoval!.complete();
      await bounded.dispose();
    },
  );
  test(
    'pending registration cannot hold signout or trigger late unregister',
    () async {
      messaging.status = NotificationPermission.granted;
      final bounded = NotificationClient(
        userId: 'owner',
        installationId: 'installation',
        repository: repository,
        messaging: messaging,
        openDestination: (_, _) async => NotificationOpenResult.unavailable,
        onError: errors.add,
        cleanupTimeout: const Duration(milliseconds: 10),
      );
      await bounded.start();
      repository.pendingToken = Completer<void>();
      messaging.refresh.add('pending');
      await Future<void>.delayed(Duration.zero);
      await bounded.beforeSignOut();
      expect(messaging.deletes, 2);
      expect(errors, hasLength(1));
      repository.pendingToken!.complete();
      await bounded.dispose();
      expect(
        repository.calls.where((call) => call.startsWith('remove:')),
        isEmpty,
      );
    },
  );
  test('SDK invalidation failure is reported and remains retryable', () async {
    messaging.failDelete = true;
    await expectLater(client.beforeSignOut(), throwsStateError);
    expect(client.isActive, isFalse);
    expect(errors, hasLength(1));
    messaging.failDelete = false;
    await client.beforeSignOut();
    expect(messaging.deletes, 2);
  });
  test(
    'throwing error reporter cannot prevent successful SDK cleanup',
    () async {
      repository.failRemoval = true;
      final reporting = NotificationClient(
        userId: 'owner',
        installationId: 'installation',
        repository: repository,
        messaging: messaging,
        openDestination: (_, _) async => NotificationOpenResult.unavailable,
        onError: (_) => throw StateError('unmounted error UI'),
      );
      await reporting.beforeSignOut();
      expect(messaging.deletes, 1);
      await reporting.dispose();
    },
  );
  test(
    'signout waits for SDK token fetch then invalidates without registering',
    () async {
      messaging.status = NotificationPermission.granted;
      await client.start();
      repository.calls.clear();
      messaging.pendingGetToken = Completer<String?>();
      final sync = client.synchronizePermission();
      await Future<void>.delayed(Duration.zero);
      final signout = client.beforeSignOut();
      expect(client.isActive, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(messaging.deletes, 1);
      messaging.pendingGetToken!.complete('late-sdk-token');
      await Future.wait([sync, signout]);
      expect(messaging.deletes, 2);
      expect(repository.calls, ['remove:owner:installation']);
    },
  );
  test(
    'existing types are preserved and grouped owned-book additions are added',
    () {
      expect(NotificationType.values.map((type) => type.name), [
        'friendRequest',
        'requestAccepted',
        'like',
        'comment',
        'booksAdded',
      ]);
    },
  );
  test('exact destinations preserve review and comment identity', () async {
    for (final type in NotificationType.values) {
      repository.items[type.name] = fixture(type);
      expect(await client.open(type.name), NotificationOpenResult.opened);
      expect(destinations.last.id, 'exact-${type.name}');
      expect(destinations.last.isReview, type == NotificationType.like);
      expect(
        destinations.last.commentId,
        type == NotificationType.comment ? 'exact-comment' : null,
      );
      expect(repository.calls.last, 'read:${type.name}');
    }
    expect(destinations.map((destination) => destination.kind), [
      NotificationDestinationKind.request,
      NotificationDestinationKind.reader,
      NotificationDestinationKind.post,
      NotificationDestinationKind.post,
      NotificationDestinationKind.bookAddition,
    ]);
  });
  test('missing or wrong-recipient records never route or mark read', () async {
    expect(await client.open('missing'), NotificationOpenResult.unavailable);
    repository.items['wrong'] = fixture(
      NotificationType.like,
      recipient: 'other',
    );
    expect(await client.open('wrong'), NotificationOpenResult.unavailable);
    expect(destinations, isEmpty);
    expect(repository.calls, isEmpty);
  });
  test('revoked live access never marks read', () async {
    repository.items['like'] = fixture(NotificationType.like);
    final revoked = NotificationClient(
      userId: 'owner',
      installationId: 'installation',
      repository: repository,
      messaging: messaging,
      openDestination: (_, destination) async =>
          NotificationOpenResult.unavailable,
      onError: errors.add,
    );
    expect(await revoked.open('like'), NotificationOpenResult.unavailable);
    expect(repository.calls, isEmpty);
    await revoked.dispose();
  });
  test(
    'startup never requests permission; denial retains preferences',
    () async {
      repository.values[NotificationType.like] = false;
      await client.start();
      expect(messaging.requests, 0);
      expect(messaging.deletes, 1);
      expect(
        await client.enableAfterRationale(),
        NotificationPermission.denied,
      );
      expect(messaging.requests, 1);
      await client.enableAfterRationale();
      expect(messaging.requests, 1);
      expect(repository.values, {NotificationType.like: false});
    },
  );
  test(
    'startup, refresh, and signout use one owner installation document',
    () async {
      messaging.status = NotificationPermission.granted;
      await client.start();
      messaging.refresh.add('rotated');
      await Future<void>.delayed(Duration.zero);
      await client.beforeSignOut();
      expect(repository.calls, [
        'save:owner:installation:token',
        'save:owner:installation:rotated',
        'remove:owner:installation',
      ]);
      expect(messaging.deletes, 2);
      messaging.refresh.add('late');
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls.last, 'remove:owner:installation');
    },
  );
  test('signout drains an in-flight refresh before removing token', () async {
    messaging.status = NotificationPermission.granted;
    await client.start();
    repository.pendingToken = Completer<void>();
    messaging.refresh.add('pending');
    await Future<void>.delayed(Duration.zero);
    final signout = client.beforeSignOut();
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.last, 'save:owner:installation:pending');
    repository.pendingToken!.complete();
    await signout;
    expect(repository.calls.last, 'remove:owner:installation');
  });
  test('cold and warm push opens fetch trusted records', () async {
    repository.items['like'] = fixture(NotificationType.like);
    messaging.initial = 'like';
    await client.start();
    messaging.opened.add('like');
    await Future<void>.delayed(Duration.zero);
    expect(destinations.length, 2);
  });
  test(
    'failed signout removal still invalidates SDK token and reports failure',
    () async {
      repository.failRemoval = true;
      await client.beforeSignOut();
      expect(messaging.deletes, 1);
      expect(errors, hasLength(1));
    },
  );
  test('permission denial survives token cleanup failure', () async {
    repository.failRemoval = true;
    expect(await client.enableAfterRationale(), NotificationPermission.denied);
    expect(errors, hasLength(1));
    expect(repository.values, isEmpty);
  });
  test(
    'empty implementation fails mutations instead of reporting success',
    () async {
      const empty = EmptyNotificationRepository();
      expect(await empty.watchNotifications('owner').first, isEmpty);
      await expectLater(
        empty.setPreference('owner', NotificationType.like, false),
        throwsStateError,
      );
      await expectLater(empty.markRead('owner', 'missing'), throwsStateError);
    },
  );

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 790);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: RepaintBoundary(key: const ValueKey('capture'), child: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('NOTIFICATION_SCREENSHOTS')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('test/notification_renders/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('canonical empty screen', (tester) async {
    await pump(tester, NotificationsScreen(client: client, onSettings: () {}));
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(find.byTooltip('Notification settings'), findsNothing);
    await capture(tester, 'notifications-empty');
  });
  testWidgets('canonical list routes exact row and provides settings', (
    tester,
  ) async {
    for (final type in [
      NotificationType.friendRequest,
      NotificationType.requestAccepted,
      NotificationType.comment,
      NotificationType.like,
    ]) {
      repository.items[type.name] = fixture(type);
    }
    var settings = 0;
    await pump(
      tester,
      NotificationsScreen(
        client: client,
        onSettings: () {
          settings++;
        },
      ),
    );
    await capture(tester, 'notifications');
    await tester.tap(find.text('Sarah liked your review'));
    await tester.pumpAndSettle();
    expect(destinations.single.id, 'exact-like');
    await tester.tap(find.byTooltip('Notification settings'));
    expect(settings, 1);
  });
  testWidgets('preferences persist independently across screen reopening', (
    tester,
  ) async {
    Widget screen() => NotificationSettingsScreen(
      userId: 'owner',
      repository: repository,
      openSettings: messaging.openSettings,
    );
    await pump(tester, screen());
    await capture(tester, 'notification-settings');
    await tester.tap(find.byType(Switch).at(2));
    await tester.pumpAndSettle();
    expect(repository.values, {NotificationType.like: false});
    await tester.pumpWidget(const SizedBox());
    await pump(tester, screen());
    expect(
      tester
          .widgetList<Switch>(find.byType(Switch))
          .map((widget) => widget.value),
      [true, true, false, true],
    );
    await tester.ensureVisible(find.text('Phone notification settings'));
    await tester.tap(find.text('Phone notification settings'));
    expect(messaging.settings, 1);
  });
  testWidgets('failed preference save is visible and not optimistic success', (
    tester,
  ) async {
    repository.failWrites = true;
    await pump(
      tester,
      NotificationSettingsScreen(
        userId: 'owner',
        repository: repository,
        openSettings: messaging.openSettings,
      ),
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Couldn’t save your preference. Please try again.'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });
  testWidgets('rationale precedes OS prompt and denied UI offers settings', (
    tester,
  ) async {
    await pump(
      tester,
      NotificationPermissionScreen(client: client, onDone: () {}),
    );
    expect(messaging.requests, 0);
    await capture(tester, 'notification-permission');
    await tester.tap(find.text('Enable notifications'));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(messaging.requests, 1);
    expect(
      find.text(
        'Notifications are off in your phone settings. Your preferences are saved.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Phone notification settings'));
    expect(messaging.settings, 1);
    expect(repository.values, isEmpty);
  });
  testWidgets('permission actions scroll above Android bottom insets', (
    tester,
  ) async {
    await pump(
      tester,
      NotificationPermissionScreen(client: client, onDone: () {}),
    );
    tester.view.physicalSize = const Size(360, 520);
    tester.view.padding = const FakeViewPadding(bottom: 32);
    tester.view.viewPadding = const FakeViewPadding(bottom: 32);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(find.text('Not now')).dy,
      lessThanOrEqualTo(488),
    );
    expect(tester.takeException(), isNull);
  });
}
