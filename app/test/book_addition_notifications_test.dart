import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/notifications/book_addition.dart';
import 'package:readuo/notifications/book_addition_screen.dart';
import 'package:readuo/notifications/notification.dart';
import 'package:readuo/notifications/notification_repository.dart';
import 'package:readuo/notifications/notification_screens.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'notifications_test.dart' show TestNotificationRepository;

class BookAdditionFixtureRepository extends TestNotificationRepository {
  final changes = StreamController<BookAdditionPage>.broadcast();
  bool revoked = false;
  BookAdditionPage page(String? after) => BookAdditionPage(
    items: [
      for (final index in after == null ? [1, 2] : [3])
        BookAdditionItem(
          book: LibraryBook(
            id: 'book$index',
            ownerId: 'actor',
            shelfId: 'shelf',
            title: index == 1
                ? 'The Left Hand of Darkness: A Reader’s Journey'
                : 'A quiet chapter $index',
            author: 'Ursula K. Le Guin',
            isbn: null,
            isOwned: true,
            readingStatus: ReadingStatus.wantToRead,
            coverUrl: null,
            createdAt: DateTime(2026),
          ),
          shelf: Shelf(
            id: 'shelf',
            ownerId: 'actor',
            name: 'Nightstand',
            visibility: ShelfVisibility.friends,
            autoShareActivity: true,
            bookCount: 3,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ),
    ],
    nextCursor: after == null ? 'page2' : null,
  );
  @override
  Future<BookAdditionPage> getBookAdditionPage(
    String userId,
    String groupId, {
    String? after,
  }) async {
    if (revoked) throw StateError('Unavailable');
    return page(after);
  }

  @override
  Stream<BookAdditionPage> watchBookAdditionPage(
    String userId,
    String groupId, {
    String? after,
  }) async* {
    yield await getBookAdditionPage(userId, groupId, after: after);
    yield* changes.stream;
  }
}

void main() {
  test('release token payload uses deployed legacy fields only', () {
    final previous = {
      'token': 'token',
      'bookAdditionV1': true,
      'bookAdditionEnabledAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    };
    final data = FirestoreNotificationRepository.tokenData(
      'token',
      existing: previous,
    );
    expect(data.keys, unorderedEquals(['token', 'platform', 'updatedAt']));
    final capable = FirestoreNotificationRepository.tokenData(
      'token',
      existing: previous,
      bookAdditionsEnabled: true,
    );
    expect(capable['bookAdditionEnabledAt'], previous['bookAdditionEnabledAt']);
    final rotated = FirestoreNotificationRepository.tokenData(
      'rotated',
      existing: previous,
      bookAdditionsEnabled: true,
    );
    expect(rotated['bookAdditionEnabledAt'], isA<FieldValue>());
  });
  testWidgets('live access failure clears previously rendered book details', (
    tester,
  ) async {
    final repository = BookAdditionFixtureRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: BookAdditionScreen(
          userId: 'owner',
          groupId: 'group',
          repository: repository,
          onOpenBook: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The Left Hand of Darkness: A Reader’s Journey'),
      findsOneWidget,
    );
    repository.changes.addError(StateError('Access revoked'));
    await tester.pumpAndSettle();
    expect(
      find.text('The Left Hand of Darkness: A Reader’s Journey'),
      findsNothing,
    );
    expect(find.text('This activity is no longer available.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await repository.changes.close();
    await repository.preferences.close();
  });
  test(
    'unknown and malformed notification types are skipped; old types remain readable',
    () {
      final data = {
        'recipientId': 'owner',
        'actorId': 'actor',
        'actorName': 'Kenny Kim',
        'type': 'like',
        'targetId': 'post',
        'createdAt': Timestamp.now(),
      };
      expect(
        FirestoreNotificationRepository.decodeData('notice', data)?.type,
        NotificationType.like,
      );
      expect(
        FirestoreNotificationRepository.decodeData('notice', {
          ...data,
          'type': 'futureType',
        }),
        isNull,
      );
      expect(
        FirestoreNotificationRepository.decodeData('notice', {
          ...data,
          'targetId': 'bad/id',
        }),
        isNull,
      );
      final addition = FirestoreNotificationRepository.decodeData(
        'books_group',
        {
          ...data,
          'type': 'booksAdded',
          'targetId': 'group',
          'preview': 'private title',
        },
      )!;
      expect(addition.title, 'New books in your circle');
      expect(addition.actorName, 'Reader');
      expect(addition.preview, isEmpty);
      expect(
        addition.destination.kind,
        NotificationDestinationKind.bookAddition,
      );
      expect(const NotificationPreferences().booksAdded, true);
      expect(
        NotificationPreferences.fromMap({
          'booksAdded': false,
        }).enabled(NotificationType.booksAdded),
        false,
      );
    },
  );
  testWidgets(
    'grouped book settings, pagination, authorized tap and live revocation',
    (tester) async {
      await runBookAdditionChecks(tester);
    },
  );
}

Future<void> runBookAdditionChecks(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  final repository = BookAdditionFixtureRepository();
  Future<void> show(Widget screen) async {
    await tester.pumpWidget(
      MaterialApp(theme: ReaduoTheme.modern, home: screen),
    );
    await tester.pumpAndSettle();
  }

  await show(
    NotificationSettingsScreen(
      userId: 'owner',
      repository: repository,
      openSettings: () async {},
    ),
  );
  expect(find.byType(Switch), findsNWidgets(4));
  expect(find.text('Friends add books'), findsNothing);
  if (capture != null) await capture('release-notification-settings');
  await show(
    NotificationSettingsScreen(
      bookAdditionsEnabled: true,
      userId: 'owner',
      repository: repository,
      openSettings: () async {},
    ),
  );
  await tester.ensureVisible(find.text('Friends add books'));
  await tester.pumpAndSettle();
  expect(
    tester
        .widgetList<Switch>(find.byType(Switch))
        .every((control) => control.value),
    true,
  );
  if (capture != null) await capture('books-added-setting');
  await tester.tap(find.byType(Switch).last);
  await tester.pumpAndSettle();
  expect(repository.values[NotificationType.booksAdded], false);
  var opened = 0;
  await show(
    BookAdditionScreen(
      userId: 'owner',
      groupId: 'group',
      repository: repository,
      onOpenBook: (_) async {
        opened++;
      },
    ),
  );
  if (capture != null) await capture('books-added-activity');
  await tester.tap(find.text('The Left Hand of Darkness: A Reader’s Journey'));
  await tester.pumpAndSettle();
  expect(opened, 1);
  await tester.ensureVisible(find.text('Next books'));
  await tester.tap(find.text('Next books'));
  await tester.pumpAndSettle();
  expect(find.text('A quiet chapter 3'), findsOneWidget);
  expect(
    find.text('The Left Hand of Darkness: A Reader’s Journey'),
    findsNothing,
  );
  if (capture != null) await capture('books-added-next-page');
  repository.revoked = true;
  await tester.tap(find.text('A quiet chapter 3'));
  await tester.pumpAndSettle();
  expect(opened, 1);
  expect(find.text('This activity is no longer available.'), findsOneWidget);
  expect(find.text('A quiet chapter 3'), findsNothing);
  if (capture != null) await capture('books-added-revoked');
  await tester.pumpWidget(const SizedBox.shrink());
  await repository.changes.close();
  await repository.preferences.close();
  expect(tester.takeException(), isNull);
}
