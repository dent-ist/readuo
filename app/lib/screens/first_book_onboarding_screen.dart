import 'dart:async';

import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/book_lookup.dart';
import '../library/book_repository.dart';
import '../library/catalogue_repository.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../onboarding/onboarding_repository.dart';
import '../theme/readuo_theme.dart';
import 'catalogue_search_screen.dart';
import 'isbn_scanner_screen.dart';
import 'my_library_screen.dart';
import 'shelf_details_screen.dart';

class FirstBookOnboardingScreen extends StatefulWidget {
  const FirstBookOnboardingScreen({
    required this.ownerId,
    required this.onboardingRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.bookLookupRepository,
    required this.catalogueRepository,
    required this.onFinished,
    super.key,
  });

  final String ownerId;
  final OnboardingRepository onboardingRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final BookLookupRepository bookLookupRepository;
  final CatalogueRepository catalogueRepository;
  final VoidCallback onFinished;

  @override
  State<FirstBookOnboardingScreen> createState() =>
      _FirstBookOnboardingScreenState();
}

class _FirstBookOnboardingScreenState extends State<FirstBookOnboardingScreen> {
  StreamSubscription<List<LibraryBook>>? _bookSubscription;
  bool _childFlowActive = false;
  bool _hasSavedBook = false;
  bool _finishing = false;
  bool _skipRequested = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bookSubscription = widget.bookRepository
        .watchLibraryBooks(widget.ownerId)
        .listen((books) {
          if (!mounted || books.isEmpty) return;
          _hasSavedBook = true;
          if (!_childFlowActive) _complete();
        }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _bookSubscription?.cancel();
    super.dispose();
  }

  Future<Shelf?> _createShelf() => showModalBottomSheet<Shelf>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: ReaduoColors.paper,
    builder: (_) => CreateShelfSheet(
      ownerId: widget.ownerId,
      shelfRepository: widget.shelfRepository,
    ),
  );

  Future<void> _openManualAdd(Shelf shelf, IsbnManualSeed seed) =>
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AddBookSheet(
          ownerId: widget.ownerId,
          shelf: shelf,
          shelfRepository: widget.shelfRepository,
          bookRepository: widget.bookRepository,
          initialTitle: seed.title,
          initialAuthor: seed.author,
          initialIsbn: seed.isbn,
        ),
      );

  Future<void> _openScanner() async {
    if (_childFlowActive || _finishing) return;
    setState(() {
      _childFlowActive = true;
      _error = null;
    });
    IsbnScanResult? result;
    try {
      result = await Navigator.of(context).push<IsbnScanResult>(
        MaterialPageRoute<IsbnScanResult>(
          builder: (_) => IsbnScannerScreen(
            ownerId: widget.ownerId,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            lookupRepository: widget.bookLookupRepository,
            onCreateShelf: _createShelf,
            onSearchCatalogue: (shelf, query) => _openCatalogue(
              initialShelf: shelf,
              initialQuery: query,
              completeAfterSave: false,
            ),
            onOpenManualAdd: _openManualAdd,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _childFlowActive = false);
    }
    if (!mounted) return;
    if (result != null || _hasSavedBook) await _complete();
  }

  Future<void> _openCatalogue({
    Shelf? initialShelf,
    String initialQuery = '',
    bool manual = false,
    bool completeAfterSave = true,
  }) async {
    if (completeAfterSave && (_childFlowActive || _finishing)) return;
    if (completeAfterSave) {
      setState(() {
        _childFlowActive = true;
        _error = null;
      });
    }
    Shelf? savedShelf;
    try {
      savedShelf = await Navigator.of(context).push<Shelf>(
        MaterialPageRoute<Shelf>(
          builder: (_) => CatalogueSearchScreen(
            ownerId: widget.ownerId,
            catalogueRepository: widget.catalogueRepository,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            initialShelf: initialShelf,
            initialQuery: initialQuery,
            onCreateShelf: _createShelf,
            startWithManualEntry: manual,
            returnAfterSave: completeAfterSave,
          ),
        ),
      );
    } finally {
      if (completeAfterSave && mounted) {
        setState(() => _childFlowActive = false);
      }
    }
    if (!mounted || !completeAfterSave) return;
    if (savedShelf != null || _hasSavedBook) await _complete();
  }

  Future<void> _complete() async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _skipRequested = false;
      _error = null;
    });
    try {
      await widget.onboardingRepository.completeFirstBook(widget.ownerId);
      if (mounted) widget.onFinished();
    } on OnboardingFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Your book is safe, but setup could not finish. Retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _skip() async {
    if (_finishing || _childFlowActive) return;
    setState(() {
      _finishing = true;
      _skipRequested = true;
      _error = null;
    });
    try {
      await widget.onboardingRepository.skipFirstBook(widget.ownerId);
      if (mounted) widget.onFinished();
    } on OnboardingFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save this choice. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _finishing || _childFlowActive;
    return Scaffold(
      key: const Key('first-book-onboarding'),
      appBar: AppBar(
        toolbarHeight: 82,
        automaticallyImplyLeading: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your library starts here'),
            SizedBox(height: 4),
            Text(
              'Connect with friends whenever you’re ready.',
              style: TextStyle(
                color: ReaduoColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ReaduoSpacing.screenHorizontal,
            36,
            ReaduoSpacing.screenHorizontal,
            24,
          ),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ReaduoColors.accentTint,
                  borderRadius: BorderRadius.circular(23),
                ),
                child: const Icon(
                  Icons.local_library_outlined,
                  color: ReaduoColors.accent,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Make room for your first book',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: ReaduoColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Scan a barcode and we’ll help fill in the details.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ReaduoColors.muted),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('first-book-scan'),
              onPressed: busy ? null : _openScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan my first book'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('first-book-search'),
              onPressed: busy ? null : () => _openCatalogue(),
              child: const Text('Search for a book instead'),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('first-book-manual'),
              onPressed: busy ? null : () => _openCatalogue(manual: true),
              child: const Text('Add a book manually'),
            ),
            TextButton(
              key: const Key('first-book-skip'),
              onPressed: busy ? null : _skip,
              child: _finishing && _skipRequested
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('I’ll do this later'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('first-book-error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const Key('first-book-retry'),
                onPressed: _finishing
                    ? null
                    : (_skipRequested ? _skip : _complete),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
