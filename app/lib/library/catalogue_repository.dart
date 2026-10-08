import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'book_lookup.dart';
import 'isbn.dart';

enum CatalogueProvider { openLibrary, googleBooks }

enum CatalogueFailureKind {
  invalidInput,
  network,
  timeout,
  rateLimited,
  service,
  malformed,
}

class CatalogueFailure implements Exception {
  const CatalogueFailure(this.kind, this.message);

  final CatalogueFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

class CatalogueWork {
  const CatalogueWork({
    required this.id,
    required this.title,
    required this.author,
    required this.provider,
    required this.editionCount,
    this.edition,
  });

  final String id;
  final String title;
  final String author;
  final CatalogueProvider provider;
  final int? editionCount;
  final CatalogueEdition? edition;
}

class CatalogueEdition {
  const CatalogueEdition({
    required this.id,
    required this.title,
    required this.author,
    required this.isbn,
    required this.publisher,
    required this.publishedYear,
    required this.format,
    required this.description,
    required this.coverUrl,
    required this.sourceUrl,
    required this.provider,
  });

  final String id;
  final String title;
  final String author;
  final String? isbn;
  final String? publisher;
  final int? publishedYear;
  final String? format;
  final String? description;
  final String? coverUrl;
  final String sourceUrl;
  final CatalogueProvider provider;

  factory CatalogueEdition.fromLookup(BookLookupResult result) {
    final provider = Uri.tryParse(result.sourceUrl)?.host == 'books.google.com'
        ? CatalogueProvider.googleBooks
        : CatalogueProvider.openLibrary;
    return CatalogueEdition(
      id: '${provider.name}:${result.isbn}',
      title: result.title,
      author: result.author,
      isbn: result.isbn,
      publisher: result.publisher,
      publishedYear: result.publishedYear,
      format: null,
      description: result.description,
      coverUrl: result.coverUrl,
      sourceUrl: result.sourceUrl,
      provider: provider,
    );
  }
}

class CatalogueSearchPage {
  const CatalogueSearchPage({
    required this.items,
    required this.offset,
    required this.hasMore,
    required this.provider,
    this.confirmedNoMatches = false,
  });

  final List<CatalogueWork> items;
  final int offset;
  final bool hasMore;
  final CatalogueProvider provider;
  final bool confirmedNoMatches;
}

class CatalogueEditionPage {
  const CatalogueEditionPage({
    required this.items,
    required this.offset,
    required this.hasMore,
  });

  final List<CatalogueEdition> items;
  final int offset;
  final bool hasMore;
}

abstract interface class CatalogueRepository {
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  });

  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  });
}

class OpenLibraryThenGoogleCatalogueRepository implements CatalogueRepository {
  const OpenLibraryThenGoogleCatalogueRepository({
    required this.openLibrary,
    required this.googleBooks,
    required this.isbnLookup,
  });

  final CatalogueRepository openLibrary;
  final CatalogueRepository googleBooks;
  final BookLookupRepository isbnLookup;

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async {
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      throw const CatalogueFailure(
        CatalogueFailureKind.invalidInput,
        'Enter a title, author, or ISBN.',
      );
    }
    final isbnShape = _wholeIsbnShape(normalized);
    if (isbnShape != null) {
      String isbn;
      try {
        isbn = Isbn.normalizeOptional(isbnShape)!;
      } on IsbnValidationException catch (error) {
        throw CatalogueFailure(
          CatalogueFailureKind.invalidInput,
          error.message,
        );
      }
      try {
        final result = await isbnLookup.lookup(isbn);
        final edition = CatalogueEdition.fromLookup(result);
        return CatalogueSearchPage(
          items: [
            CatalogueWork(
              id: edition.id,
              title: edition.title,
              author: edition.author,
              provider: edition.provider,
              editionCount: 1,
              edition: edition,
            ),
          ],
          offset: 0,
          hasMore: false,
          provider: edition.provider,
        );
      } on BookLookupFailure catch (error) {
        if (error.kind == BookLookupFailureKind.notFound) {
          return const CatalogueSearchPage(
            items: [],
            offset: 0,
            hasMore: false,
            provider: CatalogueProvider.openLibrary,
          );
        }
        throw CatalogueFailure(switch (error.kind) {
          BookLookupFailureKind.network => CatalogueFailureKind.network,
          BookLookupFailureKind.timeout => CatalogueFailureKind.timeout,
          BookLookupFailureKind.notFound => CatalogueFailureKind.service,
          BookLookupFailureKind.service => CatalogueFailureKind.service,
        }, error.message);
      }
    }
    if (provider == CatalogueProvider.googleBooks) {
      return googleBooks.search(
        normalized,
        offset: offset,
        limit: limit,
        provider: provider,
      );
    }
    final primary = await openLibrary.search(
      normalized,
      offset: offset,
      limit: limit,
      provider: CatalogueProvider.openLibrary,
    );
    if (provider == CatalogueProvider.openLibrary ||
        !primary.confirmedNoMatches) {
      return primary;
    }
    return googleBooks.search(
      normalized,
      offset: 0,
      limit: limit,
      provider: CatalogueProvider.googleBooks,
    );
  }

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) {
    if (work.edition != null) {
      return Future.value(
        CatalogueEditionPage(
          items: offset == 0 ? [work.edition!] : const [],
          offset: offset,
          hasMore: false,
        ),
      );
    }
    return switch (work.provider) {
      CatalogueProvider.openLibrary => openLibrary.editions(
        work,
        offset: offset,
        limit: limit,
      ),
      CatalogueProvider.googleBooks => googleBooks.editions(
        work,
        offset: offset,
        limit: limit,
      ),
    };
  }
}

class OpenLibraryCatalogueRepository implements CatalogueRepository {
  OpenLibraryCatalogueRepository(
    this._client, {
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Duration timeout;
  DateTime? _lastRequestAt;

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': query,
      'fields': 'key,title,author_name,edition_count',
      'offset': '$offset',
      'limit': '$limit',
    });
    final decoded = await _getJson(uri);
    final docs = decoded['docs'];
    final total = _integer(decoded['numFound'] ?? decoded['num_found']);
    if (docs is! List || total == null) {
      throw const CatalogueFailure(
        CatalogueFailureKind.malformed,
        'Open Library returned an unreadable catalogue response.',
      );
    }
    final items = <CatalogueWork>[];
    for (final raw in docs.whereType<Map>()) {
      final key = raw['key'];
      final title = raw['title'];
      if (key is! String ||
          !key.startsWith('/works/') ||
          title is! String ||
          title.trim().isEmpty) {
        continue;
      }
      items.add(
        CatalogueWork(
          id: key.substring('/works/'.length),
          title: title.trim(),
          author: _strings(raw['author_name']).join(', '),
          provider: CatalogueProvider.openLibrary,
          editionCount: _integer(raw['edition_count']),
        ),
      );
    }
    if (offset == 0 && total > 0 && items.isEmpty) {
      throw const CatalogueFailure(
        CatalogueFailureKind.malformed,
        'Open Library returned catalogue rows without usable work identities.',
      );
    }
    return CatalogueSearchPage(
      items: items,
      offset: offset,
      hasMore: docs.isNotEmpty && offset + docs.length < total,
      provider: CatalogueProvider.openLibrary,
      confirmedNoMatches: offset == 0 && total == 0 && docs.isEmpty,
    );
  }

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) async {
    final uri = Uri.https(
      'openlibrary.org',
      '/works/${work.id}/editions.json',
      {'offset': '$offset', 'limit': '$limit'},
    );
    final decoded = await _getJson(uri);
    final entries = decoded['entries'];
    final total = _integer(decoded['size']);
    if (entries is! List || total == null) {
      throw const CatalogueFailure(
        CatalogueFailureKind.malformed,
        'Open Library returned unreadable edition data.',
      );
    }
    final items = <CatalogueEdition>[];
    final seen = <String>{};
    for (final raw in entries.whereType<Map>()) {
      final key = raw['key'];
      if (key is! String || !key.startsWith('/books/')) continue;
      final identifiers = _canonicalIsbns(raw['isbn_13'], raw['isbn_10']);
      final isbnValues = identifiers.isEmpty ? <String?>[null] : identifiers;
      for (final isbn in isbnValues) {
        if (isbn != null && !seen.add(isbn)) continue;
        final coverIds = raw['covers'];
        final coverId = coverIds is List
            ? coverIds.whereType<num>().firstOrNull?.toInt()
            : null;
        items.add(
          CatalogueEdition(
            id: '${key.substring('/books/'.length)}:${isbn ?? 'manual'}',
            title: _text(raw['title']) ?? work.title,
            author: work.author,
            isbn: isbn,
            publisher: _strings(raw['publishers']).firstOrNull,
            publishedYear: _year(raw['publish_date']),
            format: _text(raw['physical_format']),
            description: _description(raw['description']),
            coverUrl: coverId == null
                ? null
                : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg',
            sourceUrl: 'https://openlibrary.org$key',
            provider: CatalogueProvider.openLibrary,
          ),
        );
      }
    }
    return CatalogueEditionPage(
      items: items,
      offset: offset,
      hasMore: offset + entries.length < total,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    await _respectRateLimit();
    http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const CatalogueFailure(
        CatalogueFailureKind.timeout,
        'Open Library timed out. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const CatalogueFailure(
        CatalogueFailureKind.network,
        'Catalogue search needs a network connection.',
      );
    } catch (_) {
      throw const CatalogueFailure(
        CatalogueFailureKind.network,
        'Catalogue search could not connect. Please retry.',
      );
    }
    if (response.statusCode == 429) {
      throw const CatalogueFailure(
        CatalogueFailureKind.rateLimited,
        'Open Library is busy. Wait a moment and retry.',
      );
    }
    if (response.statusCode != 200) {
      throw const CatalogueFailure(
        CatalogueFailureKind.service,
        'Open Library could not complete this search. Please retry.',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return decoded;
    } on FormatException {
      throw const CatalogueFailure(
        CatalogueFailureKind.malformed,
        'Open Library returned an unreadable response. Please retry.',
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
}

class GoogleBooksCatalogueRepository implements CatalogueRepository {
  GoogleBooksCatalogueRepository(
    this._client, {
    required this.apiKey,
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final String apiKey;
  final Duration timeout;

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const CatalogueFailure(
        CatalogueFailureKind.service,
        'Google Books search is not configured.',
      );
    }
    final pageSize = limit.clamp(1, 20);
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': query,
      'startIndex': '$offset',
      'maxResults': '$pageSize',
      'printType': 'books',
      'projection': 'full',
      'key': apiKey,
    });
    http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const CatalogueFailure(
        CatalogueFailureKind.timeout,
        'Google Books timed out. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const CatalogueFailure(
        CatalogueFailureKind.network,
        'Catalogue search needs a network connection.',
      );
    } catch (_) {
      throw const CatalogueFailure(
        CatalogueFailureKind.network,
        'Catalogue search could not connect. Please retry.',
      );
    }
    if (response.statusCode == 429) {
      throw const CatalogueFailure(
        CatalogueFailureKind.rateLimited,
        'Google Books is busy. Wait a moment and retry.',
      );
    }
    if (response.statusCode != 200) {
      throw const CatalogueFailure(
        CatalogueFailureKind.service,
        'Google Books could not complete this search. Please retry.',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final rawItems = decoded['items'];
      final total = _integer(decoded['totalItems']);
      if (total == null || rawItems != null && rawItems is! List) {
        throw const FormatException();
      }
      final items = <CatalogueWork>[];
      final seen = <String>{};
      for (final raw in (rawItems as List? ?? const []).whereType<Map>()) {
        final volume = raw['volumeInfo'];
        final volumeId = raw['id'];
        if (volume is! Map || volumeId is! String) continue;
        final title = _text(volume['title']);
        if (title == null) continue;
        final author = _strings(volume['authors']).join(', ');
        final identifiers = _googleIsbns(volume['industryIdentifiers']);
        final isbnValues = identifiers.isEmpty ? <String?>[null] : identifiers;
        for (final isbn in isbnValues) {
          final identity = isbn ?? '$volumeId:manual';
          if (!seen.add(identity)) continue;
          final imageLinks = volume['imageLinks'];
          final cover = imageLinks is Map
              ? _safeGoogleCover(_text(imageLinks['thumbnail']))
              : null;
          final edition = CatalogueEdition(
            id: '$volumeId:$identity',
            title: title,
            author: author,
            isbn: isbn,
            publisher: _text(volume['publisher']),
            publishedYear: _year(volume['publishedDate']),
            format: _text(volume['printType']),
            description: _description(volume['description']),
            coverUrl: cover,
            sourceUrl: Uri.https('books.google.com', '/books', {
              'id': volumeId,
            }).toString(),
            provider: CatalogueProvider.googleBooks,
          );
          items.add(
            CatalogueWork(
              id: edition.id,
              title: title,
              author: author,
              provider: CatalogueProvider.googleBooks,
              editionCount: 1,
              edition: edition,
            ),
          );
        }
      }
      return CatalogueSearchPage(
        items: items,
        offset: offset,
        hasMore: offset + pageSize < total,
        provider: CatalogueProvider.googleBooks,
      );
    } on FormatException {
      throw const CatalogueFailure(
        CatalogueFailureKind.malformed,
        'Google Books returned an unreadable response. Please retry.',
      );
    }
  }

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) => Future.value(
    CatalogueEditionPage(
      items: offset == 0 && work.edition != null ? [work.edition!] : const [],
      offset: offset,
      hasMore: false,
    ),
  );
}

class EmptyCatalogueRepository implements CatalogueRepository {
  const EmptyCatalogueRepository();

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) => throw const CatalogueFailure(
    CatalogueFailureKind.service,
    'Catalogue search is unavailable.',
  );

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) => throw const CatalogueFailure(
    CatalogueFailureKind.service,
    'Catalogue editions are unavailable.',
  );
}

String? _wholeIsbnShape(String value) {
  final match = RegExp(
    r'^(?:isbn(?:-1[03])?\s*:?\s*)?([0-9x](?:[0-9x -]*[0-9x])?)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;
  final compact = match.group(1)!.replaceAll(RegExp(r'[ -]'), '');
  return compact.length == 10 || compact.length == 13 ? compact : null;
}

List<String> _canonicalIsbns(Object? isbn13, Object? isbn10) {
  final values = [..._strings(isbn13), ..._strings(isbn10)];
  final result = <String>[];
  for (final value in values) {
    try {
      final normalized = Isbn.normalizeOptional(value);
      if (normalized != null && !result.contains(normalized))
        result.add(normalized);
    } on IsbnValidationException {
      continue;
    }
  }
  return result;
}

List<String> _googleIsbns(Object? value) {
  if (value is! List) return const [];
  final raw = value.whereType<Map>().map((item) => item['identifier']);
  return _canonicalIsbns(raw.whereType<String>().toList(), const <String>[]);
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _description(Object? value) => switch (value) {
  String text => _text(text),
  Map map => _text(map['value']),
  _ => null,
};

int? _integer(Object? value) => value is num ? value.toInt() : null;

int? _year(Object? value) {
  final text = value is String ? value : null;
  final match = text == null
      ? null
      : RegExp(r'\b(1[0-9]{3}|20[0-9]{2}|21[0-9]{2})\b').firstMatch(text);
  return match == null ? null : int.tryParse(match.group(0)!);
}

String? _safeGoogleCover(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null ||
      uri.host != 'books.google.com' ||
      uri.path != '/books/content') {
    return null;
  }
  return uri.replace(scheme: 'https').toString();
}
