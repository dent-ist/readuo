import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/shelf.dart';
import '../theme/readuo_theme.dart';
import '../widgets/readuo_bottom_navigation.dart';
import '../widgets/generated_book_cover.dart';
import 'offline_library_controller.dart';

class OfflineLibraryBoundary extends StatelessWidget {
  const OfflineLibraryBoundary({
    required this.controller,
    required this.onlineBuilder,
    this.onSignOut,
    super.key,
  });
  final OfflineLibraryController controller;
  final WidgetBuilder onlineBuilder;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.canShowOnline)
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: ReaduoColors.background),
            Padding(
              padding: EdgeInsets.only(
                top: controller.showReconnectNotice
                    ? MediaQuery.textScalerOf(context).scale(12) * 1.5 + 16
                    : 0,
              ),
              child: KeyedSubtree(
                key: ValueKey('online-library-${controller.userId}'),
                child: onlineBuilder(context),
              ),
            ),
            if (controller.showReconnectNotice)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: SafeArea(
                    child: Center(
                      child: Semantics(
                        liveRegion: true,
                        child: Material(
                          color: ReaduoColors.paper,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(16),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              'Reconnecting…',
                              style: TextStyle(
                                fontSize: 12,
                                color: ReaduoColors.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      if ((controller.connection != OfflineConnection.offline &&
              controller.connection != OfflineConnection.unavailable) ||
          controller.snapshot == null) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: controller.connection == OfflineConnection.checking
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Your library is unavailable. Check your sign-in and connection.',
                        ),
                        TextButton(
                          onPressed: controller.checkConnection,
                          child: const Text('Try connection again'),
                        ),
                        if (onSignOut != null)
                          TextButton(
                            onPressed: onSignOut,
                            child: const Text('Sign out'),
                          ),
                      ],
                    ),
            ),
          ),
        );
      }
      return Navigator(
        key: ValueKey('offline-${controller.userId}'),
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => OfflineLibraryScreen(
            controller: controller,
            onSignOut: onSignOut,
          ),
        ),
      );
    },
  );
}

class OfflineLibraryScreen extends StatefulWidget {
  const OfflineLibraryScreen({
    required this.controller,
    this.onSignOut,
    super.key,
  });
  final OfflineLibraryController controller;
  final VoidCallback? onSignOut;
  @override
  State<OfflineLibraryScreen> createState() => _OfflineLibraryScreenState();
}

class _OfflineLibraryScreenState extends State<OfflineLibraryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _shelfId;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _blocked() => showOfflineAction(context, widget.controller);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final saved = widget.controller.snapshot;
      final shelves = saved?.shelves ?? const <Shelf>[];
      final books = (saved?.books ?? const <LibraryBook>[])
          .where(
            (book) =>
                (_shelfId == null || book.shelfId == _shelfId) &&
                '${book.title} ${book.author} ${book.isbn ?? ''}'
                    .toLowerCase()
                    .contains(_query.toLowerCase()),
          )
          .toList();
      return _OfflinePage(
        title: 'Library',
        onBack: _shelfId == null ? null : () => setState(() => _shelfId = null),
        bottom: ReaduoBottomNavigation(
          onCircle: _blocked,
          onFriends: _blocked,
          onProfile: widget.onSignOut == null
              ? _blocked
              : () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  builder: (_) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ReaduoSpacing.screenHorizontal,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Profile needs a connection. You can still sign out and clear this device’s saved library.',
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: widget.onSignOut,
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          onLibrary: () => setState(() {
            _shelfId = null;
            _query = '';
            _search.clear();
          }),
        ),
        children: [
          _OfflineBanner(
            widget.controller.connection == OfflineConnection.offline
                ? 'You’re offline. Showing a partial, previously loaded copy of your own library.'
                : 'Connection check delayed. Retrying automatically. Showing only your saved library; changes and social features are unavailable.',
          ),
          if (widget.controller.cacheError != null)
            Text(
              widget.controller.cacheError!,
              style: const TextStyle(color: Colors.red),
            ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF1F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => setState(() => _shelfId = null),
                    child: const Text('My Library'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _blocked,
                    child: const Text('Explore'),
                  ),
                ),
              ],
            ),
          ),
          TextField(
            controller: _search,
            onSubmitted: (value) => setState(() => _query = value.trim()),
            decoration: InputDecoration(
              hintText: 'Search loaded books',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: TextButton(
                onPressed: () => setState(() => _query = _search.text.trim()),
                child: const Text('Search'),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: ReaduoColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: ReaduoColors.line),
              ),
            ),
          ),
          Text(
            _query.isNotEmpty
                ? 'Loaded search results'
                : _shelfId == null
                ? 'Saved on this device'
                : 'Loaded books',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: ReaduoColors.ink,
            ),
          ),
          if (_query.isEmpty && _shelfId == null && shelves.isNotEmpty)
            for (final shelf in shelves)
              InkWell(
                onTap: () => setState(() => _shelfId = shelf.id),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: ReaduoColors.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        height: 76,
                        child: Stack(
                          children: [
                            for (
                              var index = 0;
                              index < saved!.booksOn(shelf.id).take(3).length;
                              index++
                            )
                              Positioned(
                                left: index * 18,
                                top: 4,
                                child: _OfflineCover(
                                  width: 46,
                                  height: 66,
                                  book: saved.booksOn(shelf.id)[index],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shelf.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${saved.booksOn(shelf.id).length} loaded ${saved.booksOn(shelf.id).length == 1 ? 'book' : 'books'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: ReaduoColors.muted,
                              ),
                            ),
                            const SizedBox(height: 7),
                            _Badge(shelf.visibility.label),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              )
          else if (books.isNotEmpty)
            for (final book in books)
              InkWell(
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => OfflineBookScreen(
                        controller: widget.controller,
                        shelfId: book.shelfId,
                        bookId: book.id,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _OfflineCover(width: 43, height: 64, book: book),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(book.title),
                            Text(
                              book.author,
                              style: const TextStyle(
                                fontSize: 12,
                                color: ReaduoColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 35),
              child: Column(
                children: [
                  const Icon(
                    Icons.menu_book_outlined,
                    size: 36,
                    color: ReaduoColors.accent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _query.isEmpty
                        ? 'No books saved on this device'
                        : 'No loaded matches',
                    style: const TextStyle(fontSize: 21),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Try another title or reconnect for the complete library.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          OutlinedButton(
            onPressed: _blocked,
            child: const Text('Add or edit a book'),
          ),
          const Text(
            'Some covers and books may be unavailable. Social content is not available offline.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: ReaduoColors.muted,
            ),
          ),
        ],
      );
    },
  );
}

class OfflineBookScreen extends StatelessWidget {
  const OfflineBookScreen({
    required this.controller,
    required this.shelfId,
    required this.bookId,
    super.key,
  });
  final OfflineLibraryController controller;
  final String shelfId;
  final String bookId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final snapshot = controller.snapshot;
      final book = snapshot?.books
          .where((book) => book.id == bookId && book.shelfId == shelfId)
          .firstOrNull;
      final shelf = snapshot?.shelves
          .where((shelf) => shelf.id == shelfId)
          .firstOrNull;
      return _OfflinePage(
        title: 'Book details',
        onBack: () => Navigator.of(context).maybePop(),
        children: [
          _OfflineBanner(
            controller.connection == OfflineConnection.offline
                ? 'Offline · Read-only'
                : 'Connection check delayed · Read-only',
          ),
          if (book == null || shelf == null)
            const Text('This book is not saved on this device.')
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OfflineCover(width: 118, height: 174, book: book),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        book.author,
                        style: const TextStyle(
                          fontSize: 14,
                          color: ReaduoColors.muted,
                        ),
                      ),
                      if (book.isbn != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'ISBN ${book.isbn}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: ReaduoColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(
                  book.isOwned ? 'Owned' : 'Not owned',
                  green: book.isOwned,
                ),
                _Badge(book.readingStatus.label, blue: true),
              ],
            ),
            InkWell(
              onTap: () => showOfflineAction(context, controller),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: ReaduoColors.line)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_library_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('On ${shelf.name}'),
                          Text(
                            '${shelf.visibility.label} shelf',
                            style: const TextStyle(
                              fontSize: 12,
                              color: ReaduoColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () => showOfflineAction(context, controller),
              child: const Text('Change status'),
            ),
            const Text(
              'Only metadata previously loaded for your own library is shown.',
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: ReaduoColors.muted,
              ),
            ),
          ],
        ],
      );
    },
  );
}

Future<void> showOfflineAction(
  BuildContext context,
  OfflineLibraryController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => OfflineActionSheet(controller: controller),
);

class OfflineActionSheet extends StatefulWidget {
  const OfflineActionSheet({required this.controller, super.key});
  final OfflineLibraryController controller;
  @override
  State<OfflineActionSheet> createState() => _OfflineActionSheetState();
}

class _OfflineActionSheetState extends State<OfflineActionSheet> {
  bool _busy = false;
  String? _status;
  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final result = await widget.controller.checkConnection();
    if (!mounted) return;
    if (result == OfflineConnection.online) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _busy = false;
      _status = 'Still unable to connect. Your saved library is read-only.';
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        18,
        ReaduoSpacing.screenHorizontal,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ReaduoColors.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Connect to make changes',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w500,
                    color: ReaduoColors.ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Close',
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'You can browse previously loaded books while offline. Adding, editing, and social actions need an internet connection.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: ReaduoColors.muted,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Keep browsing'),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy ? null : _retry,
            child: Text(
              _busy ? 'Checking connection…' : 'Try connection again',
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(
              _status!,
              style: const TextStyle(fontSize: 12, color: ReaduoColors.muted),
            ),
          ],
        ],
      ),
    ),
  );
}

class _OfflinePage extends StatelessWidget {
  const _OfflinePage({
    required this.title,
    required this.children,
    this.onBack,
    this.bottom,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReaduoColors.background,
    bottomNavigationBar: bottom,
    body: SafeArea(
      bottom: bottom == null,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              14,
              ReaduoSpacing.screenHorizontal,
              16,
            ),
            constraints: const BoxConstraints(minHeight: 76),
            child: Row(
              children: [
                if (onBack != null) ...[
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton.outlined(
                      onPressed: onBack,
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back, size: 20),
                      style: IconButton.styleFrom(
                        side: const BorderSide(color: ReaduoColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1.15,
                      letterSpacing: -.7,
                      fontWeight: FontWeight.w500,
                      color: ReaduoColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                ReaduoSpacing.screenHorizontal,
                18,
                ReaduoSpacing.screenHorizontal,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    if (index > 0) const SizedBox(height: 16),
                    children[index],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4DF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.wifi_off, size: 18, color: Color(0xFF7A5117)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              height: 1.55,
              color: Color(0xFF7A5117),
            ),
          ),
        ),
      ],
    ),
  );
}

class _OfflineCover extends StatelessWidget {
  const _OfflineCover({
    required this.width,
    required this.height,
    required this.book,
  });
  final LibraryBook book;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Generated title cover',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: GeneratedBookCover(title: book.title, author: book.author),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.green = false, this.blue = false});
  final String label;
  final bool green;
  final bool blue;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: green
          ? const Color(0xFFEAF6F0)
          : blue
          ? ReaduoColors.accentTint
          : const Color(0xFFEFF2F7),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        color: green
            ? const Color(0xFF216445)
            : blue
            ? const Color(0xFF304E9F)
            : ReaduoColors.muted,
      ),
    ),
  );
}
