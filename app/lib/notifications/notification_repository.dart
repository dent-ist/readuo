import 'dart:async';
import '../features/online_writes.dart';
import '../library/book.dart';
import '../library/shelf.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification.dart';
import 'book_addition.dart';
import 'notification_features.dart';

abstract interface class NotificationRepository {
  Stream<List<ReaduoNotification>> watchNotifications(String userId);
  Future<ReaduoNotification?> getNotification(String userId, String id);
  Stream<NotificationPreferences> watchPreferences(String userId);
  Future<NotificationPreferences> getPreferences(String userId);
  Future<BookAdditionPage> getBookAdditionPage(
    String userId,
    String groupId, {
    String? after,
  });
  Stream<BookAdditionPage> watchBookAdditionPage(
    String userId,
    String groupId, {
    String? after,
  });
  Future<void> setPreference(
    String userId,
    NotificationType type,
    bool enabled,
  );
  Future<void> markRead(String userId, String id);
  Future<void> saveToken(String userId, String installationId, String token);
  Future<void> removeToken(String userId, String installationId);
}

class EmptyNotificationRepository implements NotificationRepository {
  const EmptyNotificationRepository();

  @override
  Future<BookAdditionPage> getBookAdditionPage(
    String userId,
    String groupId, {
    String? after,
  }) async => const BookAdditionPage(items: []);
  @override
  Stream<BookAdditionPage> watchBookAdditionPage(
    String userId,
    String groupId, {
    String? after,
  }) => Stream.fromFuture(getBookAdditionPage(userId, groupId, after: after));

  @override
  Future<NotificationPreferences> getPreferences(String userId) async =>
      const NotificationPreferences();

  @override
  Stream<List<ReaduoNotification>> watchNotifications(String userId) =>
      Stream.value(const []);
  @override
  Future<ReaduoNotification?> getNotification(String userId, String id) async =>
      null;
  @override
  Stream<NotificationPreferences> watchPreferences(String userId) =>
      Stream.value(const NotificationPreferences());
  Never _unavailable() => throw StateError('Notifications are not connected.');
  @override
  Future<void> setPreference(
    String userId,
    NotificationType type,
    bool enabled,
  ) async => _unavailable();
  @override
  Future<void> markRead(String userId, String id) async => _unavailable();
  @override
  Future<void> saveToken(
    String userId,
    String installationId,
    String token,
  ) async => _unavailable();
  @override
  Future<void> removeToken(String userId, String installationId) async =>
      _unavailable();
}

class FirestoreNotificationRepository implements NotificationRepository {
  FirestoreNotificationRepository(
    this.firestore, {
    this.bookAdditionsEnabled = bookAdditionNotificationsEnabled,
  });
  final FirebaseFirestore firestore;
  final bool bookAdditionsEnabled;

  static Map<String, dynamic> tokenData(
    String token, {
    Map<String, dynamic>? existing,
    bool bookAdditionsEnabled = bookAdditionNotificationsEnabled,
  }) => {
    'token': token,
    'platform': 'android',
    'updatedAt': FieldValue.serverTimestamp(),
    if (bookAdditionsEnabled) 'bookAdditionV1': true,
    if (bookAdditionsEnabled)
      'bookAdditionEnabledAt':
          existing?['token'] == token &&
              existing?['bookAdditionV1'] == true &&
              existing?['bookAdditionEnabledAt'] is Timestamp
          ? existing!['bookAdditionEnabledAt']
          : FieldValue.serverTimestamp(),
  };

  @override
  Future<NotificationPreferences> getPreferences(String userId) async =>
      NotificationPreferences.fromMap(
        (await _user(userId)
                    .collection('preferences')
                    .doc('notifications')
                    .get(const GetOptions(source: Source.server)))
                .data() ??
            {},
      );

  DocumentReference<Map<String, dynamic>> _user(String userId) =>
      firestore.collection('users').doc(userId);
  DocumentReference<Map<String, dynamic>> _notice(String userId, String id) =>
      _user(userId)
          .collection(
            id.startsWith('books_')
                ? 'bookAdditionNotifications'
                : 'notifications',
          )
          .doc(id);

  ReaduoNotification? _safeDecode(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => decodeData(snapshot.id, snapshot.data() ?? {});

  static ReaduoNotification? decodeData(String id, Map<String, dynamic> data) {
    try {
      String requiredId(String key) {
        final value = data[key];
        if (value is! String || value.isEmpty || value.contains('/')) {
          throw FormatException('Invalid notification $key');
        }
        return value;
      }

      return ReaduoNotification(
        id: id,
        recipientId: requiredId('recipientId'),
        actorId: requiredId('actorId'),
        actorName: data['type'] == 'booksAdded'
            ? 'Reader'
            : data['actorName'] as String,
        type: NotificationType.values.byName(data['type'] as String),
        targetId: requiredId('targetId'),
        commentId: data['commentId'] == null ? null : requiredId('commentId'),
        preview: data['type'] == 'booksAdded'
            ? ''
            : data['preview'] as String? ?? '',
        isReview: data['isReview'] as bool? ?? false,
        createdAt: (data['createdAt'] as Timestamp).toDate(),
        readAt: (data['readAt'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<List<ReaduoNotification>> watchNotifications(String userId) {
    late StreamController<List<ReaduoNotification>> controller;
    final subscriptions = <StreamSubscription>[];
    final values = <String, List<ReaduoNotification>>{};
    void emit() {
      final items = values.values.expand((items) => items).toList()
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      if (!controller.isClosed) controller.add(items.take(100).toList());
    }

    controller = StreamController(
      onListen: () {
        for (final collection in [
          'notifications',
          if (bookAdditionsEnabled) 'bookAdditionNotifications',
        ]) {
          subscriptions.add(
            _user(userId)
                .collection(collection)
                .orderBy('createdAt', descending: true)
                .limit(100)
                .snapshots()
                .listen(
                  (snapshot) {
                    values[collection] = snapshot.docs
                        .map(_safeDecode)
                        .whereType<ReaduoNotification>()
                        .where((item) => item.recipientId == userId)
                        .toList();
                    emit();
                  },
                  onError: (Object error) {
                    if (collection == 'bookAdditionNotifications' &&
                        error is FirebaseException &&
                        error.code == 'permission-denied') {
                      values[collection] = [];
                      emit();
                    } else {
                      controller.addError(error);
                    }
                  },
                ),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<ReaduoNotification?> getNotification(String userId, String id) async {
    if (id.isEmpty || id.contains('/')) return null;
    if (!bookAdditionsEnabled && id.startsWith('books_')) return null;
    final snapshot = await _notice(
      userId,
      id,
    ).get(const GetOptions(source: Source.server));
    if (!snapshot.exists) return null;
    final item = _safeDecode(snapshot);
    if (item == null) return null;
    if (item.recipientId != userId || item.actorId == userId) return null;
    if (item.type == NotificationType.booksAdded) {
      String? cursor;
      for (var page = 0; page < 50; page++) {
        final current = await getBookAdditionPage(
          userId,
          item.targetId,
          after: cursor,
        );
        if (current.items.isNotEmpty) return item;
        cursor = current.nextCursor;
        if (cursor == null) return null;
      }
      return null;
    }
    final data = snapshot.data()!;
    final sourcePath = data['sourcePath'];
    if (sourcePath is! String || data['sourceCreatedAt'] == null) return null;
    final source = await firestore
        .doc(sourcePath)
        .get(const GetOptions(source: Source.server));
    final active = await firestore
        .collection('activeAccounts')
        .doc(userId)
        .get(const GetOptions(source: Source.server));
    if (!active.exists ||
        !source.exists ||
        source.data()?['createdAt'] != data['sourceCreatedAt'])
      return null;
    if (item.type != NotificationType.friendRequest) {
      final forward = await firestore
          .collection('friendships')
          .doc('${item.actorId}--$userId')
          .get(const GetOptions(source: Source.server));
      final reverse = await firestore
          .collection('friendships')
          .doc('$userId--${item.actorId}')
          .get(const GetOptions(source: Source.server));
      if (!forward.exists && !reverse.exists) return null;
    }
    return item;
  }

  @override
  Stream<NotificationPreferences> watchPreferences(String userId) =>
      _user(userId)
          .collection('preferences')
          .doc('notifications')
          .snapshots()
          .map(
            (snapshot) =>
                NotificationPreferences.fromMap(snapshot.data() ?? {}),
          );

  @override
  Future<void> setPreference(
    String userId,
    NotificationType type,
    bool enabled,
  ) {
    if (type == NotificationType.booksAdded && !bookAdditionsEnabled) {
      return Future.error(StateError('Book alerts are not available yet.'));
    }
    return _user(
      userId,
    ).collection('preferences').doc('notifications').setOnline({
      type.name: enabled,
      if (type == NotificationType.booksAdded)
        'booksAddedSince': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> markRead(String userId, String id) => firestore.runTransaction((
    transaction,
  ) async {
    final reference = _notice(userId, id);
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists || snapshot.data()!['recipientId'] != userId) {
      throw StateError('Notification is unavailable.');
    }
    if (snapshot.data()!['readAt'] == null) {
      transaction.update(reference, {'readAt': FieldValue.serverTimestamp()});
    }
  });

  @override
  Future<void> saveToken(String userId, String installationId, String token) =>
      firestore.runTransaction((transaction) async {
        final reference = _user(
          userId,
        ).collection('notificationTokens').doc(installationId);
        final previous = await transaction.get(reference);
        final existing = previous.data();
        transaction.set(
          reference,
          tokenData(
            token,
            existing: existing,
            bookAdditionsEnabled: bookAdditionsEnabled,
          ),
        );
      });

  @override
  Future<BookAdditionPage> getBookAdditionPage(
    String userId,
    String groupId, {
    String? after,
  }) async {
    if (!bookAdditionsEnabled) throw StateError('Activity unavailable.');
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(groupId))
      throw StateError('Activity unavailable.');
    final reference = firestore.collection('bookAdditionGroups').doc(groupId);
    final group = await reference.get(const GetOptions(source: Source.server));
    if (!group.exists ||
        group.data()?['recipientId'] != userId ||
        group.data()?['state'] != 'frozen' ||
        group.data()?['overflow'] == true)
      throw StateError('Activity unavailable.');
    final actorId = group.data()!['actorId'] as String;
    Query<Map<String, dynamic>> query = reference
        .collection('bookAdditionEntries')
        .orderBy(FieldPath.documentId)
        .limit(20);
    if (after != null) query = query.startAfter([after]);
    final entries = await query.get(const GetOptions(source: Source.server));
    final items = <BookAdditionItem>[];
    final paths = <String>[reference.path];
    for (final entry in entries.docs) {
      final data = entry.data();
      final shelfId = data['shelfId'] as String;
      final bookId = data['bookId'] as String;
      final sourcePath = data['sourcePath'] as String;
      paths.addAll([
        sourcePath,
        'shelves/$shelfId',
        'shelves/$shelfId/books/$bookId',
      ]);
      try {
        final activity = await firestore
            .doc(sourcePath)
            .get(const GetOptions(source: Source.server));
        final shelf = await firestore
            .doc('shelves/$shelfId')
            .get(const GetOptions(source: Source.server));
        final book = await firestore
            .doc('shelves/$shelfId/books/$bookId')
            .get(const GetOptions(source: Source.server));
        if (!activity.exists ||
            !shelf.exists ||
            !book.exists ||
            activity.data()?['type'] != 'added' ||
            activity.data()?['createdAt'] != data['addedAt'] ||
            activity.data()?['authorId'] != actorId ||
            book.data()?['ownerId'] != actorId ||
            book.data()?['shelfId'] != shelfId ||
            book.data()?['isOwned'] != true ||
            book.data()?['activityGeneration'] != data['activityGeneration'] ||
            book.data()?['createdAt'] != data['addedAt'] ||
            shelf.data()?['ownerId'] != actorId ||
            shelf.data()?['autoShareActivity'] != true ||
            !['friends', 'public'].contains(shelf.data()?['visibility']))
          continue;
        items.add(
          BookAdditionItem(
            book: LibraryBook.fromFirestore(book.id, shelfId, book.data()!),
            shelf: Shelf.fromFirestore(shelf.id, shelf.data()!),
          ),
        );
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied' && error.code != 'not-found')
          rethrow;
      }
    }
    return BookAdditionPage(
      items: items,
      nextCursor: entries.docs.length == 20 ? entries.docs.last.id : null,
      watchPaths: paths,
    );
  }

  @override
  Stream<BookAdditionPage> watchBookAdditionPage(
    String userId,
    String groupId, {
    String? after,
  }) {
    late StreamController<BookAdditionPage> controller;
    final subscriptions = <String, StreamSubscription>{};
    Timer? debounce;
    var disposed = false;
    var generation = 0;
    void refresh() {
      debounce?.cancel();
      final current = ++generation;
      debounce = Timer(const Duration(milliseconds: 60), () async {
        try {
          final page = await getBookAdditionPage(userId, groupId, after: after);
          if (disposed || current != generation) return;
          controller.add(page);
          for (final path in page.watchPaths) {
            subscriptions.putIfAbsent(
              path,
              () => firestore
                  .doc(path)
                  .snapshots()
                  .listen((_) => refresh(), onError: (Object _) => refresh()),
            );
          }
        } catch (error) {
          if (!disposed && current == generation) controller.addError(error);
        }
      });
    }

    controller = StreamController(
      onListen: refresh,
      onCancel: () async {
        disposed = true;
        debounce?.cancel();
        for (final subscription in subscriptions.values) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> removeToken(String userId, String installationId) => _user(
    userId,
  ).collection('notificationTokens').doc(installationId).deleteOnline();
}
