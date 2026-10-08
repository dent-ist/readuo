import '../features/online_writes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CircleFailure implements Exception {
  const CircleFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

enum CircleActivityType { added, started, finished }

class CircleBookAttachment {
  const CircleBookAttachment({
    required this.ownerId,
    required this.shelfId,
    required this.bookId,
    required this.title,
    required this.author,
    required this.coverUrl,
  });

  final String ownerId;
  final String shelfId;
  final String bookId;
  final String title;
  final String author;
  final String? coverUrl;
}

class CirclePostDraft {
  const CirclePostDraft({
    required this.postId,
    required this.text,
    required this.attachment,
    this.photoPath,
  });

  final String postId;
  final String text;
  final CircleBookAttachment? attachment;
  final String? photoPath;
}

class CirclePost {
  const CirclePost({
    required this.id,
    required this.authorId,
    required this.text,
    required this.attachment,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CirclePost.fromFirestore(String id, Map<String, dynamic> data) {
    final attachedBookId = data['attachedBookId'] as String?;
    return CirclePost(
      id: id,
      authorId: data['authorId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      attachment: attachedBookId == null
          ? null
          : CircleBookAttachment(
              ownerId: data['attachedBookOwnerId'] as String? ?? '',
              shelfId: data['attachedShelfId'] as String? ?? '',
              bookId: attachedBookId,
              title: data['attachedTitle'] as String? ?? '',
              author: data['attachedAuthor'] as String? ?? '',
              coverUrl: data['attachedCoverUrl'] as String?,
            ),
      photoPath: data['photoPath'] as String?,
      createdAt: _dateFrom(data['createdAt']),
      updatedAt: _dateFrom(data['updatedAt']),
    );
  }

  final String id;
  final String authorId;
  final String text;
  final CircleBookAttachment? attachment;
  final String? photoPath;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

DateTime? _dateFrom(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

class CircleActivity {
  const CircleActivity({
    required this.id,
    required this.authorId,
    required this.shelfId,
    required this.bookId,
    required this.type,
    required this.batchId,
    this.activityGeneration = '',
    required this.createdAt,
  });

  factory CircleActivity.fromFirestore(String id, Map<String, dynamic> data) {
    final storedType = data['type'] as String?;
    return CircleActivity(
      id: id,
      authorId: data['authorId'] as String? ?? '',
      shelfId: data['shelfId'] as String? ?? '',
      bookId: data['bookId'] as String? ?? '',
      type: switch (storedType) {
        'started' => CircleActivityType.started,
        'finished' => CircleActivityType.finished,
        _ => CircleActivityType.added,
      },
      batchId: data['batchId'] as String?,
      activityGeneration: data['activityGeneration'] as String? ?? '',
      createdAt: switch (data['createdAt']) {
        Timestamp timestamp => timestamp.toDate(),
        DateTime date => date,
        _ => null,
      },
    );
  }

  final String id;
  final String authorId;
  final String shelfId;
  final String bookId;
  final CircleActivityType type;
  final String? batchId;
  final String activityGeneration;
  final DateTime? createdAt;
}

abstract interface class CircleRepository {
  Stream<List<CircleActivity>> watchBookActivities({
    required String viewerId,
    required String ownerId,
    required String shelfId,
    required String bookId,
    required String activityGeneration,
    required bool includeAdded,
  });

  Stream<List<CirclePost>> watchPostsForAuthor({
    required String viewerId,
    required String authorId,
  });

  Future<CirclePostDraft?> loadPostDraft(String ownerId);

  Future<void> savePostDraft({
    required String ownerId,
    required CirclePostDraft draft,
  });

  Future<void> clearPostDraft(String ownerId);

  String newPostId();

  Future<void> publishPostDraft({
    required String authorId,
    required CirclePostDraft draft,
  });

  Future<void> updatePost({
    required String authorId,
    required String postId,
    required String text,
    required CircleBookAttachment? attachment,
    required String? photoPath,
  });

  Future<void> deletePost({required String authorId, required String postId});
}

class FirebaseCircleRepository implements CircleRepository {
  FirebaseCircleRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Map<String, Object?> _postData({
    required String authorId,
    required String text,
    required CircleBookAttachment? attachment,
    required String? photoPath,
    required Object updatedAt,
    Object? createdAt,
  }) => {
    'authorId': authorId,
    'text': text.trim(),
    'attachedBookOwnerId': attachment?.ownerId,
    'attachedShelfId': attachment?.shelfId,
    'attachedBookId': attachment?.bookId,
    'attachedTitle': attachment?.title,
    'attachedAuthor': attachment?.author,
    'attachedCoverUrl': attachment?.coverUrl,
    'photoPath': photoPath,
    if (createdAt != null) 'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  @override
  Stream<List<CircleActivity>> watchBookActivities({
    required String viewerId,
    required String ownerId,
    required String shelfId,
    required String bookId,
    required String activityGeneration,
    required bool includeAdded,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .doc(shelfId)
              .collection('books')
              .doc(bookId)
              .collection('activities')
              .where('activityGeneration', isEqualTo: activityGeneration)
              .where(
                'type',
                whereIn: includeAdded
                    ? const ['added', 'started', 'finished']
                    : const ['started', 'finished'],
              )
              .orderBy('createdAt', descending: true)
              .limit(20)
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        yield snapshot.docs
            .map(
              (document) =>
                  CircleActivity.fromFirestore(document.id, document.data()),
            )
            .where(
              (activity) =>
                  activity.authorId == ownerId &&
                  activity.shelfId == shelfId &&
                  activity.bookId == bookId &&
                  activity.activityGeneration == activityGeneration,
            )
            .toList();
      }
    } on FirebaseException catch (error) {
      throw CircleFailure(switch (error.code) {
        'permission-denied' =>
          'This Circle activity is no longer shared with you.',
        'unavailable' =>
          'Circle needs a connection. Check your network and retry.',
        _ => 'Readuo could not load Circle activity. Please retry.',
      });
    }
  }

  @override
  Stream<List<CirclePost>> watchPostsForAuthor({
    required String viewerId,
    required String authorId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('circlePosts')
              .where('authorId', isEqualTo: authorId)
              .orderBy('createdAt', descending: true)
              .limit(20)
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        yield snapshot.docs
            .map(
              (document) =>
                  CirclePost.fromFirestore(document.id, document.data()),
            )
            .where((post) => post.authorId == authorId)
            .toList();
      }
    } on FirebaseException catch (error) {
      throw _postFailure(error, 'load Circle posts');
    }
  }

  @override
  Future<CirclePostDraft?> loadPostDraft(String ownerId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(ownerId)
          .collection('circleDrafts')
          .doc('newPost')
          .get(const GetOptions(source: Source.server));
      if (!snapshot.exists) return null;
      return _draftFromData(snapshot.data()!);
    } on FirebaseException catch (error) {
      throw _postFailure(error, 'load your draft');
    }
  }

  @override
  Future<void> savePostDraft({
    required String ownerId,
    required CirclePostDraft draft,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(ownerId)
          .collection('circleDrafts')
          .doc('newPost')
          .setOnline(
            _postData(
                authorId: ownerId,
                text: draft.text,
                attachment: draft.attachment,
                photoPath: draft.photoPath,
                updatedAt: FieldValue.serverTimestamp(),
              )
              ..remove('authorId')
              ..['text'] = draft.text
              ..['postId'] = draft.postId,
          );
    } on FirebaseException catch (error) {
      throw _postFailure(error, 'save your draft');
    }
  }

  @override
  Future<void> clearPostDraft(String ownerId) async {
    try {
      await _firestore
          .collection('users')
          .doc(ownerId)
          .collection('circleDrafts')
          .doc('newPost')
          .deleteOnline();
    } on FirebaseException catch (error) {
      throw _postFailure(error, 'clear your draft');
    }
  }

  @override
  String newPostId() => _firestore.collection('circlePosts').doc().id;

  @override
  Future<void> publishPostDraft({
    required String authorId,
    required CirclePostDraft draft,
  }) async {
    try {
      final postReference = _firestore
          .collection('circlePosts')
          .doc(draft.postId);
      final draftReference = _firestore
          .collection('users')
          .doc(authorId)
          .collection('circleDrafts')
          .doc('newPost');
      await _firestore.runTransaction((transaction) async {
        final currentDraftSnapshot = await transaction.get(draftReference);
        final currentDraft = currentDraftSnapshot.exists
            ? _draftFromData(currentDraftSnapshot.data()!)
            : null;
        if (currentDraft != null && !_draftsMatch(currentDraft, draft)) {
          throw const CircleFailure(
            'This draft changed on another device. Review it before posting.',
          );
        }
        final existing = await transaction.get(postReference);
        if (currentDraft == null && !existing.exists) {
          throw const CircleFailure(
            'Readuo could not verify this draft. Save it and try again.',
          );
        }
        if (existing.exists) {
          final post = CirclePost.fromFirestore(existing.id, existing.data()!);
          if (!_matchesDraft(post, authorId, draft)) {
            throw const CircleFailure(
              'Readuo could not safely retry this post. Please start a new draft.',
            );
          }
        } else {
          transaction.set(
            postReference,
            _postData(
              authorId: authorId,
              text: draft.text,
              attachment: draft.attachment,
              photoPath: draft.photoPath,
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            ),
          );
        }
        if (currentDraft != null) transaction.delete(draftReference);
      });
    } on CircleFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _postFailure(error, 'publish this post');
    }
  }

  bool _matchesDraft(CirclePost post, String authorId, CirclePostDraft draft) {
    final expected = draft.attachment;
    final actual = post.attachment;
    return post.authorId == authorId &&
        post.text == draft.text.trim() &&
        post.photoPath == draft.photoPath &&
        actual?.ownerId == expected?.ownerId &&
        actual?.shelfId == expected?.shelfId &&
        actual?.bookId == expected?.bookId &&
        actual?.title == expected?.title &&
        actual?.author == expected?.author &&
        actual?.coverUrl == expected?.coverUrl;
  }

  CirclePostDraft _draftFromData(Map<String, dynamic> data) {
    final attachedBookId = data['attachedBookId'] as String?;
    return CirclePostDraft(
      postId: data['postId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      attachment: attachedBookId == null
          ? null
          : CircleBookAttachment(
              ownerId: data['attachedBookOwnerId'] as String? ?? '',
              shelfId: data['attachedShelfId'] as String? ?? '',
              bookId: attachedBookId,
              title: data['attachedTitle'] as String? ?? '',
              author: data['attachedAuthor'] as String? ?? '',
              coverUrl: data['attachedCoverUrl'] as String?,
            ),
      photoPath: data['photoPath'] as String?,
    );
  }

  bool _draftsMatch(CirclePostDraft current, CirclePostDraft expected) {
    final currentAttachment = current.attachment;
    final expectedAttachment = expected.attachment;
    return current.postId == expected.postId &&
        current.text == expected.text &&
        current.photoPath == expected.photoPath &&
        currentAttachment?.ownerId == expectedAttachment?.ownerId &&
        currentAttachment?.shelfId == expectedAttachment?.shelfId &&
        currentAttachment?.bookId == expectedAttachment?.bookId &&
        currentAttachment?.title == expectedAttachment?.title &&
        currentAttachment?.author == expectedAttachment?.author &&
        currentAttachment?.coverUrl == expectedAttachment?.coverUrl;
  }

  @override
  Future<void> updatePost({
    required String authorId,
    required String postId,
    required String text,
    required CircleBookAttachment? attachment,
    required String? photoPath,
  }) async {
    try {
      await _firestore
          .collection('circlePosts')
          .doc(postId)
          .updateOnline(
            _postData(
              authorId: authorId,
              text: text,
              attachment: attachment,
              photoPath: photoPath,
              updatedAt: FieldValue.serverTimestamp(),
            )..remove('authorId'),
          );
    } on FirebaseException catch (error) {
      throw _postFailure(error, 'update this post');
    }
  }

  @override
  Future<void> deletePost({
    required String authorId,
    required String postId,
  }) async {
    try {
      await _firestore.collection('circlePosts').doc(postId).deleteOnline();
    } on FirebaseException catch (error) {
      throw _postFailure(error, 'delete this post');
    }
  }

  CircleFailure _postFailure(FirebaseException error, String action) =>
      CircleFailure(switch (error.code) {
        'permission-denied' =>
          'Readuo could not $action because access changed.',
        'unavailable' =>
          'Readuo cannot $action while offline. Retry when connected.',
        _ => 'Readuo could not $action. Please retry.',
      });
}

class EmptyCircleRepository implements CircleRepository {
  const EmptyCircleRepository();

  @override
  Stream<List<CircleActivity>> watchBookActivities({
    required String viewerId,
    required String ownerId,
    required String shelfId,
    required String bookId,
    required String activityGeneration,
    required bool includeAdded,
  }) => Stream.value(const []);

  @override
  Stream<List<CirclePost>> watchPostsForAuthor({
    required String viewerId,
    required String authorId,
  }) => Stream.value(const []);

  @override
  Future<CirclePostDraft?> loadPostDraft(String ownerId) async => null;

  @override
  Future<void> savePostDraft({
    required String ownerId,
    required CirclePostDraft draft,
  }) async {}

  @override
  Future<void> clearPostDraft(String ownerId) async {}

  @override
  String newPostId() => 'empty-post';

  @override
  Future<void> publishPostDraft({
    required String authorId,
    required CirclePostDraft draft,
  }) async {}

  @override
  Future<void> updatePost({
    required String authorId,
    required String postId,
    required String text,
    required CircleBookAttachment? attachment,
    required String? photoPath,
  }) async {}

  @override
  Future<void> deletePost({
    required String authorId,
    required String postId,
  }) async {}
}
