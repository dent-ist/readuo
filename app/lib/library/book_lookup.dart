import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'isbn.dart';

enum BookLookupFailureKind { notFound, network, timeout, service }

class BookLookupFailure implements Exception {
  const BookLookupFailure(this.kind, this.message);

  final BookLookupFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

class BookLookupResult {
  const BookLookupResult({
    required this.isbn,
    required this.title,
    required this.author,
    required this.publisher,
    required this.publishedYear,
    required this.description,
    required this.coverUrl,
    required this.sourceUrl,
  });

  final String isbn;
  final String title;
  final String author;
  final String? publisher;
  final int? publishedYear;
  final String? description;
  final String? coverUrl;
  final String sourceUrl;

  bool get isIncomplete => title.trim().isEmpty || author.trim().isEmpty;
}

abstract interface class BookLookupRepository {
  Future<BookLookupResult> lookup(String isbnInput);
}

class OpenLibraryBookLookupRepository implements BookLookupRepository {
  OpenLibraryBookLookupRepository(
    this._client, {
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Duration timeout;
  DateTime? _lastRequestAt;

  @override
  Future<BookLookupResult> lookup(String isbnInput) async {
    final isbn = Isbn.normalizeOptional(isbnInput);
    if (isbn == null) {
      throw const BookLookupFailure(
        BookLookupFailureKind.notFound,
        'Enter or scan an ISBN before looking up a book.',
      );
    }
    final uri = Uri.https('openlibrary.org', '/api/books', {
      'bibkeys': 'ISBN:$isbn',
      'jscmd': 'data',
      'format': 'json',
    });
    await _respectRateLimit();

    http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const BookLookupFailure(
        BookLookupFailureKind.timeout,
        'Book lookup timed out. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const BookLookupFailure(
        BookLookupFailureKind.network,
        'Book lookup needs a network connection. Check it and retry.',
      );
    } catch (_) {
      throw const BookLookupFailure(
        BookLookupFailureKind.network,
        'Book lookup could not connect. Check your connection and retry.',
      );
    }

    if (response.statusCode == 404 ||
        response.statusCode == 200 && response.body == '{}') {
      throw const BookLookupFailure(
        BookLookupFailureKind.notFound,
        'No Open Library match was found for this ISBN.',
      );
    }
    if (response.statusCode != 200) {
      throw const BookLookupFailure(
        BookLookupFailureKind.service,
        'Open Library could not complete this lookup. Please retry.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final rawBook = decoded['ISBN:$isbn'];
      if (rawBook is! Map<String, dynamic>) {
        throw const BookLookupFailure(
          BookLookupFailureKind.notFound,
          'No Open Library match was found for this ISBN.',
        );
      }
      final authors = _namedValues(rawBook['authors']);
      final publishers = _namedValues(rawBook['publishers']);
      final cover = rawBook['cover'];
      final rawCoverUrl = cover is Map<String, dynamic>
          ? cover['medium'] as String?
          : null;
      return BookLookupResult(
        isbn: isbn,
        title: (rawBook['title'] as String? ?? '').trim(),
        author: authors.join(', '),
        publisher: publishers.firstOrNull,
        publishedYear: _readYear(rawBook['publish_date']),
        description: _readDescription(rawBook['description']),
        coverUrl: _safeCoverUrl(rawCoverUrl),
        sourceUrl: 'https://openlibrary.org/isbn/$isbn',
      );
    } on BookLookupFailure {
      rethrow;
    } on FormatException {
      throw const BookLookupFailure(
        BookLookupFailureKind.service,
        'Open Library returned an unreadable response. Please retry.',
      );
    } on TypeError {
      throw const BookLookupFailure(
        BookLookupFailureKind.service,
        'Open Library returned incomplete data. You can retry or add manually.',
      );
    }
  }

  Future<void> _respectRateLimit() async {
    final now = DateTime.now();
    final earliest = _lastRequestAt?.add(const Duration(seconds: 1));
    final delay = earliest != null && earliest.isAfter(now)
        ? earliest.difference(now)
        : Duration.zero;
    _lastRequestAt = now.add(delay);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  static List<String> _namedValues(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) => entry['name'])
        .whereType<String>()
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
  }

  static int? _readYear(Object? value) {
    if (value is! String) return null;
    final match = RegExp(
      r'\b(1[0-9]{3}|20[0-9]{2}|21[0-9]{2})\b',
    ).firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static String? _readDescription(Object? value) {
    final raw = switch (value) {
      String text => text,
      Map<String, dynamic> map => map['value'] as String?,
      _ => null,
    };
    final normalized = raw?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? _safeCoverUrl(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host != 'covers.openlibrary.org') return null;
    return uri.replace(scheme: 'https').toString();
  }
}

class OpenLibraryThenGoogleBooksRepository implements BookLookupRepository {
  const OpenLibraryThenGoogleBooksRepository({
    required this.openLibrary,
    required this.googleBooks,
  });

  final BookLookupRepository openLibrary;
  final BookLookupRepository googleBooks;

  @override
  Future<BookLookupResult> lookup(String isbnInput) async {
    final isbn = Isbn.normalizeOptional(isbnInput);
    if (isbn == null) {
      throw const BookLookupFailure(
        BookLookupFailureKind.notFound,
        'Enter or scan an ISBN before looking up a book.',
      );
    }
    try {
      return await openLibrary.lookup(isbn);
    } on BookLookupFailure catch (error) {
      if (error.kind != BookLookupFailureKind.notFound) rethrow;
    }
    return googleBooks.lookup(isbn);
  }
}

class GoogleBooksBookLookupRepository implements BookLookupRepository {
  GoogleBooksBookLookupRepository(
    this._client, {
    required this.apiKey,
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final String apiKey;
  final Duration timeout;

  @override
  Future<BookLookupResult> lookup(String isbnInput) async {
    final isbn = Isbn.normalizeOptional(isbnInput);
    if (isbn == null) {
      throw const BookLookupFailure(
        BookLookupFailureKind.notFound,
        'Enter or scan an ISBN before looking up a book.',
      );
    }
    if (apiKey.trim().isEmpty) {
      throw const BookLookupFailure(
        BookLookupFailureKind.service,
        'Google Books lookup is not configured. You can retry or add manually.',
      );
    }
    try {
      return await _lookupQuery(isbn, 'isbn:$isbn');
    } on BookLookupFailure catch (error) {
      if (error.kind != BookLookupFailureKind.notFound) rethrow;
    }
    // Some editions are searchable by quoted ISBN but missing from the
    // ISBN-specific index. Both queries still require an exact ISBN match.
    return _lookupQuery(isbn, '"$isbn"');
  }

  Future<BookLookupResult> _lookupQuery(String isbn, String query) async {
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': query,
      'maxResults': '10',
      'projection': 'full',
      'key': apiKey,
    });

    http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const BookLookupFailure(
        BookLookupFailureKind.timeout,
        'Google Books lookup timed out. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const BookLookupFailure(
        BookLookupFailureKind.network,
        'Google Books lookup needs a network connection. Check it and retry.',
      );
    } catch (_) {
      throw const BookLookupFailure(
        BookLookupFailureKind.network,
        'Google Books lookup could not connect. Check it and retry.',
      );
    }

    if (response.statusCode != 200) {
      throw const BookLookupFailure(
        BookLookupFailureKind.service,
        'Google Books could not complete this lookup. Please retry.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final items = decoded['items'];
      if (items is! List) {
        throw const BookLookupFailure(
          BookLookupFailureKind.notFound,
          'No catalog match was found for this ISBN.',
        );
      }
      for (final item in items.whereType<Map>()) {
        final volumeInfo = item['volumeInfo'];
        if (volumeInfo is! Map) continue;
        if (!_hasExactIsbn(volumeInfo['industryIdentifiers'], isbn)) continue;
        final authors = _stringValues(volumeInfo['authors']);
        final imageLinks = volumeInfo['imageLinks'];
        final rawCoverUrl = imageLinks is Map
            ? imageLinks['thumbnail'] as String?
            : null;
        final volumeId = item['id'] as String?;
        return BookLookupResult(
          isbn: isbn,
          title: (volumeInfo['title'] as String? ?? '').trim(),
          author: authors.join(', '),
          publisher: (volumeInfo['publisher'] as String?)?.trim(),
          publishedYear: _readGoogleYear(volumeInfo['publishedDate']),
          description: (volumeInfo['description'] as String?)?.trim(),
          coverUrl: _safeGoogleCoverUrl(rawCoverUrl),
          sourceUrl: volumeId == null
              ? 'https://books.google.com/'
              : Uri.https('books.google.com', '/books', {
                  'id': volumeId,
                }).toString(),
        );
      }
      throw const BookLookupFailure(
        BookLookupFailureKind.notFound,
        'Google Books returned no exact ISBN match. You can retry or add manually.',
      );
    } on BookLookupFailure {
      rethrow;
    } on FormatException {
      throw const BookLookupFailure(
        BookLookupFailureKind.service,
        'Google Books returned an unreadable response. Please retry.',
      );
    } on TypeError {
      throw const BookLookupFailure(
        BookLookupFailureKind.service,
        'Google Books returned incomplete data. You can retry or add manually.',
      );
    }
  }

  static bool _hasExactIsbn(Object? value, String requestedIsbn) {
    if (value is! List) return false;
    for (final identifier in value.whereType<Map>()) {
      final raw = identifier['identifier'];
      if (raw is! String) continue;
      try {
        if (Isbn.normalizeOptional(raw) == requestedIsbn) return true;
      } on IsbnValidationException {
        continue;
      }
    }
    return false;
  }

  static List<String> _stringValues(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList();
  }

  static int? _readGoogleYear(Object? value) {
    if (value is! String) return null;
    final match = RegExp(
      r'\b(1[0-9]{3}|20[0-9]{2}|21[0-9]{2})\b',
    ).firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static String? _safeGoogleCoverUrl(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host != 'books.google.com' ||
        uri.path != '/books/content') {
      return null;
    }
    return uri.replace(scheme: 'https').toString();
  }
}

class EmptyBookLookupRepository implements BookLookupRepository {
  const EmptyBookLookupRepository();

  @override
  Future<BookLookupResult> lookup(String isbnInput) {
    throw const BookLookupFailure(
      BookLookupFailureKind.service,
      'Book lookup is unavailable in this test.',
    );
  }
}
