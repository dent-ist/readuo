import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../circle/circle_repository.dart';
import '../circle/review_repository.dart';
import 'book.dart';
import 'book_cover_photo.dart';
import 'shelf.dart';

class BookFailure implements Exception {
  const BookFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class DuplicateIsbnFailure extends BookFailure {
  const DuplicateIsbnFailure({required this.title, required this.shelfName})
    : super('This ISBN is already saved as “$title” on “$shelfName”.');

  final String title;
  final String shelfName;
}

String resolveDuplicateShelfName({
  required Map<String, dynamic> indexData,
  Map<String, dynamic>? currentShelfData,
}) {
  final currentName = (currentShelfData?['name'] as String?)?.trim();
  if (currentName != null && currentName.isNotEmpty) return currentName;
  return indexData['shelfName'] as String? ?? 'another shelf';
}

String? _validActivityBatchId(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null ||
      trimmed.isEmpty ||
      trimmed.length > 100 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}

@visibleForTesting
BookFailure mapBookRepositoryError(
  FirebaseException error, {
  required String action,
}) {
  return switch (error.code) {
    'unauthenticated' => const BookFailure(
      'Your sign-in session has ended. Sign in again and retry.',
    ),
    'permission-denied' => BookFailure(
      action == 'load books'
          ? 'Readuo could not load these books because access was denied. '
                'Retry, or open a shelf you own.'
          : action == 'save this book'
          ? 'Readuo could not save this book because shelf access was denied. '
                'Retry, or choose another shelf you own.'
          : 'Readuo could not $action because access was denied. '
                'Retry, or return to your library.',
    ),
    'failed-precondition' => const BookFailure(
      'The library index is not ready yet. Please retry shortly.',
    ),
    'unavailable' => BookFailure(
      'Readuo cannot $action while offline. Check your connection and retry.',
    ),
    'aborted' => BookFailure(
      'Readuo could not $action because the library changed. Please retry.',
    ),
    _ => BookFailure('Readuo could not $action. Please retry.'),
  };
}

abstract interface class BookRepository {
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId);

  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  });

  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  });

  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  });

  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  });

  Future<void> updateReadingStatus({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required ReadingStatus readingStatus,
  });

  Future<void> updateOwnership({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required bool isOwned,
  });

  Future<void> moveBook({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
    required String bookId,
  });

  Future<void> removeBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required DateTime? expectedCreatedAt,
  });
}

abstract interface class BookCreationReceiptSource {
  Future<String> createBookWithReceipt({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  });
}

abstract interface class ActivityBookMutationSource {
  Future<void> createBookWithActivityBatch({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
    required String activityBatchId,
  });
}

extension ActivityBookMutations on BookRepository {
  Future<void> createBookInActivityBatch({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
    required String activityBatchId,
  }) {
    final repository = this;
    if (repository is ActivityBookMutationSource) {
      return (repository as ActivityBookMutationSource)
          .createBookWithActivityBatch(
            ownerId: ownerId,
            shelf: shelf,
            input: input,
            activityBatchId: activityBatchId,
          );
    }
    return createBook(ownerId: ownerId, shelf: shelf, input: input);
  }
}

extension OwnedSharedBookQueries on BookRepository {
  Stream<List<LibraryBook>> watchOwnedSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) {
    final repository = this;
    if (repository is FirebaseBookRepository) {
      return repository.watchOwnedSharedBooks(
        viewerId: viewerId,
        ownerId: ownerId,
        shelfId: shelfId,
      );
    }
    return watchSharedBooks(
      viewerId: viewerId,
      ownerId: ownerId,
      shelfId: shelfId,
    ).map(
      (books) => books
          .where(
            (book) =>
                book.ownerId == ownerId &&
                book.shelfId == shelfId &&
                book.isOwned,
          )
          .toList(),
    );
  }
}

class FirebaseBookRepository
    implements
        BookRepository,
        ActivityBookMutationSource,
        BookCreationReceiptSource {
  FirebaseBookRepository(this._firestore, {BookCoverStore? covers})
    : _covers = covers ?? FirebaseBookCoverStore();

  final FirebaseFirestore _firestore;
  final BookCoverStore _covers;

  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .doc(shelfId)
              .collection('books')
              .doc(bookId)
              .snapshots()) {
        final data = snapshot.data();
        if (data == null) {
          yield null;
          continue;
        }
        final book = LibraryBook.fromFirestore(snapshot.id, shelfId, data);
        yield book.ownerId == ownerId && book.shelfId == shelfId ? book : null;
      }
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'load this book');
    }
  }

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) async* {
    try {
      await for (final snapshot
          in _firestore
              .collectionGroup('books')
              .where('ownerId', isEqualTo: ownerId)
              .snapshots()) {
        final books =
            snapshot.docs
                .map((document) {
                  final data = document.data();
                  final shelfId =
                      data['shelfId'] as String? ??
                      document.reference.parent.parent?.id ??
                      '';
                  return LibraryBook.fromFirestore(document.id, shelfId, data);
                })
                .where((book) => book.ownerId == ownerId)
                .toList()
              ..sort((left, right) {
                final leftDate =
                    left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                final rightDate =
                    right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                return rightDate.compareTo(leftDate);
              });
        yield books;
      }
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'load books');
    }
  }

  @override
  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .doc(shelfId)
              .collection('books')
              .snapshots()) {
        final books =
            snapshot.docs
                .map(
                  (document) => LibraryBook.fromFirestore(
                    document.id,
                    shelfId,
                    document.data(),
                  ),
                )
                .where(
                  (book) => book.ownerId.isEmpty || book.ownerId == ownerId,
                )
                .toList()
              ..sort((left, right) {
                final leftDate =
                    left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                final rightDate =
                    right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                return rightDate.compareTo(leftDate);
              });
        yield books;
      }
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'load books');
    }
  }

  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .doc(shelfId)
              .collection('books')
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        final books =
            snapshot.docs
                .map(
                  (document) => LibraryBook.fromFirestore(
                    document.id,
                    shelfId,
                    document.data(),
                  ),
                )
                .where(
                  (book) => book.ownerId.isEmpty || book.ownerId == ownerId,
                )
                .toList()
              ..sort((left, right) => left.title.compareTo(right.title));
        yield books;
      }
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'load books');
    }
  }

  Stream<List<LibraryBook>> watchOwnedSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('shelves')
              .doc(shelfId)
              .collection('books')
              .where('isOwned', isEqualTo: true)
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        final books =
            snapshot.docs
                .map(
                  (document) => LibraryBook.fromFirestore(
                    document.id,
                    shelfId,
                    document.data(),
                  ),
                )
                .where(
                  (book) =>
                      book.ownerId == ownerId &&
                      book.shelfId == shelfId &&
                      book.isOwned,
                )
                .toList()
              ..sort((left, right) => left.title.compareTo(right.title));
        yield books;
      }
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'load owned shared books');
    }
  }

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) => _createBook(ownerId: ownerId, shelf: shelf, input: input);

  @override
  Future<void> createBookWithActivityBatch({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
    required String activityBatchId,
  }) => _createBook(
    ownerId: ownerId,
    shelf: shelf,
    input: input,
    activityBatchId: activityBatchId,
  );

  @override
  Future<String> createBookWithReceipt({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) => _createBook(ownerId: ownerId, shelf: shelf, input: input);

  Future<String> _createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
    String? activityBatchId,
  }) async {
    final validationMessage = input.validationMessage;
    if (validationMessage != null) throw BookFailure(validationMessage);
    final isbn = input.normalizedIsbn;
    final shelfReference = _firestore.collection('shelves').doc(shelf.id);
    final bookReference = shelfReference
        .collection('books')
        .doc(isbn ?? shelfReference.collection('books').doc().id);
    final activityReference = bookReference.collection('activities').doc();
    final activityGeneration = bookReference
        .collection('activityGenerations')
        .doc()
        .id;
    final indexReference = isbn == null
        ? null
        : _firestore
              .collection('users')
              .doc(ownerId)
              .collection('libraryBookIsbns')
              .doc(isbn);

    String? uploadedCover;
    var committed = false;
    try {
      final photo =
          input.coverPhoto ??
          (isStoredBookCover(input.coverUrl)
              ? BookCoverPhoto(await _covers.load(input.coverUrl!))
              : null);
      if (photo != null) {
        uploadedCover =
            'bookCovers/$ownerId/${bookReference.id}/$activityGeneration';
        await _covers.upload(uploadedCover, photo);
      }
      await _firestore.runTransaction((transaction) async {
        final shelfSnapshot = await transaction.get(shelfReference);
        if (!shelfSnapshot.exists ||
            shelfSnapshot.data()?['ownerId'] != ownerId) {
          throw const BookFailure(
            'This shelf is unavailable or belongs to another account.',
          );
        }
        if (shelfSnapshot.data()?['mutationOperationId'] != null) {
          throw const BookFailure(
            'This shelf is already changing. Retry when that change finishes.',
          );
        }

        DocumentSnapshot<Map<String, dynamic>>? indexSnapshot;
        if (indexReference != null) {
          indexSnapshot = await transaction.get(indexReference);
          if (indexSnapshot.exists) {
            final data = indexSnapshot.data()!;
            final existingShelfId = data['shelfId'] as String?;
            Map<String, dynamic>? currentShelfData;
            if (existingShelfId != null && existingShelfId.isNotEmpty) {
              final currentShelfSnapshot = await transaction.get(
                _firestore.collection('shelves').doc(existingShelfId),
              );
              currentShelfData = currentShelfSnapshot.data();
            }
            throw DuplicateIsbnFailure(
              title: data['title'] as String? ?? 'another book',
              shelfName: resolveDuplicateShelfName(
                indexData: data,
                currentShelfData: currentShelfData,
              ),
            );
          }
        }

        final shelfData = shelfSnapshot.data()!;
        final sharesActivity =
            input.isOwned &&
            shelfData['visibility'] != ShelfVisibility.private.storageValue &&
            shelfData['autoShareActivity'] == true;
        transaction.set(bookReference, {
          'ownerId': ownerId,
          'shelfId': shelf.id,
          'title': input.title.trim(),
          'titleNormalized': input.normalizedTitle,
          'author': input.author.trim(),
          'isbn': isbn,
          'isOwned': input.isOwned,
          'readingStatus': input.readingStatus.storageValue,
          'coverUrl': uploadedCover ?? input.coverUrl,
          'coverStoragePath': uploadedCover,
          if (input.publisher.isNotEmpty) 'publisher': input.publisher.trim(),
          if (input.publishedYear.isNotEmpty)
            'publishedYear': input.publishedYear,
          if (input.description.isNotEmpty)
            'description': input.description.trim(),
          'activityGeneration': activityGeneration,
          if (sharesActivity) 'lastActivityId': activityReference.id,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (sharesActivity) {
          transaction.set(activityReference, {
            'authorId': ownerId,
            'shelfId': shelf.id,
            'bookId': bookReference.id,
            'type': 'added',
            'batchId': _validActivityBatchId(activityBatchId),
            'audience': 'friends',
            'activityGeneration': activityGeneration,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (indexReference != null) {
          transaction.set(indexReference, {
            'ownerId': ownerId,
            'shelfId': shelf.id,
            'bookId': bookReference.id,
            'title': input.title.trim(),
            'shelfName': shelf.name,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (shelfData['bookCount'] is num) {
          transaction.update(shelfReference, {
            'bookCount': (shelfData['bookCount'] as num).toInt() + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
      committed = true;
      return bookReference.id;
    } on BookFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'save this book');
    } finally {
      if (!committed && uploadedCover != null) {
        try {
          final saved = await bookReference.get(
            const GetOptions(source: Source.server),
          );
          if (saved.data()?['coverStoragePath'] != uploadedCover)
            await _covers.delete(uploadedCover);
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> updateReadingStatus({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required ReadingStatus readingStatus,
  }) => _updateReadingStatus(
    ownerId: ownerId,
    shelfId: shelfId,
    bookId: bookId,
    readingStatus: readingStatus,
  );

  @override
  Future<void> updateOwnership({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required bool isOwned,
  }) => _updateBookField(
    ownerId: ownerId,
    shelfId: shelfId,
    bookId: bookId,
    field: 'isOwned',
    value: isOwned,
  );

  @override
  Future<void> moveBook({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
    required String bookId,
  }) async {
    if (sourceShelfId == destinationShelfId) {
      throw const BookFailure('Choose another shelf for this book.');
    }
    final sourceShelfReference = _firestore
        .collection('shelves')
        .doc(sourceShelfId);
    final destinationShelfReference = _firestore
        .collection('shelves')
        .doc(destinationShelfId);
    final sourceBookReference = sourceShelfReference
        .collection('books')
        .doc(bookId);
    final destinationBookReference = destinationShelfReference
        .collection('books')
        .doc(bookId);
    final reviewId = circleReviewId(ownerId, bookId);
    final reviewReference = _firestore
        .collection('circleReviews')
        .doc(reviewId);
    final reviewDraftReference = _firestore
        .collection('users')
        .doc(ownerId)
        .collection('reviewDrafts')
        .doc(reviewId);
    final moveCollection = _firestore
        .collection('users')
        .doc(ownerId)
        .collection('bookMoves');
    final moveReference = moveCollection.doc();
    final moveId = moveReference.id;
    final destinationActivityGeneration = destinationBookReference
        .collection('activityGenerations')
        .doc()
        .id;

    try {
      await _firestore.runTransaction((transaction) async {
        final sourceShelf = await transaction.get(sourceShelfReference);
        final destinationShelf = await transaction.get(
          destinationShelfReference,
        );
        final sourceBook = await transaction.get(sourceBookReference);
        final destinationBook = await transaction.get(destinationBookReference);
        final sourceShelfData = sourceShelf.data();
        final destinationShelfData = destinationShelf.data();
        final sourceBookData = sourceBook.data();
        if (sourceShelfData == null ||
            sourceShelfData['ownerId'] != ownerId ||
            sourceBookData == null ||
            sourceBookData['ownerId'] != ownerId ||
            sourceBookData['shelfId'] != sourceShelfId) {
          throw const BookFailure(
            'This saved book is no longer on this shelf. Return to your library.',
          );
        }
        if (destinationShelfData == null ||
            destinationShelfData['ownerId'] != ownerId) {
          throw const BookFailure(
            'The destination shelf is no longer available.',
          );
        }
        if (sourceShelfData['mutationOperationId'] != null ||
            destinationShelfData['mutationOperationId'] != null) {
          throw const BookFailure(
            'One of these shelves is changing. Retry when that change finishes.',
          );
        }
        if (destinationBook.exists) {
          throw const BookFailure(
            'The destination already contains an entry with this identity.',
          );
        }
        final sourceCount = sourceShelfData['bookCount'];
        final destinationCount = destinationShelfData['bookCount'];
        if (sourceCount is! num ||
            destinationCount is! num ||
            sourceCount.toInt() <= 0) {
          throw const BookFailure(
            'A shelf count changed unexpectedly. Return to your library and retry.',
          );
        }

        DocumentReference<Map<String, dynamic>>? indexReference;
        DocumentSnapshot<Map<String, dynamic>>? index;
        final isbn = sourceBookData['isbn'] as String?;
        if (isbn != null) {
          indexReference = _firestore
              .collection('users')
              .doc(ownerId)
              .collection('libraryBookIsbns')
              .doc(isbn);
          index = await transaction.get(indexReference);
          if (!index.exists ||
              index.data()?['ownerId'] != ownerId ||
              index.data()?['shelfId'] != sourceShelfId ||
              index.data()?['bookId'] != bookId ||
              index.data()?['title'] != sourceBookData['title']) {
            throw const BookFailure(
              'This book’s ISBN index changed. Return to your library and retry.',
            );
          }
        }
        final review = await transaction.get(reviewReference);
        final reviewDraft = await transaction.get(reviewDraftReference);
        if (review.exists &&
            !_matchesReviewSource(
              review.data()!,
              ownerId: ownerId,
              shelfId: sourceShelfId,
              bookId: bookId,
              bookData: sourceBookData,
              reviewId: reviewId,
              isDraft: false,
            )) {
          throw const BookFailure(
            'This book’s review changed unexpectedly. Return to your library and retry.',
          );
        }
        if (reviewDraft.exists &&
            !_matchesReviewSource(
              reviewDraft.data()!,
              ownerId: ownerId,
              shelfId: sourceShelfId,
              bookId: bookId,
              bookData: sourceBookData,
              reviewId: reviewId,
              isDraft: true,
            )) {
          throw const BookFailure(
            'This book’s review draft changed unexpectedly. Return to your library and retry.',
          );
        }

        final moveData = <String, Object?>{
          'ownerId': ownerId,
          'moveId': moveId,
          'sourceShelfId': sourceShelfId,
          'destinationShelfId': destinationShelfId,
          'bookId': bookId,
          'isbn': isbn,
          'title': sourceBookData['title'],
          'sourceCountBefore': sourceCount.toInt(),
          'destinationCountBefore': destinationCount.toInt(),
          'sourceVisibility': sourceShelfData['visibility'],
          'destinationVisibility': destinationShelfData['visibility'],
          'sourceAutoShareActivity': sourceShelfData['autoShareActivity'],
          'destinationAutoShareActivity':
              destinationShelfData['autoShareActivity'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        transaction.set(moveReference, moveData);
        transaction.set(destinationBookReference, {
          ...sourceBookData,
          'shelfId': destinationShelfId,
          'activityGeneration': destinationActivityGeneration,
        });
        transaction.delete(sourceBookReference);
        transaction.update(sourceShelfReference, {
          'bookCount': sourceCount.toInt() - 1,
          'lastBookMoveId': moveId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(destinationShelfReference, {
          'bookCount': destinationCount.toInt() + 1,
          'lastBookMoveId': moveId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (indexReference != null) {
          transaction.update(indexReference, {
            'shelfId': destinationShelfId,
            'shelfName': destinationShelfData['name'],
          });
        }
        if (review.exists) {
          transaction.update(reviewReference, {
            'shelfId': destinationShelfId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        if (reviewDraft.exists) {
          transaction.update(reviewDraftReference, {
            'shelfId': destinationShelfId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on BookFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'move this book');
    }
  }

  @override
  Future<void> removeBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required DateTime? expectedCreatedAt,
  }) async {
    final shelfReference = _firestore.collection('shelves').doc(shelfId);
    final bookReference = shelfReference.collection('books').doc(bookId);
    final reviewId = circleReviewId(ownerId, bookId);
    final reviewReference = _firestore
        .collection('circleReviews')
        .doc(reviewId);
    final reviewDraftReference = _firestore
        .collection('users')
        .doc(ownerId)
        .collection('reviewDrafts')
        .doc(reviewId);
    final removalReference = _firestore
        .collection('users')
        .doc(ownerId)
        .collection('bookRemovals')
        .doc();
    final removalId = removalReference.id;

    try {
      await _firestore.runTransaction((transaction) async {
        final shelf = await transaction.get(shelfReference);
        final book = await transaction.get(bookReference);
        final shelfData = shelf.data();
        final bookData = book.data();
        if (shelfData == null ||
            shelfData['ownerId'] != ownerId ||
            bookData == null ||
            bookData['ownerId'] != ownerId ||
            bookData['shelfId'] != shelfId) {
          throw const BookFailure(
            'This saved book is no longer on this shelf. Return to your library.',
          );
        }
        if (shelfData['mutationOperationId'] != null) {
          throw const BookFailure(
            'This shelf is changing. Retry when that change finishes.',
          );
        }
        final sourceCount = shelfData['bookCount'];
        if (sourceCount is! num || sourceCount.toInt() <= 0) {
          throw const BookFailure(
            'The shelf count changed unexpectedly. Return to your library and retry.',
          );
        }
        final sourceCreatedAt = bookData['createdAt'];
        if (expectedCreatedAt == null ||
            sourceCreatedAt is! Timestamp ||
            sourceCreatedAt.toDate().microsecondsSinceEpoch !=
                expectedCreatedAt.microsecondsSinceEpoch) {
          throw const BookFailure(
            'This saved entry changed after confirmation. Return to your library and try again.',
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
          final indexData = index.data();
          if (indexData == null ||
              indexData['ownerId'] != ownerId ||
              indexData['shelfId'] != shelfId ||
              indexData['bookId'] != bookId ||
              indexData['title'] != bookData['title'] ||
              indexData['createdAt'] != sourceCreatedAt) {
            throw const BookFailure(
              'This book’s ISBN index changed. Return to your library and retry.',
            );
          }
        }
        final review = await transaction.get(reviewReference);
        final reviewDraft = await transaction.get(reviewDraftReference);
        if (review.exists &&
            !_matchesReviewSource(
              review.data()!,
              ownerId: ownerId,
              shelfId: shelfId,
              bookId: bookId,
              bookData: bookData,
              reviewId: reviewId,
              isDraft: false,
            )) {
          throw const BookFailure(
            'This book’s review changed unexpectedly. Return to your library and retry.',
          );
        }
        if (reviewDraft.exists &&
            !_matchesReviewSource(
              reviewDraft.data()!,
              ownerId: ownerId,
              shelfId: shelfId,
              bookId: bookId,
              bookData: bookData,
              reviewId: reviewId,
              isDraft: true,
            )) {
          throw const BookFailure(
            'This book’s review draft changed unexpectedly. Return to your library and retry.',
          );
        }

        transaction.set(removalReference, {
          'ownerId': ownerId,
          'removalId': removalId,
          'shelfId': shelfId,
          'bookId': bookId,
          'isbn': isbn,
          'title': bookData['title'],
          'sourceBookCreatedAt': sourceCreatedAt,
          'sourceCountBefore': sourceCount.toInt(),
          'sourceVisibility': shelfData['visibility'],
          'sourceAutoShareActivity': shelfData['autoShareActivity'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.delete(bookReference);
        transaction.update(shelfReference, {
          'bookCount': sourceCount.toInt() - 1,
          'lastBookRemovalId': removalId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (indexReference != null) transaction.delete(indexReference);
        if (review.exists) transaction.delete(reviewReference);
        if (reviewDraft.exists) transaction.delete(reviewDraftReference);
      });
    } on BookFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'remove this book');
    }
  }

  Future<void> _updateReadingStatus({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required ReadingStatus readingStatus,
  }) async {
    final shelfReference = _firestore.collection('shelves').doc(shelfId);
    final bookReference = shelfReference.collection('books').doc(bookId);
    final activityReference = bookReference.collection('activities').doc();
    try {
      await _firestore.runTransaction((transaction) async {
        final shelfSnapshot = await transaction.get(shelfReference);
        final shelfData = shelfSnapshot.data();
        if (shelfData == null || shelfData['ownerId'] != ownerId) {
          throw const BookFailure(
            'This shelf is no longer available. Return to your library.',
          );
        }
        if (shelfData['mutationOperationId'] != null) {
          throw const BookFailure(
            'This shelf is changing. Return to Library to continue that change.',
          );
        }
        final bookSnapshot = await transaction.get(bookReference);
        final bookData = bookSnapshot.data();
        if (bookData == null ||
            bookData['ownerId'] != ownerId ||
            bookData['shelfId'] != shelfId) {
          throw const BookFailure(
            'This saved book is no longer on this shelf. Return to your library.',
          );
        }
        final storedStatus = bookData['readingStatus'] as String?;
        if (storedStatus == readingStatus.storageValue) return;
        final activityType = switch (readingStatus) {
          ReadingStatus.reading => CircleActivityType.started,
          ReadingStatus.finished => CircleActivityType.finished,
          ReadingStatus.wantToRead => null,
        };
        final sharesActivity =
            activityType != null &&
            shelfData['visibility'] != ShelfVisibility.private.storageValue &&
            shelfData['autoShareActivity'] == true;
        final activityGeneration =
            bookData['activityGeneration'] as String? ??
            bookReference.collection('activityGenerations').doc().id;
        transaction.update(bookReference, {
          'readingStatus': readingStatus.storageValue,
          if (sharesActivity) ...{
            'lastActivityId': activityReference.id,
            'activityGeneration': activityGeneration,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (sharesActivity) {
          transaction.set(activityReference, {
            'authorId': ownerId,
            'shelfId': shelfId,
            'bookId': bookId,
            'type': activityType.name,
            'batchId': null,
            'audience': 'friends',
            'activityGeneration': activityGeneration,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on BookFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'update this book');
    }
  }

  Future<void> _updateBookField({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required String field,
    required Object value,
  }) async {
    final shelfReference = _firestore.collection('shelves').doc(shelfId);
    final bookReference = shelfReference.collection('books').doc(bookId);
    try {
      await _firestore.runTransaction((transaction) async {
        final shelfSnapshot = await transaction.get(shelfReference);
        final shelfData = shelfSnapshot.data();
        if (shelfData == null || shelfData['ownerId'] != ownerId) {
          throw const BookFailure(
            'This shelf is no longer available. Return to your library.',
          );
        }
        if (shelfData['mutationOperationId'] != null) {
          throw const BookFailure(
            'This shelf is changing. Return to Library to continue that change.',
          );
        }
        final bookSnapshot = await transaction.get(bookReference);
        final bookData = bookSnapshot.data();
        if (bookData == null ||
            bookData['ownerId'] != ownerId ||
            bookData['shelfId'] != shelfId) {
          throw const BookFailure(
            'This saved book is no longer on this shelf. Return to your library.',
          );
        }
        if (bookData[field] == value) return;
        transaction.update(bookReference, {
          field: value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on BookFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw mapBookRepositoryError(error, action: 'update this book');
    }
  }
}

bool _matchesReviewSource(
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

class EmptyBookRepository implements BookRepository {
  const EmptyBookRepository();

  @override
  Stream<List<LibraryBook>> watchLibraryBooks(String ownerId) =>
      Stream.value(const []);

  @override
  Stream<LibraryBook?> watchBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
  }) => Stream.value(null);

  @override
  Stream<List<LibraryBook>> watchBooks({
    required String ownerId,
    required String shelfId,
  }) => Stream.value(const []);

  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) => Stream.value(const []);

  @override
  Future<void> createBook({
    required String ownerId,
    required Shelf shelf,
    required CreateBookInput input,
  }) {
    throw const BookFailure('Book storage is unavailable in this test.');
  }

  @override
  Future<void> updateReadingStatus({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required ReadingStatus readingStatus,
  }) {
    throw const BookFailure('Book storage is unavailable in this test.');
  }

  @override
  Future<void> updateOwnership({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required bool isOwned,
  }) {
    throw const BookFailure('Book storage is unavailable in this test.');
  }

  @override
  Future<void> moveBook({
    required String ownerId,
    required String sourceShelfId,
    required String destinationShelfId,
    required String bookId,
  }) {
    throw const BookFailure('Book storage is unavailable in this test.');
  }

  @override
  Future<void> removeBook({
    required String ownerId,
    required String shelfId,
    required String bookId,
    required DateTime? expectedCreatedAt,
  }) {
    throw const BookFailure('Book storage is unavailable in this test.');
  }
}
