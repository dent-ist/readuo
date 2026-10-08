import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:readuo/library/book_cover_photo.dart';
import 'package:readuo/library/manual_book_draft.dart';
import 'p1_19_21_test.dart' show MemoryCache;
import 'package:readuo/screens/manual_book_flow.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'manual_book_test.dart' show FakeBookRepository, testShelf, tapSaveBook;

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ZkAAAAASUVORK5CYII=',
);
void main() {
  test(
    'camera recovery draft survives store recreation and is isolated/erased by account',
    () async {
      final memory = MemoryCache();
      final store = ManualBookDraftStore(storage: memory);
      await store.write('first', {
        'shelfId': 'shelf',
        'title': 'Unfinished',
        'photo': base64Encode(png),
      });
      final recovered = await ManualBookDraftStore(
        storage: memory,
      ).read('first');
      expect(recovered!['title'], 'Unfinished');
      expect(base64Decode(recovered['photo'] as String), png);
      expect(await store.read('second'), isNull);
      await store.clearExcept('second');
      expect(await store.read('first'), isNull);
      await store.write('second', {'shelfId': 'other'});
      await store.clearExcept(null);
      expect(await store.read('second'), isNull);
    },
  );
  test('cover validation rejects oversized, empty and unsupported uploads', () {
    expect(BookCoverPhoto(png).contentType, 'image/png');
    for (final bytes in [
      Uint8List(0),
      Uint8List(5 * 1024 * 1024 + 1),
      Uint8List.fromList([1, 2, 3]),
    ]) {
      expect(() => BookCoverPhoto(bytes), throwsArgumentError);
    }
    expect(
      isStoredBookCover('bookCovers/owner/book/abcdefghijklmnopqrst'),
      true,
    );
    expect(
      isStoredBookCover('bookCovers/owner/../abcdefghijklmnopqrst'),
      false,
    );
  });
  testWidgets(
    'picker cancellation preserves the manual entry without creating an upload',
    (tester) async {
      final repository = FakeBookRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: ManualBookFlow(
            ownerId: 'owner-user',
            shelf: testShelf(),
            bookRepository: repository,
            initialTitle: 'Keep my title',
            pickPhoto: (_) async => null,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('add-cover-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cover-library')));
      await tester.pumpAndSettle();
      expect(find.text('Keep my title'), findsOneWidget);
      expect(find.text('Add cover photo (optional)'), findsOneWidget);
      expect(repository.lastInput, isNull);
    },
  );
  testWidgets('photo denial is recoverable and does not discard text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: ManualBookFlow(
          ownerId: 'owner-user',
          shelf: testShelf(),
          bookRepository: FakeBookRepository(),
          initialTitle: 'Keep my title',
          pickPhoto: (_) async =>
              throw PlatformException(code: 'photo_access_denied'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('add-cover-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cover-camera')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your photos are unavailable'), findsOneWidget);
    await tester.tap(find.text('Continue without a photo'));
    await tester.pumpAndSettle();
    expect(find.text('Keep my title'), findsOneWidget);
  });
  testWidgets(
    'selected image and text survive failed save, and removal restores generated cover',
    (tester) async {
      final repository = FakeBookRepository(
        isbnLocations: {'9780306406157': ('Existing', 'Other shelf')},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: ManualBookFlow(
            ownerId: 'owner-user',
            shelf: testShelf(),
            bookRepository: repository,
            initialTitle: 'Manual',
            initialAuthor: 'Reader',
            initialIsbn: '0306406152',
            pickPhoto: (_) async =>
                XFile.fromData(png, mimeType: 'image/png', name: 'cover.png'),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('add-cover-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cover-library')));
      await tester.pumpAndSettle();
      expect(find.text('Cover photo selected'), findsOneWidget);
      await tapSaveBook(tester);
      await tester.pumpAndSettle();
      expect(repository.lastInput!.coverPhoto!.bytes, png);
      expect(find.textContaining('already saved'), findsOneWidget);
      expect(find.text('Optional cover photo selected'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('add-cover-photo')),
        -400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('add-cover-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use a generated title cover'));
      await tester.pumpAndSettle();
      expect(find.text('Add cover photo (optional)'), findsOneWidget);
    },
  );
}
