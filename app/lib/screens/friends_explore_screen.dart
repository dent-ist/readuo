import '../widgets/readuo_image_cache.dart';
import '../widgets/book_cover_image.dart';
import '../widgets/readuo_section_tabs.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../features/feature_services.dart';
import '../moderation/moderation_repository.dart';

import '../friends/friend_repository.dart';
import '../library/book.dart';
import '../library/book_repository.dart';
import '../library/isbn.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';
import 'library_books_screen.dart';

part 'unified_explore_body.dart';

typedef ExploreProfileCallback = Future<void> Function(ReaderProfile friend);
typedef ExploreShelfCallback =
    Future<void> Function(ReaderProfile friend, Shelf shelf);
typedef ExploreBookCallback =
    Future<void> Function(ReaderProfile friend, Shelf shelf, LibraryBook book);

class FriendsExploreBody extends StatefulWidget {
  const FriendsExploreBody({
    required this.viewerId,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.onMyLibrary,
    required this.onSearch,
    required this.onOpenProfile,
    required this.onOpenShelf,
    required this.onOpenBook,
    required this.onInviteFriend,
    required this.onPublicUnavailable,
    super.key,
  });

  final String viewerId;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final VoidCallback onMyLibrary;
  final ValueChanged<String> onSearch;
  final ExploreProfileCallback onOpenProfile;
  final ExploreShelfCallback onOpenShelf;
  final ExploreBookCallback onOpenBook;
  final VoidCallback onInviteFriend;
  final VoidCallback onPublicUnavailable;

  @override
  State<FriendsExploreBody> createState() => _FriendsExploreBodyState();
}

class _FriendsExploreBodyState extends State<FriendsExploreBody> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) widget.onSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    return _FriendsExploreLoader(
      viewerId: widget.viewerId,
      friendRepository: widget.friendRepository,
      shelfRepository: widget.shelfRepository,
      bookRepository: widget.bookRepository,
      builder: (context, state, retry) => ListView(
        key: const Key('friends-explore'),
        padding: const EdgeInsets.fromLTRB(
          16,
          8,
          16,
          28,
        ),
        children: [
          _LibrarySwitcher(onMyLibrary: widget.onMyLibrary),
          const SizedBox(height: 16),
          _ExploreSearchField(
            controller: _searchController,
            onSubmitted: _search,
          ),
          const SizedBox(height: 16),
          _ExploreScopeChips(
            onFriends: () {},
            onPublic: widget.onPublicUnavailable,
          ),
          const SizedBox(height: 24),
          Text(
            'From your friends',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: ReaduoColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (state.error != null)
            _ExploreMessage(
              key: const Key('friends-explore-error'),
              icon: Icons.cloud_off_outlined,
              title: 'Shared books unavailable',
              message: state.error!,
              actionLabel: 'Retry',
              onAction: retry,
            )
          else if (state.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(
                  key: Key('friends-explore-loading'),
                ),
              ),
            )
          else if (state.collections.isEmpty)
            _ExploreEmpty(
              onPublic: widget.onPublicUnavailable,
              onInvite: widget.onInviteFriend,
            )
          else
            ...state.collections.map(
              (collection) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _ExploreCollectionCard(
                  collection: collection,
                  onOpenProfile: () => widget.onOpenProfile(collection.friend),
                  onOpenShelf: () =>
                      widget.onOpenShelf(collection.friend, collection.shelf),
                  onOpenBook: (book) => widget.onOpenBook(
                    collection.friend,
                    collection.shelf,
                    book,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FriendsExploreSearchScreen extends StatefulWidget {
  const FriendsExploreSearchScreen({
    required this.viewerId,
    required this.initialQuery,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.onOpenShelf,
    required this.onOpenBook,
    required this.onPublic,
    super.key,
  });

  final String viewerId;
  final String initialQuery;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final ExploreShelfCallback onOpenShelf;
  final ExploreBookCallback onOpenBook;
  final ValueChanged<String> onPublic;

  @override
  State<FriendsExploreSearchScreen> createState() =>
      _FriendsExploreSearchScreenState();
}

class _FriendsExploreSearchScreenState
    extends State<FriendsExploreSearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  late String _query = normalizeLibraryText(widget.initialQuery);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateQuery() => setState(() {
    _query = normalizeLibraryText(_controller.text);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('friends-explore-search'),
      appBar: AppBar(title: const Text('Explore search')),
      body: SafeArea(
        child: _FriendsExploreLoader(
          viewerId: widget.viewerId,
          friendRepository: widget.friendRepository,
          shelfRepository: widget.shelfRepository,
          bookRepository: widget.bookRepository,
          builder: (context, state, retry) {
            final matches = state.collections
                .expand(
                  (collection) => collection.books
                      .where((book) => libraryBookMatches(book, _query))
                      .map((book) => (collection: collection, book: book)),
                )
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                ReaduoSpacing.screenHorizontal,
                12,
                ReaduoSpacing.screenHorizontal,
                28,
              ),
              children: [
                _ExploreSearchField(
                  controller: _controller,
                  onSubmitted: _updateQuery,
                  onChanged: (_) => _updateQuery(),
                ),
                const SizedBox(height: 16),
                _ExploreScopeChips(
                  onFriends: () {},
                  onPublic: () => widget.onPublic(_controller.text),
                ),
                const SizedBox(height: 18),
                if (state.error != null)
                  _ExploreMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Search unavailable',
                    message: state.error!,
                    actionLabel: 'Retry',
                    onAction: retry,
                  )
                else if (state.loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_query.isEmpty || matches.isEmpty)
                  _ExploreMessage(
                    key: const Key('friends-explore-no-results'),
                    icon: Icons.search_off_rounded,
                    title: 'No matching owned books',
                    message:
                        'Try a different title, author, or ISBN, or look in public collections.',
                    actionLabel: 'Search public collections',
                    onAction: () => widget.onPublic(_controller.text),
                  )
                else ...[
                  Text(
                    'Readers who marked this edition as owned on an accessible shelf',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final match in matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ExploreSearchResult(
                        collection: match.collection,
                        book: match.book,
                        onOpenBook: () => widget.onOpenBook(
                          match.collection.friend,
                          match.collection.shelf,
                          match.book,
                        ),
                        onOpenShelf: () => widget.onOpenShelf(
                          match.collection.friend,
                          match.collection.shelf,
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FriendsExploreLoader extends StatefulWidget {
  const _FriendsExploreLoader({
    required this.viewerId,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.builder,
  });

  final String viewerId;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final Widget Function(
    BuildContext context,
    _ExploreLoadState state,
    VoidCallback retry,
  )
  builder;

  @override
  State<_FriendsExploreLoader> createState() => _FriendsExploreLoaderState();
}

class _FriendsExploreLoaderState extends State<_FriendsExploreLoader> {
  StreamSubscription<List<ReaderProfile>>? _friendSubscription;
  final Map<String, StreamSubscription<List<Shelf>>> _shelfSubscriptions = {};
  final Map<_ExploreSourceKey, StreamSubscription<List<LibraryBook>>>
  _bookSubscriptions = {};
  final Map<String, ReaderProfile> _friends = {};
  final Map<String, List<Shelf>> _shelves = {};
  final Map<_ExploreSourceKey, List<LibraryBook>> _books = {};
  final Set<String> _loadedFriends = {};
  final Set<_ExploreSourceKey> _loadedBooks = {};
  bool _friendsLoaded = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant _FriendsExploreLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerId != widget.viewerId ||
        oldWidget.friendRepository != widget.friendRepository ||
        oldWidget.shelfRepository != widget.shelfRepository ||
        oldWidget.bookRepository != widget.bookRepository) {
      _restart();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_friendSubscription?.cancel());
    for (final subscription in _shelfSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    for (final subscription in _bookSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  void _restart() {
    final generation = ++_generation;
    unawaited(_friendSubscription?.cancel());
    for (final subscription in _shelfSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    for (final subscription in _bookSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _shelfSubscriptions.clear();
    _bookSubscriptions.clear();
    _friends.clear();
    _shelves.clear();
    _books.clear();
    _loadedFriends.clear();
    _loadedBooks.clear();
    _friendsLoaded = false;
    _error = null;
    _friendSubscription = widget.friendRepository
        .watchFriends(widget.viewerId)
        .listen(
          (friends) => _updateFriends(generation, friends),
          onError: (Object error) => _fail(generation, error),
        );
    if (mounted) setState(() {});
  }

  void _updateFriends(int generation, List<ReaderProfile> friends) {
    if (!mounted || generation != _generation) return;
    final nextIds = friends.map((friend) => friend.uid).toSet();
    final removed = _friends.keys
        .where((friendId) => !nextIds.contains(friendId))
        .toList();
    for (final friendId in removed) {
      _friends.remove(friendId);
      unawaited(_shelfSubscriptions.remove(friendId)?.cancel());
      _loadedFriends.remove(friendId);
      _shelves.remove(friendId);
      _removeBookSources((key) => key.friendId == friendId);
    }
    for (final friend in friends) {
      _friends[friend.uid] = friend;
      if (_shelfSubscriptions.containsKey(friend.uid)) continue;
      _shelfSubscriptions[friend.uid] = widget.shelfRepository
          .watchSharedShelves(viewerId: widget.viewerId, ownerId: friend.uid)
          .listen(
            (shelves) => _updateShelves(generation, friend.uid, shelves),
            onError: (Object error) => _fail(generation, error),
          );
    }
    _friendsLoaded = true;
    setState(() {});
  }

  void _updateShelves(int generation, String friendId, List<Shelf> shelves) {
    if (!mounted ||
        generation != _generation ||
        !_friends.containsKey(friendId)) {
      return;
    }
    final accessible = shelves
        .where(
          (shelf) =>
              shelf.ownerId == friendId &&
              shelf.visibility != ShelfVisibility.private,
        )
        .toList();
    final nextKeys = accessible
        .map((shelf) => _ExploreSourceKey(friendId, shelf.id))
        .toSet();
    _removeBookSources(
      (key) => key.friendId == friendId && !nextKeys.contains(key),
    );
    _shelves[friendId] = accessible;
    _loadedFriends.add(friendId);
    for (final shelf in accessible) {
      final key = _ExploreSourceKey(friendId, shelf.id);
      if (_bookSubscriptions.containsKey(key)) continue;
      _bookSubscriptions[key] = widget.bookRepository
          .watchOwnedSharedBooks(
            viewerId: widget.viewerId,
            ownerId: friendId,
            shelfId: shelf.id,
          )
          .listen(
            (books) => _updateBooks(generation, key, books),
            onError: (Object error) => _fail(generation, error),
          );
    }
    setState(() {});
  }

  void _updateBooks(
    int generation,
    _ExploreSourceKey key,
    List<LibraryBook> books,
  ) {
    if (!mounted ||
        generation != _generation ||
        !_bookSubscriptions.containsKey(key)) {
      return;
    }
    _books[key] = books
        .where(
          (book) =>
              book.ownerId == key.friendId &&
              book.shelfId == key.shelfId &&
              book.isOwned,
        )
        .toList();
    _loadedBooks.add(key);
    setState(() {});
  }

  void _removeBookSources(bool Function(_ExploreSourceKey key) remove) {
    final keys = _bookSubscriptions.keys.where(remove).toList();
    for (final key in keys) {
      unawaited(_bookSubscriptions.remove(key)?.cancel());
      _loadedBooks.remove(key);
      _books.remove(key);
    }
  }

  void _fail(int generation, Object error) {
    if (!mounted || generation != _generation) return;
    setState(() {
      _error = switch (error) {
        FriendFailure failure => failure.message,
        ShelfFailure failure => failure.message,
        BookFailure failure => failure.message,
        _ => 'Readuo could not load shared books. Please retry.',
      };
    });
  }

  _ExploreLoadState get _state {
    final currentKeys = <_ExploreSourceKey>{};
    for (final entry in _shelves.entries) {
      for (final shelf in entry.value) {
        currentKeys.add(_ExploreSourceKey(entry.key, shelf.id));
      }
    }
    final loading =
        !_friendsLoaded ||
        _friends.keys.any((friendId) => !_loadedFriends.contains(friendId)) ||
        currentKeys.any((key) => !_loadedBooks.contains(key));
    final collections = <FriendsExploreCollection>[];
    for (final friend in _friends.values) {
      for (final shelf in _shelves[friend.uid] ?? const <Shelf>[]) {
        final books =
            _books[_ExploreSourceKey(friend.uid, shelf.id)] ??
            const <LibraryBook>[];
        if (books.isNotEmpty) {
          collections.add(
            FriendsExploreCollection(
              friend: friend,
              shelf: shelf,
              books: books,
            ),
          );
        }
      }
    }
    collections.sort((left, right) {
      final friendOrder = left.friend.displayName.toLowerCase().compareTo(
        right.friend.displayName.toLowerCase(),
      );
      return friendOrder != 0
          ? friendOrder
          : left.shelf.name.toLowerCase().compareTo(
              right.shelf.name.toLowerCase(),
            );
    });
    return _ExploreLoadState(
      loading: loading,
      error: _error,
      collections: collections,
      friendIds: _friends.keys.toSet(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _state, _restart);
}

class PublicExploreBody extends StatefulWidget {
  const PublicExploreBody({
    required this.viewerId,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.onMyLibrary,
    required this.onFriends,
    required this.onSearch,
    required this.onOpenProfile,
    required this.onOpenShelf,
    required this.onOpenBook,
    super.key,
  });

  final String viewerId;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final VoidCallback onMyLibrary;
  final VoidCallback onFriends;
  final ValueChanged<String> onSearch;
  final ExploreProfileCallback onOpenProfile;
  final ExploreShelfCallback onOpenShelf;
  final ExploreBookCallback onOpenBook;

  @override
  State<PublicExploreBody> createState() => _PublicExploreBodyState();
}

class _PublicExploreBodyState extends State<PublicExploreBody> {
  final _searchController = TextEditingController();
  int _limit = 20;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PublicExploreLoader(
    viewerId: widget.viewerId,
    friendRepository: widget.friendRepository,
    shelfRepository: widget.shelfRepository,
    bookRepository: widget.bookRepository,
    limit: _limit,
    builder: (context, state, retry) => ListView(
      key: const Key('public-explore'),
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        28,
      ),
      children: [
        _LibrarySwitcher(onMyLibrary: widget.onMyLibrary),
        const SizedBox(height: 16),
        _ExploreSearchField(
          controller: _searchController,
          onSubmitted: () {
            final query = _searchController.text.trim();
            if (query.isNotEmpty) widget.onSearch(query);
          },
        ),
        const SizedBox(height: 16),
        _ExploreScopeChips(
          publicSelected: true,
          onFriends: widget.onFriends,
          onPublic: () {},
        ),
        const SizedBox(height: 24),
        Text(
          'Public collections',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: ReaduoColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Only books marked owned on Public shelves appear here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        if (state.error != null)
          _ExploreMessage(
            key: const Key('public-explore-error'),
            icon: Icons.cloud_off_outlined,
            title: 'Public collections unavailable',
            message: state.error!,
            actionLabel: 'Retry',
            onAction: retry,
          )
        else if (state.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(
                key: Key('public-explore-loading'),
              ),
            ),
          )
        else ...[
          if (state.partialFailure) const _PublicPartialNotice(),
          if (state.collections.isEmpty)
            _ExploreMessage(
              key: const Key('public-explore-empty'),
              icon: Icons.public_off_outlined,
              title: 'No public collections yet',
              message:
                  'Public shelves with owned books will appear here when available.',
              actionLabel: 'View friends',
              onAction: widget.onFriends,
            )
          else
            for (var index = 0; index < state.collections.length; index += 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _ExploreCollectionCard(
                  collection: state.collections[index],
                  publicAccess: true,
                  showReaderHeader:
                      index == 0 ||
                      state.collections[index - 1].friend.uid !=
                          state.collections[index].friend.uid,
                  onOpenProfile: () =>
                      widget.onOpenProfile(state.collections[index].friend),
                  onOpenShelf: () => widget.onOpenShelf(
                    state.collections[index].friend,
                    state.collections[index].shelf,
                  ),
                  onOpenBook: (book) => widget.onOpenBook(
                    state.collections[index].friend,
                    state.collections[index].shelf,
                    book,
                  ),
                ),
              ),
          if (state.hasMore)
            OutlinedButton(
              key: const Key('public-explore-load-more'),
              onPressed: () => setState(() => _limit += 20),
              child: const Text('Load more public collections'),
            ),
        ],
      ],
    ),
  );
}

class PublicExploreSearchScreen extends StatefulWidget {
  const PublicExploreSearchScreen({
    required this.viewerId,
    required this.initialQuery,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.onFriends,
    required this.onOpenShelf,
    required this.onOpenBook,
    super.key,
  });

  final String viewerId;
  final String initialQuery;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final ValueChanged<String> onFriends;
  final ExploreShelfCallback onOpenShelf;
  final ExploreBookCallback onOpenBook;

  @override
  State<PublicExploreSearchScreen> createState() =>
      _PublicExploreSearchScreenState();
}

class _PublicExploreSearchScreenState extends State<PublicExploreSearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  late String _query = widget.initialQuery.trim();
  int _limit = 20;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateQuery() => setState(() => _query = _controller.text.trim());

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('public-explore-search'),
    appBar: AppBar(title: const Text('Explore search')),
    body: SafeArea(
      child: _PublicExploreLoader(
        viewerId: widget.viewerId,
        friendRepository: widget.friendRepository,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
        limit: _limit,
        builder: (context, state, retry) {
          final matches = state.collections
              .expand(
                (collection) => collection.books
                    .where((book) => _publicBookMatches(book, _query))
                    .map((book) => (collection: collection, book: book)),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              12,
              ReaduoSpacing.screenHorizontal,
              28,
            ),
            children: [
              _ExploreSearchField(
                controller: _controller,
                onSubmitted: _updateQuery,
                onChanged: (_) => _updateQuery(),
              ),
              const SizedBox(height: 16),
              _ExploreScopeChips(
                publicSelected: true,
                onFriends: () => widget.onFriends(_controller.text),
                onPublic: () {},
              ),
              const SizedBox(height: 18),
              if (state.error != null)
                _ExploreMessage(
                  icon: Icons.cloud_off_outlined,
                  title: 'Search unavailable',
                  message: state.error!,
                  actionLabel: 'Retry',
                  onAction: retry,
                )
              else if (state.loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                if (state.partialFailure) const _PublicPartialNotice(),
                if (_query.isEmpty || matches.isEmpty)
                  _ExploreMessage(
                    key: const Key('public-explore-no-results'),
                    icon: Icons.search_off_rounded,
                    title: 'No matching owned books',
                    message:
                        'Try a different title, author, or exact ISBN, or look in friends’ collections.',
                    actionLabel: 'Search friends’ collections',
                    onAction: () => widget.onFriends(_controller.text),
                  )
                else ...[
                  Text(
                    'Readers who marked this edition as owned on a Public shelf',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final match in matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ExploreSearchResult(
                        collection: match.collection,
                        book: match.book,
                        publicAccess: true,
                        onOpenBook: () => widget.onOpenBook(
                          match.collection.friend,
                          match.collection.shelf,
                          match.book,
                        ),
                        onOpenShelf: () => widget.onOpenShelf(
                          match.collection.friend,
                          match.collection.shelf,
                        ),
                      ),
                    ),
                ],
                if (state.hasMore)
                  OutlinedButton(
                    key: const Key('public-search-load-more'),
                    onPressed: () => setState(() => _limit += 20),
                    child: const Text('Search more public collections'),
                  ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class PublicReaderProfileScreen extends StatefulWidget {
  const PublicReaderProfileScreen({
    required this.viewerId,
    required this.reader,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.onOpenShelf,
    required this.onOpenBook,
    super.key,
  });

  final String viewerId;
  final ReaderProfile reader;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final ExploreShelfCallback onOpenShelf;
  final ExploreBookCallback onOpenBook;

  @override
  State<PublicReaderProfileScreen> createState() =>
      _PublicReaderProfileScreenState();
}

class _PublicReaderProfileScreenState extends State<PublicReaderProfileScreen> {
  bool _sending = false;

  Future<void> _requestFriend(ReaderProfile reader) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          4,
          ReaduoSpacing.screenHorizontal,
          28 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Send friend request?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${reader.displayName} will need to approve your request before friend-only shelves become available.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('confirm-public-friend-request'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send request'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || _sending) return;
    setState(() => _sending = true);
    String message;
    try {
      final outcome = await widget.friendRepository.sendRequest(
        userId: widget.viewerId,
        recipient: reader,
        inviteCode: reader.inviteCode,
      );
      message = switch (outcome) {
        SendRequestOutcome.sent => 'Friend request sent for approval.',
        SendRequestOutcome.alreadyFriend => 'You’re already friends.',
        SendRequestOutcome.alreadySent => 'Friend request already pending.',
        SendRequestOutcome.incomingRequest =>
          'This reader already sent you a request. Review it in Friends.',
      };
    } on FriendFailure catch (error) {
      message = error.message;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('public-reader-profile'),
    appBar: AppBar(title: const Text('Reader profile')),
    body: SafeArea(
      child: _PublicExploreLoader(
        viewerId: widget.viewerId,
        ownerId: widget.reader.uid,
        friendRepository: widget.friendRepository,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
        limit: 100,
        builder: (context, state, retry) {
          final reader = state.reader;
          if (state.error != null || (!state.loading && reader == null)) {
            return _ExploreMessage(
              icon: Icons.person_off_outlined,
              title: 'Profile unavailable',
              message:
                  state.error ?? 'This reader is no longer available to you.',
              actionLabel: 'Retry',
              onAction: retry,
            );
          }
          if (state.loading || reader == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final ownedCount = state.collections.fold<int>(
            0,
            (total, collection) => total + collection.books.length,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              20,
              ReaduoSpacing.screenHorizontal,
              28,
            ),
            children: [
              Center(child: _ReaderInitials(friend: reader, radius: 38)),
              const SizedBox(height: 14),
              Text(
                reader.displayName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${state.collections.length} public ${state.collections.length == 1 ? 'shelf' : 'shelves'} · $ownedCount owned ${ownedCount == 1 ? 'book' : 'books'}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('public-send-friend-request'),
                onPressed: _sending ? null : () => _requestFriend(reader),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_sending ? 'Sending…' : 'Send friend request'),
              ),
              TextButton.icon(
                key: const Key('public-report-profile'),
                onPressed: () => FeatureServices.report(
                  context,
                  ReportTarget(kind: 'profile', id: reader.uid),
                ),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report profile'),
              ),
              const SizedBox(height: 10),
              Text(
                'Public shelves',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (state.partialFailure) const _PublicPartialNotice(),
              if (state.collections.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'This reader has no available public shelves.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final collection in state.collections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _ExploreCollectionCard(
                      collection: collection,
                      publicAccess: true,
                      showReaderHeader: false,
                      onOpenProfile: () {},
                      onOpenShelf: () =>
                          widget.onOpenShelf(reader, collection.shelf),
                      onOpenBook: (book) =>
                          widget.onOpenBook(reader, collection.shelf, book),
                    ),
                  ),
            ],
          );
        },
      ),
    ),
  );
}

class _PublicPartialNotice extends StatelessWidget {
  const _PublicPartialNotice();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('public-explore-partial'),
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ReaduoColors.accentTint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      'Some public collections are unavailable. Results may be incomplete.',
    ),
  );
}

class _PublicExploreLoader extends StatefulWidget {
  const _PublicExploreLoader({
    required this.viewerId,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.limit,
    required this.builder,
    this.ownerId,
  });

  final String viewerId;
  final String? ownerId;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final int limit;
  final Widget Function(
    BuildContext context,
    _PublicExploreLoadState state,
    VoidCallback retry,
  )
  builder;

  @override
  State<_PublicExploreLoader> createState() => _PublicExploreLoaderState();
}

class _PublicExploreLoaderState extends State<_PublicExploreLoader> {
  StreamSubscription<PublicShelfReferencePage>? _directorySubscription;
  StreamSubscription<List<Shelf>>? _ownerShelfSubscription;
  final Map<_ExploreSourceKey, StreamSubscription<Shelf?>> _shelfSubscriptions =
      {};
  final Map<String, StreamSubscription<ReaderProfile?>> _profileSubscriptions =
      {};
  final Map<_ExploreSourceKey, StreamSubscription<List<LibraryBook>>>
  _bookSubscriptions = {};
  final Map<_ExploreSourceKey, PublicShelfReference> _references = {};
  final Map<_ExploreSourceKey, Shelf> _shelves = {};
  final Map<String, ReaderProfile> _profiles = {};
  final Map<_ExploreSourceKey, List<LibraryBook>> _books = {};
  final Set<_ExploreSourceKey> _loadedShelves = {};
  final Set<_ExploreSourceKey> _loadedBooks = {};
  final Set<String> _loadedProfiles = {};
  bool _directoryLoaded = false;
  bool _directoryHasMore = false;
  bool _partialFailure = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant _PublicExploreLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerId != widget.viewerId ||
        oldWidget.ownerId != widget.ownerId ||
        oldWidget.friendRepository != widget.friendRepository ||
        oldWidget.shelfRepository != widget.shelfRepository ||
        oldWidget.bookRepository != widget.bookRepository ||
        oldWidget.limit != widget.limit) {
      _restart();
    }
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  void _cancelAll() {
    _generation += 1;
    unawaited(_directorySubscription?.cancel());
    unawaited(_ownerShelfSubscription?.cancel());
    for (final subscription in _shelfSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    for (final subscription in _profileSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    for (final subscription in _bookSubscriptions.values) {
      unawaited(subscription.cancel());
    }
  }

  void _restart() {
    _cancelAll();
    final generation = _generation;
    _directorySubscription = null;
    _ownerShelfSubscription = null;
    _shelfSubscriptions.clear();
    _profileSubscriptions.clear();
    _bookSubscriptions.clear();
    _references.clear();
    _shelves.clear();
    _profiles.clear();
    _books.clear();
    _loadedShelves.clear();
    _loadedBooks.clear();
    _loadedProfiles.clear();
    _directoryLoaded = false;
    _directoryHasMore = false;
    _partialFailure = false;
    _error = null;
    final ownerId = widget.ownerId;
    if (ownerId == null) {
      _directorySubscription = widget.shelfRepository
          .watchPublicShelfReferencePage(
            viewerId: widget.viewerId,
            limit: widget.limit,
          )
          .listen(
            (page) => _updateReferences(generation, page),
            onError: (Object error) => _fail(generation, error),
          );
    } else {
      _ownerShelfSubscription = widget.shelfRepository
          .watchPublicShelvesByOwner(
            viewerId: widget.viewerId,
            ownerId: ownerId,
          )
          .listen(
            (shelves) => _updateOwnerShelves(generation, ownerId, shelves),
            onError: (Object error) => _fail(generation, error),
          );
    }
    if (mounted) setState(() {});
  }

  void _updateReferences(int generation, PublicShelfReferencePage page) {
    if (!mounted || generation != _generation) return;
    final valid = page.references
        .where(
          (reference) =>
              reference.ownerId.isNotEmpty &&
              reference.ownerId != widget.viewerId &&
              reference.shelfId.isNotEmpty,
        )
        .toList();
    final nextKeys = valid
        .map(
          (reference) =>
              _ExploreSourceKey(reference.ownerId, reference.shelfId),
        )
        .toSet();
    _removeSources((key) => !nextKeys.contains(key));
    for (final reference in valid) {
      final key = _ExploreSourceKey(reference.ownerId, reference.shelfId);
      _references[key] = reference;
      _ensureProfile(generation, reference.ownerId);
      if (_shelfSubscriptions.containsKey(key)) continue;
      _shelfSubscriptions[key] = widget.shelfRepository
          .watchPublicShelf(
            viewerId: widget.viewerId,
            ownerId: reference.ownerId,
            shelfId: reference.shelfId,
          )
          .listen(
            (shelf) => _updateShelf(generation, key, shelf),
            onError: (Object _) => _failSource(generation, key),
          );
    }
    _directoryLoaded = true;
    _directoryHasMore = page.hasMore;
    _syncProfileSubscriptions();
    setState(() {});
  }

  void _updateOwnerShelves(
    int generation,
    String ownerId,
    List<Shelf> shelves,
  ) {
    if (!mounted || generation != _generation) return;
    final valid = shelves
        .where(
          (shelf) =>
              shelf.ownerId == ownerId &&
              ownerId != widget.viewerId &&
              shelf.visibility == ShelfVisibility.public,
        )
        .toList();
    final nextKeys = valid
        .map((shelf) => _ExploreSourceKey(ownerId, shelf.id))
        .toSet();
    _removeSources((key) => !nextKeys.contains(key));
    for (final shelf in valid) {
      final key = _ExploreSourceKey(ownerId, shelf.id);
      _references[key] = PublicShelfReference(
        ownerId: ownerId,
        shelfId: shelf.id,
      );
      _loadedShelves.add(key);
      _acceptShelf(generation, key, shelf);
    }
    _ensureProfile(generation, ownerId);
    _directoryLoaded = true;
    setState(() {});
  }

  void _ensureProfile(int generation, String ownerId) {
    if (_profileSubscriptions.containsKey(ownerId)) return;
    _profileSubscriptions[ownerId] = widget.friendRepository
        .watchPublicReaderProfile(viewerId: widget.viewerId, readerId: ownerId)
        .listen(
          (profile) {
            if (!mounted || generation != _generation) return;
            if (profile == null || profile.uid != ownerId) {
              _profiles.remove(ownerId);
            } else {
              _profiles[ownerId] = profile;
            }
            _loadedProfiles.add(ownerId);
            setState(() {});
          },
          onError: (Object error) {
            if (widget.ownerId != null) {
              _fail(generation, error);
            } else {
              _failOwner(generation, ownerId);
            }
          },
        );
  }

  void _updateShelf(int generation, _ExploreSourceKey key, Shelf? shelf) {
    if (!mounted ||
        generation != _generation ||
        !_references.containsKey(key)) {
      return;
    }
    _loadedShelves.add(key);
    if (shelf == null ||
        shelf.ownerId != key.friendId ||
        shelf.visibility != ShelfVisibility.public) {
      _dropShelf(key);
    } else {
      _acceptShelf(generation, key, shelf);
    }
    setState(() {});
  }

  void _acceptShelf(int generation, _ExploreSourceKey key, Shelf shelf) {
    _shelves[key] = shelf;
    if (_bookSubscriptions.containsKey(key)) return;
    _bookSubscriptions[key] = widget.bookRepository
        .watchOwnedSharedBooks(
          viewerId: widget.viewerId,
          ownerId: key.friendId,
          shelfId: key.shelfId,
        )
        .listen((books) {
          if (!mounted ||
              generation != _generation ||
              !_shelves.containsKey(key)) {
            return;
          }
          _books[key] = books
              .where(
                (book) =>
                    book.ownerId == key.friendId &&
                    book.shelfId == key.shelfId &&
                    book.isOwned,
              )
              .toList();
          _loadedBooks.add(key);
          setState(() {});
        }, onError: (Object _) => _failBookSource(generation, key));
  }

  void _dropShelf(_ExploreSourceKey key) {
    _shelves.remove(key);
    _books.remove(key);
    _loadedBooks.remove(key);
    unawaited(_bookSubscriptions.remove(key)?.cancel());
  }

  void _removeSources(bool Function(_ExploreSourceKey key) remove) {
    final keys = _references.keys.where(remove).toList();
    for (final key in keys) {
      _references.remove(key);
      _loadedShelves.remove(key);
      unawaited(_shelfSubscriptions.remove(key)?.cancel());
      _dropShelf(key);
    }
    _syncProfileSubscriptions();
  }

  void _syncProfileSubscriptions() {
    final owners = _references.values
        .map((reference) => reference.ownerId)
        .toSet();
    if (widget.ownerId != null) owners.add(widget.ownerId!);
    final removed = _profileSubscriptions.keys
        .where((ownerId) => !owners.contains(ownerId))
        .toList();
    for (final ownerId in removed) {
      unawaited(_profileSubscriptions.remove(ownerId)?.cancel());
      _loadedProfiles.remove(ownerId);
      _profiles.remove(ownerId);
    }
  }

  void _failSource(int generation, _ExploreSourceKey key) {
    if (!mounted || generation != _generation) return;
    _partialFailure = true;
    _loadedShelves.add(key);
    _dropShelf(key);
    setState(() {});
  }

  void _failBookSource(int generation, _ExploreSourceKey key) {
    if (!mounted || generation != _generation) return;
    _partialFailure = true;
    _books.remove(key);
    _loadedBooks.add(key);
    setState(() {});
  }

  void _failOwner(int generation, String ownerId) {
    if (!mounted || generation != _generation) return;
    _partialFailure = true;
    _profiles.remove(ownerId);
    _loadedProfiles.add(ownerId);
    setState(() {});
  }

  void _fail(int generation, Object error) {
    if (!mounted || generation != _generation) return;
    setState(() {
      _error = switch (error) {
        FriendFailure failure => failure.message,
        ShelfFailure failure => failure.message,
        BookFailure failure => failure.message,
        _ => 'Readuo could not load public collections. Please retry.',
      };
    });
  }

  _PublicExploreLoadState get _state {
    final owners = _references.values
        .map((reference) => reference.ownerId)
        .toSet();
    if (widget.ownerId != null) owners.add(widget.ownerId!);
    final loading =
        !_directoryLoaded ||
        _references.keys.any((key) => !_loadedShelves.contains(key)) ||
        _shelves.keys.any((key) => !_loadedBooks.contains(key)) ||
        owners.any((ownerId) => !_loadedProfiles.contains(ownerId));
    final collections = <FriendsExploreCollection>[];
    for (final entry in _shelves.entries) {
      final profile = _profiles[entry.key.friendId];
      if (profile == null) continue;
      final books = _books[entry.key] ?? const <LibraryBook>[];
      if (books.isEmpty && widget.ownerId == null) continue;
      collections.add(
        FriendsExploreCollection(
          friend: profile,
          shelf: entry.value,
          books: books,
        ),
      );
    }
    collections.sort((left, right) {
      final readerOrder = left.friend.displayName.toLowerCase().compareTo(
        right.friend.displayName.toLowerCase(),
      );
      return readerOrder != 0
          ? readerOrder
          : left.shelf.name.toLowerCase().compareTo(
              right.shelf.name.toLowerCase(),
            );
    });
    return _PublicExploreLoadState(
      loading: loading,
      error: _error,
      partialFailure: _partialFailure,
      hasMore: widget.ownerId == null && _directoryLoaded && _directoryHasMore,
      reader: widget.ownerId == null ? null : _profiles[widget.ownerId],
      collections: collections,
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _state, _restart);
}

class _PublicExploreLoadState {
  const _PublicExploreLoadState({
    required this.loading,
    required this.error,
    required this.partialFailure,
    required this.hasMore,
    required this.reader,
    required this.collections,
  });

  final bool loading;
  final String? error;
  final bool partialFailure;
  final bool hasMore;
  final ReaderProfile? reader;
  final List<FriendsExploreCollection> collections;
}

bool _publicBookMatches(LibraryBook book, String rawQuery) {
  final normalized = normalizeLibraryText(rawQuery);
  if (normalized.isEmpty) return true;
  final compact = rawQuery.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  final isbnShaped = RegExp(r'^(?:\d{9}[\dX]|\d{13})$').hasMatch(compact);
  if (isbnShaped) {
    try {
      final canonical = Isbn.normalizeOptional(compact);
      final stored = book.isbn == null
          ? null
          : Isbn.normalizeOptional(book.isbn!);
      return canonical != null && canonical == stored;
    } on IsbnValidationException {
      return false;
    }
  }
  return normalizeLibraryText(book.title).contains(normalized) ||
      normalizeLibraryText(book.author).contains(normalized);
}

class FriendsExploreCollection {
  const FriendsExploreCollection({
    required this.friend,
    required this.shelf,
    required this.books,
  });

  final ReaderProfile friend;
  final Shelf shelf;
  final List<LibraryBook> books;
}

class _ExploreLoadState {
  const _ExploreLoadState({
    required this.loading,
    required this.error,
    required this.collections,
    this.friendIds = const {},
  });

  final bool loading;
  final String? error;
  final List<FriendsExploreCollection> collections;
  final Set<String> friendIds;
}

class _ExploreSourceKey {
  const _ExploreSourceKey(this.friendId, this.shelfId);

  final String friendId;
  final String shelfId;

  @override
  bool operator ==(Object other) =>
      other is _ExploreSourceKey &&
      other.friendId == friendId &&
      other.shelfId == shelfId;

  @override
  int get hashCode => Object.hash(friendId, shelfId);
}

class _LibrarySwitcher extends StatelessWidget {
  const _LibrarySwitcher({required this.onMyLibrary});

  final VoidCallback onMyLibrary;

  @override
  Widget build(BuildContext context) => ReaduoSectionTabs(
    labels: const ['My Library', 'Explore'],
    selected: 1,
    tabKeys: const [Key('explore-my-library'), Key('explore-selected')],
    onSelected: (index) {
      if (index == 0) onMyLibrary();
    },
  );
}

class _ExploreSearchField extends StatelessWidget {
  const _ExploreSearchField({
    required this.controller,
    required this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('friends-explore-search-field'),
    controller: controller,
    onChanged: onChanged,
    onSubmitted: (_) => onSubmitted(),
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: 'Title, author or ISBN',
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: TextButton(
        key: const Key('friends-explore-search-submit'),
        onPressed: onSubmitted,
        child: const Text('Search'),
      ),
      filled: true,
      fillColor: ReaduoColors.paper,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ReaduoColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ReaduoColors.line),
      ),
    ),
  );
}

class _ExploreScopeChips extends StatelessWidget {
  const _ExploreScopeChips({
    required this.onFriends,
    required this.onPublic,
    this.publicSelected = false,
  });

  final VoidCallback onFriends;
  final VoidCallback onPublic;
  final bool publicSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      ActionChip(
        key: const Key('explore-friends-filter'),
        onPressed: onFriends,
        backgroundColor: publicSelected
            ? ReaduoColors.paper
            : ReaduoColors.accentTint,
        side: BorderSide(
          color: publicSelected ? ReaduoColors.line : const Color(0xFFC9D5FF),
        ),
        label: Text(
          'Friends',
          style: TextStyle(
            color: publicSelected ? ReaduoColors.ink : ReaduoColors.accent,
            fontWeight: publicSelected ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
      ),
      ActionChip(
        key: const Key('explore-public-filter'),
        onPressed: onPublic,
        backgroundColor: publicSelected
            ? ReaduoColors.accentTint
            : ReaduoColors.paper,
        side: BorderSide(
          color: publicSelected ? const Color(0xFFC9D5FF) : ReaduoColors.line,
        ),
        label: Text(
          'Public',
          style: TextStyle(
            color: publicSelected ? ReaduoColors.accent : ReaduoColors.ink,
            fontWeight: publicSelected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    ],
  );
}

class _ExploreCollectionCard extends StatelessWidget {
  const _ExploreCollectionCard({
    required this.collection,
    required this.onOpenProfile,
    required this.onOpenShelf,
    required this.onOpenBook,
    this.publicAccess = false,
    this.showReaderHeader = true,
  });

  final FriendsExploreCollection collection;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenShelf;
  final ValueChanged<LibraryBook> onOpenBook;
  final bool publicAccess;
  final bool showReaderHeader;

  @override
  Widget build(BuildContext context) {
    final books = collection.books.take(3).toList();
    return Card(
      key: Key('explore-shelf-${collection.shelf.id}'),
      margin: EdgeInsets.zero,
      color: ReaduoColors.paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: ReaduoColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (showReaderHeader) ...[
              Row(
                children: [
                  _ReaderInitials(friend: collection.friend),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          publicAccess
                              ? collection.friend.displayName
                              : '${collection.friend.displayName}’s collection',
                          style: const TextStyle(
                            color: ReaduoColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          publicAccess
                              ? 'Public collection · not connected'
                              : 'Shared with you',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('explore-profile-${collection.friend.uid}'),
                    onPressed: onOpenProfile,
                    tooltip: 'View ${collection.friend.displayName} profile',
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < books.length; index++) ...[
                  if (index > 0) const SizedBox(width: 12),
                  SizedBox(
                    width: 72,
                    child: InkWell(
                      key: Key('explore-book-${books[index].id}'),
                      onTap: () => onOpenBook(books[index]),
                      borderRadius: BorderRadius.circular(9),
                      child: _ExploreCover(book: books[index]),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              key: Key('explore-open-shelf-${collection.shelf.id}'),
              contentPadding: EdgeInsets.zero,
              onTap: onOpenShelf,
              title: Text(collection.shelf.name),
              subtitle: Text(
                '${collection.books.length} owned ${collection.books.length == 1 ? 'book' : 'books'}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreSearchResult extends StatelessWidget {
  const _ExploreSearchResult({
    required this.collection,
    required this.book,
    required this.onOpenBook,
    required this.onOpenShelf,
    this.publicAccess = false,
  });

  final FriendsExploreCollection collection;
  final LibraryBook book;
  final VoidCallback onOpenBook;
  final VoidCallback onOpenShelf;
  final bool publicAccess;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: ReaduoColors.paper,
    elevation: 0,
    child: Column(
      children: [
        ListTile(
          key: Key('explore-search-book-${book.id}'),
          onTap: onOpenBook,
          leading: SizedBox(width: 42, child: _ExploreCover(book: book)),
          title: Text(book.title),
          subtitle: Text(book.author),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        const Divider(height: 1),
        ListTile(
          key: Key('explore-search-shelf-${collection.shelf.id}'),
          onTap: onOpenShelf,
          leading: _ReaderInitials(friend: collection.friend, radius: 16),
          title: Text(collection.friend.displayName),
          subtitle: Text(
            '${collection.shelf.name} · ${publicAccess ? 'Public' : 'Friends'} shelf',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
}

class _ExploreEmpty extends StatelessWidget {
  const _ExploreEmpty({required this.onPublic, required this.onInvite});

  final VoidCallback onPublic;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) => _ExploreMessage(
    key: const Key('friends-explore-empty'),
    icon: Icons.local_library_outlined,
    title: 'No shared books yet',
    message: 'Your friends haven’t shared any owned books with you yet.',
    actionLabel: 'Explore public shelves',
    onAction: onPublic,
    secondaryLabel: 'Invite another friend',
    onSecondary: onInvite,
  );
}

class _ExploreMessage extends StatelessWidget {
  const _ExploreMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: ReaduoColors.accentTint,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Icon(icon, color: ReaduoColors.accent, size: 32),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: ReaduoColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        if (secondaryLabel != null && onSecondary != null)
          TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
      ],
    ),
  );
}

class _ReaderInitials extends StatelessWidget {
  const _ReaderInitials({required this.friend, this.radius = 20});

  final ReaderProfile friend;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final parts = friend.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials = parts.take(2).map((part) => part[0].toUpperCase()).join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: ReaduoColors.accentTint,
      foregroundImage: friend.photoUrl == null
          ? null
          : ReaduoImageCache.image(friend.photoUrl!),
      child: friend.photoUrl == null
          ? Text(
              initials,
              style: const TextStyle(
                color: ReaduoColors.accent,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _ExploreCover extends StatelessWidget {
  const _ExploreCover({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: .68,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: book.coverUrl == null
          ? Container(
              color: ReaduoColors.accentTint,
              padding: const EdgeInsets.all(8),
              alignment: Alignment.center,
              child: Text(
                book.title,
                maxLines: 4,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ReaduoColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : BookCoverImage(
              book.coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: ReaduoColors.accentTint,
                child: const Icon(Icons.menu_book_rounded),
              ),
            ),
    ),
  );
}
