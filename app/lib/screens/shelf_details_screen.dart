import 'manual_book_flow.dart';
import '../widgets/generated_book_cover.dart';
import '../widgets/book_cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../circle/review_repository.dart';
import '../library/book.dart';
import '../library/book_lookup.dart';
import '../library/book_repository.dart';
import '../library/catalogue_repository.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';
import '../widgets/readuo_bottom_navigation.dart';
import '../widgets/readuo_tab_activity.dart';
import 'book_details_screen.dart';
import 'catalogue_search_screen.dart';
import 'isbn_scanner_screen.dart';

class ShelfDetailsScreen extends StatefulWidget {
  const ShelfDetailsScreen({
    required this.ownerId,
    required this.shelf,
    this.shelfRepository = const EmptyShelfRepository(),
    required this.bookRepository,
    this.bookLookupRepository = const EmptyBookLookupRepository(),
    this.catalogueRepository = const EmptyCatalogueRepository(),
    this.reviewRepository = const EmptyReviewRepository(),
    this.onCreateShelf,
    this.onCreateShelfForSelection,
    this.onOpenFriends,
    this.onOpenProfile,
    this.showBottomNavigation = true,
    this.onNavigationBarVisibilityChanged,
    super.key,
  });

  final String ownerId;
  final Shelf shelf;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final BookLookupRepository bookLookupRepository;
  final CatalogueRepository catalogueRepository;
  final ReviewRepository reviewRepository;
  final Future<void> Function()? onCreateShelf;
  final Future<Shelf?> Function()? onCreateShelfForSelection;
  final VoidCallback? onOpenFriends;
  final VoidCallback? onOpenProfile;
  final bool showBottomNavigation;
  final ValueChanged<bool>? onNavigationBarVisibilityChanged;

  @override
  State<ShelfDetailsScreen> createState() => _ShelfDetailsScreenState();
}

class _ShelfDetailsScreenState extends State<ShelfDetailsScreen>
    with WidgetsBindingObserver {
  late Shelf _shelf;
  late Stream<List<LibraryBook>> _books;
  List<LibraryBook> _latestBooks = const [];
  final Set<ReadingStatus> _statusFilters = {};
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  bool _addExpanded = false;
  final FocusNode _addFocus = FocusNode();
  final GlobalKey _addMenuKey = GlobalKey();
  bool _scannerOpening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shelf = widget.shelf;
    _loadBooks();
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

  @override
  void didUpdateWidget(covariant ShelfDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shelf != widget.shelf) _shelf = widget.shelf;
    if (oldWidget.shelf.id != widget.shelf.id ||
        _shelf.mutationOperationId != null) {
      _addExpanded = false;
    }
  }

  void _loadBooks() {
    _books = widget.bookRepository.watchBooks(
      ownerId: widget.ownerId,
      shelfId: _shelf.id,
    );
  }

  void _retry() => setState(_loadBooks);

  Future<void> _openAddBook({Shelf? shelf, IsbnManualSeed? seed}) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: !widget.showBottomNavigation,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddBookSheet(
        ownerId: widget.ownerId,
        shelf: shelf ?? _shelf,
        shelfRepository: widget.shelfRepository,
        existingBooks: _latestBooks,
        bookRepository: widget.bookRepository,
        initialTitle: seed?.title ?? '',
        initialAuthor: seed?.author ?? '',
        initialIsbn: seed?.isbn ?? '',
      ),
    );
  }

  Future<void> _openScanner({bool enterIsbn = false}) async {
    if (_scannerOpening) return;
    _scannerOpening = true;
    widget.onNavigationBarVisibilityChanged?.call(false);
    IsbnScanResult? result;
    try {
      result = await Navigator.of(context).push<IsbnScanResult>(
        MaterialPageRoute<IsbnScanResult>(
          builder: (context) => IsbnScannerScreen(
            ownerId: widget.ownerId,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            lookupRepository: widget.bookLookupRepository,
            initialShelf: _shelf,
            startWithManualIsbn: enterIsbn,
            onCreateShelf: widget.onCreateShelfForSelection,
            onSearchCatalogue: (shelf, query) => _openCatalogue(
              initialShelf: shelf,
              initialQuery: query,
              restoreNavigation: false,
            ),
            onOpenManualAdd: (shelf, seed) =>
                _openAddBook(shelf: shelf, seed: seed),
            onViewExisting: _viewExistingFromScanner,
          ),
        ),
      );
    } finally {
      _scannerOpening = false;
      widget.onNavigationBarVisibilityChanged?.call(true);
    }
    if (!mounted || result == null) return;
    await _applyScanDestination(result.shelf);
  }

  Future<void> _applyScanDestination(Shelf returned) async {
    Shelf? exact;
    try {
      final current = await widget.shelfRepository
          .watchShelves(widget.ownerId)
          .first;
      for (final shelf in current) {
        if (shelf.id == returned.id &&
            shelf.ownerId == widget.ownerId &&
            shelf.mutationOperationId == null) {
          exact = shelf;
          break;
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Readuo could not verify the saved shelf. Return to Library to refresh.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    if (exact == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That saved shelf is no longer available. Return to Library to refresh.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _shelf = exact!;
      _statusFilters.clear();
      _loadBooks();
    });
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
            ownerId: widget.ownerId,
            catalogueRepository: widget.catalogueRepository,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            initialShelf: initialShelf ?? _shelf,
            initialQuery: initialQuery,
            onCreateShelf: widget.onCreateShelfForSelection,
          ),
        ),
      );
    } finally {
      if (restoreNavigation) {
        widget.onNavigationBarVisibilityChanged?.call(true);
      }
    }
  }

  void _closeSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = false;
      _searchController.clear();
    });
  }

  Future<void> _submitSearch(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    _closeSearch();
    await _openCatalogue(initialQuery: query);
  }

  void _chooseAddBook() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _addExpanded = !_addExpanded);
    _addFocus.requestFocus();
  }

  Future<void> _openSettings() async {
    widget.onNavigationBarVisibilityChanged?.call(false);
    try {
      final input = await Navigator.of(context).push<UpdateShelfInput>(
        MaterialPageRoute<UpdateShelfInput>(
          builder: (_) => ShelfSettingsScreen(
            ownerId: widget.ownerId,
            shelf: _shelf,
            shelfRepository: widget.shelfRepository,
            onCreateShelf: widget.onCreateShelf,
          ),
        ),
      );
      if (input == null || !mounted) return;
      setState(() {
        _shelf = _shelf.copyWith(
          name: input.name.trim(),
          description: input.description.trim(),
          visibility: input.visibility,
          autoShareActivity: input.autoShareActivity,
        );
      });
    } finally {
      widget.onNavigationBarVisibilityChanged?.call(true);
    }
  }

  Future<void> _openBook(LibraryBook book) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BookDetailsScreen(
        ownerId: widget.ownerId,
        shelfId: book.shelfId,
        bookId: book.id,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
        reviewRepository: widget.reviewRepository,
        onOpenFriends: widget.onOpenFriends,
        onOpenProfile: widget.onOpenProfile,
        onOpenShelf: (shelf) {
          if (shelf.id == _shelf.id) {
            Navigator.of(context).pop();
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ShelfDetailsScreen(
                ownerId: widget.ownerId,
                shelf: shelf,
                shelfRepository: widget.shelfRepository,
                bookRepository: widget.bookRepository,
                bookLookupRepository: widget.bookLookupRepository,
                catalogueRepository: widget.catalogueRepository,
                reviewRepository: widget.reviewRepository,
                onCreateShelf: widget.onCreateShelf,
                onCreateShelfForSelection: widget.onCreateShelfForSelection,
                onOpenFriends: widget.onOpenFriends,
                onOpenProfile: widget.onOpenProfile,
                showBottomNavigation: widget.showBottomNavigation,
                onNavigationBarVisibilityChanged:
                    widget.onNavigationBarVisibilityChanged,
              ),
            ),
          );
        },
        onCreateShelf: widget.onCreateShelf,
        showBottomNavigation: widget.showBottomNavigation,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isChanging = _shelf.mutationOperationId != null;
    return PopScope(
      canPop: !_searching && !_addExpanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _addExpanded) {
          _collapseAdd();
        } else if (!didPop && _searching) {
          _closeSearch();
        }
      },
      child: Listener(
        onPointerDown: !_addExpanded
            ? null
            : (event) {
                final box =
                    _addMenuKey.currentContext?.findRenderObject()
                        as RenderBox?;
                if (box != null &&
                    !(box.localToGlobal(Offset.zero) & box.size).contains(
                      event.position,
                    )) {
                  _collapseAdd();
                }
              },
        child: Scaffold(
          appBar: AppBar(
            leading: _searching || _addExpanded
                ? IconButton(
                    tooltip: _addExpanded
                        ? 'Close add book menu'
                        : 'Close catalogue search',
                    onPressed: _addExpanded ? _collapseAdd : _closeSearch,
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
            title: _searching
                ? TextField(
                    key: const Key('shelf-catalogue-query'),
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search catalogue',
                      border: InputBorder.none,
                    ),
                    onSubmitted: _submitSearch,
                  )
                : Text(
                    _shelf.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            actions: [
              IconButton(
                key: const Key('shelf-catalogue-button'),
                onPressed: isChanging
                    ? null
                    : () {
                        _collapseAdd(restoreFocus: false);
                        if (_searching) {
                          _submitSearch(_searchController.text);
                        } else {
                          setState(() => _searching = true);
                        }
                      },
                tooltip: 'Search catalogue',
                icon: const Icon(Icons.search_rounded),
              ),
              if (!isChanging && !_searching)
                PopupMenuButton<String>(
                  onOpened: () => _collapseAdd(restoreFocus: false),
                  key: const Key('shelf-settings-button'),
                  tooltip: 'Shelf options',
                  onSelected: (value) {
                    if (value == 'settings') _openSettings();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'settings',
                      child: Text('Shelf settings'),
                    ),
                  ],
                ),
            ],
          ),
          floatingActionButton: _searching
              ? null
              : CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _collapseAdd,
                  },
                  child: Column(
                    key: _addMenuKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_addExpanded) ...[
                        ElevatedButton.icon(
                          key: const Key('scan-isbn-button'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () {
                            _collapseAdd(restoreFocus: false);
                            _openScanner();
                          },
                          icon: const Icon(
                            Icons.document_scanner_outlined,
                            size: 20,
                          ),
                          label: const Text('Scan ISBN'),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          key: const Key('shelf-enter-isbn-choice'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () {
                            _collapseAdd(restoreFocus: false);
                            _openScanner(enterIsbn: true);
                          },
                          icon: const Icon(Icons.keyboard_rounded, size: 20),
                          label: const Text('Enter ISBN'),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          key: const Key('shelf-catalogue-choice'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () {
                            _collapseAdd(restoreFocus: false);
                            _openCatalogue();
                          },
                          icon: const Icon(Icons.search_rounded, size: 20),
                          label: const Text('Search Catalogue'),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          key: const Key('shelf-manual-choice'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () {
                            _collapseAdd(restoreFocus: false);
                            _openAddBook();
                          },
                          icon: const Icon(Icons.edit_note_rounded, size: 20),
                          label: const Text('Add Manually'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Semantics(
                        expanded: _addExpanded,
                        child: FloatingActionButton(
                          key: const Key('add-book-button'),
                          focusNode: _addFocus,
                          tooltip: _addExpanded
                              ? 'Close add book menu'
                              : 'Add books',
                          onPressed: isChanging ? null : _chooseAddBook,
                          backgroundColor: isChanging
                              ? ReaduoColors.line
                              : ReaduoColors.accent,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                          child: Icon(
                            isChanging
                                ? Icons.sync_rounded
                                : _addExpanded
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
                  onLibrary: () => Navigator.of(context).pop(),
                  onFriends: widget.onOpenFriends,
                  onProfile: widget.onOpenProfile,
                )
              : null,
          body: Stack(
            children: [
              ExcludeFocus(
                excluding: _addExpanded,
                child: SafeArea(
                  bottom: false,
                  child: StreamBuilder<List<LibraryBook>>(
                    stream: _books,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        final error = snapshot.error;
                        return _BookListError(
                          message: error is BookFailure
                              ? error.message
                              : 'Readuo could not load this shelf.',
                          onRetry: _retry,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            key: Key('books-loading'),
                          ),
                        );
                      }
                      _latestBooks = snapshot.data!;
                      final filteredBooks = _statusFilters.isEmpty
                          ? _latestBooks
                          : _latestBooks
                                .where(
                                  (book) => _statusFilters.contains(
                                    book.readingStatus,
                                  ),
                                )
                                .toList();
                      return CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              ReaduoSpacing.screenHorizontal,
                              12,
                              ReaduoSpacing.screenHorizontal,
                              8,
                            ),
                            sliver: SliverList.list(
                              children: [
                                if (isChanging) ...[
                                  const _SettingsBanner(
                                    icon: Icons.sync_rounded,
                                    text:
                                        'Shelf change in progress. Return to Library to continue the confirmed action.',
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                Row(
                                  children: [
                                    _VisibilityBadge(
                                      visibility: _shelf.visibility,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${_latestBooks.length} ${_latestBooks.length == 1 ? 'book' : 'books'} · '
                                        'Automatic activity ${_shelf.autoShareActivity ? 'on' : 'off'}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                                if ((_shelf.description ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(_shelf.description!),
                                ],
                                const SizedBox(height: 18),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final status
                                          in ReadingStatus.values) ...[
                                        if (status !=
                                            ReadingStatus.values.first)
                                          const SizedBox(width: 8),
                                        _StatusChip(
                                          icon: switch (status) {
                                            ReadingStatus.wantToRead =>
                                              Icons.bookmark_outline_rounded,
                                            ReadingStatus.reading =>
                                              Icons.auto_stories_outlined,
                                            ReadingStatus.finished =>
                                              Icons
                                                  .check_circle_outline_rounded,
                                          },
                                          label: status.label,
                                          selected: _statusFilters.contains(
                                            status,
                                          ),
                                          onSelected: () => setState(() {
                                            if (!_statusFilters.remove(
                                              status,
                                            )) {
                                              _statusFilters.add(status);
                                            }
                                          }),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                          if (_latestBooks.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _EmptyShelf(
                                onScan: isChanging ? null : _openScanner,
                                onSearchCatalogue: isChanging
                                    ? null
                                    : _openCatalogue,
                                onManualAdd: isChanging ? null : _openAddBook,
                              ),
                            )
                          else if (filteredBooks.isEmpty)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text('No books with this status.'),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                ReaduoSpacing.screenHorizontal,
                                4,
                                ReaduoSpacing.screenHorizontal,
                                100,
                              ),
                              sliver: SliverGrid.builder(
                                itemCount: filteredBooks.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 18,
                                      childAspectRatio: 0.58,
                                    ),
                                itemBuilder: (context, index) => _BookTile(
                                  key: ValueKey(filteredBooks[index].id),
                                  book: filteredBooks[index],
                                  onTap: () => _openBook(filteredBooks[index]),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (_addExpanded)
                Positioned.fill(
                  child: ModalBarrier(
                    key: const Key('shelf-add-dismiss'),
                    color: Colors.black.withValues(alpha: 0.08),
                    dismissible: true,
                    onDismiss: _collapseAdd,
                    semanticsLabel: 'Close add book menu',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShelfSettingsScreen extends StatefulWidget {
  const ShelfSettingsScreen({
    required this.ownerId,
    required this.shelf,
    required this.shelfRepository,
    this.onCreateShelf,
    super.key,
  });

  final String ownerId;
  final Shelf shelf;
  final ShelfRepository shelfRepository;
  final Future<void> Function()? onCreateShelf;

  @override
  State<ShelfSettingsScreen> createState() => _ShelfSettingsScreenState();
}

class _ShelfSettingsScreenState extends State<ShelfSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late ShelfVisibility _visibility;
  late bool _autoShareActivity;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.shelf.name);
    _descriptionController = TextEditingController(
      text: widget.shelf.description ?? '',
    );
    _visibility = widget.shelf.visibility;
    _autoShareActivity = widget.shelf.autoShareActivity;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _setVisibility(ShelfVisibility visibility) async {
    if (_saving || visibility == _visibility) return;
    if (visibility == ShelfVisibility.private &&
        _visibility != ShelfVisibility.private) {
      final mediaQuery = MediaQuery.of(context);
      final bottomInset =
          mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
          ? mediaQuery.viewInsets.bottom
          : mediaQuery.viewPadding.bottom;
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: ReaduoColors.paper,
        builder: (_) =>
            _PrivateShelfConfirmationSheet(minimumBottomInset: bottomInset),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _visibility = visibility;
      if (visibility == ShelfVisibility.private) {
        _autoShareActivity = false;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final input = UpdateShelfInput(
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
      await widget.shelfRepository.updateShelf(
        ownerId: widget.ownerId,
        shelfId: widget.shelf.id,
        input: input,
      );
      if (mounted) Navigator.of(context).pop(input);
    } on ShelfFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update the shelf. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shelf settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: ReaduoSpacing.screenHorizontal,
            vertical: 24,
          ),
          children: [
            TextField(
              key: const Key('settings-shelf-name-field'),
              controller: _nameController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              decoration: const InputDecoration(
                labelText: 'Shelf name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('settings-shelf-description-field'),
              controller: _descriptionController,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(500)],
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What belongs here?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Visibility',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
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
                    ShelfVisibility.friends,
                    ShelfVisibility.private,
                    ShelfVisibility.public,
                  ])
                    RadioListTile<ShelfVisibility>(
                      key: Key('settings-visibility-${visibility.name}'),
                      value: visibility,
                      enabled: !_saving,
                      contentPadding: EdgeInsets.zero,
                      title: Text(visibility.label),
                      subtitle: Text(switch (visibility) {
                        ShelfVisibility.friends => 'Your accepted friends',
                        ShelfVisibility.private => 'Only you',
                        ShelfVisibility.public => 'Any signed-in Readuo user',
                      }),
                    ),
                ],
              ),
            ),
            const Divider(height: 28),
            SwitchListTile(
              key: const Key('settings-auto-share-switch'),
              contentPadding: EdgeInsets.zero,
              value: _autoShareActivity,
              onChanged: _saving || _visibility == ShelfVisibility.private
                  ? null
                  : (value) => setState(() => _autoShareActivity = value),
              title: const Text('Share activity to Circle'),
              subtitle: const Text('This setting applies only to this shelf.'),
            ),
            if (_visibility == ShelfVisibility.private)
              const _SettingsBanner(
                icon: Icons.lock_outline_rounded,
                text: 'Private shelves never post to Circle.',
              ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                key: const Key('settings-shelf-error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('save-shelf-settings-button'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save changes'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              key: const Key('delete-shelf-button'),
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => DeleteShelfScreen(
                          ownerId: widget.ownerId,
                          shelf: widget.shelf,
                          shelfRepository: widget.shelfRepository,
                          onCreateShelf: widget.onCreateShelf,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete shelf'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DeleteShelfScreen extends StatelessWidget {
  const DeleteShelfScreen({
    required this.ownerId,
    required this.shelf,
    required this.shelfRepository,
    this.onCreateShelf,
    super.key,
  });

  final String ownerId;
  final Shelf shelf;
  final ShelfRepository shelfRepository;
  final Future<void> Function()? onCreateShelf;

  Future<void> _confirmRemoval(BuildContext context, Shelf currentShelf) async {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset =
        mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;
    final removed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (_) => _RemoveShelfConfirmationSheet(
        ownerId: ownerId,
        shelf: currentShelf,
        shelfRepository: shelfRepository,
        minimumBottomInset: bottomInset,
      ),
    );
    if (removed == true && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _cancel(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete shelf')),
      body: SafeArea(
        child: StreamBuilder<List<Shelf>>(
          stream: shelfRepository.watchShelves(ownerId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _ShelfMutationError(
                message: 'Readuo could not load this shelf. Please retry.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final currentShelf = _findShelf(snapshot.data!, shelf.id);
            if (currentShelf == null) {
              return const _ShelfMutationError(
                message: 'This shelf is no longer available.',
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: ReaduoSpacing.screenHorizontal,
                vertical: 24,
              ),
              children: [
                _DeletionShelfCard(shelf: currentShelf),
                const SizedBox(height: 24),
                Text(
                  'What would you like to do with the books?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                _DeletionChoice(
                  key: const Key('move-all-choice'),
                  icon: Icons.drive_file_move_outline,
                  title: 'Move books to another shelf',
                  subtitle: 'Keep every book in your library',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => MoveAllBooksScreen(
                        ownerId: ownerId,
                        sourceShelf: currentShelf,
                        shelfRepository: shelfRepository,
                        onCreateShelf: onCreateShelf,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _DeletionChoice(
                  key: const Key('remove-shelf-and-books-choice'),
                  icon: Icons.delete_outline_rounded,
                  title: 'Remove shelf and books',
                  subtitle: 'Remove these entries from your library',
                  danger: true,
                  onTap: () => _confirmRemoval(context, currentShelf),
                ),
                const SizedBox(height: 22),
                OutlinedButton(
                  key: const Key('cancel-delete-shelf-button'),
                  onPressed: () => _cancel(context),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class MoveAllBooksScreen extends StatefulWidget {
  const MoveAllBooksScreen({
    required this.ownerId,
    required this.sourceShelf,
    required this.shelfRepository,
    this.onCreateShelf,
    super.key,
  });

  final String ownerId;
  final Shelf sourceShelf;
  final ShelfRepository shelfRepository;
  final Future<void> Function()? onCreateShelf;

  @override
  State<MoveAllBooksScreen> createState() => _MoveAllBooksScreenState();
}

class _MoveAllBooksScreenState extends State<MoveAllBooksScreen> {
  String? _destinationId;
  bool _moving = false;
  String? _error;

  Future<void> _move(String destinationId) async {
    if (_moving) return;
    if (destinationId == widget.sourceShelf.id) {
      setState(() => _error = 'Choose a different destination shelf.');
      return;
    }
    setState(() {
      _moving = true;
      _error = null;
    });
    try {
      await widget.shelfRepository.moveAllBooksAndDeleteShelf(
        ownerId: widget.ownerId,
        sourceShelfId: widget.sourceShelf.id,
        destinationShelfId: destinationId,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ShelfFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Readuo could not move these books. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Move books first')),
      body: SafeArea(
        child: StreamBuilder<List<Shelf>>(
          stream: widget.shelfRepository.watchShelves(widget.ownerId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _ShelfMutationError(
                message: 'Readuo could not load destination shelves.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final source = _findShelf(snapshot.data!, widget.sourceShelf.id);
            if (source == null) {
              return const _ShelfMutationError(
                message: 'The source shelf is no longer available.',
              );
            }
            final destinations = snapshot.data!
                .where(
                  (candidate) =>
                      candidate.id != source.id &&
                      candidate.ownerId == widget.ownerId,
                )
                .toList();
            final selectedDestination =
                destinations.any((shelf) => shelf.id == _destinationId)
                ? _destinationId
                : destinations.firstOrNull?.id;
            return ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: ReaduoSpacing.screenHorizontal,
                vertical: 24,
              ),
              children: [
                Text(
                  'Choose a destination for all ${source.bookCount} ${source.bookCount == 1 ? 'book' : 'books'}. Then ${source.name} will be deleted.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 18),
                if (destinations.isEmpty)
                  const _SettingsBanner(
                    icon: Icons.folder_off_outlined,
                    text: 'Create another shelf before moving these books.',
                  )
                else
                  RadioGroup<String>(
                    groupValue: selectedDestination,
                    onChanged: _moving
                        ? (_) {}
                        : (value) => setState(() {
                            _destinationId = value;
                            _error = null;
                          }),
                    child: Column(
                      children: [
                        for (final destination in destinations)
                          RadioListTile<String>(
                            key: Key('move-destination-${destination.id}'),
                            value: destination.id,
                            enabled: !_moving,
                            contentPadding: EdgeInsets.zero,
                            title: Text(destination.name),
                            subtitle: Text(
                              '${destination.bookCount} ${destination.bookCount == 1 ? 'book' : 'books'} · ${destination.visibility.label}',
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                const _SettingsBanner(
                  icon: Icons.warning_amber_rounded,
                  text:
                      'The destination shelf’s visibility will apply to the moved books, and inaccessible derived social activity must be removed.',
                ),
                if (widget.onCreateShelf != null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    key: const Key('create-move-destination-button'),
                    onPressed: _moving ? null : widget.onCreateShelf,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create another shelf'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    key: const Key('move-all-error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  key: const Key('move-all-books-button'),
                  onPressed: _moving || selectedDestination == null
                      ? null
                      : () => _move(selectedDestination),
                  child: _moving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Move books & delete shelf'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RemoveShelfConfirmationSheet extends StatefulWidget {
  const _RemoveShelfConfirmationSheet({
    required this.ownerId,
    required this.shelf,
    required this.shelfRepository,
    required this.minimumBottomInset,
  });

  final String ownerId;
  final Shelf shelf;
  final ShelfRepository shelfRepository;
  final double minimumBottomInset;

  @override
  State<_RemoveShelfConfirmationSheet> createState() =>
      _RemoveShelfConfirmationSheetState();
}

class _RemoveShelfConfirmationSheetState
    extends State<_RemoveShelfConfirmationSheet> {
  bool _removing = false;
  String? _error;

  Future<void> _remove() async {
    if (_removing) return;
    setState(() {
      _removing = true;
      _error = null;
    });
    try {
      await widget.shelfRepository.deleteShelfAndBooks(
        ownerId: widget.ownerId,
        shelfId: widget.shelf.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ShelfFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Readuo could not remove this shelf. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dynamicBottomInset =
        mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;
    final bottomInset = dynamicBottomInset > widget.minimumBottomInset
        ? dynamicBottomInset
        : widget.minimumBottomInset;
    final count = widget.shelf.bookCount;
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
              'Remove shelf and $count ${count == 1 ? 'book' : 'books'}?',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            const Text(
              'These library entries, shelf-derived activity, associated reviews, and their comment and like threads will be removed from shared views. This cannot be undone.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('delete-shelf-error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('confirm-delete-shelf-button'),
              onPressed: _removing ? null : _remove,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: _removing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Remove shelf and books'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('cancel-confirm-delete-shelf-button'),
              onPressed: _removing ? null : () => Navigator.of(context).pop(),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeletionShelfCard extends StatelessWidget {
  const _DeletionShelfCard({required this.shelf});

  final Shelf shelf;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ReaduoColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ReaduoColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shelf.name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            '${shelf.bookCount} ${shelf.bookCount == 1 ? 'book' : 'books'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DeletionChoice extends StatelessWidget {
  const _DeletionChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final foreground = danger
        ? Theme.of(context).colorScheme.error
        : ReaduoColors.ink;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: ReaduoColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: ReaduoColors.line),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: foreground),
        title: Text(title, style: TextStyle(color: foreground)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _ShelfMutationError extends StatelessWidget {
  const _ShelfMutationError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ReaduoSpacing.screenHorizontal,
          vertical: 32,
        ),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

Shelf? _findShelf(List<Shelf> shelves, String shelfId) {
  for (final shelf in shelves) {
    if (shelf.id == shelfId) return shelf;
  }
  return null;
}

class _PrivateShelfConfirmationSheet extends StatelessWidget {
  const _PrivateShelfConfirmationSheet({required this.minimumBottomInset});

  final double minimumBottomInset;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dynamicBottomInset =
        mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;
    final bottomInset = dynamicBottomInset > minimumBottomInset
        ? dynamicBottomInset
        : minimumBottomInset;
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
              'Make this shelf private?',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            const Text(
              'Only you will be able to see its books. Earlier activity from this shelf will also disappear from your friends’ Circle feeds.',
            ),
            const SizedBox(height: 14),
            const _SettingsBanner(
              icon: Icons.lock_outline_rounded,
              text: 'Automatic posting will be turned off.',
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('confirm-private-shelf-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Make private'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('keep-shelf-visibility-button'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep current visibility'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsBanner extends StatelessWidget {
  const _SettingsBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ReaduoColors.accentTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: ReaduoColors.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({
    required this.onScan,
    required this.onSearchCatalogue,
    required this.onManualAdd,
  });

  final VoidCallback? onScan;
  final VoidCallback? onSearchCatalogue;
  final VoidCallback? onManualAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        24,
        ReaduoSpacing.screenHorizontal,
        36,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.menu_book_outlined,
            size: 64,
            color: ReaduoColors.accent,
          ),
          const SizedBox(height: 20),
          Text(
            'This shelf is empty',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Scan an ISBN, search the catalogue, or add a book manually.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('empty-shelf-scan'),
            onPressed: onScan,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan a book'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('empty-shelf-catalogue'),
            onPressed: onSearchCatalogue,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search catalogue'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('empty-shelf-manual'),
            onPressed: onManualAdd,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Add manually'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    avatar: Icon(
      icon,
      size: 18,
      color: selected ? ReaduoColors.accent : ReaduoColors.muted,
    ),
    showCheckmark: false,
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
    selectedColor: ReaduoColors.accentTint,
    side: BorderSide(color: selected ? ReaduoColors.accent : ReaduoColors.line),
    labelStyle: TextStyle(
      color: selected ? ReaduoColors.accent : ReaduoColors.ink,
      fontWeight: FontWeight.w600,
    ),
  );
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ReaduoColors.accentTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ReaduoColors.accent),
          const SizedBox(width: 5),
          Text(
            visibility.label,
            style: const TextStyle(
              color: ReaduoColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.onTap, super.key});

  final LibraryBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('shelf-book-${book.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: ReaduoColors.accentTint,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: book.coverUrl == null
                  ? GeneratedBookCover(title: book.title, author: book.author)
                  : BookCoverImage(
                      book.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.menu_book_rounded,
                        size: 42,
                        color: ReaduoColors.accent,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ReaduoColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  book.readingStatus.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ReaduoColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (book.isOwned)
                const Text(
                  'Owned',
                  style: TextStyle(
                    color: ReaduoColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookListError extends StatelessWidget {
  const _BookListError({required this.message, required this.onRetry});

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

class AddBookSheet extends ManualBookFlow {
  const AddBookSheet({
    required super.ownerId,
    required super.shelf,
    required super.bookRepository,
    super.shelfRepository,
    super.existingBooks,
    super.initialTitle,
    super.initialAuthor,
    super.initialIsbn,
    super.pickPhoto,
    super.key,
  });
}
