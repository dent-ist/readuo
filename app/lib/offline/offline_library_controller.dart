import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../library/book.dart';
import '../library/shelf.dart';
import 'offline_library_cache.dart';

enum OfflineConnection { checking, online, offline, unavailable, blocked }

class OfflineActionException implements Exception {
  const OfflineActionException();
  @override
  String toString() => 'Connect to make changes.';
}

abstract interface class OfflineServerProbe {
  Future<void> check(String uid);
}

class FirestoreOfflineServerProbe implements OfflineServerProbe {
  FirestoreOfflineServerProbe(this.firestore);
  final FirebaseFirestore firestore;
  @override
  Future<void> check(String uid) async {
    final active = await firestore
        .collection('activeAccounts')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    final deleting = await firestore
        .collection('accountDeletions')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!active.exists || deleting.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
  }
}

class OfflineLibraryController extends ChangeNotifier {
  OfflineLibraryController({
    required this.cache,
    required this.probe,
    this.probeTimeout = const Duration(seconds: 4),
    this.probeInterval = const Duration(seconds: 15),
    this.retryDelay = const Duration(seconds: 2),
    this.reconnectNoticeDelay = const Duration(seconds: 5),
    this.offlineDelay = const Duration(seconds: 30),
    this.networkRefresh,
    Stream<bool>? networkAvailable,
  }) {
    _network = networkAvailable?.listen(
      networkChanged,
      onError: (Object _) {
        unawaited(checkConnection());
      },
    );
  }

  final OfflineLibraryCache cache;
  final OfflineServerProbe probe;
  final Duration probeTimeout;
  final Duration probeInterval;
  final Duration retryDelay;
  final Duration reconnectNoticeDelay;
  final Duration offlineDelay;
  final Future<bool?> Function()? networkRefresh;
  StreamSubscription<bool>? _network;
  Timer? _timer;
  Timer? _retry;
  Timer? _disconnect;
  Timer? _reconnectNotice;
  bool showReconnectNotice = false;
  bool _foreground = true;
  Future<void> _storageWork = Future.value();
  Future<OfflineConnection>? _checking;
  String? _uid;
  int _session = 0;
  int _networkGeneration = 0;
  bool _networkAvailable = true;
  bool _disposed = false;
  OfflineConnection connection = OfflineConnection.checking;
  OfflineLibrarySnapshot? snapshot;
  String? cacheError;
  String? get userId => _uid;
  bool get canShowOnline =>
      _uid != null && connection == OfflineConnection.online;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _storageWork.then<void>((_) => operation());
    _storageWork = result.catchError((Object _) {});
    return result;
  }

  Future<void> selectUser(String uid) async {
    if (uid.isEmpty) throw ArgumentError.value(uid, 'uid');
    final session = ++_session;
    _uid = uid;
    snapshot = OfflineLibrarySnapshot.empty(uid);
    cacheError = null;
    connection = OfflineConnection.checking;
    _checking = null;
    _timer?.cancel();
    _retry?.cancel();
    _resetReconnect();
    _notify();
    await _serialize(() async {
      if (_disposed || session != _session) return;
      try {
        await cache.clearExcept(uid);
        final loaded = await cache.load(uid);
        if (session == _session && !_disposed) snapshot = loaded;
      } catch (_) {
        if (session == _session && !_disposed)
          cacheError = 'Saved library is unavailable on this device.';
      }
    });
    if (_disposed || session != _session) return;
    _notify();
    _startTimer();
    await checkConnection();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_foreground && !_disposed && _uid != null) {
      _timer = Timer.periodic(
        probeInterval,
        (_) => unawaited(checkConnection()),
      );
    }
  }

  void suspend() {
    _foreground = false;
    ++_networkGeneration;
    _checking = null;
    _timer?.cancel();
    _retry?.cancel();
    _resetReconnect();
  }

  Future<void> resume() async {
    if (_disposed) return;
    _foreground = true;
    if (_uid == null) return;
    final session = _session;
    final generation = ++_networkGeneration;
    _checking = null;
    _retry?.cancel();
    _resetReconnect();
    _startTimer();
    try {
      final available = await networkRefresh?.call().timeout(probeTimeout);
      if (_disposed || session != _session || generation != _networkGeneration)
        return;
      if (available != null) _networkAvailable = available;
    } catch (_) {
      if (_disposed || session != _session || generation != _networkGeneration)
        return;
    }
    if (!_networkAvailable) _scheduleDisconnect();
    await checkConnection();
  }

  Future<void> clearSession() {
    ++_session;
    _uid = null;
    snapshot = null;
    cacheError = null;
    connection = OfflineConnection.blocked;
    _timer?.cancel();
    _retry?.cancel();
    _resetReconnect();
    _checking = null;
    _notify();
    return _serialize(() => cache.clearExcept(null));
  }

  void networkChanged(bool available) {
    if (_disposed || _networkAvailable == available) return;
    _networkAvailable = available;
    ++_networkGeneration;
    _checking = null;
    _retry?.cancel();
    if (_uid == null || !_foreground) return;
    if (available) {
      unawaited(checkConnection());
    } else {
      _scheduleDisconnect();
      unawaited(checkConnection());
    }
  }

  void _scheduleDisconnect() {
    if (_disconnect?.isActive == true) return;
    if (canShowOnline) {
      _reconnectNotice = Timer(reconnectNoticeDelay, () {
        if (!_disposed && _foreground && canShowOnline) {
          showReconnectNotice = true;
          _notify();
        }
      });
    }
    _disconnect = Timer(
      canShowOnline ? offlineDelay : reconnectNoticeDelay,
      () {
        if (!_disposed && _foreground && _uid != null) {
          connection = _networkAvailable
              ? OfflineConnection.unavailable
              : OfflineConnection.offline;
          showReconnectNotice = false;
          _notify();
          unawaited(checkConnection());
        }
      },
    );
  }

  void _resetReconnect() {
    _disconnect?.cancel();
    _reconnectNotice?.cancel();
    showReconnectNotice = false;
  }

  Future<OfflineConnection> checkConnection() {
    if (_disposed || _uid == null)
      return Future.value(OfflineConnection.blocked);
    if (!_foreground) return Future.value(OfflineConnection.unavailable);
    final session = _session;
    final generation = _networkGeneration;
    final uid = _uid!;
    return _checking ??= Future.microtask(
      () => _probe(session, generation, uid),
    );
  }

  Future<OfflineConnection> _probe(
    int session,
    int networkGeneration,
    String uid,
  ) async {
    if (_disposed ||
        session != _session ||
        networkGeneration != _networkGeneration ||
        !_foreground)
      return OfflineConnection.blocked;
    var result = OfflineConnection.online;
    try {
      await probe.check(uid).timeout(probeTimeout);
    } on FirebaseException catch (error) {
      result = {'permission-denied', 'unauthenticated'}.contains(error.code)
          ? OfflineConnection.blocked
          : OfflineConnection.unavailable;
    } on TimeoutException {
      result = OfflineConnection.unavailable;
    } catch (_) {
      result = OfflineConnection.unavailable;
    }
    if (!_disposed &&
        session == _session &&
        networkGeneration == _networkGeneration) {
      if (result == OfflineConnection.online) {
        _networkAvailable = true;
        _resetReconnect();
        _retry?.cancel();
        connection = result;
      } else if (result == OfflineConnection.unavailable) {
        if (!_networkAvailable) result = OfflineConnection.offline;
        if (connection != OfflineConnection.online) {
          connection = result;
        } else {
          _scheduleDisconnect();
        }
        _retry?.cancel();
        _retry = Timer(retryDelay, () => unawaited(checkConnection()));
      } else {
        _resetReconnect();
        connection = result;
      }
      if (result == OfflineConnection.blocked) {
        try {
          await _serialize(() async {
            if (!_disposed &&
                session == _session &&
                networkGeneration == _networkGeneration)
              await cache.clearExcept(null);
          });
        } catch (_) {
          if (!_disposed &&
              session == _session &&
              networkGeneration == _networkGeneration) {
            cacheError =
                'Private saved data could not be cleared. Retry before continuing.';
          }
        }
        if (session != _session ||
            _disposed ||
            networkGeneration != _networkGeneration)
          return OfflineConnection.blocked;
        snapshot = OfflineLibrarySnapshot.empty(uid);
      }
      _checking = null;
      _notify();
    }
    return _disposed ||
            session != _session ||
            networkGeneration != _networkGeneration
        ? OfflineConnection.blocked
        : result;
  }

  Future<void> requireOnline() async {
    final session = _session;
    if (await checkConnection() != OfflineConnection.online ||
        session != _session ||
        !canShowOnline) {
      throw const OfflineActionException();
    }
  }

  Future<void> captureShelves(
    String uid,
    List<Shelf> shelves, {
    required bool serverConfirmed,
    required bool hasPendingWrites,
    required bool complete,
  }) => _capture(uid, serverConfirmed, hasPendingWrites, (current) {
    if (shelves.any((shelf) => shelf.ownerId != uid))
      throw ArgumentError('Only own shelves can be cached.');
    final merged = {
      if (!complete)
        for (final shelf in current.shelves) shelf.id: shelf,
      for (final shelf in shelves)
        if (shelf.mutationOperationId == null) shelf.id: shelf,
    };
    for (final shelf in shelves) {
      if (shelf.mutationOperationId != null) merged.remove(shelf.id);
    }
    return OfflineLibrarySnapshot(
      userId: uid,
      shelves: merged.values,
      books: current.books.where((book) => merged.containsKey(book.shelfId)),
      savedAt: DateTime.now(),
    );
  });

  Future<void> captureBooks(
    String uid,
    List<LibraryBook> books, {
    required bool serverConfirmed,
    required bool hasPendingWrites,
    required bool complete,
    String? shelfId,
  }) => _capture(uid, serverConfirmed, hasPendingWrites, (current) {
    if (books.any(
      (book) =>
          book.ownerId != uid || (shelfId != null && book.shelfId != shelfId),
    )) {
      throw ArgumentError(
        'Only own books in the declared scope can be cached.',
      );
    }
    final shelves = current.shelves.map((shelf) => shelf.id).toSet();
    final merged = {
      for (final book in current.books)
        if (!complete || (shelfId != null && book.shelfId != shelfId))
          '${book.shelfId}/${book.id}': book,
    };
    for (final book in books) {
      merged.removeWhere(
        (_, saved) => saved.id == book.id && saved.shelfId != book.shelfId,
      );
      if (shelves.contains(book.shelfId))
        merged['${book.shelfId}/${book.id}'] = book;
    }
    return OfflineLibrarySnapshot(
      userId: uid,
      shelves: current.shelves,
      books: merged.values,
      savedAt: DateTime.now(),
    );
  });

  Future<void> _capture(
    String uid,
    bool confirmed,
    bool pending,
    OfflineLibrarySnapshot Function(OfflineLibrarySnapshot) update,
  ) {
    final session = _session;
    if (!confirmed || pending || uid != _uid || !canShowOnline)
      return Future.value();
    return _serialize(() async {
      if (_disposed || session != _session || uid != _uid || !canShowOnline)
        return;
      final candidate = update(snapshot!);
      final sanitized = OfflineLibrarySnapshot.decode(uid, candidate.encode());
      try {
        await cache.save(sanitized);
        if (!_disposed && session == _session) {
          snapshot = sanitized;
          cacheError = null;
          _notify();
        }
      } catch (_) {
        if (!_disposed && session == _session) {
          cacheError = 'Couldn’t save a local library copy.';
          _notify();
        }
        rethrow;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    ++_session;
    _timer?.cancel();
    _retry?.cancel();
    _resetReconnect();
    unawaited(_network?.cancel());
    super.dispose();
  }
}
