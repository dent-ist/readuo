import '../widgets/readuo_image_cache.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../library/book.dart';
import '../library/book_lookup.dart';
import '../library/book_repository.dart';
import '../library/isbn.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';

class IsbnScanResult {
  const IsbnScanResult(this.shelf);

  final Shelf shelf;
}

class CameraIsbnScanner extends StatefulWidget {
  const CameraIsbnScanner({required this.onCode, super.key});
  final ValueChanged<String> onCode;

  @override
  State<CameraIsbnScanner> createState() => _CameraIsbnScannerState();
}

class _CameraIsbnScannerState extends State<CameraIsbnScanner> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    unawaited(_controller.stop());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      MobileScanner(
        controller: _controller,
        useAppLifecycleState: true,
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null) {
              widget.onCode(value);
              return;
            }
          }
        },
        errorBuilder: (context, error) => _CameraUnavailable(error: error),
      ),
      ValueListenableBuilder<MobileScannerState>(
        valueListenable: _controller,
        builder: (context, state, _) => state.error != null
            ? const SizedBox.shrink()
            : Center(
                child: Container(
                  width: 272,
                  height: 126,
                  decoration: BoxDecoration(
                    border: Border.all(color: ReaduoColors.accent, width: 3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
      ),
      const Positioned(
        left: 24,
        right: 24,
        bottom: 22,
        child: Text(
          'Line up the ISBN barcode\nUsually on the back cover',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, height: 1.45),
        ),
      ),
      Positioned(
        right: 12,
        top: 8,
        child: ValueListenableBuilder<MobileScannerState>(
          valueListenable: _controller,
          builder: (context, state, _) {
            if (state.torchState == TorchState.unavailable) {
              return const SizedBox.shrink();
            }
            return IconButton.filledTonal(
              key: const Key('scanner-torch-button'),
              tooltip: 'Toggle flashlight',
              onPressed: _controller.toggleTorch,
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.error});
  static const _platform = MethodChannel('com.zipdosa.readuo/settings');
  final MobileScannerException error;

  Future<void> _openSettings(BuildContext context) async {
    try {
      await _platform.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      _showSettingsHelp(context);
    } on MissingPluginException {
      _showSettingsHelp(context);
    }
  }

  void _showSettingsHelp(BuildContext context) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open Readuo settings to allow Camera.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: ReaduoColors.ink,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ReaduoSpacing.screenHorizontal,
          vertical: 24,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Camera access is off. Allow Camera in phone settings, or use an option below.'
                  : 'The camera is unavailable. Enter an ISBN or search instead.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (denied) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const Key('open-camera-settings'),
                onPressed: () => _openSettings(context),
                child: const Text('Open phone settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CameraChrome extends StatelessWidget {
  const _CameraChrome({
    required this.title,
    required this.onClose,
    required this.camera,
    required this.footer,
  });
  final String title;
  final VoidCallback? onClose;
  final Widget camera;
  final Widget footer;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              key: const Key('close-scanner'),
              tooltip: 'Close scanner',
              color: Colors.white,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
      Expanded(child: camera),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          16,
          ReaduoSpacing.screenHorizontal,
          20,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF202D43),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: footer,
      ),
    ],
  );
}

class _PausedCamera extends StatelessWidget {
  const _PausedCamera();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    key: Key('scanner-camera-paused'),
    color: Color(0xFF0B1220),
    child: Center(
      child: Icon(Icons.pause_circle_outline, color: Colors.white70, size: 42),
    ),
  );
}

class _ScannerSheetPage extends StatelessWidget {
  const _ScannerSheetPage({
    required this.child,
    required this.onClose,
    this.matched = false,
  });
  final Widget child;
  final VoidCallback? onClose;
  final bool matched;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cameraHeight = constraints.maxHeight < 650 ? 90.0 : 126.0;
      return Column(
        children: [
          _ScannerContextHeader(onClose: onClose),
          SizedBox(
            height: cameraHeight,
            width: double.infinity,
            child: _InactiveCameraContext(matched: matched),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: ReaduoColors.paper,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 9),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ReaduoColors.line,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ScannerContextHeader extends StatelessWidget {
  const _ScannerContextHeader({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Row(
      children: [
        IconButton(
          key: const Key('close-scanner'),
          tooltip: 'Close scanner',
          color: Colors.white,
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
        const Expanded(
          child: Text(
            'Scan a book',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    ),
  );
}

class _InactiveCameraContext extends StatelessWidget {
  const _InactiveCameraContext({this.matched = false});
  final bool matched;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ReaduoColors.ink,
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Container(
              width: constraints.maxWidth.clamp(220, 272).toDouble(),
              height: constraints.maxHeight < 110 ? 44 : 68,
              decoration: BoxDecoration(
                border: Border.all(color: ReaduoColors.accent, width: 3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Icon(
                  matched
                      ? Icons.check_rounded
                      : Icons.document_scanner_outlined,
                  color: Colors.white70,
                  size: 34,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            matched ? 'Match found. Confirm below.' : 'Camera paused',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFD6DDEB), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _DestinationPicker extends StatelessWidget {
  const _DestinationPicker({
    required this.shelves,
    required this.message,
    required this.creatingShelf,
    required this.canCreateShelf,
    required this.onSelected,
    required this.onCreateShelf,
    required this.onRetry,
  });
  final List<Shelf> shelves;
  final String? message;
  final bool creatingShelf;
  final bool canCreateShelf;
  final ValueChanged<Shelf> onSelected;
  final VoidCallback onCreateShelf;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      ReaduoSpacing.screenHorizontal,
      24,
      ReaduoSpacing.screenHorizontal,
      28,
    ),
    children: [
      _EmptyMark(
        icon: shelves.isEmpty ? Icons.shelves : Icons.library_books_outlined,
      ),
      const SizedBox(height: 20),
      Text(
        shelves.isEmpty ? 'Create your first shelf' : 'Where should books go?',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: ReaduoColors.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        shelves.isEmpty
            ? 'A shelf is required before you scan your first book.'
            : 'Choose one shelf for this scanning session.',
        textAlign: TextAlign.center,
      ),
      if (message != null) ...[
        const SizedBox(height: 12),
        Text(
          message!,
          key: const Key('scanner-destination-error'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 20),
      for (final shelf in shelves)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton(
            key: ValueKey('scanner-destination-${shelf.id}'),
            onPressed: () => onSelected(shelf),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(shelf.name),
            ),
          ),
        ),
      if (message != null && shelves.isEmpty)
        OutlinedButton(onPressed: onRetry, child: const Text('Retry shelves')),
      if (canCreateShelf) ...[
        const SizedBox(height: 4),
        FilledButton.icon(
          key: const Key('scanner-create-first-shelf'),
          onPressed: creatingShelf ? null : onCreateShelf,
          icon: const Icon(Icons.add_rounded),
          label: Text(creatingShelf ? 'Creating shelf…' : 'Create a new shelf'),
        ),
      ],
    ],
  );
}

class _ShelfChoiceSheet extends StatelessWidget {
  const _ShelfChoiceSheet({
    required this.shelves,
    required this.selectedShelfId,
    this.excludeShelfId,
  });
  final ValueNotifier<List<Shelf>> shelves;
  final String? selectedShelfId;
  final String? excludeShelfId;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.78,
    child: ValueListenableBuilder<List<Shelf>>(
      valueListenable: shelves,
      builder: (context, values, _) {
        final visible = values
            .where((shelf) => shelf.id != excludeShelfId)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ReaduoSpacing.screenHorizontal,
                4,
                ReaduoSpacing.screenHorizontal,
                10,
              ),
              child: Text(
                'Choose a shelf',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('No available shelves.'))
                  : ListView.builder(
                      key: const Key('scanner-shelf-choice-list'),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final shelf = visible[index];
                        return ListTile(
                          key: ValueKey('scanner-sheet-shelf-${shelf.id}'),
                          leading: Icon(
                            selectedShelfId == shelf.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selectedShelfId == shelf.id
                                ? ReaduoColors.accent
                                : ReaduoColors.muted,
                          ),
                          title: Text(shelf.name),
                          subtitle: Text(shelf.visibility.label),
                          onTap: () => Navigator.of(context).pop(shelf),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class IsbnManualSeed {
  const IsbnManualSeed({this.title = '', this.author = '', this.isbn = ''});

  final String title;
  final String author;
  final String isbn;
}

typedef IsbnScannerBuilder =
    Widget Function(BuildContext context, ValueChanged<String> onCode);

class IsbnScannerScreen extends StatefulWidget {
  const IsbnScannerScreen({
    required this.ownerId,
    required this.shelfRepository,
    required this.bookRepository,
    required this.lookupRepository,
    this.initialShelf,
    this.startWithManualIsbn = false,
    this.scannerBuilder,
    this.onCreateShelf,
    this.onSearchCatalogue,
    this.onOpenManualAdd,
    this.onViewExisting,
    super.key,
  });

  final String ownerId;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final BookLookupRepository lookupRepository;
  final Shelf? initialShelf;
  final bool startWithManualIsbn;
  final IsbnScannerBuilder? scannerBuilder;
  final Future<Shelf?> Function()? onCreateShelf;
  final Future<void> Function(Shelf shelf, String initialQuery)?
  onSearchCatalogue;
  final Future<void> Function(Shelf shelf, IsbnManualSeed seed)?
  onOpenManualAdd;
  final Future<void> Function(LibraryBook book)? onViewExisting;

  @override
  State<IsbnScannerScreen> createState() => _IsbnScannerScreenState();
}

enum _ScanStage {
  scanning,
  manualIsbn,
  lookingUp,
  confirmation,
  duplicate,
  failure,
}

class _IsbnScannerScreenState extends State<IsbnScannerScreen> {
  late final String _activityBatchId =
      'scan-${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(0x7fffffff)}';
  final _manualIsbnController = TextEditingController();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final ValueNotifier<List<Shelf>> _eligibleShelves = ValueNotifier(const []);
  StreamSubscription<List<Shelf>>? _shelfSubscription;
  StreamSubscription<List<LibraryBook>>? _bookSubscription;
  List<Shelf> _shelves = const [];
  List<LibraryBook> _books = const [];
  Shelf? _selectedShelf;
  Shelf? _lastSavedShelf;
  late _ScanStage _stage;
  _ScanStage _stageBeforeLookup = _ScanStage.scanning;
  BookLookupResult? _result;
  LibraryBook? _duplicateBook;
  String? _duplicateFallbackMessage;
  String? _shelfError;
  String? _lookupError;
  String? _validationMessage;
  String? _titleError;
  String? _authorError;
  String? _saveError;
  String? _activeIsbn;
  String? _savedMessage;
  bool _shelvesLoaded = false;
  bool _creatingShelf = false;
  bool _lookupBusy = false;
  bool _saving = false;
  bool _childFlowActive = false;
  bool _sessionActive = true;
  bool _isOwned = true;
  ReadingStatus _status = ReadingStatus.wantToRead;
  int _lookupGeneration = 0;
  int _detectionGeneration = 0;
  int _scannerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _stage = widget.startWithManualIsbn
        ? _ScanStage.manualIsbn
        : _ScanStage.scanning;
    _selectedShelf = _eligibleShelf(widget.initialShelf);
    _subscribeShelves();
    _subscribeBooks();
  }

  @override
  void didUpdateWidget(covariant IsbnScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.shelfRepository != widget.shelfRepository ||
        oldWidget.bookRepository != widget.bookRepository) {
      _selectedShelf = _eligibleShelf(widget.initialShelf);
      _subscribeShelves();
      _subscribeBooks();
    }
  }

  void _subscribeShelves() {
    unawaited(_shelfSubscription?.cancel());
    _shelvesLoaded = false;
    _shelfSubscription = widget.shelfRepository
        .watchShelves(widget.ownerId)
        .listen(_handleShelves, onError: (_) => _handleShelfError());
  }

  void _subscribeBooks() {
    unawaited(_bookSubscription?.cancel());
    _bookSubscription = widget.bookRepository
        .watchLibraryBooks(widget.ownerId)
        .listen(_handleBooks, onError: (_) {});
  }

  Shelf? _eligibleShelf(Shelf? shelf) {
    if (shelf == null ||
        shelf.ownerId != widget.ownerId ||
        shelf.mutationOperationId != null) {
      return null;
    }
    return shelf;
  }

  void _handleShelves(List<Shelf> shelves) {
    if (!mounted || !_sessionActive) return;
    final eligible = shelves
        .where(
          (shelf) =>
              shelf.ownerId == widget.ownerId &&
              shelf.mutationOperationId == null,
        )
        .toList(growable: false);
    final selectedId = _selectedShelf?.id;
    Shelf? selected;
    if (selectedId != null) {
      for (final shelf in eligible) {
        if (shelf.id == selectedId) selected = shelf;
      }
    }
    _eligibleShelves.value = eligible;
    setState(() {
      _shelves = eligible;
      _shelvesLoaded = true;
      _shelfError = null;
      if (selectedId != null) {
        _selectedShelf = selected;
        if (selected == null) {
          _shelfError =
              'That shelf is no longer available. Choose another shelf; your current book is preserved.';
        }
      }
    });
  }

  void _handleShelfError() {
    if (!mounted || !_sessionActive) return;
    _eligibleShelves.value = const [];
    setState(() {
      _shelves = const [];
      _shelvesLoaded = true;
      _selectedShelf = null;
      _shelfError =
          'Readuo could not verify your shelves. Check your connection and retry.';
    });
  }

  void _handleBooks(List<LibraryBook> books) {
    if (!mounted || !_sessionActive) return;
    setState(() {
      _books = books
          .where((book) => book.ownerId == widget.ownerId)
          .toList(growable: false);
      if (_stage == _ScanStage.duplicate && _activeIsbn != null) {
        _duplicateBook = _findDuplicate(_activeIsbn!);
      }
    });
  }

  @override
  void dispose() {
    _sessionActive = false;
    _lookupGeneration += 1;
    _detectionGeneration += 1;
    unawaited(_shelfSubscription?.cancel());
    unawaited(_bookSubscription?.cancel());
    _eligibleShelves.dispose();
    _manualIsbnController.dispose();
    _titleController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  LibraryBook? _findDuplicate(String isbn) {
    for (final book in _books) {
      try {
        if (book.isbn != null && Isbn.normalizeOptional(book.isbn!) == isbn) {
          return book;
        }
      } on IsbnValidationException {
        continue;
      }
    }
    return null;
  }

  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? false;

  void _handleDetection(String rawValue, int generation) {
    if (!_sessionActive ||
        !mounted ||
        generation != _detectionGeneration ||
        _stage != _ScanStage.scanning ||
        _childFlowActive ||
        _lookupBusy ||
        _saving ||
        !_routeIsCurrent) {
      return;
    }
    unawaited(_lookup(rawValue, origin: _ScanStage.scanning));
  }

  Future<void> _lookup(String rawValue, {required _ScanStage origin}) async {
    if (_lookupBusy || _saving || _childFlowActive || !_sessionActive) return;
    String? isbn;
    try {
      isbn = Isbn.normalizeOptional(rawValue);
    } on IsbnValidationException catch (error) {
      setState(() => _validationMessage = error.message);
      return;
    }
    if (isbn == null) {
      setState(() => _validationMessage = 'Enter an ISBN first.');
      return;
    }
    _stageBeforeLookup = origin;
    final duplicate = _findDuplicate(isbn);
    if (duplicate != null) {
      setState(() {
        _activeIsbn = isbn;
        _duplicateBook = duplicate;
        _duplicateFallbackMessage = null;
        _lookupError = null;
        _validationMessage = null;
        _stage = _ScanStage.duplicate;
      });
      return;
    }

    final generation = ++_lookupGeneration;
    setState(() {
      _lookupBusy = true;
      _activeIsbn = isbn;
      _lookupError = null;
      _validationMessage = null;
      _stageBeforeLookup = origin;
      _stage = _ScanStage.lookingUp;
      _detectionGeneration += 1;
    });
    try {
      final result = await widget.lookupRepository.lookup(isbn);
      if (!mounted || !_sessionActive || generation != _lookupGeneration) {
        return;
      }
      final lateDuplicate = _findDuplicate(isbn);
      setState(() {
        if (lateDuplicate != null) {
          _duplicateBook = lateDuplicate;
          _stage = _ScanStage.duplicate;
        } else {
          _result = result;
          _titleController.text = result.title;
          _authorController.text = result.author;
          _isOwned = true;
          _status = ReadingStatus.wantToRead;
          _stage = _ScanStage.confirmation;
        }
      });
    } on BookLookupFailure catch (error) {
      if (!mounted || !_sessionActive || generation != _lookupGeneration) {
        return;
      }
      setState(() {
        _lookupError = error.message;
        _stage = _ScanStage.failure;
      });
    } catch (_) {
      if (!mounted || !_sessionActive || generation != _lookupGeneration) {
        return;
      }
      setState(() {
        _lookupError = 'Book lookup failed unexpectedly. Please retry.';
        _stage = _ScanStage.failure;
      });
    } finally {
      if (mounted && generation == _lookupGeneration) {
        setState(() => _lookupBusy = false);
      }
    }
  }

  void _cancelLookup() {
    _lookupGeneration += 1;
    setState(() {
      _lookupBusy = false;
      _activeIsbn = null;
      _lookupError = null;
      _stage = _stageBeforeLookup;
      _scannerGeneration += 1;
      _detectionGeneration += 1;
    });
  }

  void _resetBookDraft({required _ScanStage nextStage}) {
    if (_saving) return;
    setState(() {
      _result = null;
      _duplicateBook = null;
      _duplicateFallbackMessage = null;
      _lookupError = null;
      _validationMessage = null;
      _saveError = null;
      _titleError = null;
      _authorError = null;
      _activeIsbn = null;
      _manualIsbnController.clear();
      _titleController.clear();
      _authorController.clear();
      _isOwned = true;
      _status = ReadingStatus.wantToRead;
      _stage = nextStage;
      _scannerGeneration += 1;
      _detectionGeneration += 1;
    });
  }

  Future<T?> _runCovered<T>(Future<T?> Function() action) async {
    if (_childFlowActive || _saving || !_sessionActive) return null;
    setState(() {
      _childFlowActive = true;
      _detectionGeneration += 1;
    });
    try {
      return await action();
    } finally {
      if (mounted && _sessionActive) {
        setState(() {
          _childFlowActive = false;
          _scannerGeneration += 1;
          _detectionGeneration += 1;
        });
      }
    }
  }

  Future<void> _createShelf() async {
    if (_creatingShelf || _saving || widget.onCreateShelf == null) return;
    setState(() => _creatingShelf = true);
    try {
      final shelf = _eligibleShelf(
        await _runCovered<Shelf>(widget.onCreateShelf!),
      );
      if (!mounted || shelf == null) return;
      final current = _shelves.where((candidate) => candidate.id == shelf.id);
      final exact = current.isEmpty ? shelf : current.first;
      if (_eligibleShelf(exact) == null) return;
      setState(() {
        if (!_shelves.any((candidate) => candidate.id == exact.id)) {
          _shelves = [..._shelves, exact];
          _eligibleShelves.value = _shelves;
        }
        _selectedShelf = exact;
        _shelfError = null;
      });
    } finally {
      if (mounted) setState(() => _creatingShelf = false);
    }
  }

  Future<void> _chooseShelf() async {
    if (_saving) return;
    if (_shelves.isEmpty) {
      await _createShelf();
      return;
    }
    final returned = await _runCovered<Shelf>(() {
      return showModalBottomSheet<Shelf>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: ReaduoColors.paper,
        builder: (_) => _ShelfChoiceSheet(
          shelves: _eligibleShelves,
          selectedShelfId: _selectedShelf?.id,
        ),
      );
    });
    if (!mounted || returned == null) return;
    Shelf? current;
    for (final shelf in _shelves) {
      if (shelf.id == returned.id) current = shelf;
    }
    if (current == null || _eligibleShelf(current) == null) {
      setState(() {
        _shelfError =
            'That shelf changed before selection. Choose an available shelf.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That shelf changed before selection. Choose an available shelf.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _selectedShelf = current;
      _shelfError = null;
    });
  }

  IsbnManualSeed get _manualSeed => IsbnManualSeed(
    title: _titleController.text,
    author: _authorController.text,
    isbn: _activeIsbn ?? _result?.isbn ?? _manualIsbnController.text,
  );

  Future<void> _openManualAdd() async {
    final shelf = _selectedShelf;
    if (shelf == null || _saving) return;
    if (widget.onOpenManualAdd != null) {
      await _runCovered<void>(() async {
        await widget.onOpenManualAdd!(shelf, _manualSeed);
        return null;
      });
    }
  }

  Future<void> _openCatalogue() async {
    final shelf = _selectedShelf;
    if (shelf == null || _saving || widget.onSearchCatalogue == null) return;
    final query = _activeIsbn ?? _result?.isbn ?? _manualIsbnController.text;
    await _runCovered<void>(() async {
      await widget.onSearchCatalogue!(shelf, query);
      return null;
    });
  }

  Future<void> _save({required bool scanAnother}) async {
    if (_saving || _childFlowActive) return;
    final shelf = _selectedShelf;
    final result = _result;
    if (shelf == null || result == null) return;
    final submittedIsbn = result.isbn;
    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    setState(() {
      _titleError = title.isEmpty ? 'Enter a book title.' : null;
      _authorError = author.isEmpty ? 'Enter an author.' : null;
      _saveError = null;
    });
    if (_titleError != null || _authorError != null) return;
    setState(() {
      _saving = true;
      _detectionGeneration += 1;
    });
    try {
      await widget.bookRepository.createBookInActivityBatch(
        ownerId: widget.ownerId,
        shelf: shelf,
        activityBatchId: _activityBatchId,
        input: CreateBookInput(
          title: title,
          author: author,
          isbnInput: submittedIsbn,
          isOwned: _isOwned,
          readingStatus: _status,
          coverUrl: result.coverUrl,
          publisher: (result.publisher ?? '').characters.take(160).toString(),
          publishedYear: result.publishedYear?.toString() ?? '',
          description: (result.description ?? '').characters
              .take(2000)
              .toString(),
        ),
      );
      if (!mounted || !_sessionActive) return;
      _lastSavedShelf = shelf;
      if (scanAnother) {
        _savedMessage = '$title added to ${shelf.name}.';
        _saving = false;
        _resetBookDraft(nextStage: _stageBeforeLookup);
      } else {
        Navigator.of(context).pop(IsbnScanResult(shelf));
      }
    } on DuplicateIsbnFailure catch (error) {
      if (!mounted || !_sessionActive) return;
      setState(() {
        _activeIsbn = submittedIsbn;
        _duplicateBook = _findDuplicate(submittedIsbn);
        _duplicateFallbackMessage = error.message;
        _stage = _ScanStage.duplicate;
      });
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

  Future<void> _moveDuplicate() async {
    final duplicate = _duplicateBook;
    if (duplicate == null || _saving) return;
    final destinations = _shelves
        .where((shelf) => shelf.id != duplicate.shelfId)
        .toList(growable: false);
    if (destinations.isEmpty) {
      setState(
        () => _saveError = 'Create another shelf before moving this book.',
      );
      return;
    }
    final destination = await _runCovered<Shelf>(() {
      return showModalBottomSheet<Shelf>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: ReaduoColors.paper,
        builder: (_) => _ShelfChoiceSheet(
          shelves: _eligibleShelves,
          selectedShelfId: _selectedShelf?.id == duplicate.shelfId
              ? null
              : _selectedShelf?.id,
          excludeShelfId: duplicate.shelfId,
        ),
      );
    });
    if (!mounted || destination == null) return;
    Shelf? current;
    for (final shelf in _shelves) {
      if (shelf.id == destination.id && shelf.id != duplicate.shelfId) {
        current = shelf;
      }
    }
    if (current == null) {
      setState(() => _saveError = 'That shelf is no longer available.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.bookRepository.moveBook(
        ownerId: widget.ownerId,
        sourceShelfId: duplicate.shelfId,
        destinationShelfId: current.id,
        bookId: duplicate.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Book moved to ${current.name}.')));
      setState(() => _saving = false);
      _resetBookDraft(nextStage: _stageBeforeLookup);
    } on BookFailure catch (error) {
      if (mounted) setState(() => _saveError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = 'Could not move this book. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _shelfName(String shelfId) {
    for (final shelf in _shelves) {
      if (shelf.id == shelfId) return shelf.name;
    }
    return null;
  }

  void _done() {
    final shelf = _lastSavedShelf;
    Navigator.of(context).pop(shelf == null ? null : IsbnScanResult(shelf));
  }

  Future<void> _viewExisting() async {
    final book = _duplicateBook;
    final callback = widget.onViewExisting;
    if (book == null || callback == null || _saving) return;
    await _runCovered<void>(() async {
      await callback(book);
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shelf = _selectedShelf;
    if (!_shelvesLoaded && shelf == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (shelf == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose a shelf')),
        body: SafeArea(
          child: _DestinationPicker(
            shelves: _shelves,
            message: _shelfError,
            creatingShelf: _creatingShelf,
            canCreateShelf: widget.onCreateShelf != null,
            onSelected: (selected) => setState(() {
              _selectedShelf = selected;
              _shelfError = null;
            }),
            onCreateShelf: _createShelf,
            onRetry: _subscribeShelves,
          ),
        ),
      );
    }
    final darkSurface = switch (_stage) {
      _ScanStage.scanning ||
      _ScanStage.lookingUp ||
      _ScanStage.confirmation ||
      _ScanStage.duplicate => true,
      _ => false,
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkSurface
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.black,
              systemNavigationBarIconBrightness: Brightness.light,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.black,
              systemNavigationBarIconBrightness: Brightness.light,
            ),
      child: PopScope(
        canPop: !_saving,
        child: Scaffold(
          backgroundColor: darkSurface
              ? ReaduoColors.ink
              : ReaduoColors.background,
          appBar: darkSurface
              ? null
              : AppBar(
                  leading: BackButton(
                    key: const Key('close-scanner'),
                    onPressed: _saving ? null : _done,
                  ),
                  title: const Text('Enter ISBN'),
                ),
          body: SafeArea(
            child: switch (_stage) {
              _ScanStage.scanning => _buildScanner(shelf),
              _ScanStage.manualIsbn => _ManualIsbnView(
                savedMessage: _savedMessage,
                controller: _manualIsbnController,
                message: _validationMessage,
                onChanged: () => setState(() => _validationMessage = null),
                onLookup: () => _lookup(
                  _manualIsbnController.text,
                  origin: _ScanStage.manualIsbn,
                ),
                onSearchCatalogue: widget.onSearchCatalogue == null
                    ? null
                    : _openCatalogue,
              ),
              _ScanStage.lookingUp => _LookupProgress(
                isbn: _activeIsbn!,
                onCancel: _cancelLookup,
                onClose: _saving ? null : _done,
              ),
              _ScanStage.confirmation => _buildConfirmation(shelf),
              _ScanStage.duplicate => _DuplicateView(
                book: _duplicateBook,
                shelfName: _duplicateBook == null
                    ? null
                    : _shelfName(_duplicateBook!.shelfId),
                fallbackMessage: _duplicateFallbackMessage,
                message: _saveError,
                busy: _saving || _childFlowActive,
                onClose: _saving ? null : _done,
                onView: _duplicateBook == null || widget.onViewExisting == null
                    ? null
                    : _viewExisting,
                onMove: _moveDuplicate,
                onScanAgain: () =>
                    _resetBookDraft(nextStage: _stageBeforeLookup),
              ),
              _ScanStage.failure => _LookupFailureView(
                message: _lookupError ?? 'Book lookup failed. Please retry.',
                onRetry: () =>
                    _lookup(_activeIsbn!, origin: _stageBeforeLookup),
                onScanAgain: () =>
                    _resetBookDraft(nextStage: _stageBeforeLookup),
                onManualAdd: widget.onOpenManualAdd == null
                    ? null
                    : _openManualAdd,
                onSearchCatalogue: widget.onSearchCatalogue == null
                    ? null
                    : _openCatalogue,
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildScanner(Shelf shelf) {
    final generation = _detectionGeneration;
    final scanner = _childFlowActive
        ? const _PausedCamera()
        : widget.scannerBuilder?.call(
                context,
                (value) => _handleDetection(value, generation),
              ) ??
              CameraIsbnScanner(
                key: ValueKey(_scannerGeneration),
                onCode: (value) => _handleDetection(value, generation),
              );
    return _CameraChrome(
      title: 'Scan a book',
      onClose: _saving ? null : _done,
      camera: scanner,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DarkShelfSelector(
            shelf: shelf,
            onTap: _saving ? null : _chooseShelf,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('scanner-enter-isbn'),
                  onPressed: _saving
                      ? null
                      : () => setState(() => _stage = _ScanStage.manualIsbn),
                  child: const Text('Enter ISBN'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('scanner-search-catalogue'),
                  onPressed: widget.onSearchCatalogue == null || _saving
                      ? null
                      : _openCatalogue,
                  child: const Text('Search'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              _savedMessage ??
                  'Scan, confirm each book, and keep this shelf for the batch.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD6DDEB), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmation(Shelf shelf) {
    final result = _result!;
    final incomplete =
        result.title.trim().isEmpty || result.author.trim().isEmpty;
    return _ScannerSheetPage(
      onClose: _saving ? null : _done,
      matched: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FoundBadge(),
          const SizedBox(height: 12),
          _BookSummary(
            title: _titleController.text,
            author: _authorController.text,
            isbn: result.isbn,
            coverUrl: result.coverUrl,
          ),
          if (incomplete) ...[
            const SizedBox(height: 14),
            Text(
              'Complete missing details',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('lookup-title-field'),
              controller: _titleController,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Title',
                errorText: _titleError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('lookup-author-field'),
              controller: _authorController,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Author',
                errorText: _authorError,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const Divider(height: 24),
          Text('Add to shelf', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 7),
          _ShelfSelector(shelf: shelf, onTap: _saving ? null : _chooseShelf),
          ExpansionTile(
            key: const Key('scanner-book-details'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              'Book details · ${_status.label}',
              style: const TextStyle(fontSize: 12, color: ReaduoColors.muted),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('scanner-wrong-book'),
                  onPressed: _saving || widget.onSearchCatalogue == null
                      ? null
                      : _openCatalogue,
                  child: const Text('Not this book?'),
                ),
              ),
              if (widget.onCreateShelf != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('scanner-create-shelf'),
                    onPressed: _saving || _creatingShelf ? null : _createShelf,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      _creatingShelf ? 'Creating shelf…' : 'Create a new shelf',
                    ),
                  ),
                ),
              SwitchListTile.adaptive(
                key: const Key('lookup-owned-switch'),
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
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                key: const Key('lookup-status-control'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in ReadingStatus.values)
                    _StatusPill(
                      key: ValueKey('lookup-status-${status.name}'),
                      label: status.label,
                      selected: _status == status,
                      onTap: _saving
                          ? null
                          : () => setState(() => _status = status),
                    ),
                ],
              ),
            ],
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 12),
            Text(
              _saveError!,
              key: const Key('lookup-save-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 4),
          FilledButton(
            key: const Key('lookup-save-another-button'),
            onPressed: _saving ? null : () => _save(scanAnother: true),
            child: Text(
              _saving
                  ? 'Adding...'
                  : _stageBeforeLookup == _ScanStage.manualIsbn
                  ? 'Add & Enter Another'
                  : 'Add & Scan Next',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('lookup-save-button'),
            onPressed: _saving ? null : () => _save(scanAnother: false),
            child: _saving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add & Finish'),
          ),
          TextButton(
            key: const Key('scanner-confirmation-scan-again'),
            onPressed: _saving
                ? null
                : () => _resetBookDraft(nextStage: _stageBeforeLookup),
            child: Text(
              _stageBeforeLookup == _ScanStage.manualIsbn
                  ? 'Enter Another ISBN'
                  : 'Scan Again',
            ),
          ),
          const Divider(height: 1),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => _resetBookDraft(nextStage: _ScanStage.manualIsbn),
                child: const Text('Enter ISBN'),
              ),
              TextButton(
                onPressed: _saving || widget.onSearchCatalogue == null
                    ? null
                    : _openCatalogue,
                child: const Text('Search books'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualIsbnView extends StatelessWidget {
  const _ManualIsbnView({
    required this.controller,
    required this.message,
    required this.onChanged,
    required this.onLookup,
    required this.onSearchCatalogue,
    this.savedMessage,
  });
  final TextEditingController controller;
  final String? message;
  final String? savedMessage;
  final VoidCallback onChanged;
  final VoidCallback onLookup;
  final VoidCallback? onSearchCatalogue;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      ReaduoSpacing.screenHorizontal,
      24,
      ReaduoSpacing.screenHorizontal,
      32,
    ),
    children: [
      if (savedMessage != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(liveRegion: true, child: Text(savedMessage!)),
        ),
      Text(
        'Enter ISBN',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: ReaduoColors.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const Key('scan-manual-isbn-field'),
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: 'ISBN',
          hintText: '978…',
          helperText: 'Find the 10- or 13-digit number near the barcode.',
          errorText: message,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => onChanged(),
        onSubmitted: (_) => onLookup(),
      ),
      const SizedBox(height: 18),
      FilledButton(
        key: const Key('lookup-isbn-button'),
        onPressed: onLookup,
        child: const Text('Find book'),
      ),
      if (onSearchCatalogue != null)
        TextButton(
          key: const Key('manual-isbn-search-catalogue'),
          onPressed: onSearchCatalogue,
          child: const Text('Search by title instead'),
        ),
    ],
  );
}

class _LookupProgress extends StatelessWidget {
  const _LookupProgress({
    required this.isbn,
    required this.onCancel,
    required this.onClose,
  });
  final String isbn;
  final VoidCallback onCancel;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => _ScannerSheetPage(
    onClose: onClose,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ReaduoColors.paper,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ReaduoColors.line),
          ),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 76,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFE5EAF2),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Finding your book…',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('ISBN $isbn'),
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(
                      key: Key('isbn-lookup-progress'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          key: const Key('cancel-isbn-lookup'),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class _FoundBadge extends StatelessWidget {
  const _FoundBadge();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: Color(0xFFE8F7ED),
        child: Icon(Icons.check_rounded, size: 20, color: Color(0xFF24733C)),
      ),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          'Book found',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: ReaduoColors.ink,
          ),
        ),
      ),
    ],
  );
}

class _BookSummary extends StatelessWidget {
  const _BookSummary({
    required this.title,
    required this.author,
    required this.isbn,
    required this.coverUrl,
  });
  final String title;
  final String author;
  final String isbn;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _BookCover(title: title, author: author, coverUrl: coverUrl),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.trim().isEmpty ? 'Title needed' : title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: ReaduoColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(author.trim().isEmpty ? 'Author needed' : author),
            const SizedBox(height: 7),
            Text('ISBN $isbn', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.title,
    required this.author,
    required this.coverUrl,
  });
  final String title;
  final String author;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final generated = Container(
      width: 76,
      height: 112,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF365BDB), Color(0xFF203A84)],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title.trim().isEmpty ? 'Untitled' : title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            author.trim().isEmpty ? 'Author' : author,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFDCE4FF),
              fontSize: 8,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
    if (coverUrl == null) return generated;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image(
        image: ReaduoImageCache.image(coverUrl!),
        key: const Key('lookup-cover'),
        width: 76,
        height: 112,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => generated,
      ),
    );
  }
}

class _ShelfSelector extends StatelessWidget {
  const _ShelfSelector({required this.shelf, required this.onTap});
  final Shelf shelf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton(
          key: const Key('scanner-shelf-selector'),
          onPressed: onTap,
          child: Row(
            children: [
              const Icon(Icons.shelves),
              const SizedBox(width: 10),
              Expanded(child: Text(shelf.name)),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        label:
            'Shelf visibility: ${shelf.visibility.label}. Inherited from the selected shelf.',
        child: Chip(
          key: const Key('scanner-shelf-visibility'),
          avatar: Icon(
            switch (shelf.visibility) {
              ShelfVisibility.private => Icons.lock_outline,
              ShelfVisibility.friends => Icons.people_outline,
              ShelfVisibility.public => Icons.public,
            },
            size: 16,
            color: ReaduoColors.accent,
          ),
          label: Text(
            shelf.visibility.label,
            style: const TextStyle(fontSize: 11, color: ReaduoColors.accent),
          ),
          backgroundColor: ReaduoColors.accentTint,
          side: BorderSide.none,
          shape: const StadiumBorder(),
        ),
      ),
    ],
  );
}

class _DarkShelfSelector extends StatelessWidget {
  const _DarkShelfSelector({required this.shelf, required this.onTap});
  final Shelf shelf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: ReaduoColors.ink,
    borderRadius: BorderRadius.circular(ReaduoRadii.button),
    child: InkWell(
      key: const Key('scanner-shelf-selector'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(ReaduoRadii.button),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.shelves, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Adding to “${shelf.name}”',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

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
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? ReaduoColors.accent : ReaduoColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}

class _LookupFailureView extends StatelessWidget {
  const _LookupFailureView({
    required this.message,
    required this.onRetry,
    required this.onScanAgain,
    required this.onManualAdd,
    required this.onSearchCatalogue,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onScanAgain;
  final VoidCallback? onManualAdd;
  final VoidCallback? onSearchCatalogue;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      ReaduoSpacing.screenHorizontal,
      28,
      ReaduoSpacing.screenHorizontal,
      32,
    ),
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EmptyMark(icon: Icons.manage_search_rounded),
          const SizedBox(height: 14),
          Text(
            'Book not found',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            key: const Key('isbn-lookup-error'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onRetry, child: const Text('Retry lookup')),
          if (onSearchCatalogue != null)
            OutlinedButton(
              key: const Key('lookup-failure-search-catalogue'),
              onPressed: onSearchCatalogue,
              child: const Text('Search catalogue'),
            ),
          if (onManualAdd != null)
            OutlinedButton(
              key: const Key('lookup-failure-manual-add'),
              onPressed: onManualAdd,
              child: const Text('Add book manually'),
            ),
          TextButton(
            onPressed: onScanAgain,
            child: const Text('Check or scan another ISBN'),
          ),
        ],
      ),
    ],
  );
}

class _DuplicateView extends StatelessWidget {
  const _DuplicateView({
    required this.book,
    required this.shelfName,
    required this.fallbackMessage,
    required this.message,
    required this.busy,
    required this.onClose,
    required this.onView,
    required this.onMove,
    required this.onScanAgain,
  });
  final LibraryBook? book;
  final String? shelfName;
  final String? fallbackMessage;
  final String? message;
  final bool busy;
  final VoidCallback? onClose;
  final VoidCallback? onView;
  final VoidCallback onMove;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) => _ScannerSheetPage(
    onClose: onClose,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Already in your library',
          key: const Key('scanner-duplicate-title'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: ReaduoColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        if (book != null)
          _BookSummary(
            title: book!.title,
            author: book!.author,
            isbn: book!.isbn ?? '',
            coverUrl: book!.coverUrl,
          )
        else
          Text(fallbackMessage ?? 'This ISBN is already saved.'),
        const SizedBox(height: 12),
        if (book != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ReaduoColors.accentTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${shelfName ?? 'Another shelf'} · ${book!.readingStatus.label} · ${book!.isOwned ? 'Owned' : 'Not owned'}\nReaduo kept this entry unchanged.',
              key: const Key('scanner-duplicate-details'),
            ),
          ),
        if (message != null) ...[
          const SizedBox(height: 10),
          Text(
            message!,
            key: const Key('scanner-duplicate-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const Key('scanner-view-existing'),
          onPressed: busy ? null : onView,
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('View existing book'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('scanner-move-existing'),
          onPressed: busy || book == null ? null : onMove,
          child: Text(busy ? 'Moving…' : 'Move to another shelf'),
        ),
        TextButton(
          key: const Key('scanner-scan-another-duplicate'),
          onPressed: busy ? null : onScanAgain,
          child: const Text('Scan another book'),
        ),
      ],
    ),
  );
}

class _EmptyMark extends StatelessWidget {
  const _EmptyMark({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.center,
    child: Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: ReaduoColors.accentTint,
        borderRadius: BorderRadius.circular(23),
      ),
      child: Icon(icon, color: ReaduoColors.accent, size: 34),
    ),
  );
}
