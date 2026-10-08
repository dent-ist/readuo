import '../widgets/readuo_image_cache.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/book_repository.dart';
import '../library/catalogue_repository.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';

class CatalogueSearchScreen extends StatefulWidget {
  const CatalogueSearchScreen({
    required this.ownerId,
    required this.catalogueRepository,
    required this.shelfRepository,
    required this.bookRepository,
    this.initialShelf,
    this.initialQuery = '',
    this.onCreateShelf,
    this.startWithManualEntry = false,
    this.returnAfterSave = false,
    super.key,
  });

  final String ownerId;
  final CatalogueRepository catalogueRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final Shelf? initialShelf;
  final String initialQuery;
  final Future<Shelf?> Function()? onCreateShelf;
  final bool startWithManualEntry;
  final bool returnAfterSave;

  @override
  State<CatalogueSearchScreen> createState() => _CatalogueSearchScreenState();
}

enum _CatalogueStage { prompt, loading, results, editions, empty, failure }

class _CatalogueSearchScreenState extends State<CatalogueSearchScreen> {
  late final TextEditingController _queryController = TextEditingController(
    text: widget.initialQuery,
  );
  final FocusNode _queryFocusNode = FocusNode();
  final ScrollController _worksScrollController = ScrollController();
  _CatalogueStage _stage = _CatalogueStage.prompt;
  List<CatalogueWork> _works = const [];
  List<CatalogueEdition> _editions = const [];
  CatalogueWork? _selectedWork;
  CatalogueProvider? _workProvider;
  String _submittedQuery = '';
  String? _message;
  bool _workHasMore = false;
  bool _workLoadingMore = false;
  int _workNextOffset = 0;
  String? _workContinuationError;
  bool _editionHasMore = false;
  bool _editionLoadingMore = false;
  int _editionNextOffset = 0;
  String? _editionContinuationError;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.startWithManualEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openManual();
      });
    } else if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(reset: true));
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _queryController.dispose();
    _queryFocusNode.dispose();
    _worksScrollController.dispose();
    super.dispose();
  }

  Future<void> _search({required bool reset}) async {
    final query = reset ? _queryController.text.trim() : _submittedQuery;
    final generation = reset ? ++_generation : _generation;
    if (query.isEmpty) {
      setState(() {
        _stage = _CatalogueStage.prompt;
        _message = 'Enter a title, author, or ISBN.';
        _works = const [];
        _selectedWork = null;
        _editions = const [];
        _workProvider = null;
        _workHasMore = false;
        _workLoadingMore = false;
        _workNextOffset = 0;
        _workContinuationError = null;
        _editionHasMore = false;
        _editionLoadingMore = false;
        _editionNextOffset = 0;
        _editionContinuationError = null;
      });
      return;
    }
    final offset = reset ? 0 : _workNextOffset;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submittedQuery = query;
      _message = null;
      if (reset) {
        _stage = _CatalogueStage.loading;
        _works = const [];
        _selectedWork = null;
        _editions = const [];
        _workProvider = null;
        _workHasMore = false;
        _workLoadingMore = false;
        _workNextOffset = 0;
        _workContinuationError = null;
        _editionHasMore = false;
        _editionLoadingMore = false;
        _editionNextOffset = 0;
        _editionContinuationError = null;
      } else {
        _workLoadingMore = true;
        _workContinuationError = null;
      }
    });
    try {
      final page = await widget.catalogueRepository.search(
        query,
        offset: offset,
        limit: 8,
        provider: reset ? null : _workProvider,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _works = reset ? page.items : _mergeWorks(_works, page.items);
        _workProvider = page.provider;
        _workHasMore = page.hasMore;
        _workNextOffset = offset + 8;
        _workLoadingMore = false;
        _workContinuationError = null;
        _stage = _works.isEmpty
            ? _CatalogueStage.empty
            : _CatalogueStage.results;
      });
    } on CatalogueFailure catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _workLoadingMore = false;
        if (reset) {
          _message = error.message;
          _stage = _CatalogueStage.failure;
        } else {
          _workContinuationError = error.message;
          _stage = _CatalogueStage.results;
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _workLoadingMore = false;
        if (reset) {
          _message = 'Catalogue search failed unexpectedly. Please retry.';
          _stage = _CatalogueStage.failure;
        } else {
          _workContinuationError = 'Could not load more matches. Please retry.';
          _stage = _CatalogueStage.results;
        }
      });
    }
  }

  Future<void> _openWork(CatalogueWork work) async {
    if (work.edition != null) {
      await _openConfirmation(
        work.edition!,
        manual: work.edition!.isbn == null,
      );
      return;
    }
    final generation = ++_generation;
    setState(() {
      _workLoadingMore = false;
      _selectedWork = work;
      _editions = const [];
      _message = null;
      _editionHasMore = false;
      _editionLoadingMore = false;
      _editionNextOffset = 0;
      _editionContinuationError = null;
      _stage = _CatalogueStage.loading;
    });
    try {
      final page = await widget.catalogueRepository.editions(work, limit: 20);
      if (!mounted || generation != _generation) return;
      setState(() {
        _editions = page.items;
        _editionHasMore = page.hasMore;
        _editionNextOffset = 20;
        _stage = _CatalogueStage.editions;
      });
    } on CatalogueFailure catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _message = error.message;
        _stage = _CatalogueStage.failure;
      });
    }
  }

  Future<void> _loadMoreEditions() async {
    final work = _selectedWork;
    if (work == null || _editionLoadingMore) return;
    final generation = _generation;
    setState(() {
      _editionLoadingMore = true;
      _editionContinuationError = null;
    });
    try {
      final page = await widget.catalogueRepository.editions(
        work,
        offset: _editionNextOffset,
        limit: 20,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _editions = _mergeEditions(_editions, page.items);
        _editionHasMore = page.hasMore;
        _editionNextOffset += 20;
        _editionLoadingMore = false;
      });
    } on CatalogueFailure catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _editionContinuationError = error.message;
        _editionLoadingMore = false;
      });
    }
  }

  void _backToResults() {
    _generation += 1;
    setState(() {
      _workLoadingMore = false;
      _selectedWork = null;
      _editions = const [];
      _message = null;
      _editionHasMore = false;
      _editionLoadingMore = false;
      _editionNextOffset = 0;
      _editionContinuationError = null;
      _stage = _works.isEmpty ? _CatalogueStage.empty : _CatalogueStage.results;
    });
  }

  Future<void> _openConfirmation(
    CatalogueEdition edition, {
    bool manual = false,
  }) async {
    final savedShelf = await Navigator.of(context).push<Shelf>(
      MaterialPageRoute<Shelf>(
        builder: (_) => CatalogueConfirmationScreen(
          ownerId: widget.ownerId,
          edition: edition,
          manualEntry: manual,
          initialShelf: widget.initialShelf,
          shelfRepository: widget.shelfRepository,
          bookRepository: widget.bookRepository,
          onCreateShelf: widget.onCreateShelf,
        ),
      ),
    );
    if (savedShelf == null || !mounted) return;
    if (widget.returnAfterSave) {
      Navigator.of(context).pop(savedShelf);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Book saved to “${savedShelf.name}”.')),
      );
  }

  void _openManual({CatalogueEdition? edition}) {
    final seed =
        edition ??
        CatalogueEdition(
          id: 'manual:${DateTime.now().microsecondsSinceEpoch}',
          title: _submittedQuery,
          author: '',
          isbn: null,
          publisher: null,
          publishedYear: null,
          format: null,
          description: null,
          coverUrl: null,
          sourceUrl: '',
          provider: _workProvider ?? CatalogueProvider.openLibrary,
        );
    _openConfirmation(seed, manual: true);
  }

  void _resetToPrompt({required bool clearQuery, bool focus = false}) {
    _generation += 1;
    if (clearQuery) _queryController.clear();
    setState(() {
      _stage = _CatalogueStage.prompt;
      _works = const [];
      _editions = const [];
      _selectedWork = null;
      _workProvider = null;
      _submittedQuery = '';
      _message = null;
      _workHasMore = false;
      _workLoadingMore = false;
      _workNextOffset = 0;
      _workContinuationError = null;
      _editionHasMore = false;
      _editionLoadingMore = false;
      _editionNextOffset = 0;
      _editionContinuationError = null;
    });
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _queryFocusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEditionRoute = _selectedWork != null;
    return PopScope<void>(
      canPop: !hasEditionRoute,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && hasEditionRoute) _backToResults();
      },
      child: Scaffold(
        key: const Key('catalogue-search'),
        appBar: _catalogueAppBar('Find a book'),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ReaduoSpacing.screenHorizontal,
                  12,
                  ReaduoSpacing.screenHorizontal,
                  10,
                ),
                child: _CatalogueSearchField(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  errorText: _stage == _CatalogueStage.prompt ? _message : null,
                  onSearch: () => _search(reset: true),
                  onChanged: (value) {
                    if (value.trim().isEmpty &&
                        (_stage != _CatalogueStage.prompt ||
                            _submittedQuery.isNotEmpty)) {
                      _resetToPrompt(clearQuery: false);
                    }
                  },
                ),
              ),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) => switch (_stage) {
    _CatalogueStage.prompt => _CataloguePrompt(onManual: _openManual),
    _CatalogueStage.loading => const Center(
      child: CircularProgressIndicator(key: Key('catalogue-loading')),
    ),
    _CatalogueStage.empty => _CatalogueMessage(
      key: const Key('catalogue-no-results'),
      icon: Icons.search_off_rounded,
      accentMark: true,
      title: 'No catalogue matches',
      message:
          'Try another title or author, or enter the book details yourself.',
      primaryLabel: 'Add manually',
      primaryOutlined: true,
      onPrimary: _openManual,
      secondaryLabel: 'Enter an ISBN',
      onSecondary: () => _resetToPrompt(clearQuery: true, focus: true),
    ),
    _CatalogueStage.failure => _CatalogueMessage(
      key: const Key('catalogue-error'),
      icon: Icons.cloud_off_outlined,
      title: 'Catalogue unavailable',
      message: _message ?? 'Please retry.',
      primaryLabel: _selectedWork == null ? 'Retry search' : 'Retry editions',
      onPrimary: _selectedWork == null
          ? () => _search(reset: true)
          : () => _openWork(_selectedWork!),
      secondaryLabel: 'Enter another ISBN',
      onSecondary: () => _resetToPrompt(clearQuery: true, focus: true),
      tertiaryLabel: 'Add manually',
      onTertiary: _openManual,
    ),
    _CatalogueStage.results => _buildResults(context),
    _CatalogueStage.editions => _buildEditions(context),
  };

  Widget _buildResults(BuildContext context) {
    return ListView(
      key: const Key('catalogue-results'),
      controller: _worksScrollController,
      padding: const EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        8,
        ReaduoSpacing.screenHorizontal,
        28,
      ),
      children: [
        Text(
          'Choose the matching book, then its ISBN-specific edition. Different ISBNs remain separate books.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final work in _works)
          _CatalogueResultRow(
            key: ValueKey('catalogue-work-${work.id}'),
            title: work.title,
            author: work.author,
            coverUrl: work.edition?.coverUrl,
            metadata: [
              if (work.editionCount != null)
                '${work.editionCount} ${work.editionCount == 1 ? 'edition' : 'editions'}',
              if (work.edition != null && work.edition!.isbn == null)
                'No ISBN — manual entry',
            ],
            onTap: () => _openWork(work),
          ),
        if (_workContinuationError != null) ...[
          const SizedBox(height: 8),
          Text(
            _workContinuationError!,
            key: const Key('catalogue-work-continuation-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_workHasMore)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              key: const Key('catalogue-load-more'),
              onPressed: _workLoadingMore ? null : () => _search(reset: false),
              child: _workLoadingMore
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _workContinuationError == null
                          ? 'Load more matches'
                          : 'Retry loading matches',
                    ),
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('catalogue-results-manual'),
          onPressed: _openManual,
          child: const Text('None of these? Add manually'),
        ),
      ],
    );
  }

  Widget _buildEditions(BuildContext context) {
    final work = _selectedWork!;
    return ListView(
      key: const Key('catalogue-editions'),
      padding: const EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        4,
        ReaduoSpacing.screenHorizontal,
        28,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('catalogue-back-to-results'),
            onPressed: _backToResults,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('All matches'),
          ),
        ),
        Text(
          work.title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (work.author.isNotEmpty) Text(work.author),
        const SizedBox(height: 8),
        Text(
          'Choose the ISBN-specific edition you own or want to save. Different ISBNs remain separate books.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: ReaduoColors.muted),
        ),
        const SizedBox(height: 8),
        if (_editions.isEmpty)
          _CatalogueMessage(
            icon: Icons.menu_book_outlined,
            title: 'No editions listed',
            message: 'You can still add this book manually.',
            primaryLabel: 'Add manually',
            onPrimary: _openManual,
          )
        else
          for (final edition in _editions)
            _EditionCard(
              edition: edition,
              onSelect: edition.isbn == null
                  ? () => _openManual(edition: edition)
                  : () => _openConfirmation(edition),
            ),
        if (_editionContinuationError != null) ...[
          const SizedBox(height: 8),
          Text(
            _editionContinuationError!,
            key: const Key('catalogue-editions-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_editionHasMore)
          OutlinedButton(
            key: const Key('catalogue-editions-load-more'),
            onPressed: _editionLoadingMore ? null : _loadMoreEditions,
            child: _editionLoadingMore
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Load more editions'),
          ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('catalogue-editions-manual'),
          onPressed: () => _openManual(),
          child: const Text('None of these? Add manually'),
        ),
      ],
    );
  }
}

List<CatalogueWork> _mergeWorks(
  List<CatalogueWork> current,
  List<CatalogueWork> incoming,
) {
  final identities = current
      .map((work) => work.edition?.isbn ?? '${work.provider.name}:${work.id}')
      .toSet();
  return [
    ...current,
    ...incoming.where(
      (work) => identities.add(
        work.edition?.isbn ?? '${work.provider.name}:${work.id}',
      ),
    ),
  ];
}

List<CatalogueEdition> _mergeEditions(
  List<CatalogueEdition> current,
  List<CatalogueEdition> incoming,
) {
  final identities = current
      .map((edition) => edition.isbn ?? edition.id)
      .toSet();
  return [
    ...current,
    ...incoming.where((edition) => identities.add(edition.isbn ?? edition.id)),
  ];
}

PreferredSizeWidget _catalogueAppBar(String title) => AppBar(
  toolbarHeight: 64,
  elevation: 0,
  scrolledUnderElevation: 0,
  backgroundColor: ReaduoColors.paper,
  surfaceTintColor: Colors.transparent,
  titleSpacing: ReaduoSpacing.screenHorizontal,
  title: Text(
    title,
    style: const TextStyle(
      color: ReaduoColors.ink,
      fontSize: 20,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.4,
    ),
  ),
);

class _CatalogueSearchField extends StatelessWidget {
  const _CatalogueSearchField({
    required this.controller,
    required this.focusNode,
    required this.onSearch,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSearch;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: ReaduoColors.line),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 46,
          child: TextField(
            key: const Key('catalogue-query-field'),
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14, color: ReaduoColors.ink),
            decoration: InputDecoration(
              hintText: 'Title, author or ISBN',
              hintStyle: const TextStyle(
                fontSize: 14,
                color: ReaduoColors.muted,
              ),
              isDense: true,
              filled: true,
              fillColor: ReaduoColors.paper,
              contentPadding: EdgeInsets.zero,
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: ReaduoColors.muted,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 42,
                minHeight: 46,
              ),
              suffixIcon: TextButton(
                key: const Key('catalogue-search-button'),
                onPressed: onSearch,
                style: TextButton.styleFrom(
                  minimumSize: const Size(68, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: const RoundedRectangleBorder(),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Search'),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 68,
                minHeight: 46,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(
                  color: ReaduoColors.accent,
                  width: 1.3,
                ),
              ),
            ),
            onChanged: onChanged,
            onSubmitted: (_) => onSearch(),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _CataloguePrompt extends StatelessWidget {
  const _CataloguePrompt({required this.onManual});

  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: ReaduoSpacing.screenHorizontal,
        vertical: 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CatalogueEmptyMark(icon: Icons.travel_explore_rounded),
          const SizedBox(height: 24),
          Text(
            'Find your next addition',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Search the catalogue, then choose the matching book and edition.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          TextButton(
            key: const Key('catalogue-prompt-manual'),
            onPressed: onManual,
            child: const Text('Can’t find it? Add manually'),
          ),
        ],
      ),
    ),
  );
}

class _CatalogueMessage extends StatelessWidget {
  const _CatalogueMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.tertiaryLabel,
    this.onTertiary,
    this.accentMark = false,
    this.primaryOutlined = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? tertiaryLabel;
  final VoidCallback? onTertiary;
  final bool accentMark;
  final bool primaryOutlined;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: ReaduoSpacing.screenHorizontal,
        vertical: 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accentMark)
            _CatalogueEmptyMark(icon: icon)
          else
            Icon(icon, size: 48),
          SizedBox(height: accentMark ? 24 : 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          if (primaryOutlined)
            OutlinedButton(onPressed: onPrimary, child: Text(primaryLabel))
          else
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
          if (secondaryLabel != null)
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          if (tertiaryLabel != null)
            TextButton(onPressed: onTertiary, child: Text(tertiaryLabel!)),
        ],
      ),
    ),
  );
}

class _CatalogueEmptyMark extends StatelessWidget {
  const _CatalogueEmptyMark({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('catalogue-empty-mark'),
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      color: ReaduoColors.accentTint,
      borderRadius: BorderRadius.circular(23),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 30, color: ReaduoColors.accent),
  );
}

class _EditionCard extends StatelessWidget {
  const _EditionCard({required this.edition, required this.onSelect});

  final CatalogueEdition edition;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (edition.format != null) edition.format!,
      if (edition.publishedYear != null) '${edition.publishedYear}',
      if (edition.publisher != null) edition.publisher!,
    ];
    return _CatalogueResultRow(
      key: ValueKey('catalogue-edition-${edition.id}'),
      title: edition.title,
      author: edition.author,
      coverUrl: edition.coverUrl,
      metadata: [
        edition.isbn == null
            ? 'No ISBN listed — add manually'
            : 'ISBN ${edition.isbn}',
        if (metadata.isNotEmpty) metadata.join(' • '),
      ],
      onTap: onSelect,
    );
  }
}

class _CatalogueResultRow extends StatelessWidget {
  const _CatalogueResultRow({
    required this.title,
    required this.author,
    required this.metadata,
    required this.onTap,
    this.coverUrl,
    super.key,
  });

  final String title;
  final String author;
  final List<String> metadata;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: ReaduoColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _CatalogueCover(
              title: title,
              author: author,
              coverUrl: coverUrl,
              width: 43,
              height: 64,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ReaduoColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ReaduoColors.muted,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                  for (final line in metadata) ...[
                    const SizedBox(height: 2),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ReaduoColors.muted,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: ReaduoColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _CatalogueCover extends StatelessWidget {
  const _CatalogueCover({
    required this.title,
    required this.author,
    required this.width,
    required this.height,
    this.coverUrl,
  });

  final String title;
  final String author;
  final String? coverUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fallback = _GeneratedCatalogueCover(
      title: title,
      author: author,
      width: width,
      height: height,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(width < 60 ? 4 : 6),
      child: SizedBox(
        width: width,
        height: height,
        child: coverUrl == null || coverUrl!.trim().isEmpty
            ? fallback
            : Image(
                image: ReaduoImageCache.image(coverUrl!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _GeneratedCatalogueCover extends StatelessWidget {
  const _GeneratedCatalogueCover({
    required this.title,
    required this.author,
    required this.width,
    required this.height,
  });

  static const _colors = [
    Color(0xFF184B61),
    Color(0xFFAB5834),
    Color(0xFF33385E),
    Color(0xFF1F6558),
    Color(0xFF634289),
    Color(0xFF426653),
  ];

  final String title;
  final String author;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final seed = title.codeUnits.fold<int>(0, (sum, value) => sum + value);
    final compact = width < 60;
    return ColoredBox(
      color: _colors[seed % _colors.length],
      child: Padding(
        padding: EdgeInsets.all(compact ? 4 : 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title.toUpperCase(),
              maxLines: compact ? 4 : 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 6.5 : 10,
                fontWeight: FontWeight.w700,
                height: 1.08,
                letterSpacing: 0.15,
              ),
            ),
            if (author.isNotEmpty)
              Text(
                author,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontSize: compact ? 5.5 : 8,
                  height: 1.05,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CatalogueConfirmationScreen extends StatefulWidget {
  const CatalogueConfirmationScreen({
    required this.ownerId,
    required this.edition,
    required this.shelfRepository,
    required this.bookRepository,
    this.manualEntry = false,
    this.initialShelf,
    this.onCreateShelf,
    super.key,
  });

  final String ownerId;
  final CatalogueEdition edition;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final bool manualEntry;
  final Shelf? initialShelf;
  final Future<Shelf?> Function()? onCreateShelf;

  @override
  State<CatalogueConfirmationScreen> createState() =>
      _CatalogueConfirmationScreenState();
}

class _CatalogueConfirmationScreenState
    extends State<CatalogueConfirmationScreen> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.edition.title,
  );
  late final TextEditingController _authorController = TextEditingController(
    text: widget.edition.author,
  );
  late final Stream<List<Shelf>> _shelves = widget.shelfRepository.watchShelves(
    widget.ownerId,
  );
  String? _selectedShelfId;
  bool _isOwned = true;
  ReadingStatus _status = ReadingStatus.wantToRead;
  bool _saving = false;
  bool _creatingShelf = false;
  String? _titleError;
  String? _authorError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    if (widget.initialShelf?.mutationOperationId == null) {
      _selectedShelfId = widget.initialShelf?.id;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _createShelf() async {
    final create = widget.onCreateShelf;
    if (create == null || _creatingShelf) return;
    setState(() {
      _creatingShelf = true;
      _saveError = null;
    });
    try {
      final created = await create();
      if (created != null && mounted) {
        setState(() => _selectedShelfId = created.id);
      }
    } finally {
      if (mounted) setState(() => _creatingShelf = false);
    }
  }

  Future<void> _save(List<Shelf> shelves) async {
    if (_saving) return;
    final shelf = shelves
        .where(
          (item) =>
              item.id == _selectedShelfId && item.mutationOperationId == null,
        )
        .firstOrNull;
    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    setState(() {
      _titleError = title.isEmpty ? 'Enter a book title.' : null;
      _authorError = author.isEmpty ? 'Enter an author.' : null;
      _saveError = shelf == null ? 'Choose a shelf before saving.' : null;
    });
    if (_titleError != null || _authorError != null || shelf == null) return;
    setState(() => _saving = true);
    try {
      await widget.bookRepository.createBook(
        ownerId: widget.ownerId,
        shelf: shelf,
        input: CreateBookInput(
          title: title,
          author: author,
          isbnInput: widget.edition.isbn ?? '',
          isOwned: _isOwned,
          readingStatus: _status,
          coverUrl: widget.edition.coverUrl,
          publisher: (widget.edition.publisher ?? '').characters
              .take(160)
              .toString(),
          publishedYear: widget.edition.publishedYear?.toString() ?? '',
          description: (widget.edition.description ?? '').characters
              .take(2000)
              .toString(),
        ),
      );
      if (mounted) Navigator.of(context).pop(shelf);
    } on BookFailure catch (error) {
      if (mounted) setState(() => _saveError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = 'Could not save this book. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('catalogue-confirmation'),
      appBar: _catalogueAppBar('Save your book'),
      body: SafeArea(
        child: StreamBuilder<List<Shelf>>(
          stream: _shelves,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _CatalogueMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Shelves unavailable',
                message: snapshot.error is ShelfFailure
                    ? (snapshot.error! as ShelfFailure).message
                    : 'Readuo could not load your shelves.',
                primaryLabel: 'Go back',
                onPrimary: () => Navigator.of(context).pop(),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final shelves = snapshot.data!
                .where((shelf) => shelf.mutationOperationId == null)
                .toList();
            if (_selectedShelfId != null &&
                !shelves.any((shelf) => shelf.id == _selectedShelfId)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _selectedShelfId = null);
              });
            }
            return _buildForm(context, shelves);
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<Shelf> shelves) {
    final compact = MediaQuery.sizeOf(context).width <= 360;
    final coverWidth = compact ? 68.0 : 76.0;
    final coverHeight = compact ? 100.0 : 112.0;
    final metadata = [
      if (widget.edition.format != null) widget.edition.format!,
      if (widget.edition.publishedYear != null)
        '${widget.edition.publishedYear}',
      if (widget.edition.publisher != null) widget.edition.publisher!,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        12,
        ReaduoSpacing.screenHorizontal,
        32,
      ),
      children: [
        if (widget.manualEntry || widget.edition.isbn == null)
          Container(
            key: const Key('catalogue-manual-warning'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Manual entry: this catalogue record has no usable ISBN. It will not be silently merged with another edition.',
            ),
          ),
        if (widget.manualEntry || widget.edition.isbn == null)
          const SizedBox(height: 14),
        if (widget.manualEntry || widget.edition.isbn == null) ...[
          TextField(
            key: const Key('catalogue-title-field'),
            controller: _titleController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Title',
              errorText: _titleError,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _titleError = null),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('catalogue-author-field'),
            controller: _authorController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Author',
              errorText: _authorError,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _authorError = null),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              key: const Key('catalogue-cover'),
              child: _CatalogueCover(
                title: _titleController.text.trim(),
                author: _authorController.text.trim(),
                coverUrl: widget.edition.coverUrl,
                width: coverWidth,
                height: coverHeight,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleController.text.trim(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_authorController.text.trim()),
                  const SizedBox(height: 8),
                  Text(
                    widget.edition.isbn == null
                        ? 'ISBN not provided'
                        : 'ISBN ${widget.edition.isbn}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (metadata.isNotEmpty)
                    Text(
                      metadata.join(' • '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (!widget.manualEntry && widget.edition.isbn != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('catalogue-not-this-book'),
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Not this book?'),
            ),
          ),
        Text(
          'Metadata provided by ${widget.edition.provider == CatalogueProvider.googleBooks ? 'Google Books' : 'Open Library'}. Verify the edition before saving.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),
        const Text(
          'Shelf · Required',
          style: TextStyle(
            color: ReaduoColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: ReaduoColors.paper,
            border: Border.all(color: ReaduoColors.line),
            borderRadius: BorderRadius.circular(11),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const Key('catalogue-shelf-picker'),
              value: shelves.any((shelf) => shelf.id == _selectedShelfId)
                  ? _selectedShelfId
                  : null,
              hint: const Text('Choose a shelf'),
              isExpanded: true,
              borderRadius: BorderRadius.circular(11),
              items: shelves
                  .map(
                    (shelf) => DropdownMenuItem(
                      value: shelf.id,
                      child: Text(
                        shelf.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _selectedShelfId = value;
                      _saveError = null;
                    }),
            ),
          ),
        ),
        if (widget.onCreateShelf != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('catalogue-create-shelf'),
              onPressed: _saving || _creatingShelf ? null : _createShelf,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _creatingShelf ? 'Creating shelf…' : 'Create a new shelf',
              ),
            ),
          ),
        ],
        SwitchListTile(
          key: const Key('catalogue-owned-switch'),
          contentPadding: EdgeInsets.zero,
          value: _isOwned,
          onChanged: _saving
              ? null
              : (value) => setState(() => _isOwned = value),
          title: const Text('I own this book'),
          activeTrackColor: ReaduoColors.accent,
          activeThumbColor: ReaduoColors.paper,
          inactiveTrackColor: ReaduoColors.line,
          inactiveThumbColor: ReaduoColors.paper,
        ),
        Text(
          'Reading status',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          key: const Key('catalogue-status-choices'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in ReadingStatus.values)
              _CatalogueStatusPill(
                key: ValueKey('catalogue-status-${status.name}'),
                label: Text(status.label),
                selected: _status == status,
                onSelected: _saving
                    ? null
                    : () => setState(() => _status = status),
              ),
          ],
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(
            _saveError!,
            key: const Key('catalogue-save-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          key: const Key('catalogue-save-button'),
          onPressed: _saving ? null : () => _save(shelves),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          child: _saving
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add book'),
        ),
      ],
    );
  }
}

class _CatalogueStatusPill extends StatelessWidget {
  const _CatalogueStatusPill({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final Widget label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? ReaduoColors.accentTint : ReaduoColors.paper,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? const Color(0xFFC9D5FF) : ReaduoColors.line,
        ),
      ),
      child: InkWell(
        onTap: onSelected,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: selected ? ReaduoColors.accent : ReaduoColors.muted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: label,
            ),
          ),
        ),
      ),
    ),
  );
}
