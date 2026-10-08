import '../widgets/book_information.dart';
import '../widgets/book_cover_image.dart';
import '../widgets/generated_book_cover.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../circle/review_repository.dart';
import '../library/book.dart';
import '../library/book_repository.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';
import '../profile/profile_widgets.dart';
import '../widgets/readuo_bottom_navigation.dart';
import 'circle_review_composer_screen.dart';

class BookDetailsScreen extends StatefulWidget {
  const BookDetailsScreen({
    required this.ownerId,
    required this.shelfId,
    required this.bookId,
    required this.shelfRepository,
    required this.bookRepository,
    this.reviewRepository = const EmptyReviewRepository(),
    this.onOpenFriends,
    this.onOpenProfile,
    this.onOpenShelf,
    this.onCreateShelf,
    this.showBottomNavigation = true,
    super.key,
  });

  final String ownerId;
  final String shelfId;
  final String bookId;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final ReviewRepository reviewRepository;
  final VoidCallback? onOpenFriends;
  final VoidCallback? onOpenProfile;
  final ValueChanged<Shelf>? onOpenShelf;
  final Future<void> Function()? onCreateShelf;
  final bool showBottomNavigation;

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  late Stream<List<Shelf>> _shelves;
  late Stream<LibraryBook?> _book;
  late Stream<CircleReview?> _review;
  late String _activeShelfId;
  LibraryBook? _latestBook;
  bool _savingOwnership = false;
  bool? _ownershipDraft;
  String? _ownershipError;

  @override
  void initState() {
    super.initState();
    _activeShelfId = widget.shelfId;
    _load();
  }

  @override
  void didUpdateWidget(covariant BookDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.shelfId != widget.shelfId ||
        oldWidget.bookId != widget.bookId ||
        oldWidget.shelfRepository != widget.shelfRepository ||
        oldWidget.bookRepository != widget.bookRepository ||
        oldWidget.reviewRepository != widget.reviewRepository) {
      _activeShelfId = widget.shelfId;
      _load();
    }
  }

  void _load() {
    _latestBook = null;
    _shelves = widget.shelfRepository.watchShelves(widget.ownerId);
    _book = widget.bookRepository.watchBook(
      ownerId: widget.ownerId,
      shelfId: _activeShelfId,
      bookId: widget.bookId,
    );
    _review = widget.reviewRepository.watchReview(
      viewerId: widget.ownerId,
      authorId: widget.ownerId,
      bookId: widget.bookId,
    );
  }

  void _retry() => setState(_load);

  void _returnToLibrary() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _showBookOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: !widget.showBottomNavigation,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (_) => const _ManageBookSheet(),
    );
    if (!mounted) return;
    if (action == 'move') {
      final book = _latestBook;
      if (book != null) await _moveBook(book);
    } else if (action == 'remove') {
      final book = _latestBook;
      if (book != null) await _removeBook(book);
    }
  }

  Future<void> _changeStatus(LibraryBook book) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: !widget.showBottomNavigation,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (_) => _ReadingStatusSheet(
        ownerId: widget.ownerId,
        shelfId: _activeShelfId,
        book: book,
        bookRepository: widget.bookRepository,
      ),
    );
  }

  Future<void> _saveOwnership(bool isOwned) async {
    if (_savingOwnership) return;
    setState(() {
      _ownershipDraft = isOwned;
      _ownershipError = null;
      _savingOwnership = true;
    });
    try {
      await widget.bookRepository.updateOwnership(
        ownerId: widget.ownerId,
        shelfId: _activeShelfId,
        bookId: widget.bookId,
        isOwned: isOwned,
      );
      if (mounted) {
        setState(() {
          _ownershipDraft = null;
          _ownershipError = null;
        });
      }
    } on BookFailure catch (error) {
      if (mounted) setState(() => _ownershipError = error.message);
    } finally {
      if (mounted) setState(() => _savingOwnership = false);
    }
  }

  Future<void> _moveBook(LibraryBook book) async {
    final destination = await showModalBottomSheet<Shelf>(
      context: context,
      useRootNavigator: !widget.showBottomNavigation,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (_) => _MoveBookSheet(
        ownerId: widget.ownerId,
        sourceShelfId: _activeShelfId,
        book: book,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
        onCreateShelf: widget.onCreateShelf,
      ),
    );
    if (destination == null || !mounted) return;
    setState(() {
      _activeShelfId = destination.id;
      _ownershipDraft = null;
      _ownershipError = null;
      _book = widget.bookRepository.watchBook(
        ownerId: widget.ownerId,
        shelfId: destination.id,
        bookId: widget.bookId,
      );
    });
  }

  Future<void> _removeBook(LibraryBook book) async {
    final removed = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: !widget.showBottomNavigation,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (_) => _RemoveBookSheet(
        ownerId: widget.ownerId,
        shelfId: _activeShelfId,
        book: book,
        bookRepository: widget.bookRepository,
      ),
    );
    if (removed != true || !mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      setState(_load);
    }
  }

  Future<void> _openReview(LibraryBook book, CircleReview? review) async {
    final createdAt = book.createdAt;
    if (createdAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This saved edition is still syncing. Try again.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CircleReviewComposerScreen(
          ownerId: widget.ownerId,
          repository: widget.reviewRepository,
          source:
              review?.toDraft() ??
              CircleReviewDraft(
                reviewId: circleReviewId(widget.ownerId, book.id),
                shelfId: _activeShelfId,
                bookId: book.id,
                bookCreatedAt: createdAt,
                title: book.title,
                bookAuthor: book.author,
                coverUrl: book.coverUrl,
                text: '',
                rating: null,
              ),
          review: review,
        ),
      ),
    );
  }

  Future<void> _deleteReview(CircleReview review) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          0,
          ReaduoSpacing.screenHorizontal,
          20 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Delete this review?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: ReaduoColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This removes the review and rating from Circle. The book stays in your library.',
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('confirm-delete-review'),
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
      await widget.reviewRepository.deleteReview(
        authorId: widget.ownerId,
        reviewId: review.id,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProfilePage(
      title: 'Book details',
      compactHeader: true,
      actions: [
        IconButton.outlined(
          key: const Key('book-options-button'),
          style: IconButton.styleFrom(
            side: const BorderSide(color: ReaduoColors.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          tooltip: 'Book options',
          onPressed: _showBookOptions,
          icon: const Icon(Icons.more_horiz_rounded),
        ),
        const SizedBox(width: 20),
      ],
      bottomNavigationBar: widget.showBottomNavigation
          ? ReaduoBottomNavigation(
              onLibrary: _returnToLibrary,
              onFriends: widget.onOpenFriends,
              onProfile: widget.onOpenProfile,
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<Shelf>>(
          stream: _shelves,
          builder: (context, shelfSnapshot) {
            if (shelfSnapshot.hasError) {
              return _DetailError(
                message: 'Readuo could not load this book’s shelf.',
                onRetry: _retry,
              );
            }
            if (!shelfSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final shelf = _findShelf(shelfSnapshot.data!, _activeShelfId);
            if (shelf == null) {
              return _MissingBook(onReturn: _returnToLibrary);
            }
            return StreamBuilder<LibraryBook?>(
              stream: _book,
              builder: (context, bookSnapshot) {
                if (bookSnapshot.hasError) {
                  final error = bookSnapshot.error;
                  return _DetailError(
                    message: error is BookFailure
                        ? error.message
                        : 'Readuo could not load this saved book.',
                    onRetry: _retry,
                  );
                }
                if (!bookSnapshot.hasData &&
                    bookSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final book = bookSnapshot.data;
                if (book == null) {
                  return _MissingBook(onReturn: _returnToLibrary);
                }
                _latestBook = book;
                return StreamBuilder<CircleReview?>(
                  stream: _review,
                  builder: (context, reviewSnapshot) => _BookDetailsBody(
                    book: book,
                    shelf: shelf,
                    review: reviewSnapshot.data,
                    reviewError: reviewSnapshot.hasError
                        ? 'Readuo could not load your review.'
                        : null,
                    displayedOwnership: _ownershipDraft ?? book.isOwned,
                    savingOwnership: _savingOwnership,
                    ownershipError: _ownershipError,
                    onOwnershipChanged: shelf.mutationOperationId == null
                        ? _saveOwnership
                        : null,
                    onRetryOwnership: _ownershipDraft == null
                        ? null
                        : () => _saveOwnership(_ownershipDraft!),
                    onChangeStatus: shelf.mutationOperationId == null
                        ? () => _changeStatus(book)
                        : null,
                    onReturnToLibrary: _returnToLibrary,
                    onOpenShelf: () => widget.onOpenShelf?.call(shelf),
                    onWriteReview: shelf.mutationOperationId == null
                        ? () => _openReview(book, reviewSnapshot.data)
                        : null,
                    onDeleteReview: reviewSnapshot.data == null
                        ? null
                        : () => _deleteReview(reviewSnapshot.data!),
                  ),
                );
              },
            );
          },
        ),
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

class _BookDetailsBody extends StatelessWidget {
  const _BookDetailsBody({
    required this.book,
    required this.shelf,
    required this.review,
    required this.reviewError,
    required this.displayedOwnership,
    required this.savingOwnership,
    required this.ownershipError,
    required this.onOwnershipChanged,
    required this.onRetryOwnership,
    required this.onChangeStatus,
    required this.onReturnToLibrary,
    required this.onOpenShelf,
    required this.onWriteReview,
    required this.onDeleteReview,
  });

  final LibraryBook book;
  final Shelf shelf;
  final CircleReview? review;
  final String? reviewError;
  final bool displayedOwnership;
  final bool savingOwnership;
  final String? ownershipError;
  final ValueChanged<bool>? onOwnershipChanged;
  final VoidCallback? onRetryOwnership;
  final VoidCallback? onChangeStatus;
  final VoidCallback onReturnToLibrary;
  final VoidCallback onOpenShelf;
  final VoidCallback? onWriteReview;
  final VoidCallback? onDeleteReview;

  @override
  Widget build(BuildContext context) {
    final locked = shelf.mutationOperationId != null;
    return ListView(
      key: const Key('book-details-scroll'),
      padding: const EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        12,
        ReaduoSpacing.screenHorizontal,
        28,
      ),
      children: [
        if (locked) ...[
          _NoticeCard(
            icon: Icons.sync_rounded,
            message:
                'This shelf is changing. Book edits are paused until the confirmed shelf change finishes.',
            actionLabel: 'Return to Library to continue',
            onAction: onReturnToLibrary,
          ),
          const SizedBox(height: 18),
        ],
        _BookHero(book: book),
        const SizedBox(height: 12),
        BookIsbnRow(book: book),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            _DetailChip(
              label: displayedOwnership ? 'Owned' : 'Not owned',
              icon: displayedOwnership ? Icons.check_rounded : null,
              emphasized: displayedOwnership,
            ),
            _DetailChip(label: book.readingStatus.label, emphasized: true),
          ],
        ),
        const SizedBox(height: 18),
        _ShelfRow(shelf: shelf, onTap: onOpenShelf),
        const SizedBox(height: 14),
        _StatusButton(onPressed: onChangeStatus),
        const SizedBox(height: 16),
        Column(
          children: [
            _OwnershipControl(
              value: displayedOwnership,
              saving: savingOwnership,
              onChanged: onOwnershipChanged,
            ),
            if (ownershipError != null) ...[
              const SizedBox(height: 10),
              _NoticeCard(
                icon: Icons.error_outline_rounded,
                message: ownershipError!,
                actionLabel: 'Retry ownership change',
                onAction: onRetryOwnership,
              ),
            ],
          ],
        ),
        if (!displayedOwnership) ...[
          const SizedBox(height: 10),
          const _SavedBookNotice(),
        ],
        const SizedBox(height: 16),
        BookDescription(book: book),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'My review',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: ReaduoColors.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('write-review-button'),
              onPressed: onWriteReview,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(review == null ? 'Write a review' : 'Edit review'),
            ),
          ],
        ),
        if (reviewError != null)
          _NoticeCard(
            icon: Icons.error_outline_rounded,
            message: reviewError!,
            actionLabel: null,
            onAction: null,
          )
        else if (review == null)
          Text(
            'Share a written review with your friends. A star rating is optional.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          _OwnReviewCard(review: review!, onDelete: onDeleteReview),
      ],
    );
  }
}

class _OwnReviewCard extends StatelessWidget {
  const _OwnReviewCard({required this.review, required this.onDelete});

  final CircleReview review;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('own-book-review'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ReaduoColors.paper,
      border: Border.all(color: ReaduoColors.line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (review.rating != null) ...[
          Semantics(
            label: '${review.rating} out of 5 stars',
            child: Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  Icon(
                    star <= review.rating!
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 22,
                    color: const Color(0xFFE3A008),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(review.text, style: const TextStyle(height: 1.45)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('delete-review-button'),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ),
      ],
    ),
  );
}

class _ReadingStatusSheet extends StatefulWidget {
  const _ReadingStatusSheet({
    required this.ownerId,
    required this.shelfId,
    required this.book,
    required this.bookRepository,
  });

  final String ownerId;
  final String shelfId;
  final LibraryBook book;
  final BookRepository bookRepository;

  @override
  State<_ReadingStatusSheet> createState() => _ReadingStatusSheetState();
}

class _ReadingStatusSheetState extends State<_ReadingStatusSheet> {
  late ReadingStatus _selected = widget.book.readingStatus;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.bookRepository.updateReadingStatus(
        ownerId: widget.ownerId,
        shelfId: widget.shelfId,
        bookId: widget.book.id,
        readingStatus: _selected,
      );
      if (mounted) Navigator.of(context).pop();
    } on BookFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        0,
        ReaduoSpacing.screenHorizontal,
        20 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reading status',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: ReaduoColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _CompactBookSummary(book: widget.book),
          const SizedBox(height: 12),
          RadioGroup<ReadingStatus>(
            groupValue: _selected,
            onChanged: _saving
                ? (_) {}
                : (value) {
                    if (value != null) setState(() => _selected = value);
                  },
            child: Column(
              children: [
                for (final status in ReadingStatus.values)
                  RadioListTile<ReadingStatus>(
                    key: Key('reading-status-${status.name}'),
                    value: status,
                    enabled: !_saving,
                    title: Text(status.label),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              key: const Key('reading-status-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('save-reading-status-button'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save status'),
          ),
        ],
      ),
    );
  }
}

class _ManageBookSheet extends StatelessWidget {
  const _ManageBookSheet();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      ReaduoSpacing.screenHorizontal,
      0,
      ReaduoSpacing.screenHorizontal,
      20 + MediaQuery.viewPaddingOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Manage book',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: ReaduoColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        ListTile(
          key: const Key('manage-book-move'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.drive_file_move_outline),
          title: const Text('Move to another shelf'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).pop('move'),
        ),
        ListTile(
          key: const Key('manage-book-remove'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_outline_rounded),
          title: const Text('Remove from my library'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).pop('remove'),
        ),
      ],
    ),
  );
}

class _RemoveBookSheet extends StatefulWidget {
  const _RemoveBookSheet({
    required this.ownerId,
    required this.shelfId,
    required this.book,
    required this.bookRepository,
  });

  final String ownerId;
  final String shelfId;
  final LibraryBook book;
  final BookRepository bookRepository;

  @override
  State<_RemoveBookSheet> createState() => _RemoveBookSheetState();
}

class _RemoveBookSheetState extends State<_RemoveBookSheet> {
  bool _removing = false;
  String? _error;

  Future<void> _remove() async {
    if (_removing) return;
    setState(() {
      _removing = true;
      _error = null;
    });
    try {
      await widget.bookRepository.removeBook(
        ownerId: widget.ownerId,
        shelfId: widget.shelfId,
        bookId: widget.book.id,
        expectedCreatedAt: widget.book.createdAt,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BookFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return SingleChildScrollView(
      key: const Key('remove-book-sheet'),
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
            'Remove from your library?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: ReaduoColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LargeBookCover(book: widget.book, width: 72, height: 104),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.book.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.book.author),
                    if (widget.book.isbn != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'ISBN ${widget.book.isbn}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'This removes the single library entry, shelf-derived activity, and any associated review thread from shared views. You can add the book again later.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('remove-book-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            key: const Key('remove-book-button'),
            onPressed: _removing ? null : _remove,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(_removing ? 'Removing…' : 'Remove book'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('keep-book-button'),
            onPressed: _removing
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Keep book'),
          ),
        ],
      ),
    );
  }
}

class _MoveBookSheet extends StatefulWidget {
  const _MoveBookSheet({
    required this.ownerId,
    required this.sourceShelfId,
    required this.book,
    required this.shelfRepository,
    required this.bookRepository,
    required this.onCreateShelf,
  });

  final String ownerId;
  final String sourceShelfId;
  final LibraryBook book;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final Future<void> Function()? onCreateShelf;

  @override
  State<_MoveBookSheet> createState() => _MoveBookSheetState();
}

class _MoveBookSheetState extends State<_MoveBookSheet> {
  late Stream<List<Shelf>> _shelves = widget.shelfRepository.watchShelves(
    widget.ownerId,
  );
  String? _selectedShelfId;
  bool _moving = false;
  String? _error;

  Future<void> _move(Shelf destination) async {
    if (_moving) return;
    setState(() {
      _moving = true;
      _error = null;
      _selectedShelfId = destination.id;
    });
    try {
      await widget.bookRepository.moveBook(
        ownerId: widget.ownerId,
        sourceShelfId: widget.sourceShelfId,
        destinationShelfId: destination.id,
        bookId: widget.book.id,
      );
      if (mounted) Navigator.of(context).pop(destination);
    } on BookFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return StreamBuilder<List<Shelf>>(
      stream: _shelves,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              0,
              ReaduoSpacing.screenHorizontal,
              20 + bottomInset + safeBottom,
            ),
            child: _DetailError(
              message: 'Readuo could not load your destination shelves.',
              onRetry: () => setState(() {
                _shelves = widget.shelfRepository.watchShelves(widget.ownerId);
              }),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 260,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final destinations = snapshot.data!
            .where(
              (shelf) =>
                  shelf.ownerId == widget.ownerId &&
                  shelf.id != widget.sourceShelfId &&
                  shelf.mutationOperationId == null,
            )
            .toList();
        final sourceShelf = snapshot.data!
            .where((shelf) => shelf.id == widget.sourceShelfId)
            .firstOrNull;
        final selected =
            destinations.any((shelf) => shelf.id == _selectedShelfId)
            ? _selectedShelfId
            : destinations.firstOrNull?.id;
        final destination = destinations
            .where((shelf) => shelf.id == selected)
            .firstOrNull;
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
                'Move to a shelf',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: ReaduoColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.book.title} is currently on ${sourceShelf?.name ?? 'this shelf'}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              if (destinations.isEmpty)
                const _NoticeCard(
                  icon: Icons.folder_off_outlined,
                  message:
                      'Create or unlock another shelf before moving this book.',
                  actionLabel: 'No destination available',
                  onAction: null,
                )
              else
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: _moving
                      ? (_) {}
                      : (value) => setState(() => _selectedShelfId = value),
                  child: Column(
                    children: [
                      for (final shelf in destinations)
                        RadioListTile<String>(
                          key: Key('book-move-destination-${shelf.id}'),
                          value: shelf.id,
                          enabled: !_moving,
                          contentPadding: EdgeInsets.zero,
                          title: Text(shelf.name),
                          subtitle: Text(
                            '${shelf.bookCount} ${shelf.bookCount == 1 ? 'book' : 'books'} · ${shelf.visibility.label}',
                          ),
                        ),
                    ],
                  ),
                ),
              if (widget.onCreateShelf != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('create-book-move-shelf-button'),
                    onPressed: _moving ? null : widget.onCreateShelf,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create another shelf'),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ReaduoColors.accentTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'The destination shelf’s visibility applies immediately. Revoke inaccessible social and discovery views, subject to documented offline-cache limits.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('move-book-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('move-book-button'),
                onPressed: _moving || destination == null
                    ? null
                    : () => _move(destination),
                child: Text(_moving ? 'Moving…' : 'Move book'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LargeBookCover extends StatelessWidget {
  const _LargeBookCover({
    required this.book,
    this.width = 132,
    this.height = 190,
  });

  final LibraryBook book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('book-details-cover'),
    width: width,
    height: height,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: ReaduoColors.accentTint,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 16,
          offset: Offset(0, 6),
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
              size: 54,
              color: ReaduoColors.accent,
            ),
          ),
  );
}

class _BookHero extends StatelessWidget {
  const _BookHero({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _LargeBookCover(book: book, width: 112, height: 160),
      const SizedBox(width: 18),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                key: const Key('book-details-title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: ReaduoColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(book.author, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              BookEditionMetadata(book: book),
            ],
          ),
        ),
      ),
    ],
  );
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('change-reading-status-button'),
    onPressed: onPressed,
    icon: const Icon(Icons.menu_book_outlined),
    label: const Text('Change reading status'),
  );
}

class _OwnershipControl extends StatelessWidget {
  const _OwnershipControl({
    required this.value,
    required this.saving,
    required this.onChanged,
  });

  final bool value;
  final bool saving;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(useMaterial3: false),
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      activeColor: ReaduoColors.accent,
      key: const Key('book-ownership-toggle'),
      value: value,
      onChanged: saving ? null : onChanged,
      title: const Text(
        'I own this book',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Turn off to hide this book from discovery.',
        style: TextStyle(fontSize: 12, height: 1.4, color: ReaduoColors.muted),
      ),
      secondary: saving
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
    ),
  );
}

class _SavedBookNotice extends StatelessWidget {
  const _SavedBookNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ReaduoColors.accentTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.bookmark_outline_rounded, color: ReaduoColors.accent),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'This book stays in your own search. Ownership discovery is coming later.',
          ),
        ),
      ],
    ),
  );
}

class _CompactBookSummary extends StatelessWidget {
  const _CompactBookSummary({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _LargeBookCover(book: book, width: 58, height: 82),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              book.title,
              style: const TextStyle(
                color: ReaduoColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(book.author, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, this.icon, this.emphasized = false});

  final String label;
  final IconData? icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: label == 'Owned'
          ? const Color(0xFFE9F5EE)
          : emphasized
          ? ReaduoColors.accentTint
          : const Color(0xFFF0F2F6),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 13,
            color: label == 'Owned'
                ? const Color(0xFF397A55)
                : ReaduoColors.accent,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: label == 'Owned'
                ? const Color(0xFF397A55)
                : ReaduoColors.accent,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.shelf, required this.onTap});

  final Shelf shelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: const Border(bottom: BorderSide(color: ReaduoColors.line)),
    child: InkWell(
      key: const Key('book-shelf-row'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'On ${shelf.name}',
                    style: const TextStyle(
                      color: ReaduoColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${shelf.visibility.label} shelf'),
                ],
              ),
            ),
            const Icon(LucideIcons.libraryBig, color: ReaduoColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3D8),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE6C36A)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: ReaduoColors.ink),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class _MissingBook extends StatelessWidget {
  const _MissingBook({required this.onReturn});

  final VoidCallback onReturn;

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
          const Icon(Icons.book_outlined, size: 48, color: ReaduoColors.accent),
          const SizedBox(height: 14),
          Text(
            'This saved book is no longer here',
            key: const Key('missing-book-message'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: ReaduoColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'It may have moved or been removed. Return to Library to open its current location.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onReturn,
            child: const Text('Return to Library'),
          ),
        ],
      ),
    ),
  );
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

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
          const Icon(Icons.cloud_off_outlined, size: 46),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
