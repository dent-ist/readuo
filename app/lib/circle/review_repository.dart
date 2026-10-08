import '../features/online_writes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewFailure implements Exception {
  const ReviewFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

String circleReviewId(String authorId, String bookId) => '$authorId--$bookId';

class CircleReviewDraft {
  const CircleReviewDraft({
    required this.reviewId,
    required this.shelfId,
    required this.bookId,
    required this.bookCreatedAt,
    required this.title,
    required this.bookAuthor,
    required this.coverUrl,
    required this.text,
    required this.rating,
  });

  final String reviewId;
  final String shelfId;
  final String bookId;
  final DateTime bookCreatedAt;
  final String title;
  final String bookAuthor;
  final String? coverUrl;
  final String text;
  final int? rating;
}

class CircleReview {
  const CircleReview({
    required this.id,
    required this.authorId,
    required this.shelfId,
    required this.bookId,
    required this.bookCreatedAt,
    required this.title,
    required this.bookAuthor,
    required this.coverUrl,
    required this.text,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CircleReview.fromFirestore(String id, Map<String, dynamic> data) =>
      CircleReview(
        id: id,
        authorId: data['authorId'] as String? ?? '',
        shelfId: data['shelfId'] as String? ?? '',
        bookId: data['bookId'] as String? ?? '',
        bookCreatedAt: _dateFrom(data['bookCreatedAt']),
        title: data['title'] as String? ?? '',
        bookAuthor: data['bookAuthor'] as String? ?? '',
        coverUrl: data['coverUrl'] as String?,
        text: data['text'] as String? ?? '',
        rating: data['rating'] as int?,
        createdAt: _nullableDateFrom(data['createdAt']),
        updatedAt: _nullableDateFrom(data['updatedAt']),
      );

  final String id;
  final String authorId;
  final String shelfId;
  final String bookId;
  final DateTime bookCreatedAt;
  final String title;
  final String bookAuthor;
  final String? coverUrl;
  final String text;
  final int? rating;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CircleReviewDraft toDraft() => CircleReviewDraft(
    reviewId: id,
    shelfId: shelfId,
    bookId: bookId,
    bookCreatedAt: bookCreatedAt,
    title: title,
    bookAuthor: bookAuthor,
    coverUrl: coverUrl,
    text: text,
    rating: rating,
  );
}

DateTime _dateFrom(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => DateTime.fromMillisecondsSinceEpoch(0),
};

DateTime? _nullableDateFrom(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

abstract interface class ReviewRepository {
  Stream<List<CircleReview>> watchReviewsForAuthor({
    required String viewerId,
    required String authorId,
  });

  Stream<CircleReview?> watchReview({
    required String viewerId,
    required String authorId,
    required String bookId,
  });

  Future<CircleReviewDraft?> loadDraft({
    required String ownerId,
    required String reviewId,
  });

  Future<void> saveDraft({
    required String ownerId,
    required CircleReviewDraft draft,
  });

  Future<void> clearDraft({required String ownerId, required String reviewId});

  Future<void> publishDraft({
    required String authorId,
    required CircleReviewDraft draft,
  });

  Future<void> deleteReview({
    required String authorId,
    required String reviewId,
  });
}

class FirebaseReviewRepository implements ReviewRepository {
  FirebaseReviewRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<CircleReview>> watchReviewsForAuthor({
    required String viewerId,
    required String authorId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('circleReviews')
              .where('authorId', isEqualTo: authorId)
              .orderBy('createdAt', descending: true)
              .limit(20)
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        yield snapshot.docs
            .map(
              (document) =>
                  CircleReview.fromFirestore(document.id, document.data()),
            )
            .where((review) => review.authorId == authorId)
            .toList();
      }
    } on FirebaseException catch (error) {
      throw _failure(error, 'load reviews');
    }
  }

  @override
  Stream<CircleReview?> watchReview({
    required String viewerId,
    required String authorId,
    required String bookId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('circleReviews')
              .doc(circleReviewId(authorId, bookId))
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        yield snapshot.exists
            ? CircleReview.fromFirestore(snapshot.id, snapshot.data()!)
            : null;
      }
    } on FirebaseException catch (error) {
      throw _failure(error, 'load this review');
    }
  }

  @override
  Future<CircleReviewDraft?> loadDraft({
    required String ownerId,
    required String reviewId,
  }) async {
    try {
      final snapshot = await _draftReference(
        ownerId,
        reviewId,
      ).get(const GetOptions(source: Source.server));
      return snapshot.exists ? _draftFromData(snapshot.data()!) : null;
    } on FirebaseException catch (error) {
      throw _failure(error, 'load your review draft');
    }
  }

  @override
  Future<void> saveDraft({
    required String ownerId,
    required CircleReviewDraft draft,
  }) async {
    try {
      await _draftReference(
        ownerId,
        draft.reviewId,
      ).setOnline(_draftData(draft, FieldValue.serverTimestamp()));
    } on FirebaseException catch (error) {
      throw _failure(error, 'save your review draft');
    }
  }

  @override
  Future<void> clearDraft({
    required String ownerId,
    required String reviewId,
  }) async {
    try {
      await _draftReference(ownerId, reviewId).deleteOnline();
    } on FirebaseException catch (error) {
      throw _failure(error, 'clear your review draft');
    }
  }

  @override
  Future<void> publishDraft({
    required String authorId,
    required CircleReviewDraft draft,
  }) async {
    final reviewReference = _firestore
        .collection('circleReviews')
        .doc(draft.reviewId);
    final draftReference = _draftReference(authorId, draft.reviewId);
    try {
      await _firestore.runTransaction((transaction) async {
        final currentDraftSnapshot = await transaction.get(draftReference);
        final currentDraft = currentDraftSnapshot.exists
            ? _draftFromData(currentDraftSnapshot.data()!)
            : null;
        if (currentDraft != null && !_sameDraft(currentDraft, draft)) {
          throw const ReviewFailure(
            'This review draft changed on another device. Review it before publishing.',
          );
        }
        final existingSnapshot = await transaction.get(reviewReference);
        final existing = existingSnapshot.exists
            ? CircleReview.fromFirestore(
                existingSnapshot.id,
                existingSnapshot.data()!,
              )
            : null;
        if (currentDraft == null && existing == null) {
          throw const ReviewFailure(
            'Readuo could not verify this review draft. Save it and try again.',
          );
        }
        if (currentDraft == null &&
            !_reviewMatches(existing!, authorId, draft)) {
          throw const ReviewFailure(
            'Readuo could not safely retry this review. Open the saved review first.',
          );
        }
        if (existing == null) {
          transaction.set(
            reviewReference,
            _reviewData(
              authorId,
              draft,
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            ),
          );
        } else if (currentDraft != null) {
          transaction.update(
            reviewReference,
            _reviewData(
              authorId,
              draft,
              updatedAt: FieldValue.serverTimestamp(),
            )..remove('authorId'),
          );
        }
        if (currentDraft != null) transaction.delete(draftReference);
      });
    } on ReviewFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _failure(error, 'publish this review');
    }
  }

  @override
  Future<void> deleteReview({
    required String authorId,
    required String reviewId,
  }) async {
    try {
      await _firestore.collection('circleReviews').doc(reviewId).deleteOnline();
    } on FirebaseException catch (error) {
      throw _failure(error, 'delete this review');
    }
  }

  DocumentReference<Map<String, dynamic>> _draftReference(
    String ownerId,
    String reviewId,
  ) => _firestore
      .collection('users')
      .doc(ownerId)
      .collection('reviewDrafts')
      .doc(reviewId);

  Map<String, Object?> _draftData(CircleReviewDraft draft, Object updatedAt) =>
      {
        'reviewId': draft.reviewId,
        'shelfId': draft.shelfId,
        'bookId': draft.bookId,
        'bookCreatedAt': Timestamp.fromDate(draft.bookCreatedAt),
        'title': draft.title,
        'bookAuthor': draft.bookAuthor,
        'coverUrl': draft.coverUrl,
        'text': draft.text,
        'rating': draft.rating,
        'updatedAt': updatedAt,
      };

  Map<String, Object?> _reviewData(
    String authorId,
    CircleReviewDraft draft, {
    Object? createdAt,
    required Object updatedAt,
  }) => {
    'authorId': authorId,
    'shelfId': draft.shelfId,
    'bookId': draft.bookId,
    'bookCreatedAt': Timestamp.fromDate(draft.bookCreatedAt),
    'title': draft.title,
    'bookAuthor': draft.bookAuthor,
    'coverUrl': draft.coverUrl,
    'text': draft.text.trim(),
    'rating': draft.rating,
    if (createdAt != null) 'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  CircleReviewDraft _draftFromData(Map<String, dynamic> data) =>
      CircleReviewDraft(
        reviewId: data['reviewId'] as String? ?? '',
        shelfId: data['shelfId'] as String? ?? '',
        bookId: data['bookId'] as String? ?? '',
        bookCreatedAt: _dateFrom(data['bookCreatedAt']),
        title: data['title'] as String? ?? '',
        bookAuthor: data['bookAuthor'] as String? ?? '',
        coverUrl: data['coverUrl'] as String?,
        text: data['text'] as String? ?? '',
        rating: data['rating'] as int?,
      );

  bool _sameDraft(CircleReviewDraft current, CircleReviewDraft expected) =>
      current.reviewId == expected.reviewId &&
      current.shelfId == expected.shelfId &&
      current.bookId == expected.bookId &&
      current.bookCreatedAt == expected.bookCreatedAt &&
      current.title == expected.title &&
      current.bookAuthor == expected.bookAuthor &&
      current.coverUrl == expected.coverUrl &&
      current.text == expected.text &&
      current.rating == expected.rating;

  bool _reviewMatches(
    CircleReview review,
    String authorId,
    CircleReviewDraft draft,
  ) =>
      review.authorId == authorId &&
      review.id == draft.reviewId &&
      review.shelfId == draft.shelfId &&
      review.bookId == draft.bookId &&
      review.bookCreatedAt == draft.bookCreatedAt &&
      review.title == draft.title &&
      review.bookAuthor == draft.bookAuthor &&
      review.coverUrl == draft.coverUrl &&
      review.text == draft.text.trim() &&
      review.rating == draft.rating;

  ReviewFailure _failure(FirebaseException error, String action) =>
      ReviewFailure(switch (error.code) {
        'permission-denied' =>
          'Readuo could not $action because access changed.',
        'unavailable' =>
          'Readuo cannot $action while offline. Retry when connected.',
        _ => 'Readuo could not $action. Please retry.',
      });
}

class EmptyReviewRepository implements ReviewRepository {
  const EmptyReviewRepository();

  @override
  Stream<List<CircleReview>> watchReviewsForAuthor({
    required String viewerId,
    required String authorId,
  }) => Stream<List<CircleReview>>.multi(
    (controller) => controller.add(const []),
    isBroadcast: true,
  );

  @override
  Stream<CircleReview?> watchReview({
    required String viewerId,
    required String authorId,
    required String bookId,
  }) => Stream<CircleReview?>.multi(
    (controller) => controller.add(null),
    isBroadcast: true,
  );

  @override
  Future<CircleReviewDraft?> loadDraft({
    required String ownerId,
    required String reviewId,
  }) async => null;

  @override
  Future<void> saveDraft({
    required String ownerId,
    required CircleReviewDraft draft,
  }) async {}

  @override
  Future<void> clearDraft({
    required String ownerId,
    required String reviewId,
  }) async {}

  @override
  Future<void> publishDraft({
    required String authorId,
    required CircleReviewDraft draft,
  }) async {}

  @override
  Future<void> deleteReview({
    required String authorId,
    required String reviewId,
  }) async {}
}
