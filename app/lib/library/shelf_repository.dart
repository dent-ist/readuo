import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../circle/review_repository.dart';
import 'shelf.dart';

class ShelfFailure implements Exception {
  const ShelfFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ShelfRepository {
  Stream<List<Shelf>> watchShelves(String ownerId);

  Stream<List<ShelfMutationOperation>> watchShelfOperations(String ownerId);

  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  });

  Stream<Shelf?> watchSharedShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  });

  Future<Shelf> createShelf({
    required String ownerId,
    required CreateShelfInput input,
  });

  Future<void> updateShelf({
    required String ownerId,
    required String shelfId,
    required UpdateShelfInput input,
  });

  Future<void> moveAllBooksAndDeleteShelf({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
  });

  Future<void> deleteShelfAndBooks({
    required String ownerId,
    required String shelfId,
  });

  Future<void> resumeShelfOperation({
    required String ownerId,
    required String sourceShelfId,
  });
}

class PublicShelfReference {
  const PublicShelfReference({required this.ownerId, required this.shelfId});

  final String ownerId;
  final String shelfId;
}

class PublicShelfReferencePage {
  const PublicShelfReferencePage({
    required this.references,
    required this.sourceCount,
    required this.hasMore,
  });

  final List<PublicShelfReference> references;
  final int sourceCount;
  final bool hasMore;
}

abstract interface class PublicShelfQuerySource {
  Stream<PublicShelfReferencePage> watchPublicShelfReferencePage({
    required String viewerId,
    required int limit,
  });

  Stream<Shelf?> watchPublicShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  });

  Stream<List<Shelf>> watchPublicShelvesByOwner({
    required String viewerId,
    required String ownerId,
  });
}

extension PublicShelfQueries on ShelfRepository {
  Stream<PublicShelfReferencePage> watchPublicShelfReferencePage({
    required String viewerId,
    required int limit,
  }) {
    final repository = this;
    if (repository is PublicShelfQuerySource) {
      return (repository as PublicShelfQuerySource)
          .watchPublicShelfReferencePage(viewerId: viewerId, limit: limit);
    }
    return Stream.value(
      const PublicShelfReferencePage(
        references: [],
        sourceCount: 0,
        hasMore: false,
      ),
    );
  }

  Stream<Shelf?> watchPublicShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) {
    final repository = this;
    if (repository is PublicShelfQuerySource) {
      return (repository as PublicShelfQuerySource).watchPublicShelf(
        viewerId: viewerId,
        ownerId: ownerId,
        shelfId: shelfId,
      );
    }
    return watchSharedShelf(
      viewerId: viewerId,
      ownerId: ownerId,
      shelfId: shelfId,
    ).map(
      (shelf) => shelf?.visibility == ShelfVisibility.public ? shelf : null,
    );
  }

  Stream<List<Shelf>> watchPublicShelvesByOwner({
    required String viewerId,
    required String ownerId,
  }) {
    final repository = this;
    if (repository is PublicShelfQuerySource) {
      return (repository as PublicShelfQuerySource).watchPublicShelvesByOwner(
        viewerId: viewerId,
        ownerId: ownerId,
      );
    }
    return watchSharedShelves(viewerId: viewerId, ownerId: ownerId).map(
      (shelves) => shelves
          .where((shelf) => shelf.visibility == ShelfVisibility.public)
          .toList(),
    );
  }
}

class FirebaseShelfRepository
    implements ShelfRepository, PublicShelfQuerySource {
  FirebaseShelfRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final Map<String, List<Shelf>> _pendingDirectorySyncs = {};
  final Set<String> _activeDirectorySyncs = {};

  @override
  Stream<List<ShelfMutationOperation>> watchShelfOperations(
    String ownerId,
  ) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('users')
              .doc(ownerId)
              .collection('shelfOperations')
              .where('status', isEqualTo: 'running')
              .snapshots()) {
        yield snapshot.docs
            .map(
              (document) => ShelfMutationOperation.fromFirestore(
                document.id,
                document.data(),
              ),
            )
            .where((operation) => operation.ownerId == ownerId)
            .toList();
      }
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .where('ownerId', isEqualTo: ownerId)
              .snapshots(includeMetadataChanges: true)) {
        final shelves =
            snapshot.docs
                .map(
                  (document) =>
                      Shelf.fromFirestore(document.id, document.data()),
                )
                .toList()
              ..sort((left, right) {
                final leftDate =
                    left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                final rightDate =
                    right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                return rightDate.compareTo(leftDate);
              });
        if (!snapshot.metadata.isFromCache) {
          _queuePublicShelfDirectorySync(ownerId, shelves);
        }
        yield shelves;
      }
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Stream<PublicShelfReferencePage> watchPublicShelfReferencePage({
    required String viewerId,
    required int limit,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('publicShelfDirectory')
              .orderBy('createdAt', descending: true)
              .limit(limit + 1)
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        final sourceDocuments = snapshot.docs.take(limit).toList();
        final references = sourceDocuments
            .map((document) {
              final ownerId = document.data()['ownerId'] as String? ?? '';
              final shelfId = document.data()['shelfId'] as String? ?? '';
              return ownerId.isNotEmpty &&
                      ownerId != viewerId &&
                      shelfId == document.id
                  ? PublicShelfReference(ownerId: ownerId, shelfId: shelfId)
                  : null;
            })
            .whereType<PublicShelfReference>()
            .toList();
        yield PublicShelfReferencePage(
          references: references,
          sourceCount: sourceDocuments.length,
          hasMore: snapshot.docs.length > limit,
        );
      }
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Stream<Shelf?> watchPublicShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .doc(shelfId)
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        final data = snapshot.data();
        if (data == null) {
          yield null;
          continue;
        }
        final shelf = Shelf.fromFirestore(snapshot.id, data);
        yield shelf.ownerId == ownerId &&
                shelf.ownerId != viewerId &&
                shelf.visibility == ShelfVisibility.public
            ? shelf
            : null;
      }
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Stream<List<Shelf>> watchPublicShelvesByOwner({
    required String viewerId,
    required String ownerId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .where('ownerId', isEqualTo: ownerId)
              .where('visibility', isEqualTo: 'public')
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        final shelves =
            snapshot.docs
                .map(
                  (document) =>
                      Shelf.fromFirestore(document.id, document.data()),
                )
                .where(
                  (shelf) =>
                      shelf.ownerId == ownerId &&
                      shelf.ownerId != viewerId &&
                      shelf.visibility == ShelfVisibility.public,
                )
                .toList()
              ..sort((left, right) => left.name.compareTo(right.name));
        yield shelves;
      }
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .where('ownerId', isEqualTo: ownerId)
              .where('visibility', whereIn: const ['friends', 'public'])
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        final shelves =
            snapshot.docs
                .map(
                  (document) =>
                      Shelf.fromFirestore(document.id, document.data()),
                )
                .where(
                  (shelf) =>
                      shelf.ownerId == ownerId &&
                      shelf.visibility != ShelfVisibility.private,
                )
                .toList()
              ..sort((left, right) => left.name.compareTo(right.name));
        yield shelves;
      }
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Stream<Shelf?> watchSharedShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .doc(shelfId)
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        final data = snapshot.data();
        if (data == null) {
          yield null;
          continue;
        }
        final shelf = Shelf.fromFirestore(snapshot.id, data);
        yield shelf.ownerId == ownerId &&
                shelf.visibility != ShelfVisibility.private
            ? shelf
            : null;
      }
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<Shelf> createShelf({
    required String ownerId,
    required CreateShelfInput input,
  }) async {
    final validationMessage = input.validationMessage;
    if (validationMessage != null) throw ShelfFailure(validationMessage);
    try {
      final reference = _firestore.collection('shelves').doc();
      await _firestore.runTransaction((batch) async {
        await batch.get(_firestore.collection('users').doc(ownerId));
        batch.set(reference, {
          'ownerId': ownerId,
          'name': input.name.trim(),
          'description': input.description.trim().isEmpty
              ? null
              : input.description.trim(),
          'visibility': input.visibility.storageValue,
          'autoShareActivity': input.autoShareActivity,
          'bookCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (input.visibility == ShelfVisibility.public) {
          batch.set(_publicDirectoryReference(reference.id), {
            'ownerId': ownerId,
            'shelfId': reference.id,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
      return Shelf(
        id: reference.id,
        ownerId: ownerId,
        name: input.name.trim(),
        description: input.description.trim().isEmpty
            ? null
            : input.description.trim(),
        visibility: input.visibility,
        autoShareActivity: input.autoShareActivity,
        bookCount: 0,
        createdAt: null,
        updatedAt: null,
      );
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> updateShelf({
    required String ownerId,
    required String shelfId,
    required UpdateShelfInput input,
  }) async {
    final validationMessage = input.validationMessage;
    if (validationMessage != null) throw ShelfFailure(validationMessage);
    final shelfReference = _firestore.collection('shelves').doc(shelfId);
    final directoryReference = _publicDirectoryReference(shelfId);
    try {
      await _firestore.runTransaction((batch) async {
        final shelfSnapshot = await batch.get(shelfReference);
        final directorySnapshot = await batch.get(directoryReference);
        if (!shelfSnapshot.exists ||
            shelfSnapshot.data()?['ownerId'] != ownerId) {
          throw const ShelfFailure(
            'This shelf is unavailable or belongs to another account.',
          );
        }
        if (shelfSnapshot.data()?['mutationOperationId'] != null) {
          throw const ShelfFailure(
            'This shelf is already changing. Retry when that change finishes.',
          );
        }
        final shelfChanges = <String, dynamic>{
          'name': input.name.trim(),
          'description': input.description.trim().isEmpty
              ? null
              : input.description.trim(),
          'visibility': input.visibility.storageValue,
          'autoShareActivity': input.autoShareActivity,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (input.visibility != ShelfVisibility.public &&
            !directorySnapshot.exists) {
          batch.update(shelfReference, shelfChanges);
        } else {
          batch.update(shelfReference, shelfChanges);
          if (input.visibility == ShelfVisibility.public) {
            batch.set(directoryReference, {
              'ownerId': ownerId,
              'shelfId': shelfId,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            batch.delete(directoryReference);
          }
        }
      });
    } on FirebaseException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> moveAllBooksAndDeleteShelf({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
  }) async {
    if (sourceShelfId == destinationShelfId) {
      throw const ShelfFailure('Choose a different destination shelf.');
    }
    final shelves = _firestore.collection('shelves');
    final sourceReference = shelves.doc(sourceShelfId);
    final destinationReference = shelves.doc(destinationShelfId);
    final operationReference = _operationReference(ownerId, sourceShelfId);
    final sourceBooks = await _loadShelfBooksForMutation(
      sourceReference,
      action: 'move these books',
    );

    try {
      final completed = await _prepareOperation(
        ownerId: ownerId,
        mode: 'move',
        sourceReference: sourceReference,
        destinationReference: destinationReference,
        operationReference: operationReference,
        loadedSourceCount: sourceBooks.length,
      );
      if (completed) return;
      while (true) {
        final chunk = await _loadShelfBookChunk(
          sourceReference,
          action: 'move these books',
        );
        if (chunk.isEmpty) break;
        await _moveBookChunk(
          ownerId: ownerId,
          sourceReference: sourceReference,
          destinationReference: destinationReference,
          operationReference: operationReference,
          books: chunk,
        );
      }
      await _finishMoveOperation(
        ownerId: ownerId,
        sourceReference: sourceReference,
        destinationReference: destinationReference,
        operationReference: operationReference,
      );
    } on ShelfFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapMutationError(error, action: 'move these books');
    }
  }

  @override
  Future<void> deleteShelfAndBooks({
    required String ownerId,
    required String shelfId,
  }) async {
    final shelfReference = _firestore.collection('shelves').doc(shelfId);
    final operationReference = _operationReference(ownerId, shelfId);
    final sourceBooks = await _loadShelfBooksForMutation(
      shelfReference,
      action: 'remove this shelf',
    );

    try {
      final completed = await _prepareOperation(
        ownerId: ownerId,
        mode: 'remove',
        sourceReference: shelfReference,
        destinationReference: null,
        operationReference: operationReference,
        loadedSourceCount: sourceBooks.length,
      );
      if (completed) return;
      while (true) {
        final chunk = await _loadShelfBookChunk(
          shelfReference,
          action: 'remove this shelf',
        );
        if (chunk.isEmpty) break;
        await _removeBookChunk(
          ownerId: ownerId,
          sourceReference: shelfReference,
          operationReference: operationReference,
          books: chunk,
        );
      }
      await _finishRemoveOperation(
        ownerId: ownerId,
        sourceReference: shelfReference,
        operationReference: operationReference,
      );
    } on ShelfFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapMutationError(error, action: 'remove this shelf');
    }
  }

  @override
  Future<void> resumeShelfOperation({
    required String ownerId,
    required String sourceShelfId,
  }) async {
    try {
      final snapshot = await _operationReference(
        ownerId,
        sourceShelfId,
      ).get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (data == null || data['ownerId'] != ownerId) {
        throw const ShelfFailure('This shelf change is no longer available.');
      }
      if (data['status'] == 'completed') return;
      if (data['mode'] == 'move') {
        final destinationShelfId = data['destinationShelfId'] as String?;
        if (destinationShelfId == null || destinationShelfId.isEmpty) {
          throw const ShelfFailure(
            'This saved move is missing its destination. Contact support before changing either shelf.',
          );
        }
        await moveAllBooksAndDeleteShelf(
          ownerId: ownerId,
          sourceShelfId: sourceShelfId,
          destinationShelfId: destinationShelfId,
        );
        return;
      }
      if (data['mode'] == 'remove') {
        await deleteShelfAndBooks(ownerId: ownerId, shelfId: sourceShelfId);
        return;
      }
      throw const ShelfFailure('This saved shelf change cannot be resumed.');
    } on ShelfFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapMutationError(error, action: 'resume this shelf change');
    }
  }

  DocumentReference<Map<String, dynamic>> _operationReference(
    String ownerId,
    String sourceShelfId,
  ) => _firestore
      .collection('users')
      .doc(ownerId)
      .collection('shelfOperations')
      .doc(sourceShelfId);

  DocumentReference<Map<String, dynamic>> _publicDirectoryReference(
    String shelfId,
  ) => _firestore.collection('publicShelfDirectory').doc(shelfId);

  void _queuePublicShelfDirectorySync(String ownerId, List<Shelf> shelves) {
    _pendingDirectorySyncs[ownerId] = List.unmodifiable(shelves);
    if (_activeDirectorySyncs.add(ownerId)) {
      unawaited(_drainPublicShelfDirectorySync(ownerId));
    }
  }

  Future<void> _drainPublicShelfDirectorySync(String ownerId) async {
    try {
      var retryCount = 0;
      while (true) {
        final shelves = _pendingDirectorySyncs.remove(ownerId);
        if (shelves == null) break;
        try {
          await _syncPublicShelfDirectory(ownerId, shelves);
          retryCount = 0;
        } on FirebaseException catch (error, stackTrace) {
          developer.log(
            'Public shelf directory sync failed for $ownerId.',
            name: 'readuo.shelves',
            error: error,
            stackTrace: stackTrace,
          );
          if (!_pendingDirectorySyncs.containsKey(ownerId) && retryCount < 2) {
            retryCount += 1;
            await Future<void>.delayed(
              Duration(milliseconds: 250 * retryCount),
            );
            _pendingDirectorySyncs[ownerId] = shelves;
          }
        }
      }
    } finally {
      _activeDirectorySyncs.remove(ownerId);
      if (_pendingDirectorySyncs.containsKey(ownerId)) {
        _queuePublicShelfDirectorySync(
          ownerId,
          _pendingDirectorySyncs[ownerId]!,
        );
      }
    }
  }

  Future<void> _syncPublicShelfDirectory(
    String ownerId,
    List<Shelf> shelves,
  ) async {
    final existing = await _firestore
        .collection('publicShelfDirectory')
        .where('ownerId', isEqualTo: ownerId)
        .get(const GetOptions(source: Source.server));
    final candidateIds = <String>{
      ...shelves.map((shelf) => shelf.id),
      ...existing.docs.map((document) => document.id),
    };
    FirebaseException? firstFailure;
    StackTrace? firstStackTrace;
    for (final shelfId in candidateIds) {
      try {
        await _syncPublicShelfDirectoryEntry(ownerId, shelfId);
      } on FirebaseException catch (error, stackTrace) {
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstStackTrace!);
    }
  }

  Future<void> _syncPublicShelfDirectoryEntry(String ownerId, String shelfId) {
    final shelfReference = _firestore.collection('shelves').doc(shelfId);
    final directoryReference = _publicDirectoryReference(shelfId);
    return _firestore.runTransaction((transaction) async {
      final shelfSnapshot = await transaction.get(shelfReference);
      final directorySnapshot = await transaction.get(directoryReference);
      final shelfData = shelfSnapshot.data();
      final shouldBePublic =
          shelfData?['ownerId'] == ownerId &&
          shelfData?['visibility'] == 'public';
      if (shouldBePublic && !directorySnapshot.exists) {
        transaction.set(directoryReference, {
          'ownerId': ownerId,
          'shelfId': shelfId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (!shouldBePublic &&
          directorySnapshot.exists &&
          directorySnapshot.data()?['ownerId'] == ownerId) {
        transaction.delete(directoryReference);
      }
    });
  }

  Future<bool> _prepareOperation({
    required String ownerId,
    required String mode,
    required DocumentReference<Map<String, dynamic>> sourceReference,
    required DocumentReference<Map<String, dynamic>>? destinationReference,
    required DocumentReference<Map<String, dynamic>> operationReference,
    required int loadedSourceCount,
  }) {
    return _firestore.runTransaction((transaction) async {
      final operation = await transaction.get(operationReference);
      if (operation.exists) {
        final data = operation.data()!;
        if (data['ownerId'] != ownerId ||
            data['mode'] != mode ||
            data['sourceShelfId'] != sourceReference.id ||
            data['destinationShelfId'] != destinationReference?.id) {
          throw const ShelfFailure(
            'Another shelf change is already in progress. Retry that change first.',
          );
        }
        return data['status'] == 'completed';
      }

      final source = await transaction.get(sourceReference);
      final sourceData = source.data();
      _requireOwnedShelf(
        sourceData,
        ownerId: ownerId,
        missingMessage: 'The source shelf is no longer available.',
      );
      final sourceCount = _requireCurrentBookCount(
        sourceData!,
        loadedSourceCount,
      );
      if (sourceData['mutationOperationId'] != null) {
        throw const ShelfFailure(
          'Another shelf change is already in progress. Please retry.',
        );
      }

      Map<String, dynamic>? destinationData;
      int? destinationCount;
      if (destinationReference != null) {
        final destination = await transaction.get(destinationReference);
        destinationData = destination.data();
        _requireOwnedShelf(
          destinationData,
          ownerId: ownerId,
          missingMessage:
              'The destination shelf is unavailable. Choose another shelf.',
        );
        destinationCount = _requireStoredBookCount(destinationData!);
        if (destinationData['mutationOperationId'] != null) {
          throw const ShelfFailure(
            'The destination shelf is already changing. Choose another shelf or retry later.',
          );
        }
      }

      final sourceDirectory = await transaction.get(
        _publicDirectoryReference(sourceReference.id),
      );
      final destinationDirectory = destinationReference == null
          ? null
          : await transaction.get(
              _publicDirectoryReference(destinationReference.id),
            );

      transaction.set(operationReference, {
        'ownerId': ownerId,
        'sourceShelfId': sourceReference.id,
        'destinationShelfId': destinationReference?.id,
        'mode': mode,
        'status': 'running',
        'totalCount': sourceCount,
        'processedCount': 0,
        'currentBookId': null,
        'currentBookIsbn': null,
        'destinationInitialCount': destinationCount,
        'destinationVisibility': destinationData?['visibility'],
        'destinationAutoShareActivity': destinationData?['autoShareActivity'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(sourceReference, {
        'mutationOperationId': sourceReference.id,
        'visibility': ShelfVisibility.private.storageValue,
        'autoShareActivity': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (sourceDirectory.exists) {
        transaction.delete(sourceDirectory.reference);
      }
      if (destinationReference != null) {
        transaction.update(destinationReference, {
          'mutationOperationId': sourceReference.id,
          'visibility': ShelfVisibility.private.storageValue,
          'autoShareActivity': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (destinationDirectory!.exists) {
          transaction.delete(destinationDirectory.reference);
        }
      }
      return false;
    });
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadShelfBookChunk(
    DocumentReference<Map<String, dynamic>> shelfReference, {
    required String action,
  }) async {
    try {
      final snapshot = await shelfReference
          .collection('books')
          .orderBy(FieldPath.documentId)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      return snapshot.docs;
    } on FirebaseException catch (error) {
      throw _mapMutationError(error, action: action);
    }
  }

  Future<void> _moveBookChunk({
    required String ownerId,
    required DocumentReference<Map<String, dynamic>> sourceReference,
    required DocumentReference<Map<String, dynamic>> destinationReference,
    required DocumentReference<Map<String, dynamic>> operationReference,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> books,
  }) {
    return _firestore.runTransaction((transaction) async {
      final operation = await transaction.get(operationReference);
      final source = await transaction.get(sourceReference);
      final destination = await transaction.get(destinationReference);
      final operationData = operation.data();
      _requireRunningOperation(
        operationData,
        ownerId: ownerId,
        mode: 'move',
        sourceShelfId: sourceReference.id,
        destinationShelfId: destinationReference.id,
      );
      final sourceData = source.data();
      final destinationData = destination.data();
      _requireLockedShelf(sourceData, ownerId, sourceReference.id);
      _requireLockedShelf(destinationData, ownerId, sourceReference.id);
      final sourceCount = _requireStoredBookCount(sourceData!);
      final destinationCount = _requireStoredBookCount(destinationData!);
      if (sourceCount < books.length) {
        throw const ShelfFailure(
          'The shelf count changed unexpectedly. Review it and retry.',
        );
      }
      final destinationName =
          (destinationData['name'] as String?)?.trim() ?? '';
      final mutations = <_ShelfBookMutation>[];
      for (final queriedBook in books) {
        final sourceBook = await transaction.get(queriedBook.reference);
        final bookData = sourceBook.data();
        if (bookData == null ||
            bookData['ownerId'] != ownerId ||
            bookData['shelfId'] != sourceReference.id) {
          throw const ShelfFailure(
            'A book changed while this request was running. Retry to continue safely.',
          );
        }
        final destinationBookReference = destinationReference
            .collection('books')
            .doc(sourceBook.id);
        if ((await transaction.get(destinationBookReference)).exists) {
          throw const ShelfFailure(
            'The destination contains a conflicting entry. Nothing else was moved.',
          );
        }
        DocumentReference<Map<String, dynamic>>? indexReference;
        final isbn = bookData['isbn'] as String?;
        if (isbn != null) {
          indexReference = _firestore
              .collection('users')
              .doc(ownerId)
              .collection('libraryBookIsbns')
              .doc(isbn);
          final index = await transaction.get(indexReference);
          if (!index.exists ||
              index.data()?['shelfId'] != sourceReference.id ||
              index.data()?['bookId'] != sourceBook.id) {
            throw const ShelfFailure(
              'A book index changed. Retry to continue without duplication.',
            );
          }
        }
        final reviewId = circleReviewId(ownerId, sourceBook.id);
        final reviewReference = _firestore
            .collection('circleReviews')
            .doc(reviewId);
        final reviewDraftReference = _firestore
            .collection('users')
            .doc(ownerId)
            .collection('reviewDrafts')
            .doc(reviewId);
        final review = await transaction.get(reviewReference);
        final reviewDraft = await transaction.get(reviewDraftReference);
        if (review.exists &&
            !_shelfReviewSourceMatches(
              review.data()!,
              ownerId: ownerId,
              shelfId: sourceReference.id,
              bookId: sourceBook.id,
              bookData: bookData,
              reviewId: reviewId,
              isDraft: false,
            )) {
          throw const ShelfFailure(
            'A book review changed. Retry to continue without moving the wrong review.',
          );
        }
        if (reviewDraft.exists &&
            !_shelfReviewSourceMatches(
              reviewDraft.data()!,
              ownerId: ownerId,
              shelfId: sourceReference.id,
              bookId: sourceBook.id,
              bookData: bookData,
              reviewId: reviewId,
              isDraft: true,
            )) {
          throw const ShelfFailure(
            'A review draft changed. Retry to continue without moving the wrong draft.',
          );
        }
        mutations.add(
          _ShelfBookMutation(
            sourceReference: queriedBook.reference,
            destinationReference: destinationBookReference,
            data: bookData,
            indexReference: indexReference,
            activityGeneration: destinationBookReference
                .collection('activityGenerations')
                .doc()
                .id,
            reviewReference: review.exists ? reviewReference : null,
            reviewDraftReference: reviewDraft.exists
                ? reviewDraftReference
                : null,
          ),
        );
      }
      for (final mutation in mutations) {
        transaction.set(mutation.destinationReference, {
          ...mutation.data,
          'shelfId': destinationReference.id,
          'activityGeneration': mutation.activityGeneration,
        });
        transaction.delete(mutation.sourceReference);
        if (mutation.indexReference != null) {
          transaction.update(mutation.indexReference!, {
            'shelfId': destinationReference.id,
            'shelfName': destinationName,
          });
        }
        if (mutation.reviewReference != null) {
          transaction.update(mutation.reviewReference!, {
            'shelfId': destinationReference.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        if (mutation.reviewDraftReference != null) {
          transaction.update(mutation.reviewDraftReference!, {
            'shelfId': destinationReference.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      transaction.update(sourceReference, {
        'bookCount': sourceCount - mutations.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(destinationReference, {
        'bookCount': destinationCount + mutations.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(operationReference, {
        'processedCount':
            (operationData!['processedCount'] as num).toInt() +
            mutations.length,
        'currentBookId': mutations.single.sourceReference.id,
        'currentBookIsbn': mutations.single.data['isbn'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _removeBookChunk({
    required String ownerId,
    required DocumentReference<Map<String, dynamic>> sourceReference,
    required DocumentReference<Map<String, dynamic>> operationReference,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> books,
  }) {
    return _firestore.runTransaction((transaction) async {
      final operation = await transaction.get(operationReference);
      final source = await transaction.get(sourceReference);
      final operationData = operation.data();
      _requireRunningOperation(
        operationData,
        ownerId: ownerId,
        mode: 'remove',
        sourceShelfId: sourceReference.id,
        destinationShelfId: null,
      );
      final sourceData = source.data();
      _requireLockedShelf(sourceData, ownerId, sourceReference.id);
      final sourceCount = _requireStoredBookCount(sourceData!);
      if (sourceCount < books.length) {
        throw const ShelfFailure(
          'The shelf count changed unexpectedly. Review it and retry.',
        );
      }
      final removals = <_ShelfBookRemoval>[];
      for (final queriedBook in books) {
        final book = await transaction.get(queriedBook.reference);
        final bookData = book.data();
        if (bookData == null ||
            bookData['ownerId'] != ownerId ||
            bookData['shelfId'] != sourceReference.id) {
          throw const ShelfFailure(
            'A book changed while this request was running. Retry to continue safely.',
          );
        }
        DocumentReference<Map<String, dynamic>>? indexReference;
        final isbn = bookData['isbn'] as String?;
        if (isbn != null) {
          indexReference = _firestore
              .collection('users')
              .doc(ownerId)
              .collection('libraryBookIsbns')
              .doc(isbn);
          final index = await transaction.get(indexReference);
          if (!index.exists ||
              index.data()?['shelfId'] != sourceReference.id ||
              index.data()?['bookId'] != book.id) {
            throw const ShelfFailure(
              'A book index changed. Retry before removing anything else.',
            );
          }
        }
        final reviewId = circleReviewId(ownerId, book.id);
        final reviewReference = _firestore
            .collection('circleReviews')
            .doc(reviewId);
        final reviewDraftReference = _firestore
            .collection('users')
            .doc(ownerId)
            .collection('reviewDrafts')
            .doc(reviewId);
        final review = await transaction.get(reviewReference);
        final reviewDraft = await transaction.get(reviewDraftReference);
        if (review.exists &&
            !_shelfReviewSourceMatches(
              review.data()!,
              ownerId: ownerId,
              shelfId: sourceReference.id,
              bookId: book.id,
              bookData: bookData,
              reviewId: reviewId,
              isDraft: false,
            )) {
          throw const ShelfFailure(
            'A book review changed. Retry before removing anything else.',
          );
        }
        if (reviewDraft.exists &&
            !_shelfReviewSourceMatches(
              reviewDraft.data()!,
              ownerId: ownerId,
              shelfId: sourceReference.id,
              bookId: book.id,
              bookData: bookData,
              reviewId: reviewId,
              isDraft: true,
            )) {
          throw const ShelfFailure(
            'A review draft changed. Retry before removing anything else.',
          );
        }
        removals.add(
          _ShelfBookRemoval(
            bookReference: queriedBook.reference,
            indexReference: indexReference,
            isbn: isbn,
            reviewReference: review.exists ? reviewReference : null,
            reviewDraftReference: reviewDraft.exists
                ? reviewDraftReference
                : null,
          ),
        );
      }
      for (final removal in removals) {
        if (removal.indexReference != null) {
          transaction.delete(removal.indexReference!);
        }
        if (removal.reviewReference != null) {
          transaction.delete(removal.reviewReference!);
        }
        if (removal.reviewDraftReference != null) {
          transaction.delete(removal.reviewDraftReference!);
        }
        transaction.delete(removal.bookReference);
      }
      transaction.update(sourceReference, {
        'bookCount': sourceCount - removals.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(operationReference, {
        'processedCount':
            (operationData!['processedCount'] as num).toInt() + removals.length,
        'currentBookId': removals.single.bookReference.id,
        'currentBookIsbn': removals.single.isbn,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _finishMoveOperation({
    required String ownerId,
    required DocumentReference<Map<String, dynamic>> sourceReference,
    required DocumentReference<Map<String, dynamic>> destinationReference,
    required DocumentReference<Map<String, dynamic>> operationReference,
  }) {
    return _firestore.runTransaction((transaction) async {
      final operation = await transaction.get(operationReference);
      final source = await transaction.get(sourceReference);
      final destination = await transaction.get(destinationReference);
      final sourceDirectory = await transaction.get(
        _publicDirectoryReference(sourceReference.id),
      );
      final destinationDirectory = await transaction.get(
        _publicDirectoryReference(destinationReference.id),
      );
      final operationData = operation.data();
      _requireRunningOperation(
        operationData,
        ownerId: ownerId,
        mode: 'move',
        sourceShelfId: sourceReference.id,
        destinationShelfId: destinationReference.id,
      );
      final sourceData = source.data();
      final destinationData = destination.data();
      _requireLockedShelf(sourceData, ownerId, sourceReference.id);
      _requireLockedShelf(destinationData, ownerId, sourceReference.id);
      if (_requireStoredBookCount(sourceData!) != 0 ||
          (operationData!['processedCount'] as num).toInt() !=
              (operationData['totalCount'] as num).toInt()) {
        throw const ShelfFailure(
          'The move is not finished yet. Retry to continue safely.',
        );
      }
      final expectedDestinationCount =
          (operationData['destinationInitialCount'] as num).toInt() +
          (operationData['totalCount'] as num).toInt();
      if (_requireStoredBookCount(destinationData!) !=
          expectedDestinationCount) {
        throw const ShelfFailure(
          'The destination count changed unexpectedly. Retry to review it safely.',
        );
      }
      transaction.delete(sourceReference);
      if (sourceDirectory.exists) {
        transaction.delete(sourceDirectory.reference);
      }
      transaction.update(destinationReference, {
        'mutationOperationId': FieldValue.delete(),
        'visibility': operationData['destinationVisibility'],
        'autoShareActivity': operationData['destinationAutoShareActivity'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (operationData['destinationVisibility'] == 'public') {
        transaction.set(destinationDirectory.reference, {
          'ownerId': ownerId,
          'shelfId': destinationReference.id,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (destinationDirectory.exists) {
        transaction.delete(destinationDirectory.reference);
      }
      transaction.update(operationReference, {
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _finishRemoveOperation({
    required String ownerId,
    required DocumentReference<Map<String, dynamic>> sourceReference,
    required DocumentReference<Map<String, dynamic>> operationReference,
  }) {
    return _firestore.runTransaction((transaction) async {
      final operation = await transaction.get(operationReference);
      final source = await transaction.get(sourceReference);
      final sourceDirectory = await transaction.get(
        _publicDirectoryReference(sourceReference.id),
      );
      final operationData = operation.data();
      _requireRunningOperation(
        operationData,
        ownerId: ownerId,
        mode: 'remove',
        sourceShelfId: sourceReference.id,
        destinationShelfId: null,
      );
      final sourceData = source.data();
      _requireLockedShelf(sourceData, ownerId, sourceReference.id);
      if (_requireStoredBookCount(sourceData!) != 0 ||
          (operationData!['processedCount'] as num).toInt() !=
              (operationData['totalCount'] as num).toInt()) {
        throw const ShelfFailure(
          'The removal is not finished yet. Retry to continue safely.',
        );
      }
      transaction.delete(sourceReference);
      if (sourceDirectory.exists) {
        transaction.delete(sourceDirectory.reference);
      }
      transaction.update(operationReference, {
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  void _requireRunningOperation(
    Map<String, dynamic>? data, {
    required String ownerId,
    required String mode,
    required String sourceShelfId,
    required String? destinationShelfId,
  }) {
    if (data == null ||
        data['ownerId'] != ownerId ||
        data['mode'] != mode ||
        data['status'] != 'running' ||
        data['sourceShelfId'] != sourceShelfId ||
        data['destinationShelfId'] != destinationShelfId) {
      throw const ShelfFailure(
        'This shelf change cannot continue safely. Return to the library and retry.',
      );
    }
  }

  void _requireLockedShelf(
    Map<String, dynamic>? data,
    String ownerId,
    String operationId,
  ) {
    _requireOwnedShelf(
      data,
      ownerId: ownerId,
      missingMessage: 'A shelf in this operation is no longer available.',
    );
    if (data?['mutationOperationId'] != operationId) {
      throw const ShelfFailure(
        'This shelf is no longer reserved for the operation. Please retry.',
      );
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadShelfBooksForMutation(
    DocumentReference<Map<String, dynamic>> shelfReference, {
    required String action,
  }) async {
    try {
      final snapshot = await shelfReference
          .collection('books')
          .get(const GetOptions(source: Source.server));
      return snapshot.docs;
    } on ShelfFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapMutationError(error, action: action);
    }
  }

  void _requireOwnedShelf(
    Map<String, dynamic>? data, {
    required String ownerId,
    required String missingMessage,
  }) {
    if (data == null || data['ownerId'] != ownerId) {
      throw ShelfFailure(missingMessage);
    }
  }

  int _requireCurrentBookCount(
    Map<String, dynamic> shelfData,
    int loadedCount,
  ) {
    final storedCount = _requireStoredBookCount(shelfData);
    if (storedCount != loadedCount) {
      throw const ShelfFailure(
        'The library changed while this request was running. Review it and retry.',
      );
    }
    return storedCount;
  }

  int _requireStoredBookCount(Map<String, dynamic> shelfData) {
    final storedCount = shelfData['bookCount'];
    if (storedCount is! num || storedCount.toInt() < 0) {
      throw const ShelfFailure(
        'This older shelf needs a library refresh before it can be changed safely. Nothing was changed.',
      );
    }
    return storedCount.toInt();
  }

  ShelfFailure _mapMutationError(
    FirebaseException error, {
    required String action,
  }) {
    return switch (error.code) {
      'permission-denied' => const ShelfFailure(
        'This shelf is unavailable or belongs to another account.',
      ),
      'unavailable' => ShelfFailure(
        'Readuo cannot $action while offline. Check your connection and retry.',
      ),
      'aborted' => const ShelfFailure(
        'The library changed while this request was running. Review it and retry.',
      ),
      'resource-exhausted' => const ShelfFailure(
        'This shelf change reached a service limit. Retry to continue from the last completed step.',
      ),
      'deadline-exceeded' => const ShelfFailure(
        'This shelf change timed out. Retry to continue from the last completed step.',
      ),
      _ => ShelfFailure('Readuo could not $action. Please retry.'),
    };
  }

  ShelfFailure _mapError(FirebaseException error) {
    return switch (error.code) {
      'permission-denied' => const ShelfFailure(
        'Your session cannot access these shelves. Sign in again and retry.',
      ),
      'unavailable' => const ShelfFailure(
        'The library service is temporarily unavailable. Please retry.',
      ),
      _ => const ShelfFailure(
        'Readuo could not load your library. Please try again.',
      ),
    };
  }
}

class EmptyShelfRepository implements ShelfRepository {
  const EmptyShelfRepository();

  @override
  Stream<List<Shelf>> watchShelves(String ownerId) => Stream.value(const []);

  @override
  Stream<List<ShelfMutationOperation>> watchShelfOperations(String ownerId) =>
      Stream.value(const []);

  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) => Stream.value(const []);

  @override
  Stream<Shelf?> watchSharedShelf({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) => Stream.value(null);

  @override
  Future<Shelf> createShelf({
    required String ownerId,
    required CreateShelfInput input,
  }) {
    throw const ShelfFailure('Shelf storage is unavailable in this test.');
  }

  @override
  Future<void> updateShelf({
    required String ownerId,
    required String shelfId,
    required UpdateShelfInput input,
  }) {
    throw const ShelfFailure('Shelf storage is unavailable in this test.');
  }

  @override
  Future<void> moveAllBooksAndDeleteShelf({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
  }) {
    throw const ShelfFailure('Shelf storage is unavailable in this test.');
  }

  @override
  Future<void> deleteShelfAndBooks({
    required String ownerId,
    required String shelfId,
  }) {
    throw const ShelfFailure('Shelf storage is unavailable in this test.');
  }

  @override
  Future<void> resumeShelfOperation({
    required String ownerId,
    required String sourceShelfId,
  }) {
    throw const ShelfFailure('Shelf storage is unavailable in this test.');
  }
}

class _ShelfBookMutation {
  const _ShelfBookMutation({
    required this.sourceReference,
    required this.destinationReference,
    required this.data,
    required this.indexReference,
    required this.activityGeneration,
    required this.reviewReference,
    required this.reviewDraftReference,
  });

  final DocumentReference<Map<String, dynamic>> sourceReference;
  final DocumentReference<Map<String, dynamic>> destinationReference;
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>>? indexReference;
  final String activityGeneration;
  final DocumentReference<Map<String, dynamic>>? reviewReference;
  final DocumentReference<Map<String, dynamic>>? reviewDraftReference;
}

class _ShelfBookRemoval {
  const _ShelfBookRemoval({
    required this.bookReference,
    required this.indexReference,
    required this.isbn,
    required this.reviewReference,
    required this.reviewDraftReference,
  });

  final DocumentReference<Map<String, dynamic>> bookReference;
  final DocumentReference<Map<String, dynamic>>? indexReference;
  final String? isbn;
  final DocumentReference<Map<String, dynamic>>? reviewReference;
  final DocumentReference<Map<String, dynamic>>? reviewDraftReference;
}

bool _shelfReviewSourceMatches(
  Map<String, dynamic> data, {
  required String ownerId,
  required String shelfId,
  required String bookId,
  required Map<String, dynamic> bookData,
  required String reviewId,
  required bool isDraft,
}) =>
    (!isDraft || data['reviewId'] == reviewId) &&
    (isDraft || data['authorId'] == ownerId) &&
    data['shelfId'] == shelfId &&
    data['bookId'] == bookId &&
    data['bookCreatedAt'] == bookData['createdAt'] &&
    data['title'] == bookData['title'] &&
    data['bookAuthor'] == bookData['author'] &&
    data['coverUrl'] == bookData['coverUrl'];
