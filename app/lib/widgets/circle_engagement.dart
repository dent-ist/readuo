import 'readuo_image_cache.dart';
import 'package:flutter/material.dart';

import '../circle/engagement_repository.dart';
import '../features/feature_services.dart';
import '../moderation/moderation_repository.dart';
import '../moderation/content_filter.dart';
import '../theme/readuo_theme.dart';

class CircleEngagementBar extends StatefulWidget {
  const CircleEngagementBar({
    required this.viewerId,
    required this.content,
    required this.repository,
    required this.onOpenComments,
    this.compact = false,
    super.key,
  });

  final String viewerId;
  final CircleContentRef content;
  final CircleEngagementRepository repository;
  final VoidCallback onOpenComments;
  final bool compact;

  @override
  State<CircleEngagementBar> createState() => _CircleEngagementBarState();
}

class _CircleEngagementBarState extends State<CircleEngagementBar> {
  bool _saving = false;

  Future<void> _toggle(Set<String> likes) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.setLiked(
        content: widget.content,
        userId: widget.viewerId,
        liked: !likes.contains(widget.viewerId),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: StreamBuilder<Set<String>>(
          stream: widget.repository.watchLikeUserIds(widget.content),
          initialData: const {},
          builder: (context, snapshot) {
            final likes = snapshot.data ?? const <String>{};
            final liked = likes.contains(widget.viewerId);
            return TextButton.icon(
              key: ValueKey('circle-like-${widget.content.id}'),
              style: widget.compact
                  ? TextButton.styleFrom(
                      foregroundColor: liked
                          ? ReaduoColors.accent
                          : ReaduoColors.muted,
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      iconSize: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    )
                  : null,
              onPressed: _saving || snapshot.hasError
                  ? null
                  : () => _toggle(likes),
              icon: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked ? ReaduoColors.accent : ReaduoColors.muted,
              ),
              label: Text(likes.isEmpty ? 'Like' : '${likes.length}'),
            );
          },
        ),
      ),
      Expanded(
        child: StreamBuilder<List<CircleComment>>(
          stream: widget.repository.watchComments(widget.content),
          initialData: const [],
          builder: (context, snapshot) {
            final count = snapshot.data?.length ?? 0;
            return TextButton.icon(
              key: ValueKey('circle-comments-${widget.content.id}'),
              style: widget.compact
                  ? TextButton.styleFrom(
                      foregroundColor: ReaduoColors.muted,
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      iconSize: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    )
                  : null,
              onPressed: widget.onOpenComments,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(count == 0 ? 'Comment' : '$count'),
            );
          },
        ),
      ),
    ],
  );
}

class CircleCommentsSection extends StatefulWidget {
  const CircleCommentsSection({
    required this.viewerId,
    required this.viewerDisplayName,
    required this.viewerPhotoUrl,
    required this.content,
    required this.repository,
    super.key,
  });

  final String viewerId;
  final String viewerDisplayName;
  final String? viewerPhotoUrl;
  final CircleContentRef content;
  final CircleEngagementRepository repository;

  @override
  State<CircleCommentsSection> createState() => _CircleCommentsSectionState();
}

class _CircleCommentsSectionState extends State<CircleCommentsSection> {
  final _controller = TextEditingController();
  final _commentFocus = FocusNode();
  bool _saving = false;
  String? _error;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_saving || text.isEmpty) return;
    if (!BasicContentFilter.check(text).allowed) {
      setState(() => _error = BasicContentFilter.explanation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.addComment(
        content: widget.content,
        authorId: widget.viewerId,
        authorDisplayName: widget.viewerDisplayName,
        authorPhotoUrl: widget.viewerPhotoUrl,
        text: text,
      );
      if (!mounted) return;
      _controller.clear();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openMenu(CircleComment comment) async {
    final own = comment.authorId == widget.viewerId;
    final ownsContent = widget.content.authorId == widget.viewerId;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (own)
                ListTile(
                  key: const Key('circle-edit-comment-action'),
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit comment'),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
              if (!own)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(
                    widget.content.kind == CircleContentKind.activity
                        ? 'Report reader'
                        : 'Report comment',
                  ),
                  onTap: () => Navigator.of(context).pop('report'),
                ),
              if (own || ownsContent)
                ListTile(
                  key: const Key('circle-delete-comment-action'),
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(own ? 'Delete comment' : 'Remove comment'),
                  textColor: Theme.of(context).colorScheme.error,
                  iconColor: Theme.of(context).colorScheme.error,
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'report') {
      await FeatureServices.report(
        context,
        widget.content.kind == CircleContentKind.activity
            ? ReportTarget(kind: 'profile', id: comment.authorId)
            : ReportTarget(
                kind: 'comment',
                id: comment.id,
                parentKind: widget.content.kind.name,
                parentId: widget.content.id,
              ),
      );
    }
    if (action == 'edit') await _edit(comment);
    if (action == 'delete') await _delete(comment, ownsContent && !own);
  }

  Future<void> _edit(CircleComment comment) async {
    final controller = TextEditingController(text: comment.text);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(
          key: const Key('circle-edit-comment-text'),
          controller: controller,
          autofocus: true,
          maxLength: 1000,
          minLines: 2,
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    if (!BasicContentFilter.check(text).allowed) {
      _showError(BasicContentFilter.explanation);
      await _edit(
        CircleComment(
          id: comment.id,
          authorId: comment.authorId,
          authorDisplayName: comment.authorDisplayName,
          authorPhotoUrl: comment.authorPhotoUrl,
          text: text,
          createdAt: comment.createdAt,
          updatedAt: comment.updatedAt,
        ),
      );
      return;
    }
    try {
      await widget.repository.updateComment(
        content: widget.content,
        comment: comment,
        text: text,
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _delete(CircleComment comment, bool moderation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(moderation ? 'Remove this comment?' : 'Delete comment?'),
        content: Text(
          moderation
              ? 'It will be removed from your post for everyone.'
              : 'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('circle-confirm-delete-comment'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(moderation ? 'Remove' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteComment(
        content: widget.content,
        commentId: comment.id,
      );
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  void dispose() {
    _commentFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleEngagementBar(
        viewerId: widget.viewerId,
        content: widget.content,
        repository: widget.repository,
        compact: true,
        onOpenComments: () => _commentFocus.requestFocus(),
      ),
      const Divider(height: 20, thickness: 1, color: Color(0xFFD5DDEA)),
      StreamBuilder<List<CircleComment>>(
        stream: widget.repository.watchComments(widget.content),
        initialData: const [],
        builder: (context, snapshot) {
          final comments = snapshot.data ?? const <CircleComment>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  comments.isEmpty || snapshot.hasError
                      ? 'Comments'
                      : 'Comments \u00b7 ${comments.length}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ReaduoColors.ink,
                  ),
                ),
              ),
              if (snapshot.hasError)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Comments are no longer available.'),
                )
              else
                ...comments.map(
                  (comment) => Column(
                    children: [
                      ListTile(
                        key: ValueKey('circle-comment-${comment.id}'),
                        contentPadding: EdgeInsets.zero,
                        minVerticalPadding: 12,
                        minLeadingWidth: 32,
                        horizontalTitleGap: 10,
                        titleAlignment: ListTileTitleAlignment.top,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: ReaduoColors.accentTint,
                          backgroundImage:
                              comment.authorPhotoUrl == null ||
                                  comment.authorPhotoUrl!.isEmpty
                              ? null
                              : ReaduoImageCache.image(comment.authorPhotoUrl!),
                          child:
                              comment.authorPhotoUrl == null ||
                                  comment.authorPhotoUrl!.isEmpty
                              ? Text(
                                  comment.authorDisplayName.trim().isEmpty
                                      ? '?'
                                      : comment
                                            .authorDisplayName
                                            .characters
                                            .first
                                            .toUpperCase(),
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                comment.authorId == widget.viewerId
                                    ? 'You'
                                    : comment.authorDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (comment.createdAt != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                _commentAge(comment.createdAt!),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: ReaduoColors.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            comment.text,
                            style: const TextStyle(
                              color: ReaduoColors.ink,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Comment options',
                          onPressed: () => _openMenu(comment),
                          icon: const Icon(Icons.more_horiz_rounded),
                        ),
                      ),
                      if (comment != comments.last)
                        const Divider(
                          height: 1,
                          indent: 42,
                          color: ReaduoColors.line,
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('circle-comment-text'),
              controller: _controller,
              focusNode: _commentFocus,
              scrollPadding: const EdgeInsets.all(24),
              enabled: !_saving,
              maxLength: 1000,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add a comment…',
                counterText: '',
                filled: true,
                fillColor: ReaduoColors.paper,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => IconButton.filled(
              key: const Key('circle-send-comment'),
              tooltip: 'Post comment',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _saving || value.text.trim().isEmpty ? null : _send,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

String _commentAge(DateTime createdAt) {
  final age = DateTime.now().difference(createdAt);
  if (age.inMinutes < 1) return 'Just now';
  if (age.inHours < 1) return '${age.inMinutes}m';
  if (age.inDays < 1) return '${age.inHours}h';
  return '${age.inDays}d';
}
