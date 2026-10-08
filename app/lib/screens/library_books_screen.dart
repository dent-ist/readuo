import '../widgets/book_cover_image.dart';
import '../widgets/generated_book_cover.dart';
import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/book_repository.dart';
import '../library/isbn.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';
import '../widgets/readuo_bottom_navigation.dart';

enum LibraryBookSort { recent, title, author }

extension LibraryBookSortDetails on LibraryBookSort {
  String get label => switch (this) {
    LibraryBookSort.recent => 'Recently added',
    LibraryBookSort.title => 'Title · A to Z',
    LibraryBookSort.author => 'Author · A to Z',
  };
}

class LibraryBooksScreen extends StatefulWidget {
  const LibraryBooksScreen({
    required this.ownerId,
    required this.bookRepository,
    required this.onOpenBook,
    required this.onSearch,
    required this.onAddBooks,
    this.onOpenLibrary,
    this.onOpenFriends,
    this.onOpenProfile,
    this.showBottomNavigation = true,
    super.key,
  });

  final String ownerId;
  final BookRepository bookRepository;
  final ValueChanged<LibraryBook> onOpenBook;
  final Future<void> Function(String query) onSearch;
  final VoidCallback onAddBooks;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenFriends;
  final VoidCallback? onOpenProfile;
  final bool showBottomNavigation;

  @override
  State<LibraryBooksScreen> createState() => _LibraryBooksScreenState();
}

class _LibraryBooksScreenState extends State<LibraryBooksScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  late Stream<List<LibraryBook>> _books;
  ReadingStatus? _filter;
  LibraryBookSort _sort = LibraryBookSort.recent;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void didUpdateWidget(covariant LibraryBooksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.bookRepository != widget.bookRepository) {
      _loadBooks();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadBooks() {
    _books = widget.bookRepository.watchLibraryBooks(widget.ownerId);
  }

  Future<void> _submitSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    await widget.onSearch(query);
  }

  Future<void> _chooseSort() async {
    final selected = await showModalBottomSheet<LibraryBookSort>(
      context: context,
      useRootNavigator: !widget.showBottomNavigation,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (_) => _SortBooksSheet(initialSort: _sort),
    );
    if (selected != null && mounted) setState(() => _sort = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My books'),
        actions: [
          IconButton(
            key: const Key('all-books-add-button'),
            tooltip: 'Add books',
            onPressed: widget.onAddBooks,
            icon: const Icon(Icons.library_add_outlined),
          ),
        ],
      ),
      bottomNavigationBar: widget.showBottomNavigation
          ? ReaduoBottomNavigation(
              onLibrary:
                  widget.onOpenLibrary ?? () => Navigator.of(context).pop(),
              onFriends: widget.onOpenFriends,
              onProfile: widget.onOpenProfile,
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<LibraryBook>>(
          stream: _books,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _LibraryBooksError(
                message: snapshot.error is BookFailure
                    ? (snapshot.error! as BookFailure).message
                    : 'Readuo could not load your books.',
                onRetry: () => setState(_loadBooks),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final filtered =
                snapshot.data!
                    .where(
                      (book) =>
                          _filter == null || book.readingStatus == _filter,
                    )
                    .toList()
                  ..sort(
                    (left, right) => compareLibraryBooks(left, right, _sort),
                  );
            return ListView(
              key: const PageStorageKey('all-library-books-list'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                ReaduoSpacing.screenHorizontal,
                8,
                ReaduoSpacing.screenHorizontal,
                28,
              ),
              children: [
                LibrarySearchField(
                  key: const Key('all-books-search-field'),
                  controller: _searchController,
                  onSearch: _submitSearch,
                ),
                const SizedBox(height: 16),
                _StatusFilters(
                  selected: _filter,
                  onSelected: (status) => setState(() => _filter = status),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _filter == null
                            ? '${filtered.length} ${filtered.length == 1 ? 'book' : 'books'}'
                            : '${filtered.length} ${_filter!.label.toLowerCase()}',
                        key: const Key('all-books-result-count'),
                        style: const TextStyle(
                          fontSize: 14,
                          color: ReaduoColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('sort-books-button'),
                      onPressed: _chooseSort,
                      icon: const Icon(Icons.swap_vert_rounded, size: 18),
                      label: const Text('Sort'),
                    ),
                  ],
                ),
                Text(
                  _sort.label,
                  key: const Key('all-books-sort-label'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  _FilterEmpty(
                    hasBooks: snapshot.data!.isNotEmpty,
                    onShowAll: () => setState(() => _filter = null),
                  )
                else
                  for (final book in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LibraryBookRow(
                        key: Key('all-books-${book.shelfId}-${book.id}'),
                        book: book,
                        onTap: () => widget.onOpenBook(book),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class LibrarySearchScreen extends StatefulWidget {
  const LibrarySearchScreen({
    required this.ownerId,
    required this.initialQuery,
    required this.bookRepository,
    required this.shelfRepository,
    required this.onOpenBook,
    required this.onOpenShelf,
    required this.onSearchCatalogue,
    super.key,
  });

  final String ownerId;
  final String initialQuery;
  final BookRepository bookRepository;
  final ShelfRepository shelfRepository;
  final ValueChanged<LibraryBook> onOpenBook;
  final ValueChanged<Shelf> onOpenShelf;
  final VoidCallback onSearchCatalogue;

  @override
  State<LibrarySearchScreen> createState() => _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends State<LibrarySearchScreen> {
  late final TextEditingController _searchController;
  final _scrollController = ScrollController();
  late Stream<List<LibraryBook>> _books;
  late Stream<List<Shelf>> _shelves;
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = normalizeLibraryText(widget.initialQuery);
    _searchController = TextEditingController(text: widget.initialQuery.trim());
    _loadLibrary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadLibrary() {
    _books = widget.bookRepository.watchLibraryBooks(widget.ownerId);
    _shelves = widget.shelfRepository.watchShelves(widget.ownerId);
  }

  void _search() {
    FocusScope.of(context).unfocus();
    setState(() => _query = normalizeLibraryText(_searchController.text));
  }

  void _clear() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search my library')),
      body: SafeArea(
        child: StreamBuilder<List<Shelf>>(
          stream: _shelves,
          builder: (context, shelfSnapshot) {
            if (shelfSnapshot.hasError) {
              return _LibraryBooksError(
                message: 'Readuo could not load your shelves.',
                onRetry: () => setState(_loadLibrary),
              );
            }
            if (!shelfSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder<List<LibraryBook>>(
              stream: _books,
              builder: (context, bookSnapshot) {
                if (bookSnapshot.hasError) {
                  return _LibraryBooksError(
                    message: bookSnapshot.error is BookFailure
                        ? (bookSnapshot.error! as BookFailure).message
                        : 'Readuo could not search your books.',
                    onRetry: () => setState(_loadLibrary),
                  );
                }
                if (!bookSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final matches =
                    _query.isEmpty
                          ? <LibraryBook>[]
                          : bookSnapshot.data!
                                .where(
                                  (book) => libraryBookMatches(book, _query),
                                )
                                .toList()
                      ..sort(
                        (left, right) => compareLibraryBooks(
                          left,
                          right,
                          LibraryBookSort.recent,
                        ),
                      );
                final matchingShelfIds = matches
                    .map((book) => book.shelfId)
                    .toSet();
                final containingShelves =
                    shelfSnapshot.data!
                        .where((shelf) => matchingShelfIds.contains(shelf.id))
                        .toList()
                      ..sort((left, right) {
                        final byName = normalizeLibraryText(
                          left.name,
                        ).compareTo(normalizeLibraryText(right.name));
                        return byName != 0
                            ? byName
                            : left.id.compareTo(right.id);
                      });
                return ListView(
                  key: const PageStorageKey('library-search-results-list'),
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    ReaduoSpacing.screenHorizontal,
                    8,
                    ReaduoSpacing.screenHorizontal,
                    28,
                  ),
                  children: [
                    LibrarySearchField(
                      key: const Key('library-search-results-field'),
                      controller: _searchController,
                      onSearch: _search,
                      onClear: _clear,
                    ),
                    const SizedBox(height: 18),
                    if (_query.isEmpty)
                      _SearchPrompt(onSearchCatalogue: widget.onSearchCatalogue)
                    else if (matches.isEmpty)
                      _SearchEmpty(onSearchCatalogue: widget.onSearchCatalogue)
                    else ...[
                      Text(
                        '${matches.length} ${matches.length == 1 ? 'book' : 'books'} · Owned and saved entries',
                        key: const Key('library-search-result-count'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      for (final book in matches)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LibraryBookRow(
                            key: Key('search-book-${book.shelfId}-${book.id}'),
                            book: book,
                            onTap: () => widget.onOpenBook(book),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Containing shelves',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: ReaduoColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final shelf in containingShelves)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ContainingShelfRow(
                            shelf: shelf,
                            actualBookCount: bookSnapshot.data!
                                .where((book) => book.shelfId == shelf.id)
                                .length,
                            onTap: () => widget.onOpenShelf(shelf),
                          ),
                        ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class LibrarySearchField extends StatefulWidget {
  const LibrarySearchField({
    required this.controller,
    required this.onSearch,
    this.onClear,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;

  @override
  State<LibrarySearchField> createState() => _LibrarySearchFieldState();
}

class _LibrarySearchFieldState extends State<LibrarySearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant LibrarySearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _clear() {
    widget.controller.clear();
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    return TextField(
      controller: widget.controller,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSearch(),
      decoration: InputDecoration(
        hintText: 'Search my books',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIconConstraints: const BoxConstraints(minHeight: 48),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText)
              IconButton(
                key: const Key('clear-library-search'),
                tooltip: 'Clear search',
                onPressed: _clear,
                icon: const Icon(Icons.close_rounded),
              ),
            TextButton(
              key: const Key('submit-library-search'),
              onPressed: hasText ? widget.onSearch : null,
              child: const Text('Search'),
            ),
          ],
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
}

class LibraryBookRow extends StatelessWidget {
  const LibraryBookRow({required this.book, required this.onTap, super.key});

  final LibraryBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ReaduoColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: ReaduoColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _LibraryBookCover(book: book),
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
                        color: ReaduoColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _BookBadge(
                          label: book.readingStatus.label,
                          color: ReaduoColors.accent,
                          background: ReaduoColors.accentTint,
                        ),
                        _BookBadge(
                          label: book.isOwned ? 'Owned' : 'Not owned',
                          color: book.isOwned
                              ? const Color(0xFF287A55)
                              : ReaduoColors.muted,
                          background: book.isOwned
                              ? const Color(0xFFE4F4EA)
                              : const Color(0xFFF0F2F6),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: ReaduoColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortBooksSheet extends StatefulWidget {
  const _SortBooksSheet({required this.initialSort});

  final LibraryBookSort initialSort;

  @override
  State<_SortBooksSheet> createState() => _SortBooksSheetState();
}

class _SortBooksSheetState extends State<_SortBooksSheet> {
  late LibraryBookSort _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSort;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        0,
        ReaduoSpacing.screenHorizontal,
        20 + bottomInset + safeBottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sort books',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: ReaduoColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          RadioGroup<LibraryBookSort>(
            groupValue: _selected,
            onChanged: (value) {
              if (value != null) setState(() => _selected = value);
            },
            child: Column(
              children: [
                for (final sort in LibraryBookSort.values)
                  RadioListTile<LibraryBookSort>(
                    key: Key('sort-${sort.name}'),
                    value: sort,
                    title: Text(sort.label),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('apply-book-sort'),
            onPressed: () => Navigator.of(context).pop(_selected),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({required this.selected, required this.onSelected});

  final ReadingStatus? selected;
  final ValueChanged<ReadingStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final status in ReadingStatus.values) ...[
            if (status != ReadingStatus.values.first) const SizedBox(width: 8),
            ChoiceChip(
              key: Key('filter-${status.name}'),
              label: Text(status.label),
              selected: selected == status,
              onSelected: (value) => onSelected(value ? status : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContainingShelfRow extends StatelessWidget {
  const _ContainingShelfRow({
    required this.shelf,
    required this.actualBookCount,
    required this.onTap,
  });

  final Shelf shelf;
  final int actualBookCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ReaduoColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: ReaduoColors.line),
      ),
      child: ListTile(
        key: Key('search-shelf-${shelf.id}'),
        onTap: onTap,
        leading: const Icon(
          Icons.local_library_outlined,
          color: ReaduoColors.accent,
        ),
        title: Text(
          shelf.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '$actualBookCount ${actualBookCount == 1 ? 'book' : 'books'}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty({required this.hasBooks, required this.onShowAll});

  final bool hasBooks;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return _EmptyCard(
      icon: Icons.fact_check_outlined,
      title: hasBooks ? 'No books in this status' : 'No books yet',
      message: hasBooks
          ? 'Change a book’s status or show all books.'
          : 'Books you save will appear here.',
      actionLabel: hasBooks ? 'Show all books' : null,
      onAction: hasBooks ? onShowAll : null,
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt({required this.onSearchCatalogue});

  final VoidCallback onSearchCatalogue;

  @override
  Widget build(BuildContext context) {
    return _EmptyCard(
      icon: Icons.search_rounded,
      title: 'Search your saved books',
      message: 'Use a title, author, or ISBN from your own library.',
      actionLabel: 'Search catalogue',
      onAction: onSearchCatalogue,
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({required this.onSearchCatalogue});

  final VoidCallback onSearchCatalogue;

  @override
  Widget build(BuildContext context) {
    return _EmptyCard(
      icon: Icons.search_off_rounded,
      title: 'No matches in your library',
      message:
          'Try another title, author, or ISBN. You can search the catalogue to add a new book.',
      actionLabel: 'Search catalogue',
      onAction: onSearchCatalogue,
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: ReaduoColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ReaduoColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: ReaduoColors.accent),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: Key(
                'empty-action-${actionLabel!.toLowerCase().replaceAll(' ', '-')}',
              ),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibraryBookCover extends StatelessWidget {
  const _LibraryBookCover({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 66,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ReaduoColors.accentTint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: book.coverUrl == null
          ? GeneratedBookCover(title: book.title, author: book.author)
          : BookCoverImage(
              book.coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.book_outlined, color: ReaduoColors.accent),
            ),
    );
  }
}

class _BookBadge extends StatelessWidget {
  const _BookBadge({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LibraryBooksError extends StatelessWidget {
  const _LibraryBooksError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ReaduoSpacing.screenHorizontal,
          vertical: 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String normalizeLibraryText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

bool libraryBookMatches(LibraryBook book, String normalizedQuery) {
  if (normalizedQuery.isEmpty) return true;
  if (normalizeLibraryText(book.title).contains(normalizedQuery) ||
      normalizeLibraryText(book.author).contains(normalizedQuery)) {
    return true;
  }
  final isbnQuery = RegExp(
    r'^(?:isbn(?:-1[03])?\s*:?\s*)?([0-9x](?:[0-9x -]*[0-9x])?)$',
    caseSensitive: false,
  ).firstMatch(normalizedQuery);
  if (isbnQuery == null) return false;
  final compactQuery = isbnQuery
      .group(1)!
      .toUpperCase()
      .replaceAll(RegExp(r'[ -]'), '');
  if (!RegExp(r'^(?:[0-9]{4,13}|[0-9]{9}X)$').hasMatch(compactQuery)) {
    return false;
  }
  final storedIsbn = book.isbn;
  if (storedIsbn == null) return false;
  String? canonical;
  try {
    canonical = Isbn.normalizeOptional(compactQuery);
  } on IsbnValidationException {
    canonical = null;
  }
  if (canonical != null && canonical == storedIsbn) return true;
  return storedIsbn.contains(compactQuery);
}

int compareLibraryBooks(
  LibraryBook left,
  LibraryBook right,
  LibraryBookSort sort,
) {
  final byPrimary = switch (sort) {
    LibraryBookSort.recent => _compareDatesDescending(
      left.createdAt,
      right.createdAt,
    ),
    LibraryBookSort.title => normalizeLibraryText(
      left.title,
    ).compareTo(normalizeLibraryText(right.title)),
    LibraryBookSort.author => normalizeLibraryText(
      left.author,
    ).compareTo(normalizeLibraryText(right.author)),
  };
  if (byPrimary != 0) return byPrimary;
  final byTitle = normalizeLibraryText(
    left.title,
  ).compareTo(normalizeLibraryText(right.title));
  if (byTitle != 0) return byTitle;
  final byAuthor = normalizeLibraryText(
    left.author,
  ).compareTo(normalizeLibraryText(right.author));
  if (byAuthor != 0) return byAuthor;
  final byShelf = left.shelfId.compareTo(right.shelfId);
  return byShelf != 0 ? byShelf : left.id.compareTo(right.id);
}

int _compareDatesDescending(DateTime? left, DateTime? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return right.compareTo(left);
}
