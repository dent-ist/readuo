import '../widgets/readuo_image_cache.dart';
import '../widgets/book_cover_image.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../features/content_check.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../circle/circle_repository.dart';
import '../circle/photo_repository.dart';
import '../library/book.dart';
import '../library/book_repository.dart';
import '../theme/readuo_theme.dart';

class CirclePostComposerScreen extends StatefulWidget {
  const CirclePostComposerScreen({
    required this.ownerId,
    required this.circleRepository,
    required this.bookRepository,
    this.photoRepository = const EmptyCirclePhotoRepository(),
    this.pickPhoto,
    this.post,
    this.displayName = 'You',
    this.photoUrl,
    super.key,
  });

  final String ownerId;
  final String displayName;
  final String? photoUrl;
  final CircleRepository circleRepository;
  final BookRepository bookRepository;
  final CirclePhotoRepository photoRepository;
  final Future<XFile?> Function(ImageSource source)? pickPhoto;
  final CirclePost? post;

  @override
  State<CirclePostComposerScreen> createState() =>
      _CirclePostComposerScreenState();
}

class _CirclePostComposerScreenState extends State<CirclePostComposerScreen> {
  late final TextEditingController _textController;
  late String _draftPostId;
  CircleBookAttachment? _attachment;
  String? _photoPath;
  Uint8List? _photoBytes;
  Timer? _draftTimer;
  Future<void> _draftWrites = Future.value();
  String? _error;
  bool _loading = false;
  bool _submitting = false;
  bool _uploadingPhoto = false;
  bool _hasUserEdited = false;
  bool _applyingDraft = false;
  bool _completed = false;
  int _lifecycleGeneration = 0;
  int _draftWriteGeneration = 0;

  bool get _isEditing => widget.post != null;
  bool get _hasContent =>
      _textController.text.trim().isNotEmpty ||
      _attachment != null ||
      _photoPath != null;

  @override
  void initState() {
    super.initState();
    final post = widget.post;
    _textController = TextEditingController(text: post?.text ?? '');
    _draftPostId = widget.circleRepository.newPostId();
    _attachment = post?.attachment;
    _photoPath = post?.photoPath;
    _textController.addListener(_onChanged);
    if (_photoPath != null) unawaited(_restorePhoto(_photoPath!));
    if (post == null) _loadDraft();
  }

  Future<void> _loadDraft() async {
    final ownerId = widget.ownerId;
    final generation = _lifecycleGeneration;
    setState(() => _loading = true);
    try {
      final draft = await widget.circleRepository.loadPostDraft(ownerId);
      if (!_isCurrent(ownerId, generation) || draft == null || _hasUserEdited) {
        return;
      }
      _applyingDraft = true;
      _textController.text = draft.text;
      _applyingDraft = false;
      setState(() {
        _draftPostId = draft.postId.isEmpty
            ? widget.circleRepository.newPostId()
            : draft.postId;
        _attachment = draft.attachment;
        _photoPath = draft.photoPath;
      });
      if (draft.photoPath != null) await _restorePhoto(draft.photoPath!);
    } catch (error) {
      if (_isCurrent(ownerId, generation)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_isCurrent(ownerId, generation)) {
        setState(() => _loading = false);
      }
    }
  }

  void _onChanged() {
    if (_applyingDraft || _loading || _submitting || _completed) return;
    _hasUserEdited = true;
    if (mounted) setState(() => _error = null);
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    if (_isEditing || _loading || _submitting || _completed) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_queueDraftWrite(_draftSnapshot(), reportError: true));
    });
  }

  CirclePostDraft _draftSnapshot() => CirclePostDraft(
    postId: _draftPostId,
    text: _textController.text,
    attachment: _attachment,
    photoPath: _photoPath,
  );

  bool _snapshotHasContent(CirclePostDraft draft) =>
      draft.text.trim().isNotEmpty ||
      draft.attachment != null ||
      draft.photoPath != null;

  Future<void> _queueDraftWrite(
    CirclePostDraft draft, {
    required bool reportError,
  }) {
    final ownerId = widget.ownerId;
    final repository = widget.circleRepository;
    final lifecycleGeneration = _lifecycleGeneration;
    final writeGeneration = _draftWriteGeneration;
    final operation = _draftWrites.then((_) async {
      if (writeGeneration != _draftWriteGeneration) return;
      if (_snapshotHasContent(draft)) {
        await repository.savePostDraft(ownerId: ownerId, draft: draft);
      } else {
        await repository.clearPostDraft(ownerId);
      }
    });
    _draftWrites = operation.catchError((_) {});
    if (reportError) {
      operation.catchError((Object error) {
        if (_isCurrent(ownerId, lifecycleGeneration) &&
            writeGeneration == _draftWriteGeneration &&
            !_submitting) {
          setState(() => _error = error.toString());
        }
      });
    }
    return operation;
  }

  bool _isCurrent(String ownerId, int generation) =>
      mounted &&
      widget.ownerId == ownerId &&
      _lifecycleGeneration == generation;

  void _queueDisposeSnapshot(
    CirclePostDraft draft,
    String ownerId,
    CircleRepository repository,
  ) {
    _draftWrites = _draftWrites
        .then((_) async {
          if (_snapshotHasContent(draft)) {
            await repository.savePostDraft(ownerId: ownerId, draft: draft);
          }
        })
        .catchError((_) {});
  }

  @override
  void didUpdateWidget(CirclePostComposerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId == widget.ownerId) return;
    _draftTimer?.cancel();
    final oldDraft = _draftSnapshot();
    if (oldWidget.post == null &&
        !_submitting &&
        !_completed &&
        _snapshotHasContent(oldDraft)) {
      _queueDisposeSnapshot(
        oldDraft,
        oldWidget.ownerId,
        oldWidget.circleRepository,
      );
    }
    _lifecycleGeneration++;
    _draftWriteGeneration++;
    _draftPostId = widget.circleRepository.newPostId();
    _applyingDraft = true;
    _textController.text = widget.post?.text ?? '';
    _applyingDraft = false;
    _attachment = widget.post?.attachment;
    _photoPath = widget.post?.photoPath;
    _photoBytes = null;
    _error = null;
    _loading = false;
    _submitting = false;
    _hasUserEdited = false;
    _completed = false;
    if (_photoPath != null) unawaited(_restorePhoto(_photoPath!));
    if (!_isEditing) _loadDraft();
  }

  Future<void> _attachBook() async {
    if (_loading || _submitting) return;
    final selected = await Navigator.of(context).push<LibraryBook>(
      MaterialPageRoute<LibraryBook>(
        builder: (_) => CircleBookAttachmentScreen(
          ownerId: widget.ownerId,
          bookRepository: widget.bookRepository,
        ),
      ),
    );
    if (selected == null || !mounted || _submitting) return;
    setState(() {
      _hasUserEdited = true;
      _attachment = CircleBookAttachment(
        ownerId: selected.ownerId,
        shelfId: selected.shelfId,
        bookId: selected.id,
        title: selected.title,
        author: selected.author,
        coverUrl: selected.coverUrl,
      );
      _error = null;
    });
    _scheduleDraftSave();
  }

  Future<void> _restorePhoto(String path) async {
    try {
      final bytes = await widget.photoRepository.load(path);
      if (!mounted || _photoPath != path) return;
      setState(() => _photoBytes = bytes);
    } catch (error) {
      if (mounted && _photoPath == path) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _choosePhoto() async {
    if (_loading || _submitting || _uploadingPhoto) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ReaduoColors.paper,
      builder: (context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ReaduoSpacing.screenHorizontal,
            0,
            ReaduoSpacing.screenHorizontal,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('circle-photo-camera'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                key: const Key('circle-photo-library'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from library'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() {
      _uploadingPhoto = true;
      _error = null;
    });
    try {
      final file =
          await (widget.pickPhoto?.call(source) ??
              ImagePicker().pickImage(
                source: source,
                maxWidth: 2048,
                imageQuality: 85,
              ));
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final mimeType = file.mimeType ?? _mimeType(file.name);
      final oldPath = _photoPath;
      final path = await widget.photoRepository.upload(
        ownerId: widget.ownerId,
        postId: _isEditing ? widget.post!.id : _draftPostId,
        bytes: bytes,
        contentType: mimeType,
      );
      if (!mounted) return;
      setState(() {
        _hasUserEdited = true;
        _photoPath = path;
        _photoBytes = bytes;
      });
      if (!_isEditing && oldPath != null && oldPath != path) {
        await widget.photoRepository.delete(oldPath);
      }
      _scheduleDraftSave();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error =
              error.code == 'camera_access_denied' ||
                  error.code == 'photo_access_denied'
              ? 'Photo access is off. Allow it in Android settings and retry.'
              : 'Readuo could not open your photos. Please retry.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _removePhoto() async {
    final path = _photoPath;
    if (path == null || _uploadingPhoto || _submitting) return;
    setState(() {
      _hasUserEdited = true;
      _photoPath = null;
      _photoBytes = null;
      _error = null;
    });
    if (!_isEditing) {
      try {
        await widget.photoRepository.delete(path);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    }
    _scheduleDraftSave();
  }

  Future<void> _submit() async {
    if (_loading || _submitting || _uploadingPhoto) return;
    if (!await checkDraftContent(context, _textController) || !mounted) return;
    final text = _textController.text.trim();
    if (text.isEmpty && _photoPath == null) {
      setState(() => _error = 'Add text or a photo before posting.');
      return;
    }
    final ownerId = widget.ownerId;
    final repository = widget.circleRepository;
    final generation = _lifecycleGeneration;
    final attachment = _attachment;
    final draft = CirclePostDraft(
      postId: _draftPostId,
      text: _textController.text,
      attachment: attachment,
      photoPath: _photoPath,
    );
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final post = widget.post;
      if (post == null) {
        _draftTimer?.cancel();
        await _queueDraftWrite(draft, reportError: false);
        if (!_isCurrent(ownerId, generation)) return;
        await repository.publishPostDraft(authorId: ownerId, draft: draft);
      } else {
        await repository.updatePost(
          authorId: ownerId,
          postId: post.id,
          text: text,
          attachment: attachment,
          photoPath: _photoPath,
        );
        final previousPhotoPath = post.photoPath;
        if (previousPhotoPath != null && previousPhotoPath != _photoPath) {
          await widget.photoRepository.delete(previousPhotoPath);
        }
      }
      if (!_isCurrent(ownerId, generation)) return;
      _completed = true;
      _draftWriteGeneration++;
      Navigator.of(context).pop();
    } catch (error) {
      if (_isCurrent(ownerId, generation)) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _handleBack(bool didPop, Object? result) async {
    if (didPop || _loading || _submitting || !_hasContent || _completed) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isEditing ? 'Discard changes?' : 'Discard draft?'),
        content: Text(
          _isEditing
              ? 'Your original post will stay unchanged.'
              : 'Your text and book attachment will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const Key('circle-discard-draft'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    final ownerId = widget.ownerId;
    final repository = widget.circleRepository;
    final generation = _lifecycleGeneration;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      _draftTimer?.cancel();
      _draftWriteGeneration++;
      await _draftWrites;
      if (!_isEditing) {
        await repository.clearPostDraft(ownerId);
      }
      final discardPhoto = _photoPath;
      final originalPhoto = widget.post?.photoPath;
      if (discardPhoto != null && discardPhoto != originalPhoto) {
        await widget.photoRepository.delete(discardPhoto);
      }
      if (!_isCurrent(ownerId, generation)) return;
      _completed = true;
      Navigator.of(context).pop();
    } catch (error) {
      if (_isCurrent(ownerId, generation)) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    final draft = _draftSnapshot();
    if (!_completed &&
        !_isEditing &&
        !_submitting &&
        _snapshotHasContent(draft)) {
      _queueDisposeSnapshot(draft, widget.ownerId, widget.circleRepository);
    }
    _lifecycleGeneration++;
    _textController
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop:
        !_loading &&
        !_submitting &&
        !_uploadingPhoto &&
        (!_hasContent || _completed),
    onPopInvokedWithResult: _handleBack,
    child: Scaffold(
      key: Key(_isEditing ? 'circle-edit-post' : 'circle-new-post'),
      appBar: AppBar(title: Text(_isEditing ? 'Edit post' : 'New post')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  ReaduoSpacing.screenHorizontal,
                  12,
                  ReaduoSpacing.screenHorizontal,
                  24,
                ),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: ReaduoColors.accentTint,
                        backgroundImage: widget.photoUrl?.isNotEmpty == true
                            ? ReaduoImageCache.image(widget.photoUrl!)
                            : null,
                        child: widget.photoUrl?.isNotEmpty == true
                            ? null
                            : const Icon(
                                Icons.person_outline_rounded,
                                color: ReaduoColors.accent,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Sharing with friends',
                              style: TextStyle(
                                fontSize: 12,
                                color: ReaduoColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('circle-post-text'),
                    controller: _textController,
                    readOnly: _loading || _submitting,
                    enableInteractiveSelection: !_loading && !_submitting,
                    minLines: 6,
                    maxLines: 12,
                    maxLength: 5000,
                    autofocus: !_loading,
                    style: const TextStyle(fontSize: 17, height: 1.5),
                    decoration: const InputDecoration(
                      hintText: 'What are you reading or thinking about?',
                      hintStyle: TextStyle(
                        color: ReaduoColors.muted,
                        fontWeight: FontWeight.w400,
                      ),
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      border: InputBorder.none,
                    ),
                  ),
                  if (_attachment case final attachment?) ...[
                    const SizedBox(height: 4),
                    _AttachedBookCard(
                      attachment: attachment,
                      enabled: !_loading && !_submitting,
                      onRemove: () {
                        setState(() {
                          _hasUserEdited = true;
                          _attachment = null;
                          _error = null;
                        });
                        _scheduleDraftSave();
                      },
                    ),
                  ],
                  if (_photoPath != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          AspectRatio(
                            aspectRatio: 4 / 3,
                            child: ColoredBox(
                              color: ReaduoColors.accentTint,
                              child: _photoBytes == null
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : Image.memory(
                                      _photoBytes!,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton.filled(
                              key: const Key('circle-remove-photo'),
                              tooltip: 'Remove photo',
                              onPressed: _removePhoto,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_attachment == null && _photoPath == null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            key: const Key('circle-add-photo'),
                            onPressed:
                                _loading || _submitting || _uploadingPhoto
                                ? null
                                : _choosePhoto,
                            icon: _uploadingPhoto
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.image_outlined),
                            label: Text(
                              _uploadingPhoto
                                  ? 'Uploading…'
                                  : _photoPath == null
                                  ? 'Add photo'
                                  : 'Replace photo',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextButton.icon(
                            key: const Key('circle-attach-book'),
                            onPressed: _loading || _submitting
                                ? null
                                : _attachBook,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: const Text('Add book'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ReaduoSpacing.screenHorizontal,
                12,
                ReaduoSpacing.screenHorizontal,
                16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const Key('circle-post-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  FilledButton(
                    key: const Key('circle-submit-post'),
                    onPressed:
                        _loading ||
                            _submitting ||
                            _uploadingPhoto ||
                            (_textController.text.trim().isEmpty &&
                                _photoPath == null)
                        ? null
                        : _submit,
                    child: Text(
                      _submitting
                          ? 'Saving…'
                          : _isEditing
                          ? 'Save changes'
                          : 'Post to Circle',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AttachedBookCard extends StatelessWidget {
  const _AttachedBookCard({
    required this.attachment,
    required this.enabled,
    required this.onRemove,
  });

  final CircleBookAttachment attachment;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('circle-attached-book'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ReaduoColors.paper,
      border: Border.all(color: ReaduoColors.line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        _AttachmentCover(attachment: attachment),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                attachment.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                attachment.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            key: const Key('circle-remove-book'),
            tooltip: 'Remove book attachment',
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    ),
  );
}

class _AttachmentCover extends StatelessWidget {
  const _AttachmentCover({required this.attachment});

  final CircleBookAttachment attachment;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 68,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: ReaduoColors.accentTint),
        child: attachment.coverUrl == null
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: Center(
                  child: Text(
                    attachment.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ReaduoColors.ink,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            : BookCoverImage(
                attachment.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.menu_book_rounded,
                  color: ReaduoColors.accent,
                ),
              ),
      ),
    ),
  );
}

class CircleBookAttachmentScreen extends StatefulWidget {
  const CircleBookAttachmentScreen({
    required this.ownerId,
    required this.bookRepository,
    super.key,
  });

  final String ownerId;
  final BookRepository bookRepository;

  @override
  State<CircleBookAttachmentScreen> createState() =>
      _CircleBookAttachmentScreenState();
}

class _CircleBookAttachmentScreenState
    extends State<CircleBookAttachmentScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('circle-attach-book-screen'),
    appBar: AppBar(title: const Text('Attach a book')),
    body: SafeArea(
      child: StreamBuilder<List<LibraryBook>>(
        stream: widget.bookRepository.watchLibraryBooks(widget.ownerId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Your library could not be loaded.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final query = _query.trim().toLowerCase();
          final books = snapshot.data!
              .where(
                (book) =>
                    query.isEmpty ||
                    '${book.title} ${book.author}'.toLowerCase().contains(
                      query,
                    ),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              12,
              ReaduoSpacing.screenHorizontal,
              24,
            ),
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: ReaduoColors.paper,
                  border: Border.all(color: ReaduoColors.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: ReaduoColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('circle-book-search'),
                        onChanged: (value) => setState(() => _query = value),
                        style: const TextStyle(
                          color: ReaduoColors.ink,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search your library',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose one optional book attachment from your own library.',
                style: TextStyle(color: ReaduoColors.muted),
              ),
              const SizedBox(height: 12),
              if (books.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text('No books found')),
                )
              else
                ...books.map(
                  (book) => Column(
                    children: [
                      ListTile(
                        key: ValueKey('circle-attach-${book.id}'),
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        onTap: () => Navigator.of(context).pop(book),
                        leading: SizedBox(
                          width: 44,
                          height: 62,
                          child: _LibraryBookCover(book: book),
                        ),
                        title: Text(
                          book.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(book.author),
                        trailing: const Icon(Icons.add_rounded),
                      ),
                      const Divider(height: 1, color: ReaduoColors.line),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _LibraryBookCover extends StatelessWidget {
  const _LibraryBookCover({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(7),
    child: ColoredBox(
      color: ReaduoColors.accentTint,
      child: book.coverUrl == null || book.coverUrl!.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(5),
              child: Center(
                child: Text(
                  book.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ReaduoColors.ink,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : BookCoverImage(
              book.coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.menu_book_rounded,
                color: ReaduoColors.accent,
              ),
            ),
    ),
  );
}
