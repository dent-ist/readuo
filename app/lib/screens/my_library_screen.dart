import '../widgets/book_cover_image.dart';
import '../widgets/generated_book_cover.dart';
import '../widgets/library_search_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_service.dart';
import '../circle/review_repository.dart';
import '../friends/friend_repository.dart';
import '../library/book.dart';
import '../library/book_lookup.dart';
import '../library/book_repository.dart';
import '../library/catalogue_repository.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';
import '../widgets/readuo_bottom_navigation.dart';
import '../widgets/readuo_section_tabs.dart';
import '../widgets/readuo_tab_header.dart';
import '../widgets/readuo_tab_activity.dart';
import 'account_screen.dart';
import 'book_details_screen.dart';
import 'catalogue_search_screen.dart';
import 'friends_explore_screen.dart';
import 'friends_screen.dart';
import 'isbn_scanner_screen.dart';
import 'library_books_screen.dart';
import 'shelf_details_screen.dart';

class MyLibraryScreen extends StatefulWidget {
  const MyLibraryScreen({
    required this.authService,
    required this.shelfRepository,
    required this.bookRepository,
    required this.bookLookupRepository,
    this.catalogueRepository = const EmptyCatalogueRepository(),
    this.reviewRepository = const EmptyReviewRepository(),
    required this.friendRepository,
    required this.user,
    this.showBottomNavigation = true,
    this.onSelectDestination,
    this.onNavigationBarVisibilityChanged,
    super.key,
  });
  final AuthService authService;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final BookLookupRepository bookLookupRepository;
  final CatalogueRepository catalogueRepository;
  final ReviewRepository reviewRepository;
  final FriendRepository friendRepository;
  final AuthUser user;
  final bool showBottomNavigation;
  final ValueChanged<ReaduoNavDestination>? onSelectDestination;
  final ValueChanged<bool>? onNavigationBarVisibilityChanged;
  @override
  State<MyLibraryScreen> createState() => _MyLibraryScreenState();
}

class _MyLibraryScreenState extends State<MyLibraryScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  late Stream<List<Shelf>> _shelves;
  late Stream<List<ShelfMutationOperation>> _operations;
  late Stream<List<LibraryBook>> _books;
  String _query = '';
  bool _searchExpanded = false;
  ReadingStatus? _readingStatus;
  String? _resumingOperationId;
  bool _scannerOpening = false;
  bool _addBooksOpening = false;
  bool _addExpanded = false;
  final _addFocus = FocusNode();
  bool _showExplore = false;
  bool _exploreVisited = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLibrary();
  }

  @override
  void didUpdateWidget(covariant MyLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.shelfRepository != widget.shelfRepository ||
        oldWidget.bookRepository != widget.bookRepository) {
      _addExpanded = false;
      _searchExpanded = false;
      _query = '';
      _searchController.clear();
      _showExplore = false;
      _exploreVisited = false;
      _loadLibrary();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ReaduoTabActivity.isActive(context)) _addExpanded = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _collapseAdd(restoreFocus: false);
  }

  void _collapseAdd({bool restoreFocus = true}) {
    if (!_addExpanded) return;
    setState(() => _addExpanded = false);
    if (restoreFocus) _addFocus.requestFocus();
  }

  void _loadLibrary() {
    _shelves = widget.shelfRepository.watchShelves(widget.user.uid);
    _operations = widget.shelfRepository.watchShelfOperations(widget.user.uid);
    _books = widget.bookRepository.watchLibraryBooks(widget.user.uid);
  }

  void _retry() => setState(_loadLibrary);

  Future<void> _resumeOperation(ShelfMutationOperation operation) async {
    if (_resumingOperationId != null) return;
    setState(() => _resumingOperationId = operation.id);
    try {
      await widget.shelfRepository.resumeShelfOperation(
        ownerId: widget.user.uid,
        sourceShelfId: operation.sourceShelfId,
      );
    } on ShelfFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _resumingOperationId = null);
    }
  }

  Future<Shelf?> _openCreateShelfForSelection() => showModalBottomSheet<Shelf>(
    context: context,
    useRootNavigator: !widget.showBottomNavigation,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: ReaduoColors.paper,
    builder: (_) => CreateShelfSheet(
      ownerId: widget.user.uid,
      shelfRepository: widget.shelfRepository,
    ),
  );

  Future<void> _openCreateShelf() async {
    await _openCreateShelfForSelection();
  }

  Future<void> _chooseAddBooks() async {
    if (_addBooksOpening) return;
    _addBooksOpening = true;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: !widget.showBottomNavigation,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add books', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final option in [
                ('scan', 'Scan barcode', Icons.document_scanner_outlined),
                ('catalogue', 'Search catalogue', Icons.search_rounded),
                ('manual', 'Add manually', Icons.edit_note_rounded),
              ])
                ListTile(
                  key: ValueKey('add-books-${option.$1}'),
                  leading: Icon(option.$3, color: ReaduoColors.accent),
                  title: Text(option.$2),
                  onTap: () => Navigator.of(context).pop(option.$1),
                ),
            ],
          ),
        ),
      ),
    );
    _addBooksOpening = false;
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'scan':
        await _openScanner();
      case 'catalogue':
        await _openCatalogue();
      case 'manual':
        await _openManualEntry();
    }
  }

  Future<void> _openManualEntry() async {
    widget.onNavigationBarVisibilityChanged?.call(false);
    Shelf? savedShelf;
    try {
      savedShelf = await Navigator.of(context).push<Shelf>(
        MaterialPageRoute<Shelf>(
          builder: (_) => CatalogueConfirmationScreen(
            ownerId: widget.user.uid,
            manualEntry: true,
            edition: const CatalogueEdition(
              id: 'manual',
              title: '',
              author: '',
              isbn: null,
              publisher: null,
              publishedYear: null,
              format: null,
              description: null,
              coverUrl: null,
              sourceUrl: '',
              provider: CatalogueProvider.openLibrary,
            ),
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            onCreateShelf: _openCreateShelfForSelection,
          ),
        ),
      );
    } finally {
      if (mounted) widget.onNavigationBarVisibilityChanged?.call(true);
    }
    if (mounted && savedShelf != null) await _openShelf(savedShelf);
  }

  Future<void> _openManualAdd(Shelf shelf, IsbnManualSeed seed) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: !widget.showBottomNavigation,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddBookSheet(
        ownerId: widget.user.uid,
        shelf: shelf,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
        initialTitle: seed.title,
        initialAuthor: seed.author,
        initialIsbn: seed.isbn,
      ),
    );
  }

  Future<void> _openScanner({Shelf? initialShelf}) async {
    if (_scannerOpening) return;
    _scannerOpening = true;
    widget.onNavigationBarVisibilityChanged?.call(false);
    try {
      final result = await Navigator.of(context).push<IsbnScanResult>(
        MaterialPageRoute<IsbnScanResult>(
          builder: (_) => IsbnScannerScreen(
            ownerId: widget.user.uid,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            lookupRepository: widget.bookLookupRepository,
            initialShelf: initialShelf,
            onCreateShelf: _openCreateShelfForSelection,
            onSearchCatalogue: (shelf, query) => _openCatalogue(
              initialShelf: shelf,
              initialQuery: query,
              restoreNavigation: false,
            ),
            onOpenManualAdd: _openManualAdd,
            onViewExisting: _viewExistingFromScanner,
          ),
        ),
      );
      if (!mounted || result == null) return;
      _scannerOpening = false;
      widget.onNavigationBarVisibilityChanged?.call(true);
      await _openShelf(result.shelf);
    } finally {
      _scannerOpening = false;
      widget.onNavigationBarVisibilityChanged?.call(true);
    }
  }

  Future<void> _viewExistingFromScanner(LibraryBook book) async {
    widget.onNavigationBarVisibilityChanged?.call(true);
    try {
      await _openBook(book);
    } finally {
      if (mounted && _scannerOpening) {
        widget.onNavigationBarVisibilityChanged?.call(false);
      }
    }
  }

  void _openAccount() {
    final select = widget.onSelectDestination;
    if (select != null) {
      select(ReaduoNavDestination.profile);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AccountScreen(authService: widget.authService, user: widget.user),
      ),
    );
  }

  void _openFriends() {
    final select = widget.onSelectDestination;
    if (select != null) {
      select(ReaduoNavDestination.friends);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendsScreen(
          authService: widget.authService,
          repository: widget.friendRepository,
          shelfRepository: widget.shelfRepository,
          bookRepository: widget.bookRepository,
          user: widget.user,
        ),
      ),
    );
  }

  Future<void> _openShelf(Shelf shelf) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ShelfDetailsScreen(
        ownerId: widget.user.uid,
        shelf: shelf,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
        bookLookupRepository: widget.bookLookupRepository,
        catalogueRepository: widget.catalogueRepository,
        reviewRepository: widget.reviewRepository,
        onCreateShelf: _openCreateShelf,
        onCreateShelfForSelection: _openCreateShelfForSelection,
        onOpenFriends: _openFriends,
        onOpenProfile: _openAccount,
        showBottomNavigation: widget.showBottomNavigation,
        onNavigationBarVisibilityChanged:
            widget.onNavigationBarVisibilityChanged,
      ),
    ),
  );

  Future<void> _openBook(LibraryBook book) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BookDetailsScreen(
        ownerId: widget.user.uid,
        shelfId: book.shelfId,
        bookId: book.id,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
        reviewRepository: widget.reviewRepository,
        onOpenFriends: _openFriends,
        onOpenProfile: _openAccount,
        onOpenShelf: _openShelf,
        onCreateShelf: _openCreateShelf,
        showBottomNavigation: widget.showBottomNavigation,
      ),
    ),
  );

  void _openAllBooks() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LibraryBooksScreen(
        ownerId: widget.user.uid,
        bookRepository: widget.bookRepository,
        onOpenBook: _openBook,
        onSearch: _openSearch,
        onAddBooks: _chooseAddBooks,
        onOpenFriends: _openFriends,
        onOpenProfile: _openAccount,
        showBottomNavigation: widget.showBottomNavigation,
      ),
    ),
  );

  Future<void> _openSearchDestination(
    Future<void> Function() openDestination,
  ) async {
    widget.onNavigationBarVisibilityChanged?.call(true);
    try {
      await openDestination();
    } finally {
      if (mounted) widget.onNavigationBarVisibilityChanged?.call(false);
    }
  }

  Future<void> _openCatalogue({
    Shelf? initialShelf,
    String initialQuery = '',
    bool restoreNavigation = true,
  }) async {
    widget.onNavigationBarVisibilityChanged?.call(false);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CatalogueSearchScreen(
            ownerId: widget.user.uid,
            catalogueRepository: widget.catalogueRepository,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            initialShelf: initialShelf,
            initialQuery: initialQuery,
            onCreateShelf: _openCreateShelfForSelection,
          ),
        ),
      );
    } finally {
      if (restoreNavigation) {
        widget.onNavigationBarVisibilityChanged?.call(true);
      }
    }
  }

  void _openSearchBook(LibraryBook book) {
    _openSearchDestination(() => _openBook(book));
  }

  void _openSearchShelf(Shelf shelf) {
    _openSearchDestination(() => _openShelf(shelf));
  }

  void _openExploreSearch() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Search Explore')),
          body: SafeArea(
            child: ExploreBody(
              searchMode: true,
              viewerId: widget.user.uid,
              friendRepository: widget.friendRepository,
              shelfRepository: widget.shelfRepository,
              bookRepository: widget.bookRepository,
              onMyLibrary: () => setState(() => _showExplore = false),
              onOpenProfile: (reader, isFriend) => isFriend
                  ? _openExploreProfile(reader)
                  : _openPublicProfile(reader),
              onOpenShelf: (reader, shelf, isFriend) => isFriend
                  ? _openExploreShelf(reader, shelf)
                  : _openPublicShelf(reader, shelf),
              onOpenBook: (reader, shelf, book, isFriend) => isFriend
                  ? _openExploreBook(reader, shelf, book)
                  : _openPublicBook(reader, shelf, book),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSearch(String query) async {
    FocusScope.of(context).unfocus();
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;
    widget.onNavigationBarVisibilityChanged?.call(false);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LibrarySearchScreen(
            ownerId: widget.user.uid,
            initialQuery: trimmedQuery,
            bookRepository: widget.bookRepository,
            shelfRepository: widget.shelfRepository,
            onOpenBook: _openSearchBook,
            onOpenShelf: _openSearchShelf,
            onSearchCatalogue: () => _openCatalogue(
              initialQuery: trimmedQuery,
              restoreNavigation: false,
            ),
          ),
        ),
      );
    } finally {
      widget.onNavigationBarVisibilityChanged?.call(true);
    }
  }

  Future<void> _openExploreProfile(ReaderProfile friend) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FriendProfileScreen(
            repository: widget.friendRepository,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            userId: widget.user.uid,
            friend: friend,
          ),
        ),
      );

  Future<void> _openExploreShelf(ReaderProfile friend, Shelf shelf) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SharedShelfScreen(
            viewerId: widget.user.uid,
            friend: friend,
            shelf: shelf,
            friendRepository: widget.friendRepository,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            ownedOnly: true,
            onCreateShelf: _openCreateShelfForSelection,
            onOpenOwnedBook: _openBook,
          ),
        ),
      );

  Future<void> _openExploreBook(
    ReaderProfile friend,
    Shelf shelf,
    LibraryBook book,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FriendBookSheet(
      viewerId: widget.user.uid,
      friend: friend,
      sourceShelf: shelf,
      book: book,
      friendRepository: widget.friendRepository,
      shelfRepository: widget.shelfRepository,
      bookRepository: widget.bookRepository,
      ownedOnly: true,
      onCreateShelf: _openCreateShelfForSelection,
      onOpenOwnedBook: _openBook,
      onSeeShelf: () => _openExploreShelf(friend, shelf),
    ),
  );

  Future<void> _openPublicProfile(ReaderProfile reader) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PublicReaderProfileScreen(
            viewerId: widget.user.uid,
            reader: reader,
            friendRepository: widget.friendRepository,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            onOpenShelf: _openPublicShelf,
            onOpenBook: _openPublicBook,
          ),
        ),
      );

  Future<void> _openPublicShelf(ReaderProfile reader, Shelf shelf) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SharedShelfScreen(
            viewerId: widget.user.uid,
            friend: reader,
            shelf: shelf,
            friendRepository: widget.friendRepository,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            ownedOnly: true,
            publicAccess: true,
            onCreateShelf: _openCreateShelfForSelection,
            onOpenOwnedBook: _openBook,
          ),
        ),
      );

  Future<void> _openPublicBook(
    ReaderProfile reader,
    Shelf shelf,
    LibraryBook book,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FriendBookSheet(
      viewerId: widget.user.uid,
      friend: reader,
      sourceShelf: shelf,
      book: book,
      friendRepository: widget.friendRepository,
      shelfRepository: widget.shelfRepository,
      bookRepository: widget.bookRepository,
      ownedOnly: true,
      publicAccess: true,
      onCreateShelf: _openCreateShelfForSelection,
      onOpenOwnedBook: _openBook,
      onSeeShelf: () => _openPublicShelf(reader, shelf),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Shelf>>(
    stream: _shelves,
    builder: (context, shelfSnapshot) => _buildLibrary(context, shelfSnapshot),
  );

  Widget _buildLibrary(
    BuildContext context,
    AsyncSnapshot<List<Shelf>> shelfSnapshot,
  ) {
    final canAddBooks =
        !shelfSnapshot.hasError &&
        (shelfSnapshot.data?.any(
              (shelf) =>
                  shelf.ownerId == widget.user.uid &&
                  shelf.mutationOperationId == null,
            ) ??
            false);
    return PopScope(
      canPop: !_addExpanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _addExpanded) _collapseAdd();
      },
      child: Scaffold(
        appBar: _searchExpanded
            ? AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: ReaduoColors.background,
                toolbarHeight: 64,
                titleSpacing: 16,
                title: TextField(
                  key: const Key('library-search-field'),
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) =>
                      setState(() => _query = normalizeLibraryText(value)),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    hintText: 'Search your books',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      key: const Key('clear-library-search'),
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _query = '';
                      }),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    key: const Key('cancel-library-search'),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _searchExpanded = false;
                        _query = '';
                        _searchController.clear();
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              )
            : ReaduoTabHeader(
                context: context,
                title: 'Library',
                actions: [
                  ReaduoTabHeaderAction(
                    key: const Key('library-search-button'),
                    tooltip: _showExplore
                        ? 'Search books or libraries'
                        : 'Search your books',
                    icon: Icons.search_rounded,
                    onPressed: _showExplore
                        ? _openExploreSearch
                        : () => setState(() => _searchExpanded = true),
                  ),
                ],
              ),
        floatingActionButton: _searchExpanded || _showExplore
            ? null
            : CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      _collapseAdd,
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_addExpanded) ...[
                      ElevatedButton.icon(
                        key: const Key('library-create-bookshelf-button'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () {
                          _collapseAdd(restoreFocus: false);
                          _openCreateShelf();
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('Create Bookshelf'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        key: const Key('library-add-book-button'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: canAddBooks
                            ? () {
                                _collapseAdd(restoreFocus: false);
                                _chooseAddBooks();
                              }
                            : null,
                        icon: const Icon(Icons.library_add_outlined),
                        label: const Text('Add Books'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Semantics(
                      expanded: _addExpanded,
                      child: FloatingActionButton(
                        key: const Key('library-add-fab'),
                        focusNode: _addFocus,
                        shape: const CircleBorder(),
                        tooltip: _addExpanded
                            ? 'Close Library actions'
                            : 'Add to Library',
                        onPressed: () =>
                            setState(() => _addExpanded = !_addExpanded),
                        child: Icon(
                          _addExpanded
                              ? Icons.close_rounded
                              : Icons.add_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        bottomNavigationBar: widget.showBottomNavigation
            ? ReaduoBottomNavigation(
                onProfile: _openAccount,
                onFriends: _openFriends,
              )
            : null,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              IndexedStack(
                index: _showExplore ? 1 : 0,
                children: [
                  Builder(
                    builder: (context) {
                      if (shelfSnapshot.hasError)
                        return _LibraryError(
                          message: shelfSnapshot.error is ShelfFailure
                              ? (shelfSnapshot.error! as ShelfFailure).message
                              : 'Readuo could not load your shelves.',
                          onRetry: _retry,
                        );
                      if (!shelfSnapshot.hasData)
                        return const Center(
                          child: CircularProgressIndicator(
                            key: Key('library-loading'),
                          ),
                        );
                      return StreamBuilder<List<ShelfMutationOperation>>(
                        stream: _operations,
                        builder: (context, operationSnapshot) {
                          if (operationSnapshot.hasError) {
                            return _LibraryError(
                              message:
                                  'Readuo could not load pending shelf changes.',
                              onRetry: _retry,
                            );
                          }
                          if (!operationSnapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return StreamBuilder<List<LibraryBook>>(
                            stream: _books,
                            builder: (context, bookSnapshot) {
                              if (bookSnapshot.hasError) {
                                return _LibraryError(
                                  message: bookSnapshot.error is BookFailure
                                      ? (bookSnapshot.error! as BookFailure)
                                            .message
                                      : 'Readuo could not load your books.',
                                  onRetry: _retry,
                                );
                              }
                              if (!bookSnapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return _LibraryContent(
                                shelves: shelfSnapshot.data!,
                                operations: operationSnapshot.data!,
                                books: bookSnapshot.data!,
                                query: _query,
                                readingStatus: _readingStatus,
                                onStatusChanged: (status) =>
                                    setState(() => _readingStatus = status),
                                onCreateShelf: _openCreateShelf,
                                onOpenShelf: _openShelf,
                                onOpenBook: _openBook,
                                onViewAllBooks: _query.isEmpty
                                    ? _openAllBooks
                                    : () => _openSearch(_searchController.text),
                                onResumeOperation: _resumeOperation,
                                resumingOperationId: _resumingOperationId,
                                onExplore: () => setState(() {
                                  _searchExpanded = false;
                                  _searchController.clear();
                                  _query = '';
                                  _showExplore = true;
                                  _exploreVisited = true;
                                }),
                                onScan: _openScanner,
                                onSearchCatalogue: _openCatalogue,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                  _exploreVisited
                      ? ExploreBody(
                          key: ValueKey('explore-${widget.user.uid}'),
                          viewerId: widget.user.uid,
                          friendRepository: widget.friendRepository,
                          shelfRepository: widget.shelfRepository,
                          bookRepository: widget.bookRepository,
                          onMyLibrary: () =>
                              setState(() => _showExplore = false),
                          onOpenProfile: (reader, isFriend) => isFriend
                              ? _openExploreProfile(reader)
                              : _openPublicProfile(reader),
                          onOpenShelf: (reader, shelf, isFriend) => isFriend
                              ? _openExploreShelf(reader, shelf)
                              : _openPublicShelf(reader, shelf),
                          onOpenBook: (reader, shelf, book, isFriend) =>
                              isFriend
                              ? _openExploreBook(reader, shelf, book)
                              : _openPublicBook(reader, shelf, book),
                        )
                      : const SizedBox.shrink(),
                ],
              ),
              if (_addExpanded)
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('library-add-dismiss'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _collapseAdd,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .08),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.shelves,
    required this.operations,
    required this.books,
    required this.query,
    required this.readingStatus,
    required this.onStatusChanged,
    required this.onCreateShelf,
    required this.onOpenShelf,
    required this.onOpenBook,
    required this.onViewAllBooks,
    required this.onResumeOperation,
    required this.resumingOperationId,
    required this.onExplore,
    required this.onScan,
    required this.onSearchCatalogue,
  });
  final List<Shelf> shelves;
  final List<ShelfMutationOperation> operations;
  final List<LibraryBook> books;
  final String query;
  final ReadingStatus? readingStatus;
  final ValueChanged<ReadingStatus?> onStatusChanged;
  final VoidCallback onCreateShelf;
  final ValueChanged<Shelf> onOpenShelf;
  final ValueChanged<LibraryBook> onOpenBook;
  final VoidCallback onViewAllBooks;
  final ValueChanged<ShelfMutationOperation> onResumeOperation;
  final String? resumingOperationId;
  final VoidCallback onExplore;
  final VoidCallback onScan;
  final VoidCallback onSearchCatalogue;

  @override
  Widget build(BuildContext context) {
    if (shelves.isEmpty &&
        books.isEmpty &&
        operations.isEmpty &&
        query.isEmpty) {
      return CustomScrollView(
        key: const Key('empty-library'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _LibrarySwitcher(onExplore: onExplore),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 32,
                ),
                child: Column(
                  key: const Key('empty-library-guidance'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your library is empty',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ReaduoColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create a bookshelf first, then add books to your library.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ReaduoColors.muted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final matchingBooks = books
        .where((book) => query.isEmpty || libraryBookMatches(book, query))
        .toList();
    final matchingShelfIds = matchingBooks.map((book) => book.shelfId).toSet();
    final visibleBooks = matchingBooks
        .where(
          (book) =>
              query.isNotEmpty ||
              readingStatus == null ||
              book.readingStatus == readingStatus,
        )
        .toList();
    final matchingShelves = shelves
        .where(
          (shelf) =>
              query.isEmpty ||
              normalizeLibraryText(shelf.name).contains(query) ||
              matchingShelfIds.contains(shelf.id),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        _LibrarySwitcher(onExplore: onExplore),
        for (final operation in operations) ...[
          const SizedBox(height: 12),
          _PendingShelfOperationCard(
            operation: operation,
            shelves: shelves,
            busy: resumingOperationId == operation.id,
            onResume: () => onResumeOperation(operation),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          query.isNotEmpty
              ? '${matchingBooks.length} ${matchingBooks.length == 1 ? 'book' : 'books'} found'
              : '${books.length} ${books.length == 1 ? 'book' : 'books'} · ${shelves.length} ${shelves.length == 1 ? 'shelf' : 'shelves'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (query.isEmpty) ...[
          const SizedBox(height: 16),
          const _SectionHeader(title: 'My shelves'),
          const SizedBox(height: 12),
          if (matchingShelves.isEmpty)
            _EmptyLibrary(
              hasQuery: query.isNotEmpty,
              onCreate: onCreateShelf,
              onScan: onScan,
              onSearchCatalogue: onSearchCatalogue,
            )
          else
            SingleChildScrollView(
              key: const Key('library-shelf-carousel'),
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final shelf in matchingShelves)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: (MediaQuery.sizeOf(context).width - 42) / 2,
                          child: LibraryShelfCard(
                            shelf: shelf,
                            books: books
                                .where((book) => book.shelfId == shelf.id)
                                .toList(),
                            onTap: () => onOpenShelf(shelf),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 20),
        _SectionHeader(
          title: 'My books',
          actionLabel: 'View all',
          actionKey: const Key('view-all-books'),
          onAction: onViewAllBooks,
        ),
        if (query.isEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final status in ReadingStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('library-status-${status.name}'),
                      label: Text(status.label),
                      selected: readingStatus == status,
                      showCheckmark: false,
                      selectedColor: ReaduoColors.accent,
                      backgroundColor: ReaduoColors.accentTint,
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                      labelStyle: TextStyle(
                        color: readingStatus == status
                            ? Colors.white
                            : ReaduoColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (value) =>
                          onStatusChanged(value ? status : null),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (visibleBooks.isEmpty)
          Text(
            readingStatus != null
                ? 'No books with this reading status.'
                : query.isEmpty
                ? 'Books you add will appear here.'
                : 'No books match your search.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else if (query.isNotEmpty)
          ...visibleBooks.map(
            (book) => LibrarySearchResult(
              key: Key('library-book-${book.shelfId}-${book.id}'),
              book: book,
              shelfName:
                  shelves
                      .where((shelf) => shelf.id == book.shelfId)
                      .firstOrNull
                      ?.name ??
                  '',
              onTap: () => onOpenBook(book),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 20,
              children: [
                for (final book in visibleBooks.take(12))
                  SizedBox(
                    width: (constraints.maxWidth - 24) / 3,
                    child: _BookPreview(
                      book: book,
                      onTap: () => onOpenBook(book),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PendingShelfOperationCard extends StatelessWidget {
  const _PendingShelfOperationCard({
    required this.operation,
    required this.shelves,
    required this.busy,
    required this.onResume,
  });

  final ShelfMutationOperation operation;
  final List<Shelf> shelves;
  final bool busy;
  final VoidCallback onResume;

  String _shelfName(String id) {
    for (final shelf in shelves) {
      if (shelf.id == id) return shelf.name;
    }
    return 'this shelf';
  }

  @override
  Widget build(BuildContext context) {
    final sourceName = _shelfName(operation.sourceShelfId);
    final remaining = operation.totalCount - operation.processedCount;
    final description = switch (operation.mode) {
      ShelfMutationMode.move =>
        'Continue moving $remaining ${remaining == 1 ? 'book' : 'books'} from $sourceName to ${_shelfName(operation.destinationShelfId!)}.',
      ShelfMutationMode.remove =>
        'Continue removing $remaining ${remaining == 1 ? 'book' : 'books'} from $sourceName.',
    };
    return Container(
      key: Key('pending-shelf-operation-${operation.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6C36A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sync_rounded, color: ReaduoColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shelf change paused',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ReaduoColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(description),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: Key('resume-shelf-operation-${operation.id}'),
                  onPressed: busy ? null : onResume,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(busy ? 'Continuing…' : 'Continue shelf change'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrarySwitcher extends StatelessWidget {
  const _LibrarySwitcher({required this.onExplore});
  final VoidCallback onExplore;
  @override
  Widget build(BuildContext context) => ReaduoSectionTabs(
    labels: const ['My Library', 'Explore'],
    selected: 0,
    tabKeys: const [null, Key('explore-library-tab')],
    onSelected: (index) {
      if (index == 1) onExplore();
    },
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.actionKey,
    this.onAction,
  });
  final String title;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: ReaduoColors.ink,
          ),
        ),
      ),
      if (actionLabel != null)
        TextButton.icon(
          key: actionKey,
          onPressed: onAction,
          icon: actionLabel == 'New shelf'
              ? const Icon(Icons.add_rounded, size: 18)
              : const SizedBox.shrink(),
          label: Text(actionLabel!),
        ),
    ],
  );
}

class LibraryShelfCard extends StatelessWidget {
  const LibraryShelfCard({
    required this.shelf,
    required this.books,
    required this.onTap,
  });
  final Shelf shelf;
  final List<LibraryBook> books;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: ReaduoColors.paper,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: ReaduoColors.line),
    ),
    child: InkWell(
      key: Key('shelf-${shelf.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShelfCoverStack(books: books),
            const SizedBox(height: 10),
            Text(
              shelf.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ReaduoColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            if (shelf.mutationOperationId != null)
              const Row(
                children: [
                  Icon(Icons.sync_rounded, size: 16),
                  SizedBox(width: 5),
                  Expanded(child: Text('Shelf change in progress')),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${shelf.bookCount} ${shelf.bookCount == 1 ? 'book' : 'books'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _VisibilityBadge(visibility: shelf.visibility),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

class _ShelfCoverStack extends StatelessWidget {
  const _ShelfCoverStack({required this.books});
  final List<LibraryBook> books;
  @override
  Widget build(BuildContext context) {
    if (books.isEmpty)
      return const SizedBox(
        height: 64,
        child: Center(
          child: Icon(
            Icons.auto_stories_outlined,
            size: 36,
            color: ReaduoColors.muted,
          ),
        ),
      );
    return SizedBox(
      height: 64,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.center,
          children: List.generate(books.take(3).length, (index) {
            final book = books[index];
            return Positioned(
              left:
                  (constraints.maxWidth - 60) / 2 +
                  (index - (books.take(3).length - 1) / 2) * 30,
              child: Transform.rotate(
                angle: (index - (books.take(3).length - 1) / 2) * 0.09,
                child: Container(
                  width: 60,
                  height: 60,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: ReaduoColors.accentTint,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ReaduoColors.paper, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x20000000), blurRadius: 5),
                    ],
                  ),
                  child: book.coverUrl == null
                      ? GeneratedBookCover(
                          title: book.title,
                          author: book.author,
                        )
                      : BookCoverImage(
                          book.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.menu_book_rounded,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visibility});
  final ShelfVisibility visibility;
  @override
  Widget build(BuildContext context) {
    final icon = switch (visibility) {
      ShelfVisibility.private => Icons.lock_outline_rounded,
      ShelfVisibility.friends => Icons.people_outline_rounded,
      ShelfVisibility.public => Icons.public_rounded,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ReaduoColors.accentTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: ReaduoColors.accent),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                visibility.label,
                style: const TextStyle(
                  color: ReaduoColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookPreview extends StatelessWidget {
  const _BookPreview({required this.book, required this.onTap});
  final LibraryBook book;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: Key('library-book-${book.shelfId}-${book.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _BookCover(book: book),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(14) * 1.4 * 2,
            child: Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: ReaduoColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 3),
          Text(
            book.readingStatus.label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: ReaduoColors.accent),
          ),
        ],
      ),
    ),
  );
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});
  final LibraryBook book;
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: ReaduoColors.accentTint,
      borderRadius: BorderRadius.circular(6),
    ),
    child: book.coverUrl == null
        ? GeneratedBookCover(title: book.title, author: book.author)
        : BookCoverImage(
            book.coverUrl!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.book_outlined, color: ReaduoColors.accent),
          ),
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.hasQuery,
    required this.onCreate,
    required this.onScan,
    required this.onSearchCatalogue,
  });
  final bool hasQuery;
  final VoidCallback onCreate;
  final VoidCallback onScan;
  final VoidCallback onSearchCatalogue;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    decoration: BoxDecoration(
      color: ReaduoColors.paper,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ReaduoColors.line),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.auto_stories_outlined,
          size: 42,
          color: ReaduoColors.accent,
        ),
        const SizedBox(height: 12),
        Text(
          hasQuery ? 'No matching shelves' : 'Your first shelf awaits',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          hasQuery
              ? 'Try another title, author, or shelf name.'
              : 'Add a book and choose a shelf to make it yours.',
          textAlign: TextAlign.center,
        ),
        if (!hasQuery) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('empty-library-scan'),
            onPressed: onScan,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan a book'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('empty-library-catalogue'),
            onPressed: onSearchCatalogue,
            child: const Text('Search for a book'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('create-shelf-button'),
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create a shelf first'),
          ),
        ],
      ],
    ),
  );
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
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

class CreateShelfSheet extends StatefulWidget {
  const CreateShelfSheet({
    required this.ownerId,
    required this.shelfRepository,
    super.key,
  });
  final String ownerId;
  final ShelfRepository shelfRepository;
  @override
  State<CreateShelfSheet> createState() => _CreateShelfSheetState();
}

class _CreateShelfSheetState extends State<CreateShelfSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  ShelfVisibility _visibility = ShelfVisibility.friends;
  bool _autoShareActivity = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _setVisibility(ShelfVisibility visibility) => setState(() {
    _visibility = visibility;
    if (visibility == ShelfVisibility.private) _autoShareActivity = false;
    _error = null;
  });

  Future<void> _save() async {
    final input = CreateShelfInput(
      name: _nameController.text,
      description: _descriptionController.text,
      visibility: _visibility,
      autoShareActivity: _autoShareActivity,
    );
    final validationMessage = input.validationMessage;
    if (validationMessage != null) {
      setState(() => _error = validationMessage);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final shelf = await widget.shelfRepository.createShelf(
        ownerId: widget.ownerId,
        input: input,
      );
      if (mounted) Navigator.of(context).pop(shelf);
    } on ShelfFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not create the shelf. Please retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset =
        mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        4,
        ReaduoSpacing.screenHorizontal,
        24 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New shelf',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('shelf-name-field'),
              controller: _nameController,
              enabled: !_saving,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              decoration: InputDecoration(
                labelText: 'Shelf name',
                hintText: 'Weekend reads',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('shelf-description-field'),
              controller: _descriptionController,
              enabled: !_saving,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(500)],
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What belongs on this shelf?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Who can see this shelf?',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            RadioGroup<ShelfVisibility>(
              groupValue: _visibility,
              onChanged: _saving
                  ? (_) {}
                  : (value) {
                      if (value != null) _setVisibility(value);
                    },
              child: Column(
                children: [
                  for (final visibility in const [
                    ShelfVisibility.private,
                    ShelfVisibility.friends,
                    ShelfVisibility.public,
                  ])
                    RadioListTile<ShelfVisibility>(
                      key: Key('visibility-${visibility.name}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: visibility,
                      enabled: !_saving,
                      title: Text(visibility.label),
                      subtitle: Text(visibility.description),
                    ),
                ],
              ),
            ),
            const Divider(height: 26),
            SwitchListTile(
              key: const Key('auto-share-switch'),
              contentPadding: EdgeInsets.zero,
              value: _autoShareActivity,
              onChanged: _saving || _visibility == ShelfVisibility.private
                  ? null
                  : (value) => setState(() => _autoShareActivity = value),
              title: const Text('Share activity to Circle'),
              subtitle: Text(
                _visibility == ShelfVisibility.private
                    ? 'Private shelves keep activity private.'
                    : 'Your preference is saved; posting arrives later.',
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('save-shelf-button'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create shelf'),
            ),
          ],
        ),
      ),
    );
  }
}
