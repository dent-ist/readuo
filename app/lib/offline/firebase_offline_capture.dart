import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../library/book.dart';
import '../library/shelf.dart';
import 'offline_library_controller.dart';

class FirebaseOfflineCapture {
  FirebaseOfflineCapture(this.firestore, this.controller);
  final FirebaseFirestore firestore;
  final OfflineLibraryController controller;
  StreamSubscription? _shelves;
  StreamSubscription? _books;
  List<LibraryBook>? _lastBooks;
  bool _shelvesReady = false;
  int _generation = 0;

  void start(String uid) {
    stop();
    final generation = _generation;
    _shelves = firestore
        .collection('shelves')
        .where('ownerId', isEqualTo: uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) async {
          if (generation != _generation ||
              snapshot.metadata.isFromCache ||
              snapshot.metadata.hasPendingWrites)
            return;
          try {
            await controller.captureShelves(
              uid,
              snapshot.docs
                  .map((doc) => Shelf.fromFirestore(doc.id, doc.data()))
                  .toList(),
              serverConfirmed: true,
              hasPendingWrites: false,
              complete: true,
            );
            if (generation != _generation) return;
            _shelvesReady = true;
            final books = _lastBooks;
            if (books != null)
              await controller.captureBooks(
                uid,
                books,
                serverConfirmed: true,
                hasPendingWrites: false,
                complete: true,
              );
          } catch (_) {}
        }, onError: (Object _) {});
    _books = firestore
        .collectionGroup('books')
        .where('ownerId', isEqualTo: uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) async {
          if (generation != _generation ||
              snapshot.metadata.isFromCache ||
              snapshot.metadata.hasPendingWrites)
            return;
          _lastBooks = snapshot.docs
              .where(
                (doc) => doc.reference.parent.parent?.parent.id == 'shelves',
              )
              .map(
                (doc) => LibraryBook.fromFirestore(
                  doc.id,
                  doc.reference.parent.parent!.id,
                  doc.data(),
                ),
              )
              .toList();
          if (!_shelvesReady) return;
          try {
            await controller.captureBooks(
              uid,
              _lastBooks!,
              serverConfirmed: true,
              hasPendingWrites: false,
              complete: true,
            );
          } catch (_) {}
        }, onError: (Object _) {});
  }

  void stop() {
    ++_generation;
    unawaited(_shelves?.cancel());
    unawaited(_books?.cancel());
    _shelves = null;
    _books = null;
    _lastBooks = null;
    _shelvesReady = false;
  }
}
