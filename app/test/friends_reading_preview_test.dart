import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/library/shelf_repository.dart';
import 'package:readuo/screens/friends_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'friends_test.dart'
    show FakeAuthService, FakeFriendRepository, bailey, testUser;
import 'widget_test.dart' show shelf;

void main() {
  testWidgets(
    'friend preview is authorized, live, and clears on privacy or errors',
    (tester) async {
      final shared = shelf(
        id: 'shared',
        ownerId: bailey.uid,
        name: 'Shared',
        bookCount: 1,
      );
      final shelves = _SharedShelves([shared]);
      final books = _SharedBooks();
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: FriendsScreen(
            authService: const FakeAuthService(),
            repository: FakeFriendRepository(friends: const [bailey]),
            shelfRepository: shelves,
            bookRepository: books,
            user: testUser,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reading A shared story'), findsOneWidget);
      expect(books.viewerId, testUser.uid);
      expect(books.ownerId, bailey.uid);
      expect(books.shelfId, 'shared');
      books.changes.add([]);
      await tester.pumpAndSettle();
      expect(find.text('Reading A shared story'), findsNothing);
      expect(find.text('View shared shelves'), findsOneWidget);
      books.changes.add([books.book]);
      await tester.pumpAndSettle();
      expect(find.text('Reading A shared story'), findsOneWidget);
      books.changes.addError(const BookFailure('Access removed'));
      await tester.pumpAndSettle();
      expect(find.text('Reading A shared story'), findsNothing);
      books.changes.add([books.book]);
      await tester.pumpAndSettle();
      shelves.changes.add([
        shared.copyWith(visibility: ShelfVisibility.private),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Reading A shared story'), findsNothing);
      expect(books.changes.hasListener, isFalse);
      shelves.changes.add([shared.copyWith(autoShareActivity: false)]);
      await tester.pumpAndSettle();
      expect(find.text('Reading A shared story'), findsNothing);
      expect(books.changes.hasListener, isFalse);
      shelves.changes.add([shared]);
      await tester.pumpAndSettle();
      expect(find.text('Reading A shared story'), findsOneWidget);
      shelves.changes.addError(const ShelfFailure('Access removed'));
      await tester.pumpAndSettle();
      expect(find.text('Reading A shared story'), findsNothing);
      expect(books.changes.hasListener, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await shelves.changes.close();
      await books.changes.close();
    },
  );
}

class _SharedShelves extends EmptyShelfRepository {
  _SharedShelves(this.initial);
  final List<Shelf> initial;
  final changes = StreamController<List<Shelf>>.broadcast();
  @override
  Stream<List<Shelf>> watchSharedShelves({
    required String viewerId,
    required String ownerId,
  }) async* {
    yield initial;
    yield* changes.stream;
  }
}

class _SharedBooks extends EmptyBookRepository {
  final changes = StreamController<List<LibraryBook>>.broadcast();
  String? viewerId;
  String? ownerId;
  String? shelfId;
  final book = LibraryBook(
    id: 'book',
    ownerId: bailey.uid,
    shelfId: 'shared',
    title: 'A shared story',
    author: 'Reader',
    isbn: null,
    isOwned: true,
    readingStatus: ReadingStatus.reading,
    coverUrl: null,
    createdAt: DateTime(2026),
  );
  @override
  Stream<List<LibraryBook>> watchSharedBooks({
    required String viewerId,
    required String ownerId,
    required String shelfId,
  }) async* {
    this.viewerId = viewerId;
    this.ownerId = ownerId;
    this.shelfId = shelfId;
    yield [book];
    yield* changes.stream;
  }
}
