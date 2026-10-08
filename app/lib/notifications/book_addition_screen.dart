import 'package:flutter/material.dart';
import '../theme/readuo_theme.dart';
import '../widgets/book_cover_image.dart';
import 'book_addition.dart';
import 'notification.dart';
import 'notification_presentation.dart';
import 'notification_repository.dart';

class BookAdditionScreen extends StatefulWidget {
  const BookAdditionScreen({
    required this.userId,
    required this.groupId,
    required this.repository,
    required this.onOpenBook,
    super.key,
  });
  final String userId;
  final String groupId;
  final NotificationRepository repository;
  final Future<void> Function(BookAdditionItem) onOpenBook;
  @override
  State<BookAdditionScreen> createState() => _BookAdditionScreenState();
}

class _BookAdditionScreenState extends State<BookAdditionScreen>
    with WidgetsBindingObserver {
  late Stream<BookAdditionPage> _page;
  final _previous = <String?>[];
  String? _cursor;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _page = widget.repository.watchBookAdditionPage(
      widget.userId,
      widget.groupId,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  void _reload() => setState(() {
    _page = widget.repository.watchBookAdditionPage(
      widget.userId,
      widget.groupId,
      after: _cursor,
    );
  });
  Future<void> _open(BookAdditionItem item) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final fresh = await widget.repository.getBookAdditionPage(
        widget.userId,
        widget.groupId,
        after: _cursor,
      );
      final current = fresh.items
          .where(
            (value) =>
                value.book.id == item.book.id &&
                value.book.shelfId == item.book.shelfId &&
                value.book.createdAt == item.book.createdAt,
          )
          .firstOrNull;
      if (!mounted) return;
      if (current == null) throw StateError('Unavailable');
      await widget.onOpenBook(current);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This book is no longer available.')),
        );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: NotificationDestinationMarker(
        destination: NotificationDestination(
          NotificationDestinationKind.bookAddition,
          widget.groupId,
        ),
        child: const Text('Books added'),
      ),
    ),
    body: SafeArea(
      top: false,
      child: StreamBuilder<BookAdditionPage>(
        stream: _page,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'This activity is no longer available.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _reload,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          if (!snapshot.hasData ||
              snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final page = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Only books still shared with you appear here.',
                style: TextStyle(color: ReaduoColors.muted),
              ),
              const SizedBox(height: 16),
              if (page.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No books on this page are currently available.'),
                ),
              for (final item in page.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: ReaduoColors.paper,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: _opening ? null : () => _open(item),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 64,
                              height: 92,
                              child: item.book.coverUrl == null
                                  ? const ColoredBox(
                                      color: ReaduoColors.accentTint,
                                      child: Icon(
                                        Icons.menu_book_outlined,
                                        color: ReaduoColors.accent,
                                      ),
                                    )
                                  : BookCoverImage(
                                      item.book.coverUrl!,
                                      fit: BoxFit.contain,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.book.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.book.author,
                                    style: const TextStyle(
                                      color: ReaduoColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_previous.isNotEmpty)
                OutlinedButton(
                  onPressed: () {
                    _cursor = _previous.removeLast();
                    _reload();
                  },
                  child: const Text('Previous books'),
                ),
              if (page.nextCursor != null)
                OutlinedButton(
                  onPressed: () {
                    _previous.add(_cursor);
                    _cursor = page.nextCursor;
                    _reload();
                  },
                  child: const Text('Next books'),
                ),
            ],
          );
        },
      ),
    ),
  );
}
