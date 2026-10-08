import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/auth/auth_service.dart';
import 'package:readuo/circle/circle_repository.dart';
import 'package:readuo/circle/photo_repository.dart';
import 'package:readuo/circle/review_repository.dart';
import 'package:readuo/friends/friend_repository.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/catalogue_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/screens/authenticated_shell.dart';
import 'package:readuo/screens/circle_post_composer_screen.dart';
import 'package:readuo/screens/circle_screen.dart';
import 'package:readuo/screens/friends_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_bottom_navigation.dart';

void main() {
  testWidgets('feed separates compact cards by seven pixels', (tester) async {
    final repositories = _CircleFakes(
      posts: {
        'viewer': [
          for (final id in ['first', 'second'])
            CirclePost(
              id: id,
              authorId: 'viewer',
              text: 'A quiet reading day.',
              attachment: null,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
        ],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    final cards = [
      tester.getRect(find.byKey(const ValueKey('circle-post-first'))),
      tester.getRect(find.byKey(const ValueKey('circle-post-second'))),
    ]..sort((left, right) => left.top.compareTo(right.top));
    expect(cards.last.top - cards.first.bottom, 7);
    final card = tester.widget<Container>(
      find.byKey(const ValueKey('circle-post-first')),
    );
    expect(card.padding, const EdgeInsets.fromLTRB(16, 8, 16, 0));
  });
  testWidgets(
    'all Circle card kinds are edge-to-edge with distinct top borders',
    (tester) async {
      await runCircleEdgeChecks(tester, capture: (_) async {});
    },
  );
  const viewerId = 'viewer';
  const friend = ReaderProfile(
    uid: 'friend',
    displayName: 'Bailey',
    photoUrl: null,
    inviteCode: 'ABC234',
  );
  final shelf = Shelf(
    id: 'shared',
    ownerId: friend.uid,
    name: 'Nightstand',
    visibility: ShelfVisibility.public,
    autoShareActivity: true,
    bookCount: 2,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final firstBook = LibraryBook(
    id: 'first',
    ownerId: friend.uid,
    shelfId: shelf.id,
    title: 'The Left Hand of Darkness',
    author: 'Ursula K. Le Guin',
    isbn: null,
    isOwned: true,
    readingStatus: ReadingStatus.finished,
    coverUrl: null,
    createdAt: DateTime(2026),
    activityGeneration: 'current-generation',
  );
  final secondBook = LibraryBook(
    id: 'second',
    ownerId: friend.uid,
    shelfId: shelf.id,
    title: 'Kindred',
    author: 'Octavia E. Butler',
    isbn: null,
    isOwned: true,
    readingStatus: ReadingStatus.wantToRead,
    coverUrl: null,
    createdAt: DateTime(2026),
    activityGeneration: 'current-generation',
  );

  testWidgets('shows canonical Circle empty state', (tester) async {
    final repositories = _CircleFakes();
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-empty')), findsOneWidget);
    expect(find.text('A little quiet, for now'), findsOneWidget);
    expect(
      find.text('Your friends’ posts and reading updates will appear here.'),
      findsOneWidget,
    );
    expect(find.text('Invite a friend'), findsOneWidget);
    expect(find.text('Visit my library'), findsOneWidget);
  });

  testWidgets('groups scan additions and sorts newest activity first', (
    tester,
  ) async {
    final repositories = _CircleFakes(
      friends: const [friend],
      shelves: {
        friend.uid: [shelf],
      },
      books: {
        '${friend.uid}/${shelf.id}': [firstBook, secondBook],
      },
      activities: {
        '${friend.uid}/${shelf.id}/${firstBook.id}': [
          CircleActivity(
            id: 'finished',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: firstBook.id,
            type: CircleActivityType.finished,
            batchId: null,
            createdAt: DateTime.now(),
          ),
          CircleActivity(
            id: 'added-first',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: firstBook.id,
            type: CircleActivityType.added,
            batchId: 'scan-one',
            createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ],
        '${friend.uid}/${shelf.id}/${secondBook.id}': [
          CircleActivity(
            id: 'added-second',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: secondBook.id,
            type: CircleActivityType.added,
            batchId: 'scan-one',
            createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
          ),
        ],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    expect(find.text('Bailey added 2 books'), findsOneWidget);
    expect(find.text('Bailey finished'), findsOneWidget);
    expect(find.byKey(const Key('circle-thought-composer')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Bailey finished')).dy,
      lessThan(tester.getTopLeft(find.text('Bailey added 2 books')).dy),
    );
  });

  testWidgets('removes activity immediately when friendship is revoked', (
    tester,
  ) async {
    final repositories = _CircleFakes(
      friends: const [friend],
      shelves: {
        friend.uid: [shelf],
      },
      books: {
        '${friend.uid}/${shelf.id}': [firstBook],
      },
      activities: {
        '${friend.uid}/${shelf.id}/${firstBook.id}': [
          CircleActivity(
            id: 'added',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: firstBook.id,
            type: CircleActivityType.added,
            batchId: null,
            createdAt: DateTime.now(),
          ),
        ],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    expect(find.text('Bailey added a book'), findsOneWidget);

    repositories.friendRepository.setFriends(const []);
    await tester.pumpAndSettle();

    expect(find.text('Bailey added a book'), findsNothing);
    expect(find.byKey(const Key('circle-empty')), findsOneWidget);
  });

  testWidgets('clears stale activity when nested access is revoked', (
    tester,
  ) async {
    final repositories = _CircleFakes(
      friends: const [friend],
      shelves: {
        friend.uid: [shelf],
      },
      books: {
        '${friend.uid}/${shelf.id}': [firstBook],
      },
      activities: {
        '${friend.uid}/${shelf.id}/${firstBook.id}': [
          CircleActivity(
            id: 'added',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: firstBook.id,
            type: CircleActivityType.added,
            batchId: null,
            createdAt: DateTime.now(),
          ),
        ],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    expect(find.text('Bailey added a book'), findsOneWidget);

    repositories.circleRepository.revoke(
      '${friend.uid}/${shelf.id}/${firstBook.id}',
    );
    await tester.pumpAndSettle();

    expect(find.text('Bailey added a book'), findsNothing);
    expect(find.byKey(const Key('circle-partial-error')), findsOneWidget);
  });

  testWidgets('shows status activity for a non-owned shared book', (
    tester,
  ) async {
    final savedBook = LibraryBook(
      id: 'saved',
      ownerId: friend.uid,
      shelfId: shelf.id,
      title: 'Parable of the Sower',
      author: 'Octavia E. Butler',
      isbn: null,
      isOwned: false,
      readingStatus: ReadingStatus.reading,
      coverUrl: null,
      createdAt: DateTime(2026),
      activityGeneration: 'saved-generation',
    );
    final repositories = _CircleFakes(
      friends: const [friend],
      shelves: {
        friend.uid: [shelf],
      },
      books: {
        '${friend.uid}/${shelf.id}': [savedBook],
      },
      activities: {
        '${friend.uid}/${shelf.id}/${savedBook.id}/saved-generation': [
          CircleActivity(
            id: 'saved-started',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: savedBook.id,
            type: CircleActivityType.started,
            batchId: null,
            activityGeneration: 'saved-generation',
            createdAt: DateTime.now(),
          ),
        ],
      },
    );

    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    expect(find.text('Bailey started reading'), findsOneWidget);
    expect(find.text('Parable of the Sower'), findsWidgets);
  });

  testWidgets('ignores retained activity listeners after generation changes', (
    tester,
  ) async {
    const nextGeneration = 'next-generation';
    final repositories = _CircleFakes(
      friends: const [friend],
      shelves: {
        friend.uid: [shelf],
      },
      books: {
        '${friend.uid}/${shelf.id}': [firstBook],
      },
      activities: {
        '${friend.uid}/${shelf.id}/${firstBook.id}/current-generation': [
          CircleActivity(
            id: 'old-finished',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: firstBook.id,
            type: CircleActivityType.finished,
            batchId: null,
            activityGeneration: 'current-generation',
            createdAt: DateTime.now(),
          ),
        ],
        '${friend.uid}/${shelf.id}/${firstBook.id}/$nextGeneration': [
          CircleActivity(
            id: 'new-started',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: firstBook.id,
            type: CircleActivityType.started,
            batchId: null,
            activityGeneration: nextGeneration,
            createdAt: DateTime.now(),
          ),
        ],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    expect(find.text('Bailey finished'), findsOneWidget);

    repositories.bookRepository.setBooks(friend.uid, shelf.id, [
      LibraryBook(
        id: firstBook.id,
        ownerId: firstBook.ownerId,
        shelfId: firstBook.shelfId,
        title: firstBook.title,
        author: firstBook.author,
        isbn: firstBook.isbn,
        isOwned: firstBook.isOwned,
        readingStatus: ReadingStatus.reading,
        coverUrl: firstBook.coverUrl,
        createdAt: firstBook.createdAt,
        activityGeneration: nextGeneration,
      ),
    ]);
    await tester.pumpAndSettle();
    repositories.circleRepository
        .emit('${friend.uid}/${shelf.id}/${firstBook.id}/current-generation', [
          CircleActivity(
            id: 'late-old',
            authorId: friend.uid,
            shelfId: shelf.id,
            bookId: firstBook.id,
            type: CircleActivityType.finished,
            batchId: null,
            activityGeneration: 'current-generation',
            createdAt: DateTime.now().add(const Duration(minutes: 1)),
          ),
        ]);
    await tester.pumpAndSettle();

    expect(find.text('Bailey started reading'), findsOneWidget);
    expect(find.text('Bailey finished'), findsNothing);
  });

  testWidgets('shows an error and retries Circle loading', (tester) async {
    final repositories = _CircleFakes();
    repositories.friendRepository.failNext = true;
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(repositories.friendRepository.watchCount, 2);
    expect(find.byKey(const Key('circle-empty')), findsOneWidget);
  });

  testWidgets('persists a post draft and retries publication without loss', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'A thoughtful first post.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      repositories.circleRepository.draft?.text,
      'A thoughtful first post.',
    );

    repositories.circleRepository.failCreate = true;
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-post-error')), findsOneWidget);
    expect(find.text('A thoughtful first post.'), findsOneWidget);

    repositories.circleRepository.failCreate = false;
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-new-post')), findsNothing);
    expect(find.text('A thoughtful first post.'), findsOneWidget);
    expect(repositories.circleRepository.draft, isNull);
  });

  testWidgets('restores and explicitly discards a durable draft', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    repositories.circleRepository.draft = const CirclePostDraft(
      postId: 'restored-post',
      text: 'Saved across navigation',
      attachment: null,
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();

    expect(find.text('Saved across navigation'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard draft?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('circle-discard-draft')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-new-post')), findsNothing);
    expect(repositories.circleRepository.draft, isNull);
  });

  testWidgets('ambiguous publish retry creates exactly one post', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Publish this once.',
    );
    await tester.pump(const Duration(milliseconds: 300));

    repositories.circleRepository.commitThenFailPublishOnce = true;
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-new-post')), findsOneWidget);
    expect(repositories.circleRepository.publishAttempts, 1);
    expect(repositories.circleRepository.posts[viewerId], hasLength(1));
    expect(repositories.circleRepository.draft, isNotNull);

    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();

    expect(repositories.circleRepository.publishAttempts, 2);
    expect(repositories.circleRepository.posts[viewerId], hasLength(1));
    expect(repositories.circleRepository.draft, isNull);
    expect(find.byKey(const Key('circle-new-post')), findsNothing);
  });

  testWidgets('publication never consumes a concurrently replaced draft', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Original device draft.',
    );
    await tester.pump(const Duration(milliseconds: 300));

    repositories.circleRepository.replaceDraftBeforePublish =
        const CirclePostDraft(
          postId: 'newer-device-post',
          text: 'Newer draft from another device.',
          attachment: null,
        );
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-new-post')), findsOneWidget);
    expect(
      find.text(
        'This draft changed on another device. Review it before posting.',
      ),
      findsOneWidget,
    );
    expect(repositories.circleRepository.posts[viewerId], isEmpty);
    expect(repositories.circleRepository.draft?.postId, 'newer-device-post');
  });

  testWidgets('slow autosave finishes before discard clears the draft', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    final saveGate = Completer<void>();
    repositories.circleRepository
      ..saveGate = saveGate
      ..saveStarted = Completer<void>();
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Discard after slow save.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(repositories.circleRepository.saveStarted!.isCompleted, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-discard-draft')));
    await tester.pump();
    expect(find.byKey(const Key('circle-new-post')), findsOneWidget);
    expect(repositories.circleRepository.clearAttempts, 0);

    saveGate.complete();
    await tester.pumpAndSettle();
    expect(repositories.circleRepository.clearAttempts, 1);
    expect(repositories.circleRepository.draft, isNull);
    expect(find.byKey(const Key('circle-new-post')), findsNothing);
  });

  testWidgets('failed discard stays visible and remains retryable', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Do not silently discard.',
    );
    await tester.pump(const Duration(milliseconds: 300));

    repositories.circleRepository.failClear = true;
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-discard-draft')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-new-post')), findsOneWidget);
    expect(find.text('Discard failed. Retry.'), findsOneWidget);
    expect(repositories.circleRepository.draft, isNotNull);

    repositories.circleRepository.failClear = false;
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-discard-draft')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-new-post')), findsNothing);
    expect(repositories.circleRepository.draft, isNull);
  });

  testWidgets('slow autosave is flushed before publication', (tester) async {
    final repositories = _CircleFakes();
    final saveGate = Completer<void>();
    repositories.circleRepository
      ..saveGate = saveGate
      ..saveStarted = Completer<void>();
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Wait for the draft write.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(repositories.circleRepository.saveStarted!.isCompleted, isTrue);

    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pump();
    expect(repositories.circleRepository.publishAttempts, 0);

    saveGate.complete();
    await tester.pumpAndSettle();
    expect(repositories.circleRepository.publishAttempts, 1);
    expect(repositories.circleRepository.posts[viewerId], hasLength(1));
    expect(repositories.circleRepository.draft, isNull);
  });

  testWidgets('queued draft write remains scoped to the disposed owner', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    final saveGate = Completer<void>();
    repositories.circleRepository
      ..saveGate = saveGate
      ..saveStarted = Completer<void>();
    Widget composer(String ownerId) => MaterialApp(
      theme: ReaduoTheme.modern,
      home: CirclePostComposerScreen(
        key: const ValueKey('stable-composer'),
        ownerId: ownerId,
        circleRepository: repositories.circleRepository,
        bookRepository: repositories.bookRepository,
      ),
    );

    await tester.pumpWidget(composer(viewerId));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Belongs to the first reader.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(repositories.circleRepository.saveStarted!.isCompleted, isTrue);

    await tester.pumpWidget(composer('next-reader'));
    await tester.pump();
    saveGate.complete();
    await tester.pumpAndSettle();

    expect(
      repositories.circleRepository.drafts[viewerId]?.text,
      'Belongs to the first reader.',
    );
    expect(repositories.circleRepository.drafts['next-reader'], isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('circle-post-text')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('pending publication locks edits and back navigation', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    final publishGate = Completer<void>();
    repositories.circleRepository.publishGate = publishGate;
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Locked while publishing.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pump();

    expect(repositories.circleRepository.publishAttempts, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('circle-post-text')))
          .readOnly,
      isTrue,
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('circle-submit-post')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('circle-new-post')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('circle-attach-book')))
          .onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pump();
    expect(find.byKey(const Key('circle-new-post')), findsOneWidget);
    expect(find.text('Discard draft?'), findsNothing);

    publishGate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-new-post')), findsNothing);
  });

  testWidgets('draft loading blocks publication until restoration finishes', (
    tester,
  ) async {
    final repositories = _CircleFakes();
    final loadGate = Completer<void>();
    repositories.circleRepository
      ..draft = const CirclePostDraft(
        postId: 'loading-post',
        text: 'Restore before publishing.',
        attachment: null,
      )
      ..loadGate = loadGate
      ..loadStarted = Completer<void>();
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-share-first-post')));
    await tester.pumpAndSettle();

    expect(repositories.circleRepository.loadStarted!.isCompleted, isTrue);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('circle-post-text')))
          .readOnly,
      isTrue,
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('circle-submit-post')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('circle-new-post')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('circle-submit-post')))
          .onPressed,
      isNull,
    );

    loadGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Restore before publishing.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('circle-submit-post')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('attaches an exact own book then edits and deletes own post', (
    tester,
  ) async {
    final ownBook = LibraryBook(
      id: 'own-book',
      ownerId: viewerId,
      shelfId: 'own-shelf',
      title: 'The Dispossessed',
      author: 'Ursula K. Le Guin',
      isbn: null,
      isOwned: true,
      readingStatus: ReadingStatus.finished,
      coverUrl: null,
      createdAt: DateTime(2026),
    );
    final repositories = _CircleFakes(
      books: {
        '$viewerId/library': [ownBook],
      },
      posts: {
        viewerId: [
          CirclePost(
            id: 'own-post',
            authorId: viewerId,
            text: 'Original text',
            attachment: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('circle-post-menu-own-post')));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.byKey(const Key('circle-edit-post-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Edited text',
    );
    await tester.tap(find.byKey(const Key('circle-attach-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-attach-own-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-attached-book')), findsOneWidget);
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();

    expect(find.text('Edited text'), findsOneWidget);
    expect(find.text('The Dispossessed'), findsOneWidget);
    expect(
      repositories.circleRepository.posts[viewerId]!.single.attachment?.bookId,
      ownBook.id,
    );

    await tester.tap(find.byKey(const Key('circle-post-menu-own-post')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-delete-post-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-confirm-delete-post')));
    await tester.pumpAndSettle();

    expect(find.text('Edited text'), findsNothing);
    expect(find.byKey(const Key('circle-empty')), findsOneWidget);
  });

  testWidgets('friend posts never expose author edit or delete controls', (
    tester,
  ) async {
    final repositories = _CircleFakes(
      friends: const [friend],
      posts: {
        friend.uid: [
          CirclePost(
            id: 'friend-post',
            authorId: friend.uid,
            text: 'A friend-only thought',
            attachment: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    expect(find.text('A friend-only thought'), findsOneWidget);
    expect(find.byKey(const Key('circle-post-menu-friend-post')), findsNothing);
    expect(find.byKey(const Key('circle-edit-post-action')), findsNothing);
    expect(find.byKey(const Key('circle-delete-post-action')), findsNothing);

    repositories.friendRepository.setFriends(const []);
    await tester.pumpAndSettle();
    expect(find.text('A friend-only thought'), findsNothing);
  });

  testWidgets('failed author edit and delete remain retryable', (tester) async {
    final repositories = _CircleFakes(
      posts: {
        viewerId: [
          CirclePost(
            id: 'retry-post',
            authorId: viewerId,
            text: 'Keep this post',
            attachment: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    repositories.circleRepository.failUpdate = true;
    await tester.tap(find.byKey(const Key('circle-post-menu-retry-post')));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.byKey(const Key('circle-edit-post-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-post-text')),
      'Retry this edit',
    );
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-edit-post')), findsOneWidget);
    expect(find.byKey(const Key('circle-post-error')), findsOneWidget);
    expect(find.text('Retry this edit'), findsOneWidget);

    repositories.circleRepository.failUpdate = false;
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();
    expect(find.text('Retry this edit'), findsOneWidget);

    repositories.circleRepository.failDelete = true;
    await tester.tap(find.byKey(const Key('circle-post-menu-retry-post')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-delete-post-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-confirm-delete-post')));
    await tester.pumpAndSettle();
    expect(find.text('Retry this edit'), findsOneWidget);
    expect(find.text('Delete failed. Retry.'), findsOneWidget);
  });

  testWidgets('returning-user shell opens on Circle', (tester) async {
    final repositories = _CircleFakes();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: AuthenticatedShell(
          authService: _AuthFake(),
          shelfRepository: repositories.shelfRepository,
          bookRepository: repositories.bookRepository,
          bookLookupRepository: const EmptyBookLookupRepository(),
          catalogueRepository: const EmptyCatalogueRepository(),
          circleRepository: repositories.circleRepository,
          friendRepository: repositories.friendRepository,
          user: const AuthUser(
            uid: viewerId,
            displayName: 'Alex',
            email: null,
            photoUrl: null,
            providerIds: {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-screen')), findsOneWidget);
    final circleIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('nav-circle')),
        matching: find.byType(Icon),
      ),
    );
    expect(circleIcon.color, ReaduoColors.accent);
  });

  testWidgets('shows exact friend reviews and revokes them with friendship', (
    tester,
  ) async {
    final review = CircleReview(
      id: 'friend--first',
      authorId: friend.uid,
      shelfId: shelf.id,
      bookId: firstBook.id,
      bookCreatedAt: firstBook.createdAt!,
      title: firstBook.title,
      bookAuthor: firstBook.author,
      coverUrl: null,
      text: 'Ambitious, humane, and still surprising.',
      rating: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final repositories = _CircleFakes(
      friends: const [friend],
      shelves: {
        friend.uid: [shelf],
      },
      books: {
        '${friend.uid}/${shelf.id}': [firstBook],
      },
      reviews: {
        friend.uid: [review],
      },
    );
    await tester.pumpWidget(repositories.app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('circle-review-friend--first')),
      findsOneWidget,
    );
    expect(
      find.text('Ambitious, humane, and still surprising.'),
      findsOneWidget,
    );
    expect(find.textContaining('reviews'), findsNothing);
    await tester.tap(find.text('Ambitious, humane, and still surprising.'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-review-detail')), findsOneWidget);
    expect(find.text('The Left Hand of Darkness'), findsWidgets);
    expect(find.byKey(const Key('review-detail-edit')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    repositories.friendRepository.setFriends(const []);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('circle-review-friend--first')), findsNothing);
  });
}

Future<void> runCircleEdgeChecks(
  WidgetTester tester, {
  required Future<void> Function(String) capture,
}) async {
  const friend = ReaderProfile(
    uid: 'friend',
    displayName: 'Bailey',
    photoUrl: null,
    inviteCode: 'ABC234',
  );
  final shelf = Shelf(
    id: 'shared',
    ownerId: 'friend',
    name: 'Nightstand',
    visibility: ShelfVisibility.friends,
    autoShareActivity: true,
    bookCount: 2,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final books = [
    for (final id in ['first', 'second'])
      LibraryBook(
        id: id,
        ownerId: 'friend',
        shelfId: 'shared',
        title: id == 'first'
            ? 'The Left Hand of Darkness: A Reader’s Journey'
            : 'Weekend reading',
        author: 'Ursula K. Le Guin',
        isbn: null,
        isOwned: true,
        readingStatus: ReadingStatus.reading,
        coverUrl: null,
        createdAt: DateTime(2026),
        activityGeneration: 'edge-generation',
        description:
            'Sample book description: a journey through unfamiliar places, shared stories, and unexpected friendships.',
        publisher: 'Sample publisher',
        publishedYear: '2024',
      ),
  ];
  for (final kind in [
    'general',
    'attachment',
    'photo',
    'review',
    'activity',
    'started',
    'finished',
    'batch',
  ]) {
    await tester.pumpWidget(const SizedBox());
    final repositories = _CircleFakes(
      friends: [friend],
      shelves: {
        'friend': [shelf],
      },
      books: {'friend/shared': books},
      posts: {
        if (['general', 'attachment', 'photo'].contains(kind))
          'friend': [
            CirclePost(
              id: kind,
              authorId: 'friend',
              text:
                  'A quiet chapter and a good cup of coffee. What are you reading today?',
              attachment: kind == 'attachment'
                  ? const CircleBookAttachment(
                      ownerId: 'friend',
                      shelfId: 'shared',
                      bookId: 'first',
                      title: 'The Left Hand of Darkness: A Reader’s Journey',
                      author: 'Ursula K. Le Guin',
                      coverUrl: null,
                    )
                  : null,
              photoPath: kind == 'photo'
                  ? 'circlePhotos/friend/photo/image.jpg'
                  : null,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
            if (kind == 'general')
              CirclePost(
                id: 'general-next',
                authorId: 'friend',
                text: 'Another chapter, another good conversation.',
                attachment: null,
                createdAt: DateTime(2025),
                updatedAt: DateTime(2025),
              ),
          ],
      },
      reviews: {
        if (kind == 'review')
          'friend': [
            CircleReview(
              id: 'review',
              authorId: 'friend',
              shelfId: 'shared',
              bookId: 'first',
              bookCreatedAt: DateTime(2026),
              title: 'The Left Hand of Darkness: A Reader’s Journey',
              bookAuthor: 'Ursula K. Le Guin',
              coverUrl: null,
              text: 'A thoughtful story worth sharing with friends.',
              rating: 4,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
      },
      activities: {
        if (['activity', 'started', 'finished', 'batch'].contains(kind))
          for (final book in kind == 'batch' ? books : books.take(1))
            'friend/shared/${book.id}': [
              CircleActivity(
                id: 'activity-${book.id}',
                authorId: 'friend',
                shelfId: 'shared',
                bookId: book.id,
                type: kind == 'started'
                    ? CircleActivityType.started
                    : kind == 'finished'
                    ? CircleActivityType.finished
                    : CircleActivityType.added,
                batchId: kind == 'batch' ? 'scan-batch' : null,
                createdAt: DateTime(2026),
              ),
            ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: Scaffold(
          bottomNavigationBar: ReaduoBottomNavigation(
            active: ReaduoNavDestination.circle,
            onCircle: () {},
            onLibrary: () {},
            onFriends: () {},
            onProfile: () {},
          ),
          body:
              (repositories.app(photoRepository: _EdgePhotoRepository())
                      as MaterialApp)
                  .home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          (key.value == 'circle-post-$kind' ||
              key.value == 'circle-review-review' ||
              key.value.startsWith('circle-activity-activity-'));
    });
    expect(card, findsOneWidget, reason: kind);
    expect(tester.getTopLeft(card).dx, 0, reason: kind);
    expect(
      tester.getSize(card).width,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
      reason: kind,
    );
    final widget = tester.widget(card);
    final border = widget is Container
        ? (widget.decoration! as BoxDecoration).border! as Border
        : (widget as Material).shape! as Border;
    expect(border.top.width, 3);
    expect(border.bottom.width, 1);
    if (['attachment', 'review', 'started', 'finished'].contains(kind)) {
      final coverSize = ['attachment', 'review'].contains(kind)
          ? const Size(72, 108)
          : const Size(116, 174);
      final cover = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == coverSize.width &&
              widget.height == coverSize.height,
        ),
      );
      expect(cover, findsOneWidget, reason: kind);
      expect(tester.getSize(cover), coverSize, reason: kind);
      if (kind == 'review') {
        expect(
          tester
              .getTopLeft(
                find.text('A thoughtful story worth sharing with friends.'),
              )
              .dx,
          16.0,
        );
      }
    }
    if (kind == 'batch') {
      final cover = find
          .descendant(
            of: card,
            matching: find.byWidgetPredicate(
              (widget) => widget is SizedBox && widget.width == 164,
            ),
          )
          .first;
      expect(tester.getSize(cover), const Size(164, 252), reason: kind);
    }
    for (final action in ['like', 'comments']) {
      final button = find.byKey(ValueKey('circle-$action-$kind'));
      if (button.evaluate().isNotEmpty) {
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      }
    }
    await capture('circle-edge-$kind');
    final menuKey = ['general', 'attachment', 'photo'].contains(kind)
        ? 'circle-report-post-$kind'
        : kind == 'review'
        ? 'circle-report-review-$kind'
        : 'circle-activity-menu-activity-first';
    await tester.tap(find.byKey(Key(menuKey)));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Report a concern'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    if (kind == 'review') await capture('circle-report-menu');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    if (kind == 'started') {
      await Scrollable.ensureVisible(
        tester.element(find.text('Book details ›')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book details ›'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('friend-book-see-more')), findsOneWidget);
      expect(find.byKey(const Key('book-description')), findsOneWidget);
      await capture('friend-book-rich');
      await tester.ensureVisible(find.byKey(const Key('friend-book-see-more')));
      await tester.tap(find.byKey(const Key('friend-book-see-more')));
      await tester.pumpAndSettle();
      expect(find.byType(FriendProfileScreen), findsOneWidget);
      await capture('friend-see-more');
    }
    if (kind == 'general') {
      expect(
        tester
                .getTopLeft(
                  find.byKey(const ValueKey('circle-post-general-next')),
                )
                .dy -
            tester.getBottomLeft(card).dy,
        7,
      );
    }
    if (kind == 'batch') {
      final strip = find.descendant(of: card, matching: find.byType(ListView));
      await tester.drag(strip, const Offset(-150, 0));
      await tester.pumpAndSettle();
      await capture('circle-batch-scrolled');
    }
    if (kind == 'review' || kind == 'attachment') {
      await tester.ensureVisible(find.byKey(ValueKey('circle-comments-$kind')));
      await tester.pumpAndSettle();
      await capture('circle-actions-$kind');
    }
    expect(tester.takeException(), isNull, reason: kind);
  }
}

class _EdgePhotoRepository extends EmptyCirclePhotoRepository {
  @override
  Future<Uint8List?> load(String storagePath) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
}

class _CircleFakes {
  _CircleFakes({
    List<ReaderProfile> friends = const [],
    Map<String, List<Shelf>> shelves = const {},
    Map<String, List<LibraryBook>> books = const {},
    Map<String, List<CircleActivity>> activities = const {},
    Map<String, List<CirclePost>> posts = const {},
    Map<String, List<CircleReview>> reviews = const {},
  }) : friendRepository = _FriendFake(friends),
       shelfRepository = _ShelfFake(shelves),
       bookRepository = _BookFake(books),
       circleRepository = _CircleFake(activities, posts),
       reviewRepository = _ReviewFake(reviews);

  final _FriendFake friendRepository;
  final _ShelfFake shelfRepository;
  final _BookFake bookRepository;
  final _CircleFake circleRepository;
  final _ReviewFake reviewRepository;

  Widget app({
    CirclePhotoRepository photoRepository = const EmptyCirclePhotoRepository(),
  }) => MaterialApp(
    theme: ReaduoTheme.modern,
    home: CircleScreen(
      viewerId: 'viewer',
      friendRepository: friendRepository,
      shelfRepository: shelfRepository,
      bookRepository: bookRepository,
      circleRepository: circleRepository,
      reviewRepository: reviewRepository,
      photoRepository: photoRepository,
      onInviteFriend: () {},
      onOpenLibrary: () {},
    ),
  );
}

class _ReviewFake implements ReviewRepository {
  _ReviewFake(Map<String, List<CircleReview>> reviews)
    : replays = reviews.map((key, value) => MapEntry(key, _Replay(value)));

  final Map<String, _Replay<List<CircleReview>>> replays;

  @override
  Stream<List<CircleReview>> watchReviewsForAuthor({
    required String viewerId,
    required String authorId,
  }) => replays.putIfAbsent(authorId, () => _Replay(const [])).watch();

  @override
  Stream<CircleReview?> watchReview({
    required String viewerId,
    required String authorId,
    required String bookId,
  }) async* {
    await for (final reviews
        in replays.putIfAbsent(authorId, () => _Replay(const [])).watch()) {
      yield reviews.cast<CircleReview?>().firstWhere(
        (review) => review!.bookId == bookId,
        orElse: () => null,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Replay<T> {
  _Replay(this.value);

  T value;
  final controller = StreamController<T>.broadcast();

  Stream<T> watch() async* {
    yield value;
    yield* controller.stream;
  }

  void add(T next) {
    value = next;
    controller.add(next);
  }

  void addError(Object error) => controller.addError(error);
}

class _FriendFake implements FriendRepository {
  _FriendFake(List<ReaderProfile> friends) : replay = _Replay(friends);

  final _Replay<List<ReaderProfile>> replay;
  bool failNext = false;
  int watchCount = 0;

  void setFriends(List<ReaderProfile> friends) => replay.add(friends);

  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) async* {
    watchCount += 1;
    if (failNext) {
      failNext = false;
      throw const FriendFailure('offline');
    }
    yield* replay.watch();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShelfFake implements ShelfRepository {
  _ShelfFake(Map<String, List<Shelf>> values)
    : replays = values.map((key, value) => MapEntry(key, _Replay(value)));

  final Map<String, _Replay<List<Shelf>>> replays;

  @override
  Stream<Shelf?> watchSharedShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) => watchSharedShelves(
    viewerId: viewerId,
    ownerId: ownerId,
  ).map((shelves) => shelves.where((shelf) => shelf.id == shelfId).firstOrNull);

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) =>
      replays.putIfAbsent(ownerId, () => _Replay(const [])).watch();

  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) => replays.putIfAbsent(ownerId, () => _Replay(const [])).watch();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BookFake implements BookRepository {
  _BookFake(Map<String, List<LibraryBook>> values)
    : replays = values.map((key, value) => MapEntry(key, _Replay(value)));

  final Map<String, _Replay<List<LibraryBook>>> replays;

  void setBooks(String ownerId, String shelfId, List<LibraryBook> books) =>
      replays
          .putIfAbsent('$ownerId/$shelfId', () => _Replay(const []))
          .add(books);

  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) =>
      replays.putIfAbsent('$ownerId/$shelfId', () => _Replay(const [])).watch();

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) =>
      replays.putIfAbsent('$ownerId/library', () => _Replay(const [])).watch();

  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) => replays
      .putIfAbsent('$ownerId/$shelfId', () => _Replay(const []))
      .watch()
      .map((books) => books.where((book) => book.id == bookId).firstOrNull);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CircleFake implements CircleRepository {
  static const _defaultOwnerId = 'viewer';

  _CircleFake(
    Map<String, List<CircleActivity>> values,
    Map<String, List<CirclePost>> posts,
  ) : replays = values.map((key, value) => MapEntry(key, _Replay(value))),
      postReplays = posts.map((key, value) => MapEntry(key, _Replay(value)));

  final Map<String, _Replay<List<CircleActivity>>> replays;
  final Map<String, _Replay<List<CirclePost>>> postReplays;
  final Map<String, CirclePostDraft> drafts = {};
  bool failCreate = false;
  bool failClear = false;
  bool failUpdate = false;
  bool failDelete = false;
  bool commitThenFailPublishOnce = false;
  CirclePostDraft? replaceDraftBeforePublish;
  Completer<void>? saveGate;
  Completer<void>? saveStarted;
  Completer<void>? loadGate;
  Completer<void>? loadStarted;
  Completer<void>? publishGate;
  int publishAttempts = 0;
  int clearAttempts = 0;
  int _postSequence = 0;

  CirclePostDraft? get draft => drafts[_defaultOwnerId];

  set draft(CirclePostDraft? value) {
    if (value == null) {
      drafts.remove(_defaultOwnerId);
    } else {
      drafts[_defaultOwnerId] = value;
    }
  }

  Map<String, List<CirclePost>> get posts =>
      postReplays.map((key, replay) => MapEntry(key, replay.value));

  void revoke(String key) =>
      replays[key]!.addError(const CircleFailure('revoked'));

  void emit(String key, List<CircleActivity> activities) =>
      replays[key]!.add(activities);

  @override
  Stream<List<CircleActivity>> watchBookActivities({
    required String viewerId,
    required String ownerId,
    required String shelfId,
    required String bookId,
    required String activityGeneration,
    required bool includeAdded,
  }) {
    final baseKey = '$ownerId/$shelfId/$bookId';
    final generationKey = '$baseKey/$activityGeneration';
    return (replays[generationKey] ??
            replays.putIfAbsent(baseKey, () => _Replay(const [])))
        .watch();
  }

  @override
  Stream<List<CirclePost>> watchPostsForAuthor({
    required String viewerId,
    required String authorId,
  }) => postReplays.putIfAbsent(authorId, () => _Replay(const [])).watch();

  @override
  Future<CirclePostDraft?> loadPostDraft(String ownerId) async {
    final started = loadStarted;
    if (started != null && !started.isCompleted) started.complete();
    await loadGate?.future;
    return drafts[ownerId];
  }

  @override
  Future<void> savePostDraft({
    required String ownerId,
    required CirclePostDraft draft,
  }) async {
    final started = saveStarted;
    if (started != null && !started.isCompleted) started.complete();
    await saveGate?.future;
    drafts[ownerId] = draft;
  }

  @override
  Future<void> clearPostDraft(String ownerId) async {
    clearAttempts++;
    if (failClear) throw const CircleFailure('Discard failed. Retry.');
    drafts.remove(ownerId);
  }

  @override
  String newPostId() => 'created-post-${_postSequence++}';

  @override
  Future<void> publishPostDraft({
    required String authorId,
    required CirclePostDraft draft,
  }) async {
    publishAttempts++;
    await publishGate?.future;
    if (failCreate) throw const CircleFailure('Publish failed. Retry.');
    final replacement = replaceDraftBeforePublish;
    if (replacement != null) {
      drafts[authorId] = replacement;
      replaceDraftBeforePublish = null;
    }
    final currentDraft = drafts[authorId];
    if (currentDraft != null &&
        (currentDraft.postId != draft.postId ||
            currentDraft.text != draft.text ||
            currentDraft.attachment?.bookId != draft.attachment?.bookId)) {
      throw const CircleFailure(
        'This draft changed on another device. Review it before posting.',
      );
    }
    final post = CirclePost(
      id: draft.postId,
      authorId: authorId,
      text: draft.text.trim(),
      attachment: draft.attachment,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final replay = postReplays.putIfAbsent(authorId, () => _Replay(const []));
    replay.add([
      post,
      ...replay.value.where((existing) => existing.id != draft.postId),
    ]);
    if (commitThenFailPublishOnce) {
      commitThenFailPublishOnce = false;
      throw const CircleFailure('Publish result was interrupted. Retry.');
    }
    drafts.remove(authorId);
  }

  @override
  Future<void> updatePost({
    required String authorId,
    required String postId,
    required String text,
    required CircleBookAttachment? attachment,
    required String? photoPath,
  }) async {
    if (failUpdate) throw const CircleFailure('Update failed. Retry.');
    final replay = postReplays[authorId]!;
    replay.add([
      for (final post in replay.value)
        if (post.id == postId)
          CirclePost(
            id: post.id,
            authorId: post.authorId,
            text: text,
            attachment: attachment,
            photoPath: photoPath,
            createdAt: post.createdAt,
            updatedAt: DateTime.now(),
          )
        else
          post,
    ]);
  }

  @override
  Future<void> deletePost({
    required String authorId,
    required String postId,
  }) async {
    if (failDelete) throw const CircleFailure('Delete failed. Retry.');
    final replay = postReplays[authorId]!;
    replay.add(replay.value.where((post) => post.id != postId).toList());
  }
}

class _AuthFake implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
