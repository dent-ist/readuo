import 'package:cloud_firestore/cloud_firestore.dart';

import 'isbn.dart';
import 'book_cover_photo.dart';

enum ReadingStatus { wantToRead, reading, finished }

extension ReadingStatusDetails on ReadingStatus {
  String get storageValue => name;

  String get label => switch (this) {
    ReadingStatus.wantToRead => 'Want to read',
    ReadingStatus.reading => 'Reading',
    ReadingStatus.finished => 'Finished',
  };
}

class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.ownerId,
    required this.shelfId,
    required this.title,
    required this.author,
    required this.isbn,
    required this.isOwned,
    required this.readingStatus,
    required this.coverUrl,
    required this.createdAt,
    this.activityGeneration,
    this.description = '',
    this.publisher = '',
    this.publishedYear = '',
  });

  factory LibraryBook.fromFirestore(
    String id,
    String shelfId,
    Map<String, dynamic> data,
  ) {
    final legacyAuthors = data['authors'];
    final author =
        data['author'] as String? ??
        (legacyAuthors is List && legacyAuthors.isNotEmpty
            ? legacyAuthors.first.toString()
            : 'Unknown author');
    return LibraryBook(
      id: id,
      ownerId: data['ownerId'] as String? ?? data['addedBy'] as String? ?? '',
      shelfId: shelfId,
      title: (data['title'] as String? ?? 'Untitled book').trim(),
      author: author.trim(),
      isbn: data['isbn'] as String?,
      isOwned: data['isOwned'] as bool? ?? false,
      readingStatus: _readStatus(data['readingStatus'] ?? data['status']),
      coverUrl: data['coverUrl'] as String?,
      createdAt: _readDate(data['createdAt'] ?? data['addedAt']),
      activityGeneration: data['activityGeneration'] as String?,
      description: data['description'] as String? ?? '',
      publisher: data['publisher'] as String? ?? '',
      publishedYear: data['publishedYear']?.toString() ?? '',
    );
  }

  final String id;
  final String ownerId;
  final String shelfId;
  final String title;
  final String author;
  final String? isbn;
  final bool isOwned;
  final ReadingStatus readingStatus;
  final String? coverUrl;
  final DateTime? createdAt;
  final String? activityGeneration;
  final String description;
  final String publisher;
  final String publishedYear;

  static ReadingStatus _readStatus(Object? value) {
    return switch (value) {
      'reading' || 'READING' => ReadingStatus.reading,
      'finished' || 'READ' => ReadingStatus.finished,
      _ => ReadingStatus.wantToRead,
    };
  }

  static DateTime? _readDate(Object? value) {
    return switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime date => date,
      _ => null,
    };
  }
}

class CreateBookInput {
  CreateBookInput({
    required this.title,
    required this.author,
    required this.isbnInput,
    required this.isOwned,
    required this.readingStatus,
    this.coverUrl,
    this.coverPhoto,
    this.publisher = '',
    this.publishedYear = '',
    this.description = '',
  });

  final String title;
  final String author;
  final String isbnInput;
  final bool isOwned;
  final ReadingStatus readingStatus;
  final String? coverUrl;
  final BookCoverPhoto? coverPhoto;
  final String publisher;
  final String publishedYear;
  final String description;

  String? get validationMessage {
    if (publisher.length > 160 ||
        description.length > 2000 ||
        (publishedYear.isNotEmpty &&
            !RegExp(r'^[0-9]{4}$').hasMatch(publishedYear)))
      return 'Check the optional book details.';
    if (title.trim().isEmpty) return 'Enter a book title.';
    if (title.trim().length > 160) {
      return 'Book titles must be 160 characters or fewer.';
    }
    if (author.trim().isEmpty) return 'Enter an author.';
    if (author.trim().length > 120) {
      return 'Author names must be 120 characters or fewer.';
    }
    try {
      Isbn.normalizeOptional(isbnInput);
    } on IsbnValidationException catch (error) {
      return error.message;
    }
    if (coverUrl != null && !isStoredBookCover(coverUrl)) {
      final uri = Uri.tryParse(coverUrl!);
      if (uri == null ||
          uri.scheme != 'https' ||
          !((uri.host == 'covers.openlibrary.org') ||
              (uri.host == 'books.google.com' &&
                  uri.path == '/books/content'))) {
        return 'The catalog cover URL is invalid.';
      }
    }
    return null;
  }

  String? get normalizedIsbn => Isbn.normalizeOptional(isbnInput);

  String get normalizedTitle =>
      title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
