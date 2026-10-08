import '../widgets/readuo_image_cache.dart';
import '../widgets/generated_book_cover.dart';
import '../widgets/circle_book_metadata.dart';
import '../widgets/book_information.dart';
import 'book_details_screen.dart';
import '../widgets/book_cover_image.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../circle/circle_repository.dart';
import '../circle/engagement_repository.dart';
import '../circle/photo_repository.dart';
import '../circle/cached_photo_repository.dart';
import '../circle/review_repository.dart';
import '../friends/friend_repository.dart';
import '../features/feature_services.dart';
import '../moderation/moderation_repository.dart';
import '../library/book.dart';
import '../library/book_repository.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';
import '../profile/profile_widgets.dart';
import '../widgets/circle_engagement.dart';
import '../widgets/circle_photo.dart';
import '../widgets/readuo_tab_header.dart';
import '../notifications/notification.dart';
import '../notifications/notification_presentation.dart';
import 'circle_post_composer_screen.dart';
import 'circle_review_composer_screen.dart';
import 'friends_screen.dart';

class CircleScreen extends StatefulWidget {
  const CircleScreen({
    required this.viewerId,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.circleRepository,
    this.reviewRepository = const EmptyReviewRepository(),
    this.engagementRepository = const EmptyCircleEngagementRepository(),
    this.photoRepository = const EmptyCirclePhotoRepository(),
    required this.onInviteFriend,
    required this.onOpenLibrary,
    this.viewerDisplayName = 'You',
    this.viewerPhotoUrl,
    this.onNotifications,
    super.key,
  });

  final String viewerId;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final CircleRepository circleRepository;
  final ReviewRepository reviewRepository;
  final CircleEngagementRepository engagementRepository;
  final CirclePhotoRepository photoRepository;
  final VoidCallback onInviteFriend;
  final VoidCallback onOpenLibrary;
  final String viewerDisplayName;
  final String? viewerPhotoUrl;
  final VoidCallback? onNotifications;

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> {
  late var _photoCache = CachedCirclePhotoRepository(widget.photoRepository);
  StreamSubscription<List<ReaderProfile>>? _friendsSubscription;
  final Map<String, StreamSubscription<List<Shelf>>> _shelfSubscriptions = {};
  final Map<String, StreamSubscription<List<LibraryBook>>> _bookSubscriptions =
      {};
  final Map<String, StreamSubscription<List<CircleActivity>>>
  _activitySubscriptions = {};
  final Map<String, StreamSubscription<List<CirclePost>>> _postSubscriptions =
      {};
  final Map<String, StreamSubscription<dynamic>> _reviewSubscriptions = {};
  final Map<String, String> _activityGenerations = {};
  final Map<String, ReaderProfile> _friends = {};
  final Map<String, Shelf> _shelves = {};
  final Map<String, LibraryBook> _books = {};
  final Map<String, List<CircleActivity>> _activities = {};
  final Map<String, List<CirclePost>> _posts = {};
  final Map<String, List<CircleReview>> _reviews = {};
  final Set<String> _pending = {};
  Completer<void>? _refreshCompleter;
  Object? _error;
  bool _hasRootError = false;
  bool _friendsLoaded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant CircleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerId != widget.viewerId ||
        oldWidget.friendRepository != widget.friendRepository ||
        oldWidget.shelfRepository != widget.shelfRepository ||
        oldWidget.bookRepository != widget.bookRepository ||
        oldWidget.circleRepository != widget.circleRepository ||
        oldWidget.reviewRepository != widget.reviewRepository ||
        oldWidget.photoRepository != widget.photoRepository) {
      _restart();
    }
  }

  @override
  void dispose() {
    _photoCache.clear();
    _cancelAll();
    super.dispose();
  }

  void _start() {
    final generation = ++_generation;
    _subscribePosts(generation, widget.viewerId);
    _subscribeReviews(generation, widget.viewerId);
    _friendsSubscription = widget.friendRepository
        .watchFriends(widget.viewerId)
        .listen(
          (friends) => _onFriends(generation, friends),
          onError: (Object error) => _onError(generation, error),
        );
  }

  Future<void> _restart() async {
    _photoCache.clear();
    _photoCache = CachedCirclePhotoRepository(widget.photoRepository);
    final cancellation = _cancelAll();
    if (!mounted) return;
    setState(() {
      _friends.clear();
      _shelves.clear();
      _books.clear();
      _activities.clear();
      _posts.clear();
      _reviews.clear();
      _activityGenerations.clear();
      _pending.clear();
      _error = null;
      _hasRootError = false;
      _friendsLoaded = false;
    });
    _start();
    await cancellation;
  }

  Future<void> _refresh() async {
    final previousRefresh = _refreshCompleter;
    if (previousRefresh != null && !previousRefresh.isCompleted) {
      previousRefresh.complete();
    }
    final completer = Completer<void>();
    _refreshCompleter = completer;
    await _restart();
    if (!_isLoading && !completer.isCompleted) completer.complete();
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
  }

  Future<void> _cancelAll() async {
    _generation += 1;
    final friendsSubscription = _friendsSubscription;
    final subscriptions = [
      ..._shelfSubscriptions.values,
      ..._bookSubscriptions.values,
      ..._activitySubscriptions.values,
      ..._postSubscriptions.values,
      ..._reviewSubscriptions.values,
    ];
    _friendsSubscription = null;
    _shelfSubscriptions.clear();
    _bookSubscriptions.clear();
    _activitySubscriptions.clear();
    _postSubscriptions.clear();
    _reviewSubscriptions.clear();
    _activityGenerations.clear();
    await Future.wait([
      if (friendsSubscription != null) friendsSubscription.cancel(),
      ...subscriptions.map((subscription) => subscription.cancel()),
    ]);
  }

  void _onFriends(int generation, List<ReaderProfile> friends) {
    if (!mounted || generation != _generation) return;
    final nextIds = friends.map((friend) => friend.uid).toSet();
    for (final removedId in _friends.keys.toSet().difference(nextIds)) {
      _removeFriend(removedId);
    }
    _friends
      ..clear()
      ..addEntries(friends.map((friend) => MapEntry(friend.uid, friend)));
    for (final friend in friends) {
      _subscribePosts(generation, friend.uid);
      if (_shelfSubscriptions.containsKey(friend.uid)) continue;
      final pendingKey = 'shelves:${friend.uid}';
      _pending.add(pendingKey);
      _shelfSubscriptions[friend.uid] = widget.shelfRepository
          .watchSharedShelves(viewerId: widget.viewerId, ownerId: friend.uid)
          .listen(
            (shelves) => _onShelves(generation, friend.uid, shelves),
            onError: (Object error) => _onError(generation, error, pendingKey),
          );
    }
    _friendsLoaded = true;
    _notify();
  }

  void _subscribePosts(int generation, String authorId) {
    if (_postSubscriptions.containsKey(authorId)) return;
    final pendingKey = 'posts:$authorId';
    _pending.add(pendingKey);
    _postSubscriptions[authorId] = widget.circleRepository
        .watchPostsForAuthor(viewerId: widget.viewerId, authorId: authorId)
        .listen((posts) {
          if (!mounted || generation != _generation) return;
          _pending.remove(pendingKey);
          _posts[authorId] = posts;
          _notify();
        }, onError: (Object error) => _onError(generation, error, pendingKey));
  }

  void _subscribeReviews(int generation, String authorId) {
    if (_reviewSubscriptions.containsKey(authorId)) return;
    final pendingKey = 'reviews:$authorId';
    _pending.add(pendingKey);
    _reviewSubscriptions[authorId] = widget.reviewRepository
        .watchReviewsForAuthor(viewerId: widget.viewerId, authorId: authorId)
        .listen((reviews) {
          if (!mounted || generation != _generation) return;
          _pending.remove(pendingKey);
          _reviews[authorId] = reviews;
          _notify();
        }, onError: (Object error) => _onError(generation, error, pendingKey));
  }

  void _onShelves(int generation, String friendId, List<Shelf> shelves) {
    if (!mounted || generation != _generation) return;
    final pendingKey = 'shelves:$friendId';
    _pending.remove(pendingKey);
    final prefix = '$friendId/';
    final nextKeys = shelves.map((shelf) => '$prefix${shelf.id}').toSet();
    final oldKeys = _shelves.keys
        .where((key) => key.startsWith(prefix))
        .toSet();
    for (final removedKey in oldKeys.difference(nextKeys)) {
      _removeShelf(removedKey);
    }
    for (final shelf in shelves) {
      final shelfKey = '$friendId/${shelf.id}';
      _shelves[shelfKey] = shelf;
      if (_bookSubscriptions.containsKey(shelfKey)) continue;
      final bookPendingKey = 'books:$shelfKey';
      _pending.add(bookPendingKey);
      _bookSubscriptions[shelfKey] = widget.bookRepository
          .watchSharedBooks(
            viewerId: widget.viewerId,
            ownerId: friendId,
            shelfId: shelf.id,
          )
          .listen(
            (books) => _onBooks(generation, shelfKey, books),
            onError: (Object error) =>
                _onError(generation, error, bookPendingKey),
          );
    }
    _notify();
  }

  void _onBooks(int generation, String shelfKey, List<LibraryBook> books) {
    if (!mounted || generation != _generation) return;
    final pendingKey = 'books:$shelfKey';
    _pending.remove(pendingKey);
    final prefix = '$shelfKey/';
    final nextKeys = books.map((book) => '$prefix${book.id}').toSet();
    final oldKeys = _books.keys.where((key) => key.startsWith(prefix)).toSet();
    for (final removedKey in oldKeys.difference(nextKeys)) {
      _removeBook(removedKey);
    }
    final friendId = shelfKey.substring(0, shelfKey.indexOf('/'));
    final shelfId = shelfKey.substring(shelfKey.indexOf('/') + 1);
    for (final book in books) {
      final bookKey = '$shelfKey/${book.id}';
      _books[bookKey] = book;
      _subscribeBookReview(generation, friendId, bookKey, book.id);
      final activityGeneration = book.activityGeneration;
      if (activityGeneration == null || activityGeneration.isEmpty) {
        _removeActivitySubscription(bookKey);
        continue;
      }
      final activitySubscriptionKey =
          '$activityGeneration/${book.isOwned ? 'owned' : 'saved'}';
      if (_activityGenerations[bookKey] == activitySubscriptionKey &&
          _activitySubscriptions.containsKey(bookKey)) {
        continue;
      }
      _removeActivitySubscription(bookKey);
      final activityPendingKey = 'activities:$bookKey';
      _pending.add(activityPendingKey);
      _activityGenerations[bookKey] = activitySubscriptionKey;
      _activitySubscriptions[bookKey] = widget.circleRepository
          .watchBookActivities(
            viewerId: widget.viewerId,
            ownerId: friendId,
            shelfId: shelfId,
            bookId: book.id,
            activityGeneration: activityGeneration,
            includeAdded: book.isOwned,
          )
          .listen(
            (activities) => _onActivities(
              generation,
              bookKey,
              activitySubscriptionKey,
              activities,
            ),
            onError: (Object error) => _onActivityError(
              generation,
              bookKey,
              activitySubscriptionKey,
              error,
              activityPendingKey,
            ),
          );
    }
    _notify();
  }

  void _onActivities(
    int generation,
    String bookKey,
    String activityGeneration,
    List<CircleActivity> activities,
  ) {
    if (!mounted ||
        generation != _generation ||
        _activityGenerations[bookKey] != activityGeneration) {
      return;
    }
    _pending.remove('activities:$bookKey');
    _activities[bookKey] = activities;
    _notify();
  }

  void _subscribeBookReview(
    int generation,
    String authorId,
    String bookKey,
    String bookId,
  ) {
    final subscriptionKey = 'book:$bookKey';
    if (_reviewSubscriptions.containsKey(subscriptionKey)) return;
    final pendingKey = 'bookReview:$bookKey';
    _pending.add(pendingKey);
    _reviewSubscriptions[subscriptionKey] = widget.reviewRepository
        .watchReview(
          viewerId: widget.viewerId,
          authorId: authorId,
          bookId: bookId,
        )
        .listen((review) {
          if (!mounted || generation != _generation) return;
          _pending.remove(pendingKey);
          _reviews[subscriptionKey] = review == null ? const [] : [review];
          _notify();
        }, onError: (Object error) => _onError(generation, error, pendingKey));
  }

  void _onActivityError(
    int generation,
    String bookKey,
    String activityGeneration,
    Object error,
    String pendingKey,
  ) {
    if (_activityGenerations[bookKey] != activityGeneration) return;
    _onError(generation, error, pendingKey);
  }

  void _onError(int generation, Object error, [String? pendingKey]) {
    if (!mounted || generation != _generation) return;
    if (pendingKey != null) {
      _pending.remove(pendingKey);
      if (pendingKey.startsWith('activities:')) {
        final bookKey = pendingKey.substring('activities:'.length);
        _activities.remove(bookKey);
        _activitySubscriptions.remove(bookKey);
        _activityGenerations.remove(bookKey);
      } else if (pendingKey.startsWith('books:')) {
        final shelfKey = pendingKey.substring('books:'.length);
        _bookSubscriptions.remove(shelfKey);
        for (final bookKey
            in _books.keys
                .where((key) => key.startsWith('$shelfKey/'))
                .toList()) {
          _removeBook(bookKey);
        }
      } else if (pendingKey.startsWith('shelves:')) {
        final friendId = pendingKey.substring('shelves:'.length);
        _shelfSubscriptions.remove(friendId);
        for (final shelfKey
            in _shelves.keys
                .where((key) => key.startsWith('$friendId/'))
                .toList()) {
          _removeShelf(shelfKey);
        }
      } else if (pendingKey.startsWith('posts:')) {
        final authorId = pendingKey.substring('posts:'.length);
        _posts.remove(authorId);
        _postSubscriptions.remove(authorId)?.cancel();
      } else if (pendingKey.startsWith('reviews:')) {
        final authorId = pendingKey.substring('reviews:'.length);
        _reviews.remove(authorId);
        _reviewSubscriptions.remove(authorId)?.cancel();
      } else if (pendingKey.startsWith('bookReview:')) {
        final bookKey = pendingKey.substring('bookReview:'.length);
        final subscriptionKey = 'book:$bookKey';
        _reviews.remove(subscriptionKey);
        _reviewSubscriptions.remove(subscriptionKey)?.cancel();
      }
    } else {
      _hasRootError = true;
    }
    _error = error;
    _notify();
  }

  void _removeFriend(String friendId) {
    _friends.remove(friendId);
    _posts.remove(friendId);
    _postSubscriptions.remove(friendId)?.cancel();
    _pending.remove('posts:$friendId');
    _shelfSubscriptions.remove(friendId)?.cancel();
    _pending.remove('shelves:$friendId');
    for (final key
        in _shelves.keys
            .where((key) => key.startsWith('$friendId/'))
            .toList()) {
      _removeShelf(key);
    }
  }

  void _removeShelf(String shelfKey) {
    _shelves.remove(shelfKey);
    _bookSubscriptions.remove(shelfKey)?.cancel();
    _pending.remove('books:$shelfKey');
    for (final key
        in _books.keys.where((key) => key.startsWith('$shelfKey/')).toList()) {
      _removeBook(key);
    }
  }

  void _removeBook(String bookKey) {
    _books.remove(bookKey);
    _removeActivitySubscription(bookKey);
    final reviewKey = 'book:$bookKey';
    _reviews.remove(reviewKey);
    _reviewSubscriptions.remove(reviewKey)?.cancel();
    _pending.remove('bookReview:$bookKey');
  }

  void _removeActivitySubscription(String bookKey) {
    _activities.remove(bookKey);
    _activitySubscriptions.remove(bookKey)?.cancel();
    _activityGenerations.remove(bookKey);
    _pending.remove('activities:$bookKey');
  }

  bool get _isLoading => !_friendsLoaded || _pending.isNotEmpty;

  void _notify() {
    if (!mounted) return;
    _photoCache.retainPaths(
      _hasRootError
          ? {}
          : {
              for (final posts in _posts.values)
                for (final post in posts)
                  if (post.photoPath != null) post.photoPath!,
            },
    );
    setState(() {});
    if (!_isLoading && !(_refreshCompleter?.isCompleted ?? true)) {
      _refreshCompleter!.complete();
    }
  }

  List<_CircleFeedItem> get _feedItems {
    final grouped = <String, List<_CircleFeedEntry>>{};
    final singles = <_CircleFeedEntry>[];
    for (final activityEntry in _activities.entries) {
      final book = _books[activityEntry.key];
      if (book == null) continue;
      final shelfKey = activityEntry.key.substring(
        0,
        activityEntry.key.lastIndexOf('/'),
      );
      final shelf = _shelves[shelfKey];
      final friendId = shelfKey.substring(0, shelfKey.indexOf('/'));
      final friend = _friends[friendId];
      if (shelf == null || friend == null) continue;
      for (final activity in activityEntry.value) {
        final entry = _CircleFeedEntry(
          friend: friend,
          shelf: shelf,
          book: book,
          activity: activity,
        );
        final batchId = activity.batchId;
        if (activity.type == CircleActivityType.added && batchId != null) {
          grouped
              .putIfAbsent('$friendId/${shelf.id}/$batchId', () => [])
              .add(entry);
        } else {
          singles.add(entry);
        }
      }
    }
    final items = <_CircleFeedItem>[
      ...singles.map((entry) => _CircleFeedItem([entry])),
      ...grouped.values.map(_CircleFeedItem.new),
    ];
    items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return items;
  }

  List<_CircleTimelineItem> get _timelineItems {
    final items = <_CircleTimelineItem>[
      ..._feedItems.map(_CircleTimelineItem.activity),
      for (final posts in _posts.values) ...posts.map(_CircleTimelineItem.post),
      for (final reviews in _reviews.values)
        ...reviews.map(_CircleTimelineItem.review),
    ];
    items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return items;
  }

  void _openBook(_CircleFeedEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (_) => FriendBookSheet(
        viewerId: widget.viewerId,
        friend: entry.friend,
        sourceShelf: entry.shelf,
        book: entry.book,
        friendRepository: widget.friendRepository,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
        ownedOnly: false,
      ),
    );
  }

  Future<void> _openAttachedBook(LibraryBook book) async {
    if (book.ownerId == widget.viewerId) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BookDetailsScreen(
            ownerId: book.ownerId,
            shelfId: book.shelfId,
            bookId: book.id,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            reviewRepository: widget.reviewRepository,
            showBottomNavigation: false,
          ),
        ),
      );
      return;
    }
    final friend = _friends[book.ownerId];
    if (friend == null) return;
    try {
      final shelf = await widget.shelfRepository
          .watchSharedShelf(
            viewerId: widget.viewerId,
            ownerId: book.ownerId,
            shelfId: book.shelfId,
          )
          .first;
      if (!mounted || shelf == null || !_friends.containsKey(book.ownerId))
        return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FriendBookSheet(
          viewerId: widget.viewerId,
          friend: friend,
          sourceShelf: shelf,
          book: book,
          friendRepository: widget.friendRepository,
          shelfRepository: widget.shelfRepository,
          bookRepository: widget.bookRepository,
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This book is no longer available.')),
        );
    }
  }

  Future<void> _openComposer([CirclePost? post]) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => CirclePostComposerScreen(
            ownerId: widget.viewerId,
            displayName: widget.viewerDisplayName,
            photoUrl: widget.viewerPhotoUrl,
            circleRepository: widget.circleRepository,
            bookRepository: widget.bookRepository,
            photoRepository: widget.photoRepository,
            post: post,
          ),
        ),
      );

  Future<void> _openOwnPostMenu(CirclePost post) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          0,
          ReaduoSpacing.screenHorizontal,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your post', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ListTile(
              key: const Key('circle-edit-post-action'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              key: const Key('circle-delete-post-action'),
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      await _openComposer(post);
    }
    if (action == 'delete') {
      await _confirmDelete(post);
    }
  }

  Future<void> _openFriendPostMenu(CirclePost post, ReaderProfile? friend) =>
      showCircleReportOptions(context, ReportTarget(kind: 'post', id: post.id));

  Future<void> _confirmDelete(CirclePost post) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          0,
          ReaduoSpacing.screenHorizontal,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Delete this post?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'This removes the post from Circle. The book stays in your library.',
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('circle-confirm-delete-post'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete post'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep post'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.engagementRepository.deleteInteractions(
        CircleContentRef(
          kind: CircleContentKind.post,
          id: post.id,
          authorId: post.authorId,
        ),
      );
      if (post.photoPath != null) {
        await widget.photoRepository.delete(post.photoPath!);
      }
      await widget.circleRepository.deletePost(
        authorId: widget.viewerId,
        postId: post.id,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openReviewComposer(CircleReview review) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CircleReviewComposerScreen(
            ownerId: widget.viewerId,
            repository: widget.reviewRepository,
            source: review.toDraft(),
            review: review,
          ),
        ),
      );

  Future<void> _openOwnReviewMenu(CircleReview review) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          0,
          ReaduoSpacing.screenHorizontal,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your review', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ListTile(
              key: const Key('circle-delete-review-action'),
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') {
      await _confirmDeleteReview(review);
    }
  }

  Future<void> _confirmDeleteReview(CircleReview review) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          0,
          ReaduoSpacing.screenHorizontal,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Delete this review?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'This removes the review and rating from Circle. The book stays in your library.',
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('circle-confirm-delete-review'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete review'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep review'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.engagementRepository.deleteInteractions(
        CircleContentRef(
          kind: CircleContentKind.review,
          id: review.id,
          authorId: review.authorId,
        ),
      );
      await widget.reviewRepository.deleteReview(
        authorId: widget.viewerId,
        reviewId: review.id,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _openReviewDetail(CircleReview review) {
    final own = review.authorId == widget.viewerId;
    final friend = _friends[review.authorId];
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CircleReviewDetailScreen(
          review: review,
          viewerId: widget.viewerId,
          repository: widget.reviewRepository,
          bookRepository: widget.bookRepository,
          onOpenBook: _openAttachedBook,
          engagementRepository: widget.engagementRepository,
          displayName: own ? 'You' : friend?.displayName ?? 'Reader',
          photoUrl: own ? widget.viewerPhotoUrl : friend?.photoUrl,
          viewerDisplayName: widget.viewerDisplayName,
          viewerPhotoUrl: widget.viewerPhotoUrl,
          onEdit: own ? _openReviewComposer : null,
          onDelete: own ? _confirmDeleteReview : null,
        ),
      ),
    );
  }

  CircleContentRef _activityContent(_CircleFeedEntry entry) => CircleContentRef(
    kind: CircleContentKind.activity,
    id: entry.activity.id,
    authorId: entry.friend.uid,
    shelfId: entry.shelf.id,
    bookId: entry.book.id,
  );

  void _openActivityComments(_CircleFeedEntry entry) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Book activity')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${entry.friend.displayName} shared a book activity',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => _openBook(entry),
                  child: _CircleBookAttachment(
                    title: entry.book.title,
                    author: entry.book.author,
                    coverUrl: entry.book.coverUrl,
                  ),
                ),
                const SizedBox(height: 12),
                CircleCommentsSection(
                  viewerId: widget.viewerId,
                  viewerDisplayName: widget.viewerDisplayName,
                  viewerPhotoUrl: widget.viewerPhotoUrl,
                  content: _activityContent(entry),
                  repository: widget.engagementRepository,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPostDetail(CirclePost post) {
    final own = post.authorId == widget.viewerId;
    final friend = _friends[post.authorId];
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CirclePostDetailScreen(
          post: post,
          onEdit: own ? _openComposer : null,
          viewerId: widget.viewerId,
          displayName: own ? 'You' : friend?.displayName ?? 'Reader',
          photoUrl: own ? widget.viewerPhotoUrl : friend?.photoUrl,
          viewerDisplayName: widget.viewerDisplayName,
          viewerPhotoUrl: widget.viewerPhotoUrl,
          engagementRepository: widget.engagementRepository,
          photoRepository: widget.photoRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _timelineItems;
    return ProfilePage(
      key: const Key('circle-screen'),
      back: false,
      title: 'Circle',
      mainTab: true,
      backgroundColor: const Color(0xFFF0F3F8),
      floatingActionButton: FloatingActionButton(
        key: const Key('circle-thought-composer'),
        heroTag: 'circle-compose',
        tooltip: 'Share a thought',
        onPressed: _openComposer,
        shape: const CircleBorder(),
        backgroundColor: const Color(0xFF3D7A1A),
        foregroundColor: Colors.white,
        child: const Icon(Icons.edit_outlined),
      ),
      tabActions: [
        ReaduoTabHeaderAction(
          tooltip: 'Notifications',
          onPressed: widget.onNotifications,
          icon: Icons.notifications_none_rounded,
        ),
      ],
      body: _buildBody(items),
    );
  }

  Widget _buildBody(List<_CircleTimelineItem> items) {
    if (_isLoading && items.isEmpty && _error == null) {
      return const Center(
        key: Key('circle-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_hasRootError && items.isEmpty) {
      return _CircleError(onRetry: _restart);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const Key('circle-feed-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_error != null)
            SliverToBoxAdapter(
              child: Container(
                key: const Key('circle-partial-error'),
                margin: const EdgeInsets.fromLTRB(
                  ReaduoSpacing.screenHorizontal,
                  8,
                  ReaduoSpacing.screenHorizontal,
                  4,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync_problem_rounded, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Some Circle updates could not be loaded.'),
                    ),
                    TextButton(onPressed: _restart, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          if (items.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final post = item.post;
                  if (post != null) {
                    final own = post.authorId == widget.viewerId;
                    final friend = _friends[post.authorId];
                    return _PostCard(
                      post: post,
                      bookMetadata: post.attachment == null
                          ? null
                          : CircleBookMetadata(
                              showDescription: false,
                              repository: widget.bookRepository,
                              ownerId: post.attachment!.ownerId,
                              shelfId: post.attachment!.shelfId,
                              bookId: post.attachment!.bookId,
                              onOpen: _openAttachedBook,
                            ),
                      displayName: own
                          ? 'You'
                          : friend?.displayName ?? 'Reader',
                      photoUrl: own ? widget.viewerPhotoUrl : friend?.photoUrl,
                      isOwn: own,
                      viewerId: widget.viewerId,
                      engagementRepository: widget.engagementRepository,
                      photoRepository: _photoCache,
                      onOpen: () => _openPostDetail(post),
                      onMenu: own
                          ? () => _openOwnPostMenu(post)
                          : () => _openFriendPostMenu(post, friend),
                    );
                  }
                  final review = item.review;
                  if (review != null) {
                    final own = review.authorId == widget.viewerId;
                    final friend = _friends[review.authorId];
                    return _ReviewCard(
                      review: review,
                      bookMetadata: CircleBookMetadata(
                        showDescription: false,
                        repository: widget.bookRepository,
                        ownerId: review.authorId,
                        shelfId: review.shelfId,
                        bookId: review.bookId,
                        onOpen: _openAttachedBook,
                      ),
                      displayName: own
                          ? 'You'
                          : friend?.displayName ?? 'Reader',
                      photoUrl: own ? widget.viewerPhotoUrl : friend?.photoUrl,
                      isOwn: own,
                      viewerId: widget.viewerId,
                      engagementRepository: widget.engagementRepository,
                      onOpen: () => _openReviewDetail(review),
                      onMenu: own
                          ? () => _openOwnReviewMenu(review)
                          : () => showCircleReportOptions(
                              context,
                              ReportTarget(kind: 'review', id: review.id),
                            ),
                    );
                  }
                  return _ActivityCard(
                    item: item.activity!,
                    engagement: Column(
                      children: [
                        for (final entry in item.activity!.entries) ...[
                          if (item.activity!.entries.length > 1)
                            Text(
                              entry.book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          CircleEngagementBar(
                            viewerId: widget.viewerId,
                            content: _activityContent(entry),
                            repository: widget.engagementRepository,
                            compact: true,
                            onOpenComments: () => _openActivityComments(entry),
                          ),
                        ],
                      ],
                    ),
                    onOpenBook: _openBook,
                    onMenu: () => showCircleReportOptions(
                      context,
                      ReportTarget(
                        kind: 'profile',
                        id: item.activity!.primary.friend.uid,
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  ReaduoSpacing.screenHorizontal,
                  0,
                  ReaduoSpacing.screenHorizontal,
                  24,
                ),
                child: TextButton.icon(
                  key: const Key('circle-refresh'),
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh Circle'),
                ),
              ),
            ),
          ] else
            SliverFillRemaining(
              hasScrollBody: false,
              child: _CircleEmpty(
                onInviteFriend: widget.onInviteFriend,
                onOpenLibrary: widget.onOpenLibrary,
                onShare: _openComposer,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ),
    );
  }
}

class _CircleFeedEntry {
  const _CircleFeedEntry({
    required this.friend,
    required this.shelf,
    required this.book,
    required this.activity,
  });

  final ReaderProfile friend;
  final Shelf shelf;
  final LibraryBook book;
  final CircleActivity activity;
}

class _CircleFeedItem {
  _CircleFeedItem(List<_CircleFeedEntry> entries)
    : entries = [...entries]
        ..sort(
          (left, right) => right.activity.createdAt.getOrEpoch().compareTo(
            left.activity.createdAt.getOrEpoch(),
          ),
        );

  final List<_CircleFeedEntry> entries;

  _CircleFeedEntry get primary => entries.first;
  DateTime get createdAt => primary.activity.createdAt.getOrEpoch();
  bool get isAdded => primary.activity.type == CircleActivityType.added;
}

class _CircleTimelineItem {
  const _CircleTimelineItem.activity(this.activity)
    : post = null,
      review = null;
  const _CircleTimelineItem.post(this.post) : activity = null, review = null;
  const _CircleTimelineItem.review(this.review) : activity = null, post = null;

  final _CircleFeedItem? activity;
  final CirclePost? post;
  final CircleReview? review;

  DateTime get createdAt =>
      post?.createdAt.getOrEpoch() ??
      review?.createdAt.getOrEpoch() ??
      activity!.createdAt;
}

extension on DateTime? {
  DateTime getOrEpoch() => this ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    this.bookMetadata,
    required this.displayName,
    required this.photoUrl,
    required this.isOwn,
    required this.viewerId,
    required this.engagementRepository,
    required this.photoRepository,
    required this.onOpen,
    required this.onMenu,
  });

  final CirclePost post;
  final Widget? bookMetadata;
  final String displayName;
  final String? photoUrl;
  final bool isOwn;
  final String viewerId;
  final CircleEngagementRepository engagementRepository;
  final CirclePhotoRepository photoRepository;
  final VoidCallback onOpen;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final attachment = post.attachment;
    return Container(
      key: ValueKey('circle-post-${post.id}'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: const BoxDecoration(
        color: ReaduoColors.paper,
        border: Border(
          top: BorderSide(color: ReaduoColors.line, width: 3),
          bottom: BorderSide(color: ReaduoColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: ReaduoColors.accentTint,
                backgroundImage: photoUrl == null || photoUrl!.isEmpty
                    ? null
                    : ReaduoImageCache.image(photoUrl!),
                child: photoUrl == null || photoUrl!.isEmpty
                    ? Text(
                        displayName.isEmpty
                            ? 'R'
                            : displayName.characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: ReaduoColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Posted · ${_relativeTime(post.createdAt.getOrEpoch())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onMenu != null)
                IconButton(
                  key: ValueKey(
                    isOwn
                        ? 'circle-post-menu-${post.id}'
                        : 'circle-report-post-${post.id}',
                  ),
                  tooltip: isOwn ? 'Your post options' : 'Report post',
                  onPressed: onMenu,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _CircleTextPreview(text: post.text, onReadMore: onOpen),
          if (post.photoPath case final photoPath?) ...[
            const SizedBox(height: 8),
            CirclePhoto(storagePath: photoPath, repository: photoRepository),
          ],
          if (attachment != null) ...[
            const SizedBox(height: 14),
            _CircleBookAttachment(
              key: ValueKey('circle-post-book-${post.id}'),
              title: attachment.title,
              author: attachment.author,
              coverUrl: attachment.coverUrl,
              bookMetadata: bookMetadata,
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: ReaduoColors.line),
          CircleEngagementBar(
            compact: true,
            viewerId: viewerId,
            content: CircleContentRef(
              kind: CircleContentKind.post,
              id: post.id,
              authorId: post.authorId,
            ),
            repository: engagementRepository,
            onOpenComments: onOpen,
          ),
        ],
      ),
    );
  }
}

class _CircleTextPreview extends StatelessWidget {
  const _CircleTextPreview({required this.text, required this.onReadMore});

  final String text;
  final VoidCallback onReadMore;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(
        context,
      ).style.merge(const TextStyle(height: 1.45));
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 10,
        ellipsis: '\u2026',
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final truncated = painter.didExceedMaxLines;
      var preview = text;
      if (truncated) {
        final characters = text.characters.toList();
        var low = 0;
        var high = characters.length;
        while (low < high) {
          final middle = (low + high + 1) ~/ 2;
          final candidate =
              '${characters.take(middle).join().trimRight()}\u2026';
          painter.text = TextSpan(text: candidate, style: style);
          painter.layout(maxWidth: constraints.maxWidth);
          if (painter.didExceedMaxLines) {
            high = middle - 1;
          } else {
            low = middle;
          }
        }
        preview = '${characters.take(low).join().trimRight()}\u2026';
      }
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview,
            style: style,
            maxLines: 10,
            overflow: TextOverflow.ellipsis,
          ),
          if (truncated)
            TextButton(onPressed: onReadMore, child: const Text('Read more')),
        ],
      );
    },
  );
}

class _CircleBookAttachment extends StatelessWidget {
  const _CircleBookAttachment({
    required this.title,
    required this.author,
    required this.coverUrl,
    this.bookMetadata,
    super.key,
  });
  final String title;
  final String author;
  final String? coverUrl;
  final Widget? bookMetadata;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ReaduoColors.accentTint.withValues(alpha: .45),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          height: 108,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: coverUrl == null || coverUrl!.isEmpty
                ? GeneratedBookCover(title: title, author: author)
                : BookCoverImage(
                    coverUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: ReaduoColors.accentTint,
                      child: Icon(
                        Icons.menu_book_rounded,
                        color: ReaduoColors.accent,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(author, style: Theme.of(context).textTheme.bodySmall),
              if (bookMetadata != null) bookMetadata!,
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    this.bookMetadata,
    required this.displayName,
    required this.photoUrl,
    required this.isOwn,
    required this.viewerId,
    required this.engagementRepository,
    required this.onOpen,
    required this.onMenu,
  });

  final CircleReview review;
  final Widget? bookMetadata;
  final String displayName;
  final String? photoUrl;
  final bool isOwn;
  final String viewerId;
  final CircleEngagementRepository engagementRepository;
  final VoidCallback onOpen;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) => Material(
    key: ValueKey('circle-review-${review.id}'),
    color: ReaduoColors.paper,
    shape: const Border(
      top: BorderSide(color: ReaduoColors.line, width: 3),
      bottom: BorderSide(color: ReaduoColors.line),
    ),
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CircleAvatar(displayName: displayName, photoUrl: photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Reviewed · ${_relativeTime(review.createdAt.getOrEpoch())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onMenu != null)
                  IconButton(
                    key: ValueKey(
                      isOwn
                          ? 'circle-review-menu-${review.id}'
                          : 'circle-report-review-${review.id}',
                    ),
                    tooltip: isOwn ? 'Your review options' : 'Report review',
                    onPressed: onMenu,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (review.rating != null) ...[
              _ReviewStars(rating: review.rating!),
              const SizedBox(height: 8),
            ],
            _CircleTextPreview(text: review.text, onReadMore: onOpen),
            const SizedBox(height: 14),
            _CircleBookAttachment(
              key: ValueKey('circle-review-book-${review.id}'),
              title: review.title,
              author: review.bookAuthor,
              coverUrl: review.coverUrl,
              bookMetadata: bookMetadata,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: ReaduoColors.line),
            CircleEngagementBar(
              compact: true,
              viewerId: viewerId,
              content: CircleContentRef(
                kind: CircleContentKind.review,
                id: review.id,
                authorId: review.authorId,
              ),
              repository: engagementRepository,
              onOpenComments: onOpen,
            ),
          ],
        ),
      ),
    ),
  );
}

class CirclePostDetailScreen extends StatelessWidget {
  const CirclePostDetailScreen({
    required this.post,
    required this.viewerId,
    required this.displayName,
    required this.photoUrl,
    required this.viewerDisplayName,
    required this.viewerPhotoUrl,
    required this.engagementRepository,
    required this.photoRepository,
    this.onEdit,
    super.key,
  });

  final CirclePost post;
  final ValueChanged<CirclePost>? onEdit;
  final String viewerId;
  final String displayName;
  final String? photoUrl;
  final String viewerDisplayName;
  final String? viewerPhotoUrl;
  final CircleEngagementRepository engagementRepository;
  final CirclePhotoRepository photoRepository;

  @override
  Widget build(BuildContext context) {
    final services = FeatureServices.maybeOf(context);
    if (services == null) return _content(context, post);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: services.firestore
          .collection('circlePosts')
          .doc(post.id)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (snapshot.hasError || (snapshot.hasData && !snapshot.data!.exists)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Post')),
            body: const SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ReaduoSpacing.screenHorizontal,
                    vertical: 24,
                  ),
                  child: Text('This post is no longer available.'),
                ),
              ),
            ),
          );
        }
        final document = snapshot.data;
        if (document == null || document.metadata.isFromCache) {
          return Scaffold(
            appBar: AppBar(title: const Text('Post')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return _content(
          context,
          CirclePost.fromFirestore(document.id, document.data()!),
        );
      },
    );
  }

  Widget _content(BuildContext context, CirclePost post) => Scaffold(
    key: const Key('circle-post-detail'),
    appBar: AppBar(
      title: NotificationDestinationMarker(
        destination: NotificationDestination(
          NotificationDestinationKind.post,
          post.id,
        ),
        child: const Text('Post'),
      ),
      actions: [
        if (post.authorId == viewerId && onEdit != null)
          TextButton.icon(
            key: const Key('circle-post-detail-edit'),
            onPressed: () => onEdit!(post),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
        if (post.authorId != viewerId)
          IconButton(
            tooltip: 'Report post',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => FeatureServices.report(
              context,
              ReportTarget(kind: 'post', id: post.id),
            ),
          ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          16,
          ReaduoSpacing.screenHorizontal,
          28,
        ),
        children: [
          Row(
            children: [
              _CircleAvatar(displayName: displayName, photoUrl: photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Posted ${_relativeTime(post.createdAt.getOrEpoch())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (post.text.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(post.text, style: const TextStyle(fontSize: 16, height: 1.55)),
          ],
          if (post.photoPath case final photoPath?) ...[
            const SizedBox(height: 16),
            CirclePhoto(storagePath: photoPath, repository: photoRepository),
          ],
          if (post.attachment case final attachment?) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ReaduoColors.paper,
                border: Border.all(color: ReaduoColors.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 68,
                    height: 102,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child:
                          attachment.coverUrl == null ||
                              attachment.coverUrl!.isEmpty
                          ? GeneratedBookCover(
                              title: attachment.title,
                              author: attachment.author,
                            )
                          : BookCoverImage(
                              attachment.coverUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => GeneratedBookCover(
                                title: attachment.title,
                                author: attachment.author,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          attachment.author,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          CircleCommentsSection(
            viewerId: viewerId,
            viewerDisplayName: viewerDisplayName,
            viewerPhotoUrl: viewerPhotoUrl,
            content: CircleContentRef(
              kind: CircleContentKind.post,
              id: post.id,
              authorId: post.authorId,
            ),
            repository: engagementRepository,
          ),
        ],
      ),
    ),
  );
}

class CircleReviewDetailScreen extends StatefulWidget {
  const CircleReviewDetailScreen({
    required this.review,
    required this.viewerId,
    required this.repository,
    this.bookRepository,
    this.onOpenBook,
    this.engagementRepository = const EmptyCircleEngagementRepository(),
    required this.displayName,
    required this.photoUrl,
    this.viewerDisplayName = 'You',
    this.viewerPhotoUrl,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final CircleReview review;
  final String viewerId;
  final ReviewRepository repository;
  final BookRepository? bookRepository;
  final ValueChanged<LibraryBook>? onOpenBook;
  final CircleEngagementRepository engagementRepository;
  final String displayName;
  final String? photoUrl;
  final String viewerDisplayName;
  final String? viewerPhotoUrl;
  final ValueChanged<CircleReview>? onEdit;
  final ValueChanged<CircleReview>? onDelete;

  @override
  State<CircleReviewDetailScreen> createState() =>
      _CircleReviewDetailScreenState();
}

class _CircleReviewDetailScreenState extends State<CircleReviewDetailScreen> {
  late Stream<CircleReview?> _review;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CircleReviewDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerId != widget.viewerId ||
        oldWidget.review.id != widget.review.id ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  void _load() {
    _review = widget.repository.watchReview(
      viewerId: widget.viewerId,
      authorId: widget.review.authorId,
      bookId: widget.review.bookId,
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<CircleReview?>(
    stream: _review,
    initialData: widget.review,
    builder: (context, snapshot) {
      final review = snapshot.data;
      return Scaffold(
        key: const Key('circle-review-detail'),
        appBar: AppBar(
          title: NotificationDestinationMarker(
            destination: NotificationDestination(
              NotificationDestinationKind.post,
              widget.review.id,
              isReview: true,
            ),
            child: const Text(
              'Review',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
          ),
          actions: [
            if (review != null && review.authorId != widget.viewerId)
              IconButton(
                tooltip: 'Report review',
                icon: const Icon(Icons.flag_outlined),
                onPressed: () => FeatureServices.report(
                  context,
                  ReportTarget(kind: 'review', id: review.id),
                ),
              ),
            if (review != null && widget.onEdit != null)
              IconButton(
                key: const Key('review-detail-edit'),
                tooltip: 'Edit review',
                onPressed: () => widget.onEdit!(review),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (review != null && widget.onDelete != null)
              IconButton(
                key: const Key('review-detail-delete'),
                tooltip: 'Delete review',
                onPressed: () => widget.onDelete!(review),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
        body: SafeArea(
          child: snapshot.hasError || review == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ReaduoSpacing.screenHorizontal,
                      vertical: 28,
                    ),
                    child: Text(
                      'This review is no longer available.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    ReaduoSpacing.screenHorizontal,
                    16,
                    ReaduoSpacing.screenHorizontal,
                    28,
                  ),
                  children: [
                    Row(
                      children: [
                        _CircleAvatar(
                          displayName: widget.displayName,
                          photoUrl: widget.photoUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Reviewed ${_relativeTime(review.createdAt.getOrEpoch())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _CircleBookAttachment(
                      title: review.title,
                      author: review.bookAuthor,
                      coverUrl: review.coverUrl,
                      bookMetadata:
                          widget.bookRepository != null &&
                              widget.onOpenBook != null
                          ? CircleBookMetadata(
                              repository: widget.bookRepository!,
                              ownerId: review.authorId,
                              shelfId: review.shelfId,
                              bookId: review.bookId,
                              showDescription: false,
                              onOpen: widget.onOpenBook!,
                            )
                          : null,
                    ),
                    if (review.rating != null) ...[
                      const SizedBox(height: 18),
                      _ReviewStars(rating: review.rating!),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      review.text,
                      style: const TextStyle(fontSize: 16, height: 1.55),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: ReaduoColors.line),
                    CircleCommentsSection(
                      viewerId: widget.viewerId,
                      viewerDisplayName: widget.viewerDisplayName,
                      viewerPhotoUrl: widget.viewerPhotoUrl,
                      content: CircleContentRef(
                        kind: CircleContentKind.review,
                        id: review.id,
                        authorId: review.authorId,
                      ),
                      repository: widget.engagementRepository,
                    ),
                  ],
                ),
        ),
      );
    },
  );
}

class _CircleAvatar extends StatelessWidget {
  const _CircleAvatar({required this.displayName, required this.photoUrl});

  final String displayName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 22,
    backgroundColor: ReaduoColors.accentTint,
    backgroundImage: photoUrl == null || photoUrl!.isEmpty
        ? null
        : ReaduoImageCache.image(photoUrl!),
    child: photoUrl == null || photoUrl!.isEmpty
        ? Text(
            displayName.isEmpty
                ? 'R'
                : displayName.characters.first.toUpperCase(),
            style: const TextStyle(
              color: ReaduoColors.accent,
              fontWeight: FontWeight.w700,
            ),
          )
        : null,
  );
}

class _ReviewStars extends StatelessWidget {
  const _ReviewStars({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$rating out of 5 stars',
    child: Row(
      children: [
        for (var star = 1; star <= 5; star++)
          Icon(
            star <= rating ? Icons.star_rounded : Icons.star_border_rounded,
            size: 22,
            color: const Color(0xFFE3A008),
          ),
      ],
    ),
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.item,
    required this.engagement,
    required this.onOpenBook,
    required this.onMenu,
  });

  final Widget engagement;
  final VoidCallback onMenu;

  final _CircleFeedItem item;
  final ValueChanged<_CircleFeedEntry> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final primary = item.primary;
    final name = primary.friend.displayName;
    final headline = switch (primary.activity.type) {
      CircleActivityType.added =>
        item.entries.length == 1
            ? '$name added a book'
            : '$name added ${item.entries.length} books',
      CircleActivityType.started => '$name started reading',
      CircleActivityType.finished => '$name finished',
    };
    return Container(
      key: ValueKey('circle-activity-${primary.activity.id}'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: const BoxDecoration(
        color: ReaduoColors.paper,
        border: Border(
          top: BorderSide(color: ReaduoColors.line, width: 3),
          bottom: BorderSide(color: ReaduoColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReaderAvatar(profile: primary.friend),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        color: ReaduoColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${primary.shelf.name} · ${_relativeTime(item.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('circle-activity-menu-${primary.activity.id}'),
                tooltip: 'Post options',
                onPressed: onMenu,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: ReaduoColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (item.isAdded && item.entries.length > 1)
            SizedBox(
              height: 252,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.entries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final entry = item.entries[index];
                  return _BookCoverButton(
                    entry: entry,
                    onTap: () => onOpenBook(entry),
                  );
                },
              ),
            )
          else
            InkWell(
              onTap: () => onOpenBook(primary),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ReaduoColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 116,
                      height: 174,
                      child: _BookCover(book: primary.book),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            primary.book.title,
                            style: const TextStyle(
                              color: ReaduoColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            primary.book.author,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          BookEditionMetadata(book: primary.book),
                          BookDescription(book: primary.book, compact: true),
                          TextButton(
                            onPressed: () => onOpenBook(primary),
                            child: const Text('Book details ›'),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: ReaduoColors.line),
          engagement,
        ],
      ),
    );
  }
}

class _ReaderAvatar extends StatelessWidget {
  const _ReaderAvatar({required this.profile});

  final ReaderProfile profile;

  @override
  Widget build(BuildContext context) {
    final photoUrl = profile.photoUrl;
    return CircleAvatar(
      radius: 22,
      backgroundColor: ReaduoColors.accentTint,
      backgroundImage: photoUrl == null || photoUrl.isEmpty
          ? null
          : ReaduoImageCache.image(photoUrl),
      child: photoUrl == null || photoUrl.isEmpty
          ? Text(
              profile.displayName.isEmpty
                  ? 'R'
                  : profile.displayName.characters.first.toUpperCase(),
              style: const TextStyle(
                color: ReaduoColors.accent,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _BookCoverButton extends StatelessWidget {
  const _BookCoverButton({required this.entry, required this.onTap});

  final _CircleFeedEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open ${entry.book.title}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 164, child: _BookCover(book: entry.book)),
    ),
  );
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final coverUrl = book.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: ReaduoColors.accentTint),
        child: coverUrl == null || coverUrl.isEmpty
            ? GeneratedBookCover(title: book.title, author: book.author)
            : BookCoverImage(
                coverUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: ReaduoColors.accent,
                  ),
                ),
              ),
      ),
    );
  }
}

class _CircleEmpty extends StatelessWidget {
  const _CircleEmpty({
    required this.onInviteFriend,
    required this.onOpenLibrary,
    required this.onShare,
  });

  final VoidCallback onInviteFriend;
  final VoidCallback onOpenLibrary;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => Align(
    key: const Key('circle-empty'),
    alignment: Alignment.topCenter,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        68,
        ReaduoSpacing.screenHorizontal,
        28,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: ReaduoColors.accentTint,
              borderRadius: BorderRadius.circular(23),
            ),
            child: const Icon(
              LucideIcons.usersRound,
              color: ReaduoColors.accent,
              size: 30,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'A little quiet, for now',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: ReaduoColors.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your friends’ posts and reading updates will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ReaduoColors.muted, height: 1.45),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  key: const Key('circle-invite-friend'),
                  onPressed: onInviteFriend,
                  icon: const Icon(LucideIcons.userPlus, size: 30),
                  label: const Text('Invite a friend'),
                ),
                const SizedBox(height: 44),
                OutlinedButton(
                  key: const Key('circle-share-first-post'),
                  onPressed: onShare,
                  child: const Text('Share your first post'),
                ),
                TextButton(
                  key: const Key('circle-visit-library'),
                  onPressed: onOpenLibrary,
                  child: const Text('Visit my library'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CircleError extends StatelessWidget {
  const _CircleError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    key: const Key('circle-error'),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ReaduoSpacing.screenHorizontal,
        vertical: 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 14),
          const Text(
            'Circle could not load right now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ReaduoColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text('Check your connection and retry.'),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              onRetry();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

String _relativeTime(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${date.month}/${date.day}/${date.year}';
}

Future<void> showCircleReportOptions(
  BuildContext context,
  ReportTarget target,
) async {
  final report = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ListTile(
          key: const Key('circle-report-action'),
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Report'),
          onTap: () => Navigator.pop(sheetContext, true),
        ),
      ),
    ),
  );
  if (report == true && context.mounted)
    await FeatureServices.report(context, target);
}
