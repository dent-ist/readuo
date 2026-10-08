import '../widgets/book_cover_image.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../features/content_check.dart';

import '../circle/review_repository.dart';
import '../theme/readuo_theme.dart';

class CircleReviewComposerScreen extends StatefulWidget {
  const CircleReviewComposerScreen({
    required this.ownerId,
    required this.repository,
    required this.source,
    this.review,
    super.key,
  });

  final String ownerId;
  final ReviewRepository repository;
  final CircleReviewDraft source;
  final CircleReview? review;

  @override
  State<CircleReviewComposerScreen> createState() =>
      _CircleReviewComposerScreenState();
}

class _CircleReviewComposerScreenState
    extends State<CircleReviewComposerScreen> {
  late final TextEditingController _controller;
  Timer? _timer;
  Future<void> _writes = Future.value();
  int? _rating;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _applying = false;
  bool _completed = false;
  int _generation = 0;
  int _writeGeneration = 0;

  bool get _isEditing => widget.review != null;
  bool get _hasChanges => _isEditing
      ? _controller.text != widget.review!.text ||
            _rating != widget.review!.rating
      : _controller.text.trim().isNotEmpty || _rating != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.review?.text ?? '');
    _rating = widget.review?.rating;
    _controller.addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    final ownerId = widget.ownerId;
    final generation = _generation;
    try {
      final draft = await widget.repository.loadDraft(
        ownerId: ownerId,
        reviewId: widget.source.reviewId,
      );
      if (!_current(ownerId, generation) || draft == null) return;
      if (draft.bookId != widget.source.bookId ||
          draft.bookCreatedAt != widget.source.bookCreatedAt) {
        return;
      }
      _applying = true;
      _controller.text = draft.text;
      _applying = false;
      setState(() => _rating = draft.rating);
    } catch (error) {
      if (_current(ownerId, generation)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_current(ownerId, generation)) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (_applying || _loading || _submitting || _completed) return;
    setState(() => _error = null);
    _scheduleSave();
  }

  void _setRating(int? rating) {
    if (_loading || _submitting) return;
    setState(() {
      _rating = rating;
      _error = null;
    });
    _scheduleSave();
  }

  CircleReviewDraft _snapshot() => CircleReviewDraft(
    reviewId: widget.source.reviewId,
    shelfId: widget.source.shelfId,
    bookId: widget.source.bookId,
    bookCreatedAt: widget.source.bookCreatedAt,
    title: widget.source.title,
    bookAuthor: widget.source.bookAuthor,
    coverUrl: widget.source.coverUrl,
    text: _controller.text,
    rating: _rating,
  );

  void _scheduleSave() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_queue(_snapshot(), reportError: true));
    });
  }

  Future<void> _queue(CircleReviewDraft draft, {required bool reportError}) {
    final ownerId = widget.ownerId;
    final repository = widget.repository;
    final generation = _generation;
    final writeGeneration = _writeGeneration;
    final operation = _writes.then((_) async {
      if (writeGeneration != _writeGeneration) return;
      if (draft.text.trim().isEmpty && draft.rating == null) {
        await repository.clearDraft(ownerId: ownerId, reviewId: draft.reviewId);
      } else {
        await repository.saveDraft(ownerId: ownerId, draft: draft);
      }
    });
    _writes = operation.catchError((_) {});
    if (reportError) {
      operation.catchError((Object error) {
        if (_current(ownerId, generation) &&
            writeGeneration == _writeGeneration &&
            !_submitting) {
          setState(() => _error = error.toString());
        }
      });
    }
    return operation;
  }

  bool _current(String ownerId, int generation) =>
      mounted && widget.ownerId == ownerId && _generation == generation;

  Future<void> _submit() async {
    if (_loading || _submitting) return;
    if (!await checkDraftContent(context, _controller) || !mounted) return;
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = 'Write a review before publishing.');
      return;
    }
    final ownerId = widget.ownerId;
    final repository = widget.repository;
    final generation = _generation;
    final draft = _snapshot();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      _timer?.cancel();
      await _queue(draft, reportError: false);
      if (!_current(ownerId, generation)) return;
      await repository.publishDraft(authorId: ownerId, draft: draft);
      if (!_current(ownerId, generation)) return;
      _completed = true;
      _writeGeneration++;
      Navigator.of(context).pop();
    } catch (error) {
      if (_current(ownerId, generation)) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _back(bool didPop, Object? result) async {
    if (didPop || _loading || _submitting || !_hasChanges || _completed) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isEditing ? 'Discard changes?' : 'Discard review draft?'),
        content: Text(
          _isEditing
              ? 'Your published review will stay unchanged.'
              : 'Your review text and rating will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const Key('review-discard'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    final ownerId = widget.ownerId;
    final repository = widget.repository;
    final generation = _generation;
    setState(() => _submitting = true);
    try {
      _timer?.cancel();
      _writeGeneration++;
      await _writes;
      await repository.clearDraft(
        ownerId: ownerId,
        reviewId: widget.source.reviewId,
      );
      if (!_current(ownerId, generation)) return;
      _completed = true;
      Navigator.of(context).pop();
    } catch (error) {
      if (_current(ownerId, generation)) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final draft = _snapshot();
    if (!_completed && !_submitting && _hasChanges) {
      final ownerId = widget.ownerId;
      final repository = widget.repository;
      _writes = _writes
          .then((_) => repository.saveDraft(ownerId: ownerId, draft: draft))
          .catchError((_) {});
    }
    _generation++;
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !_loading && !_submitting && (!_hasChanges || _completed),
    onPopInvokedWithResult: _back,
    child: Scaffold(
      key: Key(_isEditing ? 'circle-edit-review' : 'circle-new-review'),
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit review' : 'Write a review'),
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            ReaduoSpacing.screenHorizontal,
            12,
            ReaduoSpacing.screenHorizontal,
            24,
          ),
          children: [
            _ReviewBookSummary(source: widget.source),
            const SizedBox(height: 8),
            Text(
              'Visible to friends · current shelf',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            const Text(
              'Your rating (optional)',
              style: TextStyle(
                color: ReaduoColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    key: ValueKey('review-rating-$star'),
                    tooltip: 'Rate $star stars',
                    onPressed: _loading || _submitting
                        ? null
                        : () => _setRating(star),
                    iconSize: 34,
                    color: const Color(0xFFE3A008),
                    icon: Icon(
                      (_rating ?? 0) >= star
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                    ),
                  ),
                if (_rating != null)
                  TextButton(
                    key: const Key('review-clear-rating'),
                    onPressed: _loading || _submitting
                        ? null
                        : () => _setRating(null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Your review',
              style: TextStyle(
                color: ReaduoColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              key: const Key('review-text'),
              controller: _controller,
              readOnly: _loading || _submitting,
              minLines: 6,
              maxLines: 12,
              maxLength: 5000,
              decoration: const InputDecoration(
                hintText: 'What stayed with you?',
                filled: true,
                fillColor: ReaduoColors.paper,
                contentPadding: EdgeInsets.all(12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                  borderSide: BorderSide(color: ReaduoColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                  borderSide: BorderSide(color: ReaduoColors.accent, width: 2),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ReaduoColors.accentTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Spoilers ahead? Give your friends a heads-up in your review.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('review-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('review-submit'),
              onPressed: _loading || _submitting ? null : _submit,
              child: Text(
                _submitting
                    ? 'Saving…'
                    : _isEditing
                    ? 'Save changes'
                    : 'Publish review',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReviewBookSummary extends StatelessWidget {
  const _ReviewBookSummary({required this.source});

  final CircleReviewDraft source;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 68,
        height: 98,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: ReaduoColors.accentTint,
            child: source.coverUrl == null || source.coverUrl!.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(7),
                    child: Center(
                      child: Text(
                        source.title,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ReaduoColors.ink,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : BookCoverImage(
                    source.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Padding(
                      padding: const EdgeInsets.all(7),
                      child: Center(
                        child: Text(
                          source.title,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: ReaduoColors.ink,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: ReaduoColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              source.bookAuthor,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ],
  );
}
