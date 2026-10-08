import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readuo/library/book_lookup.dart';
import 'package:readuo/library/catalogue_repository.dart';

void main() {
  test('Open Library search encodes title, author, and digits safely', () async {
    final repository = OpenLibraryCatalogueRepository(
      MockClient((request) async {
        expect(request.url.path, '/search.json');
        expect(request.url.queryParameters['q'], 'Book 2 & Jane Doe');
        expect(request.url.queryParameters['offset'], '0');
        expect(request.url.queryParameters['limit'], '8');
        return http.Response(
          '{"numFound":1,"docs":[{"key":"/works/OL1W","title":"Book 2","author_name":["Jane Doe"],"edition_count":3}]}',
          200,
        );
      }),
    );

    final page = await repository.search('Book 2 & Jane Doe');

    expect(page.items.single.id, 'OL1W');
    expect(page.items.single.author, 'Jane Doe');
    expect(page.items.single.editionCount, 3);
    expect(page.hasMore, isFalse);
  });

  test(
    'Open Library editions keep distinct ISBNs and explicit no-ISBN row',
    () async {
      final repository = OpenLibraryCatalogueRepository(
        MockClient((request) async {
          expect(request.url.path, '/works/OL1W/editions.json');
          expect(request.url.queryParameters['offset'], '20');
          return http.Response('''{"size":42,"entries":[
            {"key":"/books/OL1M","title":"A Book","isbn_10":["0306406152"],"isbn_13":["9780306406157"],"publishers":["Press"],"publish_date":"May 1981","physical_format":"Hardcover","covers":[123]},
            {"key":"/books/OL2M","title":"A Book: Revised","isbn_13":["9780140328721"]},
            {"key":"/books/OL3M","title":"A Book: Notes"}
          ]}''', 200);
        }),
      );
      const work = CatalogueWork(
        id: 'OL1W',
        title: 'A Book',
        author: 'Writer',
        provider: CatalogueProvider.openLibrary,
        editionCount: 42,
      );

      final page = await repository.editions(work, offset: 20, limit: 20);

      expect(page.items, hasLength(3));
      expect(page.items[0].isbn, '9780306406157');
      expect(page.items[0].publisher, 'Press');
      expect(page.items[0].publishedYear, 1981);
      expect(page.items[0].format, 'Hardcover');
      expect(page.items[0].coverUrl, contains('/123-M.jpg'));
      expect(page.items[1].isbn, '9780140328721');
      expect(page.items[2].isbn, isNull);
      expect(page.hasMore, isTrue);
    },
  );

  test('Google results deduplicate ISBN-10 and ISBN-13 identity', () async {
    final repository = GoogleBooksCatalogueRepository(
      MockClient((request) async {
        expect(request.url.queryParameters['q'], 'Piranesi Clarke');
        expect(request.url.queryParameters['key'], 'fixture-key');
        return http.Response('''{"totalItems":2,"items":[
            {"id":"v1","volumeInfo":{"title":"Piranesi","authors":["Susanna Clarke"],"industryIdentifiers":[{"type":"ISBN_10","identifier":"163557563X"},{"type":"ISBN_13","identifier":"9781635575637"}],"publisher":"Bloomsbury","publishedDate":"2020-09-15","printType":"BOOK","imageLinks":{"thumbnail":"http://books.google.com/books/content?id=v1"}}},
            {"id":"v2","volumeInfo":{"title":"Piranesi Companion"}}
          ]}''', 200);
      }),
      apiKey: 'fixture-key',
    );

    final page = await repository.search('Piranesi Clarke');

    expect(page.items, hasLength(2));
    expect(page.items[0].edition!.isbn, '9781635575637');
    expect(page.items[0].edition!.coverUrl, startsWith('https://'));
    expect(page.items[1].edition!.isbn, isNull);
  });

  test(
    'Google fallback runs only after a successful Open Library no-match',
    () async {
      final openLibrary = _FakeCatalogue(
        searchResult: const CatalogueSearchPage(
          items: [],
          offset: 0,
          hasMore: false,
          provider: CatalogueProvider.openLibrary,
          confirmedNoMatches: true,
        ),
      );
      final google = _FakeCatalogue(
        searchResult: CatalogueSearchPage(
          items: [_directWork('Google match')],
          offset: 0,
          hasMore: false,
          provider: CatalogueProvider.googleBooks,
        ),
      );
      final repository = OpenLibraryThenGoogleCatalogueRepository(
        openLibrary: openLibrary,
        googleBooks: google,
        isbnLookup: const EmptyBookLookupRepository(),
      );

      final page = await repository.search('uncommon title');

      expect(page.provider, CatalogueProvider.googleBooks);
      expect(openLibrary.searchCalls, 1);
      expect(google.searchCalls, 1);
    },
  );

  test(
    'Google fallback session continues Google without re-running Open Library',
    () async {
      final openLibrary = _FakeCatalogue(
        searchResult: const CatalogueSearchPage(
          items: [],
          offset: 0,
          hasMore: false,
          provider: CatalogueProvider.openLibrary,
          confirmedNoMatches: true,
        ),
      );
      final google = _FakeCatalogue(
        searchResult: CatalogueSearchPage(
          items: [_directWork('Google page')],
          offset: 0,
          hasMore: true,
          provider: CatalogueProvider.googleBooks,
        ),
      );
      final repository = OpenLibraryThenGoogleCatalogueRepository(
        openLibrary: openLibrary,
        googleBooks: google,
        isbnLookup: const EmptyBookLookupRepository(),
      );

      final first = await repository.search('continued search', limit: 8);
      await repository.search(
        'continued search',
        offset: 8,
        limit: 8,
        provider: first.provider,
      );

      expect(first.provider, CatalogueProvider.googleBooks);
      expect(openLibrary.offsets, [0]);
      expect(google.offsets, [0, 8]);
    },
  );

  test(
    'an exhausted later Open Library page never switches provider',
    () async {
      final openLibrary = _FakeCatalogue(
        searchResult: const CatalogueSearchPage(
          items: [],
          offset: 8,
          hasMore: false,
          provider: CatalogueProvider.openLibrary,
        ),
      );
      final google = _FakeCatalogue();
      final repository = OpenLibraryThenGoogleCatalogueRepository(
        openLibrary: openLibrary,
        googleBooks: google,
        isbnLookup: const EmptyBookLookupRepository(),
      );

      final page = await repository.search(
        'continued search',
        offset: 8,
        provider: CatalogueProvider.openLibrary,
      );

      expect(page.provider, CatalogueProvider.openLibrary);
      expect(google.searchCalls, 0);
    },
  );

  test(
    'unusable Open Library rows are malformed, not a no-match fallback',
    () async {
      final repository = OpenLibraryCatalogueRepository(
        MockClient(
          (_) async => http.Response(
            '{"numFound":1,"docs":[{"key":"bad","title":"Dune"}]}',
            200,
          ),
        ),
      );

      await expectLater(
        repository.search('Dune'),
        throwsA(
          isA<CatalogueFailure>().having(
            (failure) => failure.kind,
            'kind',
            CatalogueFailureKind.malformed,
          ),
        ),
      );
    },
  );

  test(
    'empty later Open Library page is exhausted, not a new fallback',
    () async {
      final repository = OpenLibraryCatalogueRepository(
        MockClient(
          (_) async => http.Response('{"numFound":10,"docs":[]}', 200),
        ),
      );

      final page = await repository.search('Dune', offset: 8);

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.confirmedNoMatches, isFalse);
      expect(page.provider, CatalogueProvider.openLibrary);
    },
  );

  test('Open Library errors never trigger Google fallback', () async {
    final openLibrary = _FakeCatalogue(
      searchError: const CatalogueFailure(
        CatalogueFailureKind.rateLimited,
        'busy',
      ),
    );
    final google = _FakeCatalogue(
      searchResult: const CatalogueSearchPage(
        items: [],
        offset: 0,
        hasMore: false,
        provider: CatalogueProvider.googleBooks,
      ),
    );
    final repository = OpenLibraryThenGoogleCatalogueRepository(
      openLibrary: openLibrary,
      googleBooks: google,
      isbnLookup: const EmptyBookLookupRepository(),
    );

    await expectLater(
      repository.search('Dune'),
      throwsA(
        isA<CatalogueFailure>().having(
          (failure) => failure.kind,
          'kind',
          CatalogueFailureKind.rateLimited,
        ),
      ),
    );
    expect(google.searchCalls, 0);
  });

  test(
    'Open Library HTTP fixtures distinguish malformed and throttled',
    () async {
      final malformed = OpenLibraryCatalogueRepository(
        MockClient((_) async => http.Response('{bad json', 200)),
      );
      final throttled = OpenLibraryCatalogueRepository(
        MockClient((_) async => http.Response('busy', 429)),
      );

      await expectLater(
        malformed.search('Dune'),
        throwsA(
          isA<CatalogueFailure>().having(
            (failure) => failure.kind,
            'kind',
            CatalogueFailureKind.malformed,
          ),
        ),
      );
      await expectLater(
        throttled.search('Dune'),
        throwsA(
          isA<CatalogueFailure>().having(
            (failure) => failure.kind,
            'kind',
            CatalogueFailureKind.rateLimited,
          ),
        ),
      );
    },
  );

  test('Open Library fixture timeout is finite and recoverable', () async {
    final repository = OpenLibraryCatalogueRepository(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      repository.search('Dune'),
      throwsA(
        isA<CatalogueFailure>().having(
          (failure) => failure.kind,
          'kind',
          CatalogueFailureKind.timeout,
        ),
      ),
    );
  });

  test(
    'exact ISBN uses preserved lookup while title plus digit stays text',
    () async {
      final lookup = _FakeLookup();
      final openLibrary = _FakeCatalogue(
        searchResult: const CatalogueSearchPage(
          items: [],
          offset: 0,
          hasMore: false,
          provider: CatalogueProvider.openLibrary,
        ),
      );
      final repository = OpenLibraryThenGoogleCatalogueRepository(
        openLibrary: openLibrary,
        googleBooks: openLibrary,
        isbnLookup: lookup,
      );

      final isbnPage = await repository.search('0-306-40615-2');
      await repository.search('Dune 2');

      expect(lookup.queries, ['9780306406157']);
      expect(isbnPage.items.single.edition!.isbn, '9780306406157');
      expect(openLibrary.queries, ['Dune 2']);
    },
  );

  test('exact ISBN no-match becomes canonical empty results', () async {
    final repository = OpenLibraryThenGoogleCatalogueRepository(
      openLibrary: _FakeCatalogue(),
      googleBooks: _FakeCatalogue(),
      isbnLookup: _FakeLookup(notFound: true),
    );

    final page = await repository.search('9780306406157');

    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });
}

CatalogueWork _directWork(String title) {
  final edition = CatalogueEdition(
    id: title,
    title: title,
    author: 'Author',
    isbn: '9780306406157',
    publisher: null,
    publishedYear: null,
    format: null,
    description: null,
    coverUrl: null,
    sourceUrl: 'https://books.google.com/books?id=v1',
    provider: CatalogueProvider.googleBooks,
  );
  return CatalogueWork(
    id: title,
    title: title,
    author: 'Author',
    provider: CatalogueProvider.googleBooks,
    editionCount: 1,
    edition: edition,
  );
}

class _FakeCatalogue implements CatalogueRepository {
  _FakeCatalogue({this.searchResult, this.searchError});

  final CatalogueSearchPage? searchResult;
  final CatalogueFailure? searchError;
  int searchCalls = 0;
  final List<String> queries = [];
  final List<int> offsets = [];

  @override
  Future<CatalogueSearchPage> search(
    String query, {
    int offset = 0,
    int limit = 8,
    CatalogueProvider? provider,
  }) async {
    searchCalls += 1;
    queries.add(query);
    offsets.add(offset);
    if (searchError != null) throw searchError!;
    return searchResult ??
        const CatalogueSearchPage(
          items: [],
          offset: 0,
          hasMore: false,
          provider: CatalogueProvider.openLibrary,
        );
  }

  @override
  Future<CatalogueEditionPage> editions(
    CatalogueWork work, {
    int offset = 0,
    int limit = 20,
  }) async => const CatalogueEditionPage(items: [], offset: 0, hasMore: false);
}

class _FakeLookup implements BookLookupRepository {
  _FakeLookup({this.notFound = false});

  final bool notFound;
  final List<String> queries = [];

  @override
  Future<BookLookupResult> lookup(String isbn) async {
    queries.add(isbn);
    if (notFound) {
      throw const BookLookupFailure(BookLookupFailureKind.notFound, 'No match');
    }
    return BookLookupResult(
      isbn: isbn,
      title: 'A Book',
      author: 'Author',
      publisher: null,
      publishedYear: null,
      description: null,
      coverUrl: null,
      sourceUrl: 'https://openlibrary.org/books/OL1M',
    );
  }
}
