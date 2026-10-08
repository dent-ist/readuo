import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/isbn.dart';

void main() {
  test('ISBN-10 and equivalent ISBN-13 normalize to one identity', () {
    expect(Isbn.normalizeOptional('0-306-40615-2'), '9780306406157');
    expect(Isbn.normalizeOptional('978 0 306 40615 7'), '9780306406157');
  });

  test('invalid ISBN checksum is rejected', () {
    expect(
      () => Isbn.normalizeOptional('9780306406158'),
      throwsA(isA<IsbnValidationException>()),
    );
  });

  test('blank ISBN remains absent and is not a title identity', () {
    final first = CreateBookInput(
      title: 'Same title',
      author: 'One Author',
      isbnInput: '',
      isOwned: true,
      readingStatus: ReadingStatus.wantToRead,
    );
    final second = CreateBookInput(
      title: '  Same   title ',
      author: 'Another Author',
      isbnInput: '   ',
      isOwned: false,
      readingStatus: ReadingStatus.finished,
    );

    expect(first.normalizedIsbn, isNull);
    expect(second.normalizedIsbn, isNull);
    expect(first.normalizedTitle, second.normalizedTitle);
  });
}
