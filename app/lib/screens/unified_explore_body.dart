part of 'friends_explore_screen.dart';

class ExploreBody extends StatefulWidget {
  const ExploreBody({
    required this.viewerId,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.onMyLibrary,
    required this.onOpenProfile,
    required this.onOpenShelf,
    required this.onOpenBook,
    this.searchMode = false,
    super.key,
  });

  final bool searchMode;
  final String viewerId;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final VoidCallback onMyLibrary;
  final Future<void> Function(ReaderProfile reader, bool isFriend)
  onOpenProfile;
  final Future<void> Function(ReaderProfile reader, Shelf shelf, bool isFriend)
  onOpenShelf;
  final Future<void> Function(
    ReaderProfile reader,
    Shelf shelf,
    LibraryBook book,
    bool isFriend,
  )
  onOpenBook;

  @override
  State<ExploreBody> createState() => _ExploreBodyState();
}

class _ExploreBodyState extends State<ExploreBody> {
  final _search = TextEditingController();
  int _publicLimit = 20;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FriendsExploreLoader(
    viewerId: widget.viewerId,
    friendRepository: widget.friendRepository,
    shelfRepository: widget.shelfRepository,
    bookRepository: widget.bookRepository,
    builder: (context, friends, retryFriends) => _PublicExploreLoader(
      viewerId: widget.viewerId,
      friendRepository: widget.friendRepository,
      shelfRepository: widget.shelfRepository,
      bookRepository: widget.bookRepository,
      limit: _publicLimit,
      builder: (context, public, retryPublic) {
        final copies = <String, _ExploreCopy>{};
        void collect(
          List<FriendsExploreCollection> collections,
          bool fromFriends,
        ) {
          for (final collection in collections) {
            for (final book in collection.books) {
              final copy = _ExploreCopy(
                collection,
                book,
                fromFriends ||
                    friends.friendIds.contains(collection.friend.uid),
              );
              copies.putIfAbsent(copy.id, () => copy);
            }
          }
        }

        if (friends.error == null) collect(friends.collections, true);
        if (public.error == null) collect(public.collections, false);
        final query = normalizeLibraryText(_search.text);
        final groups = <String, List<_ExploreCopy>>{};
        for (final copy in copies.values) {
          (groups[copy.editionKey] ??= []).add(copy);
        }
        final matches =
            groups.entries
                .where(
                  (entry) => entry.value.any(
                    (copy) =>
                        query.isEmpty ||
                        _publicBookMatches(copy.book, _search.text) ||
                        normalizeLibraryText(
                          copy.collection.friend.displayName,
                        ).contains(query) ||
                        normalizeLibraryText(
                          copy.collection.shelf.name,
                        ).contains(query),
                  ),
                )
                .toList()
              ..sort(
                (a, b) => normalizeLibraryText(
                  a.value.first.book.title,
                ).compareTo(normalizeLibraryText(b.value.first.book.title)),
              );
        final loading =
            (friends.loading && friends.error == null) ||
            (public.loading && public.error == null);
        final failed =
            friends.error != null ||
            public.error != null ||
            public.partialFailure;
        void retry() {
          retryFriends();
          retryPublic();
        }

        return CustomScrollView(
          key: const Key('unified-explore'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (!widget.searchMode)
                      _LibrarySwitcher(onMyLibrary: widget.onMyLibrary),
                    if (widget.searchMode)
                      TextField(
                        autofocus: true,
                        key: const Key('explore-search-field'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search books or libraries',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () => setState(_search.clear),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: ReaduoColors.paper,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: ReaduoColors.line,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: ReaduoColors.line,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (failed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          copies.isEmpty
                              ? 'Libraries couldn’t be loaded.'
                              : 'Some libraries couldn’t be loaded.',
                        ),
                      ),
                      TextButton(onPressed: retry, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            if (matches.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: loading
                        ? const CircularProgressIndicator()
                        : failed && copies.isEmpty
                        ? const SizedBox.shrink()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                query.isEmpty
                                    ? 'Nothing to explore yet'
                                    : 'No books found',
                                key: const Key('explore-empty-title'),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                query.isEmpty
                                    ? 'Books shared by friends and the community will appear here.'
                                    : 'Try another title, author, or library name.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: ReaduoColors.muted,
                                  height: 1.5,
                                ),
                              ),
                              if (public.hasMore) _moreLibraries(),
                            ],
                          ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final entry = matches[index];
                    return _ExploreBookRow(
                      key: ValueKey(entry.key),
                      copies: entry.value,
                      onOpenBook: (copy) => widget.onOpenBook(
                        copy.collection.friend,
                        copy.collection.shelf,
                        copy.book,
                        copy.isFriend,
                      ),
                      onOpenShelf: (copy) => widget.onOpenShelf(
                        copy.collection.friend,
                        copy.collection.shelf,
                        copy.isFriend,
                      ),
                      onOpenProfile: (copy) => widget.onOpenProfile(
                        copy.collection.friend,
                        copy.isFriend,
                      ),
                    );
                  },
                ),
              ),
              if (loading)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (public.hasMore && !loading)
                SliverToBoxAdapter(child: _moreLibraries()),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        );
      },
    ),
  );

  Widget _moreLibraries() => Padding(
    padding: const EdgeInsets.all(16),
    child: TextButton(
      key: const Key('explore-load-more'),
      onPressed: () => setState(() => _publicLimit += 20),
      child: const Text('Load more libraries'),
    ),
  );
}

class _ExploreCopy {
  const _ExploreCopy(this.collection, this.book, this.isFriend);
  final FriendsExploreCollection collection;
  final LibraryBook book;
  final bool isFriend;
  String get id => '${book.ownerId}/${book.shelfId}/${book.id}';
  String get editionKey {
    try {
      final isbn = Isbn.normalizeOptional(book.isbn ?? '');
      if (isbn != null) return 'isbn:$isbn';
    } on IsbnValidationException {
      /* Keep unidentified editions separate. */
    }
    return id;
  }
}

class _ExploreBookRow extends StatelessWidget {
  const _ExploreBookRow({
    required this.copies,
    required this.onOpenBook,
    required this.onOpenShelf,
    required this.onOpenProfile,
    super.key,
  });
  final List<_ExploreCopy> copies;
  final ValueChanged<_ExploreCopy> onOpenBook;
  final ValueChanged<_ExploreCopy> onOpenShelf;
  final ValueChanged<_ExploreCopy> onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final first = copies.first;
    final owners = {
      for (final copy in copies) copy.collection.friend.uid: copy,
    };
    final book = first.book;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: _ExploreCover(book: book)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'By ${book.author}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: ReaduoColors.muted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  InkWell(
                    key: ValueKey(
                      'explore-profile-${first.collection.friend.uid}',
                    ),
                    onTap: () => onOpenProfile(first),
                    child: Tooltip(
                      message:
                          'View ${first.collection.friend.displayName} profile',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _ExploreAvatar(copy: first),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      owners.length == 1
                          ? first.collection.friend.displayName
                          : 'In ${owners.length} libraries',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ReaduoColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (copies.any((copy) => copy.isFriend))
                Text(
                  owners.length == 1 ? 'Friend' : 'Includes a friend',
                  style: const TextStyle(
                    color: ReaduoColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: ReaduoColors.paper,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: copies.length == 1
            ? InkWell(
                key: ValueKey('explore-book-${book.id}'),
                onTap: () => onOpenBook(first),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(child: header),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: ReaduoColors.muted,
                      ),
                    ],
                  ),
                ),
              )
            : ExpansionTile(
                key: PageStorageKey('explore-group-${first.editionKey}'),
                tilePadding: const EdgeInsets.all(12),
                shape: const Border(),
                collapsedShape: const Border(),
                title: header,
                children: [
                  for (final copy in copies) ...[
                    const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: ReaduoColors.line,
                    ),
                    ListTile(
                      key: ValueKey('explore-copy-${copy.id}'),
                      leading: InkWell(
                        onTap: () => onOpenProfile(copy),
                        child: Tooltip(
                          message:
                              'View ${copy.collection.friend.displayName} profile',
                          child: _ExploreAvatar(copy: copy),
                        ),
                      ),
                      title: Text(
                        copy.collection.friend.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${copy.collection.shelf.name}${copy.isFriend ? ' · Friend' : ''}',
                      ),
                      onTap: () => onOpenBook(copy),
                      trailing: IconButton(
                        tooltip: 'Open ${copy.collection.shelf.name}',
                        icon: const Icon(Icons.shelves),
                        onPressed: () => onOpenShelf(copy),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ExploreAvatar extends StatelessWidget {
  const _ExploreAvatar({required this.copy});
  final _ExploreCopy copy;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: copy.isFriend ? ReaduoColors.accent : Colors.transparent,
        width: 1.5,
      ),
    ),
    child: _ReaderInitials(friend: copy.collection.friend, radius: 12),
  );
}
