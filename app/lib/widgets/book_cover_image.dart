import 'readuo_image_cache.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../library/book_cover_photo.dart';

class BookCoverImage extends StatefulWidget {
  const BookCoverImage(
    this.url, {
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.width,
    this.height,
    super.key,
  });
  final String url;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final double? width;
  final double? height;
  @override
  State<BookCoverImage> createState() => _BookCoverImageState();
}

class _BookCoverImageState extends State<BookCoverImage> {
  Future<Uint8List>? _photo;
  Timer? _retryTimer;
  int _attempt = 0;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BookCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  void _load() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
    _photo = isStoredBookCover(widget.url)
        ? FirebaseBookCoverStore().load(widget.url)
        : null;
  }

  Widget _fallback(Object error) =>
      widget.errorBuilder?.call(context, error, null) ??
      const Icon(Icons.menu_book_outlined);
  @override
  Widget build(BuildContext context) {
    if (_photo == null)
      return Image(
        image: ReaduoImageCache.image(widget.url),
        key: ValueKey('${widget.url}-$_attempt'),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stack) {
          final retryable =
              error is! NetworkImageLoadException ||
              error.statusCode == 429 ||
              error.statusCode >= 500;
          if (_attempt < 2 && retryable) {
            _retryTimer ??= Timer(Duration(seconds: 2 * (_attempt + 1)), () {
              _retryTimer = null;
              if (mounted) setState(() => _attempt++);
            });
            return const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              _fallback(error),
              Positioned(
                right: 0,
                bottom: 0,
                child: IconButton.filledTonal(
                  tooltip: 'Retry book cover',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: () => setState(() => _attempt = 0),
                ),
              ),
            ],
          );
        },
      );
    return FutureBuilder<Uint8List>(
      future: _photo,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _fallback(snapshot.error!);
        if (!snapshot.hasData)
          return const Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }
}
