import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/circle/review_repository.dart';
import 'package:readuo/screens/circle_review_composer_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';

void main() {
  const ownerId = 'owner';
  final source = CircleReviewDraft(
    reviewId: circleReviewId(ownerId, '9780143111597'),
    shelfId: 'shelf-one',
    bookId: '9780143111597',
    bookCreatedAt: DateTime.utc(2026, 1, 2),
    title: 'The Left Hand of Darkness',
    bookAuthor: 'Ursula K. Le Guin',
    coverUrl: null,
    text: '',
    rating: null,
  );

  testWidgets('publishes a written review without requiring stars', (
    tester,
  ) async {
    final repository = _ReviewMemory();
    await tester.pumpWidget(_app(repository, source));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('review-text')),
      'A precise and moving review.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _tapVisible(tester, const Key('review-submit'));
    await tester.pumpAndSettle();

    expect(repository.reviews, hasLength(1));
    expect(repository.reviews[source.reviewId]!.rating, isNull);
    expect(
      repository.reviews[source.reviewId]!.text,
      'A precise and moving review.',
    );
    expect(repository.drafts, isEmpty);
  });

  testWidgets('restores a draft and allows removing its rating', (
    tester,
  ) async {
    final repository = _ReviewMemory()
      ..drafts[source.reviewId] = _copyDraft(
        source,
        text: 'Restored words',
        rating: 4,
      );
    await tester.pumpWidget(_app(repository, source));
    await tester.pumpAndSettle();

    expect(find.text('Restored words'), findsOneWidget);
    expect(find.byKey(const Key('review-clear-rating')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-clear-rating')));
    await tester.pump(const Duration(milliseconds: 300));
    await _tapVisible(tester, const Key('review-submit'));
    await tester.pumpAndSettle();

    expect(repository.reviews[source.reviewId]!.rating, isNull);
  });

  testWidgets('preserves text and rating after failure and retries once', (
    tester,
  ) async {
    final repository = _ReviewMemory()..failPublishOnce = true;
    await tester.pumpWidget(_app(repository, source));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('review-text')),
      'Keep this exact review for retry.',
    );
    await tester.tap(find.byKey(const Key('review-rating-5')));
    await tester.pump(const Duration(milliseconds: 300));
    await _tapVisible(tester, const Key('review-submit'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-new-review')), findsOneWidget);
    expect(find.text('Keep this exact review for retry.'), findsOneWidget);
    expect(find.byKey(const Key('review-error')), findsOneWidget);
    await _tapVisible(tester, const Key('review-submit'));
    await tester.pumpAndSettle();

    expect(repository.publishAttempts, 2);
    expect(repository.reviews, hasLength(1));
    expect(repository.reviews[source.reviewId]!.rating, 5);
  });

  testWidgets('ambiguous committed publish retries without a duplicate', (
    tester,
  ) async {
    final repository = _ReviewMemory()..commitThenFailOnce = true;
    await tester.pumpWidget(_app(repository, source));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('review-text')),
      'Exactly once even after interruption.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _tapVisible(tester, const Key('review-submit'));
    await tester.pumpAndSettle();
    expect(repository.reviews, hasLength(1));
    expect(find.byKey(const Key('review-error')), findsOneWidget);

    await _tapVisible(tester, const Key('review-submit'));
    await tester.pumpAndSettle();
    expect(repository.reviews, hasLength(1));
    expect(repository.publishAttempts, 2);
  });

  testWidgets('does not consume a concurrently replaced draft', (tester) async {
    final replacement = _copyDraft(
      source,
      text: 'Newer text from another device',
      rating: 2,
    );
    final repository = _ReviewMemory()..replaceBeforePublish = replacement;
    await tester.pumpWidget(_app(repository, source));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('review-text')),
      'Stale local text',
    );
    await tester.tap(find.byKey(const Key('review-rating-4')));
    await tester.pump(const Duration(milliseconds: 300));
    await _tapVisible(tester, const Key('review-submit'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-error')), findsOneWidget);
    expect(repository.reviews, isEmpty);
    expect(repository.drafts[source.reviewId]!.text, replacement.text);
    expect(repository.drafts[source.reviewId]!.rating, replacement.rating);
  });

  testWidgets('failed discard remains retryable', (tester) async {
    final repository = _ReviewMemory()..failClear = true;
    await tester.pumpWidget(_app(repository, source));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('review-text')), 'Draft text');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-error')), findsOneWidget);
    expect(find.text('Draft text'), findsOneWidget);

    repository.failClear = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-discard')));
    await tester.pumpAndSettle();
    expect(repository.drafts, isEmpty);
  });
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Widget _app(_ReviewMemory repository, CircleReviewDraft source) => MaterialApp(
  theme: ReaduoTheme.modern,
  home: CircleReviewComposerScreen(
    ownerId: 'owner',
    repository: repository,
    source: source,
  ),
);

CircleReviewDraft _copyDraft(
  CircleReviewDraft source, {
  required String text,
  required int? rating,
}) => CircleReviewDraft(
  reviewId: source.reviewId,
  shelfId: source.shelfId,
  bookId: source.bookId,
  bookCreatedAt: source.bookCreatedAt,
  title: source.title,
  bookAuthor: source.bookAuthor,
  coverUrl: source.coverUrl,
  text: text,
  rating: rating,
);

class _ReviewMemory implements ReviewRepository {
  final Map<String, CircleReviewDraft> drafts = {};
  final Map<String, CircleReview> reviews = {};
  bool failPublishOnce = false;
  bool commitThenFailOnce = false;
  bool failClear = false;
  CircleReviewDraft? replaceBeforePublish;
  int publishAttempts = 0;

  @override
  Stream<List<CircleReview>> watchReviewsForAuthor({
    required String viewerId,
    required String authorId,
  }) => Stream.value(
    reviews.values.where((review) => review.authorId == authorId).toList(),
  );

  @override
  Stream<CircleReview?> watchReview({
    required String viewerId,
    required String authorId,
    required String bookId,
  }) => Stream.value(reviews[circleReviewId(authorId, bookId)]);

  @override
  Future<CircleReviewDraft?> loadDraft({
    required String ownerId,
    required String reviewId,
  }) async => drafts[reviewId];

  @override
  Future<void> saveDraft({
    required String ownerId,
    required CircleReviewDraft draft,
  }) async {
    drafts[draft.reviewId] = draft;
  }

  @override
  Future<void> clearDraft({
    required String ownerId,
    required String reviewId,
  }) async {
    if (failClear) throw const ReviewFailure('Discard failed. Retry.');
    drafts.remove(reviewId);
  }

  @override
  Future<void> publishDraft({
    required String authorId,
    required CircleReviewDraft draft,
  }) async {
    publishAttempts++;
    if (failPublishOnce) {
      failPublishOnce = false;
      throw const ReviewFailure('Publish failed. Retry.');
    }
    final replacement = replaceBeforePublish;
    if (replacement != null) {
      drafts[draft.reviewId] = replacement;
      replaceBeforePublish = null;
    }
    final current = drafts[draft.reviewId];
    final existing = reviews[draft.reviewId];
    if (current == null && existing == null) {
      throw const ReviewFailure('Missing draft.');
    }
    if (current != null && !_same(current, draft)) {
      throw const ReviewFailure('This review draft changed on another device.');
    }
    final now = DateTime.now();
    reviews[draft.reviewId] = CircleReview(
      id: draft.reviewId,
      authorId: authorId,
      shelfId: draft.shelfId,
      bookId: draft.bookId,
      bookCreatedAt: draft.bookCreatedAt,
      title: draft.title,
      bookAuthor: draft.bookAuthor,
      coverUrl: draft.coverUrl,
      text: draft.text.trim(),
      rating: draft.rating,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    drafts.remove(draft.reviewId);
    if (commitThenFailOnce) {
      commitThenFailOnce = false;
      throw const ReviewFailure('Publish result was interrupted. Retry.');
    }
  }

  @override
  Future<void> deleteReview({
    required String authorId,
    required String reviewId,
  }) async {
    reviews.remove(reviewId);
  }

  bool _same(CircleReviewDraft first, CircleReviewDraft second) =>
      first.reviewId == second.reviewId &&
      first.shelfId == second.shelfId &&
      first.bookId == second.bookId &&
      first.bookCreatedAt == second.bookCreatedAt &&
      first.title == second.title &&
      first.bookAuthor == second.bookAuthor &&
      first.coverUrl == second.coverUrl &&
      first.text == second.text &&
      first.rating == second.rating;
}
