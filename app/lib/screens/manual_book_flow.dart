import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../library/book.dart';
import '../library/manual_book_draft.dart';
import '../library/book_cover_photo.dart';
import '../library/book_repository.dart';
import '../library/isbn.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';
import '../profile/profile_widgets.dart';
import '../widgets/generated_book_cover.dart';
import 'book_details_screen.dart';
import 'my_library_screen.dart';

class ManualBookFlow extends StatefulWidget {
  const ManualBookFlow({
    required this.ownerId,
    required this.shelf,
    required this.bookRepository,
    this.shelfRepository,
    this.existingBooks = const [],
    this.initialTitle = '',
    this.initialAuthor = '',
    this.initialIsbn = '',
    this.pickPhoto,
    super.key,
  });
  final String ownerId;
  final Shelf shelf;
  final BookRepository bookRepository;
  final ShelfRepository? shelfRepository;
  final List<LibraryBook> existingBooks;
  final String initialTitle;
  final String initialAuthor;
  final String initialIsbn;
  final Future<XFile?> Function(ImageSource)? pickPhoto;
  @override
  State<ManualBookFlow> createState() => _ManualBookFlowState();
}

class _ManualBookFlowState extends State<ManualBookFlow> {
  late final _title = TextEditingController(text: widget.initialTitle);
  late final _author = TextEditingController(text: widget.initialAuthor);
  late final _isbn = TextEditingController(text: widget.initialIsbn);
  final _publisher = TextEditingController();
  final _year = TextEditingController();
  final _description = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  StreamSubscription<List<LibraryBook>>? _bookSubscription;
  late List<LibraryBook> _existingBooks = widget.existingBooks;
  late Shelf _shelf = widget.shelf;
  BookCoverPhoto? _photo;
  bool _confirming = false;
  bool _busy = false;
  bool _owned = true;
  ReadingStatus _status = ReadingStatus.wantToRead;
  String? _error;
  String? _savedMessage;
  final _drafts = ManualBookDraftStore();
  @override
  void initState() {
    super.initState();
    _bookSubscription = widget.bookRepository
        .watchLibraryBooks(widget.ownerId)
        .listen((books) {
          if (mounted) setState(() => _existingBooks = books);
        }, onError: (_) {});
    if (widget.pickPhoto == null) unawaited(_restorePhotoDraft());
  }

  Future<void> _restorePhotoDraft() async {
    try {
      final draft = await _drafts.read(widget.ownerId);
      if (!mounted || draft == null || draft['shelfId'] != widget.shelf.id)
        return;
      for (final entry in {
        'title': _title,
        'author': _author,
        'isbn': _isbn,
        'publisher': _publisher,
        'year': _year,
        'description': _description,
      }.entries) {
        entry.value.text = draft[entry.key] as String? ?? '';
      }
      _owned = draft['owned'] as bool? ?? true;
      _status =
          ReadingStatus.values
              .where((status) => status.name == draft['status'])
              .firstOrNull ??
          ReadingStatus.wantToRead;
      if (draft['photo'] is String)
        _photo = BookCoverPhoto(base64Decode(draft['photo'] as String));
      if (mounted) setState(() {});
      final lost = await ImagePicker().retrieveLostData();
      if (!mounted) return;
      if (lost.files?.isNotEmpty == true) {
        final photo = BookCoverPhoto(await lost.files!.first.readAsBytes());
        if (!mounted) return;
        if (mounted) setState(() => _photo = photo);
        await _savePhotoDraft();
      } else if (lost.exception != null) {
        setState(
          () => _error =
              'Your book details were recovered. Please choose the cover again.',
        );
      }
    } catch (_) {}
  }

  Future<void> _savePhotoDraft() async {
    if (widget.pickPhoto != null) return;
    await _drafts.write(widget.ownerId, {
      'shelfId': _shelf.id,
      'title': _title.text,
      'author': _author.text,
      'isbn': _isbn.text,
      'publisher': _publisher.text,
      'year': _year.text,
      'description': _description.text,
      'owned': _owned,
      'status': _status.name,
      if (_photo != null) 'photo': base64Encode(_photo!.bytes),
    });
  }

  Future<void> _clearDraft() async {
    try {
      await _drafts.clear(widget.ownerId);
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_bookSubscription?.cancel());
    _scrollController.dispose();
    for (final controller in [
      _title,
      _author,
      _isbn,
      _publisher,
      _year,
      _description,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _duplicate =>
      _isbn.text.trim().isEmpty &&
      _existingBooks.any(
        (book) =>
            book.shelfId == _shelf.id &&
            book.isbn == null &&
            book.title.trim().toLowerCase() == _title.text.trim().toLowerCase(),
      );

  Future<void> _choosePhoto() async {
    FocusScope.of(context).unfocus();
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ReaduoSpacing.screenHorizontal,
            vertical: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Book cover',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                key: const Key('cover-camera'),
                onPressed: () => Navigator.pop(sheetContext, 'camera'),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take a photo'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('cover-library'),
                onPressed: () => Navigator.pop(sheetContext, 'gallery'),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from library'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, 'remove'),
                child: const Text('Use a generated title cover'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'remove') {
      setState(() => _photo = null);
      await _clearDraft();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _savePhotoDraft();
      final imageSource = source == 'camera'
          ? ImageSource.camera
          : ImageSource.gallery;
      final file =
          await (widget.pickPhoto?.call(imageSource) ??
              ImagePicker().pickImage(
                source: imageSource,
                maxWidth: 1600,
                maxHeight: 2200,
                imageQuality: 85,
              ));
      if (file == null) return;
      final photo = BookCoverPhoto(await file.readAsBytes());
      if (!mounted) return;
      if (mounted) setState(() => _photo = photo);
      await _savePhotoDraft();
    } on PlatformException {
      if (mounted)
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (pageContext) => ProfilePage(
              title: 'Photo access',
              children: [
                const SizedBox(height: 45),
                const Icon(
                  Icons.image_not_supported_outlined,
                  size: 52,
                  color: ReaduoColors.accent,
                ),
                const Text(
                  'Your photos are unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
                ),
                const Text(
                  'Allow camera or photo access in phone settings, or continue without a photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ReaduoColors.muted, height: 1.6),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await const MethodChannel(
                        'com.zipdosa.readuo/settings',
                      ).invokeMethod<void>('openAppSettings');
                    } catch (_) {}
                  },
                  child: const Text('Open phone settings'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(pageContext),
                  child: const Text('Continue without a photo'),
                ),
              ],
            ),
          ),
        );
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not open this photo. Try another photo or continue without one.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _confirming = true;
      _error = null;
    });
    _scrollController.jumpTo(0);
  }

  Future<void> _createShelf() async {
    final repository = widget.shelfRepository;
    if (repository == null) return;
    final shelf = await showModalBottomSheet<Shelf>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CreateShelfSheet(
        ownerId: widget.ownerId,
        shelfRepository: repository,
      ),
    );
    if (shelf != null && mounted) setState(() => _shelf = shelf);
  }

  Future<void> _save({bool enterAnother = false}) async {
    if (_busy) return;
    if (_duplicate) {
      final existing = _existingBooks.firstWhere(
        (book) =>
            book.shelfId == _shelf.id &&
            book.isbn == null &&
            book.title.trim().toLowerCase() == _title.text.trim().toLowerCase(),
      );
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (reviewContext) => ProfilePage(
            title: 'Review possible duplicate',
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4DE),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Text(
                  'No ISBN was entered. These titles may refer to the same book, but nothing has been merged or discarded.',
                ),
              ),
              const Text(
                'Your manual entry',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: ReaduoColors.line),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title.text,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(_author.text),
                    const SizedBox(height: 8),
                    const Text(
                      'Will receive a unique entry ID · No ISBN',
                      style: TextStyle(fontSize: 12, color: ReaduoColors.muted),
                    ),
                  ],
                ),
              ),
              const Text(
                'Possible existing entry',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 90,
                    child: GeneratedBookCover(
                      title: existing.title,
                      author: existing.author,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          existing.title,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(existing.author),
                      ],
                    ),
                  ),
                ],
              ),
              const Text(
                'Confirm these are separate entries now, or review the details. A later ISBN match must also require explicit resolution.',
                style: TextStyle(fontSize: 12, color: ReaduoColors.muted),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(reviewContext, true),
                child: const Text('Add as a separate entry'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(reviewContext).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BookDetailsScreen(
                      ownerId: widget.ownerId,
                      shelfId: existing.shelfId,
                      bookId: existing.id,
                      shelfRepository:
                          widget.shelfRepository ??
                          const EmptyShelfRepository(),
                      bookRepository: widget.bookRepository,
                      showBottomNavigation: false,
                    ),
                  ),
                ),
                child: const Text('View existing entry'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(reviewContext, false),
                child: const Text('Review manual details'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_photo != null) await _savePhotoDraft();
      if (!mounted) return;
      await widget.bookRepository.createBook(
        ownerId: widget.ownerId,
        shelf: _shelf,
        input: CreateBookInput(
          title: _title.text,
          author: _author.text,
          isbnInput: _isbn.text,
          isOwned: _owned,
          readingStatus: _status,
          coverPhoto: _photo,
          publisher: _publisher.text,
          publishedYear: _year.text,
          description: _description.text,
        ),
      );
      await _clearDraft();
      if (!mounted) return;
      if (enterAnother) {
        final savedTitle = _title.text.trim();
        FocusScope.of(context).unfocus();
        setState(() {
          _confirming = false;
          for (final controller in [
            _title,
            _author,
            _isbn,
            _publisher,
            _year,
            _description,
          ]) {
            controller.clear();
          }
          _photo = null;
          _owned = true;
          _status = ReadingStatus.wantToRead;
          _error = null;
          _savedMessage = '$savedTitle added to ${_shelf.name}.';
        });
        _scrollController.jumpTo(0);
      } else {
        Navigator.of(context).pop();
      }
    } on BookFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not save this book. Your details and photo are still here. Check your connection and retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    String keyName,
    TextEditingController controller, {
    int lines = 1,
    int limit = 160,
    String? Function(String?)? validator,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 7),
      TextFormField(
        key: Key(keyName),
        controller: controller,
        enabled: !_busy,
        maxLines: lines,
        inputFormatters: [LengthLimitingTextInputFormatter(limit)],
        validator: validator,
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.all(13),
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
    ],
  );
  Widget _generatedCover() => Container(
    width: 76,
    height: 112,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xFF416071),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _title.text,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        Text(
          _author.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: ReaduoColors.line),
    );
    return PopScope(
      canPop: !_busy && !_confirming,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) unawaited(_clearDraft());
        if (!didPop && !_busy && _confirming)
          setState(() => _confirming = false);
      },
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: Scaffold(
          backgroundColor: ReaduoColors.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 64,
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(
                left: ReaduoSpacing.screenHorizontal,
                top: 10,
                bottom: 10,
              ),
              child: IconButton.outlined(
                onPressed: _busy
                    ? null
                    : () {
                        if (_confirming) {
                          setState(() => _confirming = false);
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                icon: const Icon(Icons.arrow_back, size: 20),
                style: IconButton.styleFrom(
                  side: const BorderSide(color: ReaduoColors.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
            titleSpacing: 10,
            title: Text(
              _confirming ? 'Save your book' : 'Add a book',
              style: const TextStyle(
                fontSize: 20,
                letterSpacing: -.7,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                ReaduoSpacing.screenHorizontal,
                18,
                ReaduoSpacing.screenHorizontal,
                24,
              ),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_confirming) ...[
                      if (_savedMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_savedMessage!),
                          ),
                        ),
                      OutlinedButton.icon(
                        key: const Key('add-cover-photo'),
                        onPressed: _busy ? null : _choosePhoto,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _photo == null
                              ? 'Add cover photo (optional)'
                              : 'Cover photo selected',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _field(
                        'Title · Required',
                        'book-title-field',
                        _title,
                        validator: (value) => value!.trim().isEmpty
                            ? 'Enter a book title.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        'Author · Required',
                        'book-author-field',
                        _author,
                        limit: 120,
                        validator: (value) =>
                            value!.trim().isEmpty ? 'Enter an author.' : null,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        'ISBN (optional)',
                        'book-isbn-field',
                        _isbn,
                        limit: 20,
                        validator: (value) {
                          try {
                            Isbn.normalizeOptional(value!);
                            return null;
                          } on IsbnValidationException catch (error) {
                            return error.message;
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      _field(
                        'Publisher (optional)',
                        'book-publisher-field',
                        _publisher,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        'Published year (optional)',
                        'book-year-field',
                        _year,
                        limit: 4,
                        validator: (value) =>
                            value!.isEmpty ||
                                RegExp(r'^[0-9]{4}$').hasMatch(value)
                            ? null
                            : 'Enter a four-digit year or leave blank.',
                      ),
                      const SizedBox(height: 16),
                      _field(
                        'Description (optional)',
                        'book-description-field',
                        _description,
                        lines: 3,
                        limit: 2000,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ReaduoColors.accentTint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'ISBN-10 is normalized to ISBN-13. Without an ISBN, a unique entry is created. Similar titles are never silently merged.',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                      if (_duplicate)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'A no-ISBN book with this title is already on this shelf.',
                            key: Key('same-title-warning'),
                          ),
                        ),
                    ] else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _photo == null
                              ? _generatedCover()
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    _photo!.bytes,
                                    width: 76,
                                    height: 112,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _title.text,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(_author.text),
                                const SizedBox(height: 10),
                                Text(
                                  _photo == null
                                      ? 'Generated title cover'
                                      : 'Optional cover photo selected',
                                  style: const TextStyle(
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
                      const Text(
                        'Shelf · Required',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 7),
                      StreamBuilder<List<Shelf>>(
                        stream: widget.shelfRepository?.watchShelves(
                          widget.ownerId,
                        ),
                        builder: (context, snapshot) {
                          final shelves = <String, Shelf>{
                            _shelf.id: _shelf,
                            for (final shelf in snapshot.data ?? <Shelf>[])
                              if (shelf.ownerId == widget.ownerId &&
                                  shelf.mutationOperationId == null)
                                shelf.id: shelf,
                          };
                          return DropdownButtonFormField<String>(
                            isExpanded: true,
                            key: ValueKey('destination-${_shelf.id}'),
                            initialValue: _shelf.id,
                            decoration: InputDecoration(
                              border: border,
                              enabledBorder: border,
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: shelves.values
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
                            onChanged: _busy
                                ? null
                                : (value) =>
                                      setState(() => _shelf = shelves[value]!),
                          );
                        },
                      ),
                      if (widget.shelfRepository != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _busy ? null : _createShelf,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Create a new shelf'),
                          ),
                        ),
                      SwitchListTile(
                        activeThumbColor: Colors.white,
                        activeTrackColor: ReaduoColors.accent,
                        key: const Key('book-owned-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('I own this book'),
                        value: _owned,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _owned = value),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        key: const Key('book-status-control'),
                        spacing: 8,
                        runSpacing: 8,
                        children: ReadingStatus.values
                            .map(
                              (status) => ChoiceChip(
                                shape: const StadiumBorder(),
                                side: const BorderSide(
                                  color: ReaduoColors.line,
                                ),
                                label: Text(status.label),
                                selected: _status == status,
                                showCheckmark: false,
                                selectedColor: ReaduoColors.accent,
                                labelStyle: TextStyle(
                                  color: _status == status
                                      ? Colors.white
                                      : ReaduoColors.ink,
                                  fontSize: 12,
                                ),
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(() => _status = status),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          key: const Key('book-save-error'),
                          style: const TextStyle(
                            color: Color(0xFFAC2C40),
                            height: 1.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (_confirming) ...[
                      FilledButton(
                        key: const Key('save-book-another-button'),
                        onPressed: _busy
                            ? null
                            : () => _save(enterAnother: true),
                        child: const Text('Add & Enter Another'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        key: const Key('save-book-button'),
                        onPressed: _busy ? null : _save,
                        child: Text(_busy ? 'Adding...' : 'Add & Finish'),
                      ),
                    ] else
                      FilledButton(
                        key: const Key('manual-next-button'),
                        onPressed: _busy ? null : _next,
                        child: const Text('Choose shelf & status'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
