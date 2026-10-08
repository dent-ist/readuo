import '../features/online_writes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum CircleContentKind { post, review, activity }

class CircleContentRef {
  const CircleContentRef({
    required this.kind,
    required this.id,
    required this.authorId,
    this.shelfId,
    this.bookId,
  });

  final CircleContentKind kind;
  final String id;
  final String authorId;
  final String? shelfId;
  final String? bookId;

  String get collection => switch (kind) {
    CircleContentKind.post => 'circlePosts',
    CircleContentKind.review => 'circleReviews',
    CircleContentKind.activity => 'shelves/$shelfId/books/$bookId/activities',
  };
}

class CircleComment {
  const CircleComment({
    required this.id,
    required this.authorId,
    required this.authorDisplayName,
    required this.authorPhotoUrl,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CircleComment.fromFirestore(String id, Map<String, dynamic> data) =>
      CircleComment(
        id: id,
        authorId: data['authorId'] as String? ?? '',
        authorDisplayName: data['authorDisplayName'] as String? ?? 'Reader',
        authorPhotoUrl: data['authorPhotoUrl'] as String?,
        text: data['text'] as String? ?? '',
        createdAt: _dateFrom(data['createdAt']),
        updatedAt: _dateFrom(data['updatedAt']),
      );

  final String id;
  final String authorId;
  final String authorDisplayName;
  final String? authorPhotoUrl;
  final String text;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

DateTime? _dateFrom(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

abstract interface class CircleEngagementRepository {
  Stream<Set<String>> watchLikeUserIds(CircleContentRef content);

  Future<void> setLiked({
    required CircleContentRef content,
    required String userId,
    required bool liked,
  });

  Stream<List<CircleComment>> watchComments(CircleContentRef content);

  Future<void> addComment({
    required CircleContentRef content,
    required String authorId,
    required String authorDisplayName,
    required String? authorPhotoUrl,
    required String text,
  });

  Future<void> updateComment({
    required CircleContentRef content,
    required CircleComment comment,
    required String text,
  });

  Future<void> deleteComment({
    required CircleContentRef content,
    required String commentId,
  });

  Future<void> deleteInteractions(CircleContentRef content);
}

class FirebaseCircleEngagementRepository implements CircleEngagementRepository {
  FirebaseCircleEngagementRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _content(CircleContentRef content) =>
      _firestore.collection(content.collection).doc(content.id);

  @override
  Stream<Set<String>> watchLikeUserIds(CircleContentRef content) =>
      _content(content)
          .collection('likes')
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map((document) => document.id).toSet(),
          );

  @override
  Future<void> setLiked({
    required CircleContentRef content,
    required String userId,
    required bool liked,
  }) async {
    final reference = _content(content).collection('likes').doc(userId);
    try {
      if (liked) {
        await reference.setOnline({
          'userId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await reference.deleteOnline();
      }
    } on FirebaseException catch (error) {
      throw _failure(error, liked ? 'like this post' : 'remove your like');
    }
  }

  @override
  Stream<List<CircleComment>> watchComments(CircleContentRef content) =>
      _content(content)
          .collection('comments')
          .orderBy('createdAt')
          .limit(200)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (document) =>
                      CircleComment.fromFirestore(document.id, document.data()),
                )
                .toList(),
          );

  @override
  Future<void> addComment({
    required CircleContentRef content,
    required String authorId,
    required String authorDisplayName,
    required String? authorPhotoUrl,
    required String text,
  }) async {
    try {
      await _content(content).collection('comments').doc().setOnline({
        'authorId': authorId,
        'authorDisplayName': authorDisplayName,
        'authorPhotoUrl': authorPhotoUrl,
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      throw _failure(error, 'add this comment');
    }
  }

  @override
  Future<void> updateComment({
    required CircleContentRef content,
    required CircleComment comment,
    required String text,
  }) async {
    try {
      await _content(
        content,
      ).collection('comments').doc(comment.id).updateOnline({
        'text': text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      throw _failure(error, 'update this comment');
    }
  }

  @override
  Future<void> deleteComment({
    required CircleContentRef content,
    required String commentId,
  }) async {
    try {
      await _content(
        content,
      ).collection('comments').doc(commentId).deleteOnline();
    } on FirebaseException catch (error) {
      throw _failure(error, 'remove this comment');
    }
  }

  @override
  Future<void> deleteInteractions(CircleContentRef content) async {
    try {
      for (final collectionName in const ['likes', 'comments']) {
        while (true) {
          final snapshot = await _content(content)
              .collection(collectionName)
              .limit(100)
              .get(const GetOptions(source: Source.server));
          if (snapshot.docs.isEmpty) break;
          for (final document in snapshot.docs) {
            await document.reference.deleteOnline();
          }
        }
      }
    } on FirebaseException catch (error) {
      throw _failure(error, 'remove post activity');
    }
  }

  Exception _failure(FirebaseException error, String action) =>
      Exception(switch (error.code) {
        'permission-denied' => 'You no longer have access to $action.',
        'unavailable' => 'Readuo cannot $action while offline.',
        _ => 'Readuo could not $action. Please retry.',
      });
}

class EmptyCircleEngagementRepository implements CircleEngagementRepository {
  const EmptyCircleEngagementRepository();

  @override
  Stream<Set<String>> watchLikeUserIds(CircleContentRef content) =>
      Stream.value(const {});

  @override
  Future<void> setLiked({
    required CircleContentRef content,
    required String userId,
    required bool liked,
  }) async {}

  @override
  Stream<List<CircleComment>> watchComments(CircleContentRef content) =>
      Stream.value(const []);

  @override
  Future<void> addComment({
    required CircleContentRef content,
    required String authorId,
    required String authorDisplayName,
    required String? authorPhotoUrl,
    required String text,
  }) async {}

  @override
  Future<void> updateComment({
    required CircleContentRef content,
    required CircleComment comment,
    required String text,
  }) async {}

  @override
  Future<void> deleteComment({
    required CircleContentRef content,
    required String commentId,
  }) async {}

  @override
  Future<void> deleteInteractions(CircleContentRef content) async {}
}
