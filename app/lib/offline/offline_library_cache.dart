import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../library/book.dart';
import '../library/shelf.dart';

abstract interface class OfflineCacheStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  Future<Set<String>> keys();
}

class PreferencesOfflineCacheStorage implements OfflineCacheStorage {
  PreferencesOfflineCacheStorage(this.preferences);
  final SharedPreferencesAsync preferences;
  @override
  Future<String?> read(String key) => preferences.getString(key);
  @override
  Future<void> write(String key, String value) =>
      preferences.setString(key, value);
  @override
  Future<void> remove(String key) => preferences.remove(key);
  @override
  Future<Set<String>> keys() => preferences.getKeys();
}

class OfflineLibrarySnapshot {
  OfflineLibrarySnapshot({
    required this.userId,
    required Iterable<Shelf> shelves,
    required Iterable<LibraryBook> books,
    required this.savedAt,
  }) : shelves = List.unmodifiable(shelves),
       books = List.unmodifiable(books);

  factory OfflineLibrarySnapshot.empty(String userId) => OfflineLibrarySnapshot(
    userId: userId,
    shelves: const [],
    books: const [],
    savedAt: null,
  );

  final String userId;
  final List<Shelf> shelves;
  final List<LibraryBook> books;
  final DateTime? savedAt;

  List<LibraryBook> booksOn(String shelfId) =>
      books.where((book) => book.shelfId == shelfId).toList();

  String encode() => jsonEncode({
    'version': 1,
    'uid': userId,
    'savedAt': savedAt?.toUtc().toIso8601String(),
    'shelves': [
      for (final shelf in shelves)
        {
          'id': shelf.id,
          'ownerId': shelf.ownerId,
          'name': shelf.name,
          'visibility': shelf.visibility.name,
        },
    ],
    'books': [
      for (final book in books)
        {
          'id': book.id,
          'ownerId': book.ownerId,
          'shelfId': book.shelfId,
          'title': book.title,
          'author': book.author,
          'isbn': book.isbn,
          'isOwned': book.isOwned,
          'readingStatus': book.readingStatus.name,
        },
    ],
  });

  static OfflineLibrarySnapshot decode(String expectedUserId, String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['version'] != 1 || data['uid'] != expectedUserId)
      throw const FormatException('Invalid library cache.');
    String text(Map<String, dynamic> value, String key) {
      final field = value[key];
      if (field is! String || field.isEmpty)
        throw FormatException('Invalid cached $key.');
      return field;
    }

    final shelves = <Shelf>[];
    for (final entry in data['shelves'] as List) {
      final value = entry as Map<String, dynamic>;
      if (value['ownerId'] != expectedUserId)
        throw const FormatException('Cache owner mismatch.');
      shelves.add(
        Shelf(
          id: text(value, 'id'),
          ownerId: expectedUserId,
          name: text(value, 'name'),
          visibility: ShelfVisibility.values.byName(text(value, 'visibility')),
          autoShareActivity: false,
          bookCount: 0,
          createdAt: null,
          updatedAt: null,
        ),
      );
    }
    final books = <LibraryBook>[];
    for (final entry in data['books'] as List) {
      final value = entry as Map<String, dynamic>;
      if (value['ownerId'] != expectedUserId)
        throw const FormatException('Cache owner mismatch.');
      final shelfId = text(value, 'shelfId');
      if (!shelves.any((shelf) => shelf.id == shelfId))
        throw const FormatException('Unknown cached shelf.');
      books.add(
        LibraryBook(
          id: text(value, 'id'),
          ownerId: expectedUserId,
          shelfId: shelfId,
          title: text(value, 'title'),
          author: text(value, 'author'),
          isbn: value['isbn'] as String?,
          isOwned: value['isOwned'] as bool,
          readingStatus: ReadingStatus.values.byName(
            text(value, 'readingStatus'),
          ),
          coverUrl: null,
          createdAt: null,
        ),
      );
    }
    return OfflineLibrarySnapshot(
      userId: expectedUserId,
      shelves: shelves,
      books: books,
      savedAt: data['savedAt'] == null
          ? null
          : DateTime.parse(data['savedAt'] as String),
    );
  }
}

class OfflineLibraryCache {
  OfflineLibraryCache(this.storage);
  final OfflineCacheStorage storage;
  static const prefix = 'readuo.offline.library.v1.';
  static String keyFor(String uid) =>
      '$prefix${base64Url.encode(utf8.encode(uid))}';

  Future<void> clearExcept(String? uid) async {
    for (final key in await storage.keys()) {
      if (key.startsWith(prefix) && (uid == null || key != keyFor(uid))) {
        await storage.remove(key);
      }
    }
  }

  Future<OfflineLibrarySnapshot> load(String uid) async {
    final source = await storage.read(keyFor(uid));
    if (source == null) return OfflineLibrarySnapshot.empty(uid);
    try {
      return OfflineLibrarySnapshot.decode(uid, source);
    } catch (_) {
      await storage.remove(keyFor(uid));
      throw const FormatException('Saved library could not be read.');
    }
  }

  Future<void> save(OfflineLibrarySnapshot snapshot) =>
      storage.write(keyFor(snapshot.userId), snapshot.encode());
}
