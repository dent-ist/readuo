import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readuo/library/book_lookup.dart';

void main() {
  test(
    'Open Library lookup canonicalizes ISBN and parses edition metadata',
    () async {
      final repository = OpenLibraryBookLookupRepository(
        MockClient((request) async {
          expect(request.url.host, 'openlibrary.org');
          expect(request.url.path, '/api/books');
          expect(request.url.queryParameters['bibkeys'], 'ISBN:9780306406157');
          return http.Response(
            '''{"ISBN:9780306406157":{"title":"A Book","authors":[{"name":"First Author"},{"name":"Second Author"},{"name":"First Author"}],"publishers":[{"name":"Example Press"}],"publish_date":"May 1981","description":{"value":"Edition description"},"cover":{"medium":"http://covers.openlibrary.org/b/id/123-M.jpg"}}}''',
            200,
          );
        }),
      );

      final result = await repository.lookup('0-306-40615-2');

      expect(result.isbn, '9780306406157');
      expect(result.title, 'A Book');
      expect(result.author, 'First Author, Second Author');
      expect(result.publisher, 'Example Press');
      expect(result.publishedYear, 1981);
      expect(result.description, 'Edition description');
      expect(result.coverUrl, 'https://covers.openlibrary.org/b/id/123-M.jpg');
    },
  );

  test('incomplete catalog result is returned for user correction', () async {
    final repository = OpenLibraryBookLookupRepository(
      MockClient(
        (_) async => http.Response(
          '{"ISBN:9780306406157":{"title":"Known title"}}',
          200,
        ),
      ),
    );

    final result = await repository.lookup('9780306406157');

    expect(result.title, 'Known title');
    expect(result.author, isEmpty);
    expect(result.isIncomplete, isTrue);
  });

  test('not-found response is distinct and recoverable', () async {
    final repository = OpenLibraryBookLookupRepository(
      MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      repository.lookup('9780306406157'),
      throwsA(
        isA<BookLookupFailure>().having(
          (error) => error.kind,
          'kind',
          BookLookupFailureKind.notFound,
        ),
      ),
    );
  });

  test('network and service failures have distinct error kinds', () async {
    final networkRepository = OpenLibraryBookLookupRepository(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    final serviceRepository = OpenLibraryBookLookupRepository(
      MockClient((_) async => http.Response('unavailable', 503)),
    );

    await expectLater(
      networkRepository.lookup('9780306406157'),
      throwsA(
        isA<BookLookupFailure>().having(
          (error) => error.kind,
          'kind',
          BookLookupFailureKind.network,
        ),
      ),
    );
    await expectLater(
      serviceRepository.lookup('9780306406157'),
      throwsA(
        isA<BookLookupFailure>().having(
          (error) => error.kind,
          'kind',
          BookLookupFailureKind.service,
        ),
      ),
    );
  });

  test('lookup timeout is reported without creating metadata', () async {
    final never = Completer<http.Response>();
    final repository = OpenLibraryBookLookupRepository(
      MockClient((_) => never.future),
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      repository.lookup('9780306406157'),
      throwsA(
        isA<BookLookupFailure>().having(
          (error) => error.kind,
          'kind',
          BookLookupFailureKind.timeout,
        ),
      ),
    );
  });

  test('Open Library match does not call Google Books', () async {
    var googleCalls = 0;
    final repository = OpenLibraryThenGoogleBooksRepository(
      openLibrary: OpenLibraryBookLookupRepository(
        MockClient(
          (_) async => http.Response(
            '{"ISBN:9780306406157":{"title":"Primary","authors":[{"name":"Primary Author"}]}}',
            200,
          ),
        ),
      ),
      googleBooks: GoogleBooksBookLookupRepository(
        MockClient((_) async {
          googleCalls += 1;
          return http.Response('{}', 200);
        }),
        apiKey: 'test-key',
      ),
    );

    final result = await repository.lookup('9780306406157');

    expect(result.title, 'Primary');
    expect(googleCalls, 0);
  });

  test('Open Library no-match falls back to exact Google Books ISBN', () async {
    var googleCalls = 0;
    final repository = OpenLibraryThenGoogleBooksRepository(
      openLibrary: OpenLibraryBookLookupRepository(
        MockClient((_) async => http.Response('{}', 200)),
      ),
      googleBooks: GoogleBooksBookLookupRepository(
        MockClient((request) async {
          googleCalls += 1;
          expect(request.url.host, 'www.googleapis.com');
          expect(request.url.path, '/books/v1/volumes');
          expect(request.url.queryParameters['q'], 'isbn:9780306406157');
          expect(request.url.queryParameters['key'], 'test-key');
          return http.Response(
            '''{"items":[{"id":"wrong","volumeInfo":{"title":"Wrong","authors":["Wrong Author"],"industryIdentifiers":[{"type":"ISBN_13","identifier":"9780439708180"}]}},{"id":"right","volumeInfo":{"title":"Fallback Book","authors":["Fallback Author","Fallback Author"],"publisher":"Fallback Press","publishedDate":"1981-05","description":"Fallback description","industryIdentifiers":[{"type":"ISBN_10","identifier":"0306406152"}],"imageLinks":{"thumbnail":"http://books.google.com/books/content?id=right&printsec=frontcover"}}}]}''',
            200,
          );
        }),
        apiKey: 'test-key',
      ),
    );

    final result = await repository.lookup('9780306406157');

    expect(googleCalls, 1);
    expect(result.isbn, '9780306406157');
    expect(result.title, 'Fallback Book');
    expect(result.author, 'Fallback Author');
    expect(result.publisher, 'Fallback Press');
    expect(result.publishedYear, 1981);
    expect(
      result.coverUrl,
      startsWith('https://books.google.com/books/content?'),
    );
    expect(result.sourceUrl, 'https://books.google.com/books?id=right');
  });

  test(
    'Open Library transport and service failures never call fallback',
    () async {
      for (final primary in <BookLookupRepository>[
        OpenLibraryBookLookupRepository(
          MockClient((_) async => throw http.ClientException('offline')),
        ),
        OpenLibraryBookLookupRepository(
          MockClient((_) async => http.Response('unavailable', 503)),
        ),
        OpenLibraryBookLookupRepository(
          MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(milliseconds: 10),
        ),
      ]) {
        var googleCalls = 0;
        final repository = OpenLibraryThenGoogleBooksRepository(
          openLibrary: primary,
          googleBooks: GoogleBooksBookLookupRepository(
            MockClient((_) async {
              googleCalls += 1;
              return http.Response('{}', 200);
            }),
            apiKey: 'test-key',
          ),
        );

        await expectLater(
          repository.lookup('9780306406157'),
          throwsA(isA<BookLookupFailure>()),
        );
        expect(googleCalls, 0);
      }
    },
  );

  test(
    'quoted ISBN fallback finds an exact edition after an empty or unrelated result',
    () async {
      for (final primaryBody in [
        '{"totalItems":0}',
        '{"items":[{"volumeInfo":{"industryIdentifiers":[{"identifier":"9798893313116"}]}}]}',
      ]) {
        final queries = <String>[];
        final repository = GoogleBooksBookLookupRepository(
          MockClient((request) async {
            queries.add(request.url.queryParameters['q']!);
            return http.Response(
              queries.length == 1
                  ? primaryBody
                  : '{"items":[{"id":"7xHkEQAAQBAJ","volumeInfo":{"title":"The AI-Driven Leader","authors":["Geoff Woods"],"industryIdentifiers":[{"type":"ISBN_13","identifier":"9798893313109"}]}}]}',
              200,
            );
          }),
          apiKey: 'test-key',
        );

        final result = await repository.lookup('979-8-89331-310-9');

        expect(queries, ['isbn:9798893313109', '"9798893313109"']);
        expect(result.isbn, '9798893313109');
        expect(result.title, 'The AI-Driven Leader');
        expect(result.author, 'Geoff Woods');
      }
    },
  );

  test(
    'Google Books empty and ISBN mismatch never return a wrong book',
    () async {
      for (final responseBody in <String>[
        '{"totalItems":0}',
        '''{"items":[{"id":"wrong","volumeInfo":{"title":"Wrong","authors":["Wrong Author"],"industryIdentifiers":[{"type":"ISBN_13","identifier":"9780439708180"}]}}]}''',
      ]) {
        var calls = 0;
        final repository = GoogleBooksBookLookupRepository(
          MockClient((_) async {
            calls += 1;
            return http.Response(responseBody, 200);
          }),
          apiKey: 'test-key',
        );

        await expectLater(
          repository.lookup('9780306406157'),
          throwsA(
            isA<BookLookupFailure>().having(
              (error) => error.kind,
              'kind',
              BookLookupFailureKind.notFound,
            ),
          ),
        );
        expect(calls, 2);
      }
    },
  );

  test('Google Books errors remain retryable service failures', () async {
    var calls = 0;
    final repository = GoogleBooksBookLookupRepository(
      MockClient((_) async {
        calls += 1;
        return http.Response('{"error":{}}', 403);
      }),
      apiKey: 'test-key',
    );

    await expectLater(
      repository.lookup('9780306406157'),
      throwsA(
        isA<BookLookupFailure>().having(
          (error) => error.kind,
          'kind',
          BookLookupFailureKind.service,
        ),
      ),
    );
    expect(calls, 1);
  });

  test('quoted ISBN fallback preserves service failures', () async {
    var calls = 0;
    final repository = GoogleBooksBookLookupRepository(
      MockClient((_) async {
        calls += 1;
        return calls == 1
            ? http.Response('{"totalItems":0}', 200)
            : http.Response('{"error":{}}', 503);
      }),
      apiKey: 'test-key',
    );
    await expectLater(
      repository.lookup('9798893313109'),
      throwsA(
        isA<BookLookupFailure>().having(
          (error) => error.kind,
          'kind',
          BookLookupFailureKind.service,
        ),
      ),
    );
    expect(calls, 2);
  });
}
