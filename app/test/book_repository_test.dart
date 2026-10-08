import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book_repository.dart';

void main() {
  test('duplicate location uses the current shelf name after a rename', () {
    expect(
      resolveDuplicateShelfName(
        indexData: const {'shelfName': 'Old shelf'},
        currentShelfData: const {'name': 'Renamed shelf'},
      ),
      'Renamed shelf',
    );
  });

  test(
    'book repository errors distinguish reads, auth, index, and offline',
    () {
      BookFailure mapped(String code, String action) => mapBookRepositoryError(
        FirebaseException(plugin: 'cloud_firestore', code: code),
        action: action,
      );

      expect(
        mapped('permission-denied', 'load books').message,
        contains('load these books because access was denied'),
      );
      expect(
        mapped('permission-denied', 'save this book').message,
        contains('save this book because shelf access was denied'),
      );
      expect(
        mapped('unauthenticated', 'load books').message,
        contains('ended'),
      );
      expect(
        mapped('failed-precondition', 'load books').message,
        contains('index is not ready'),
      );
      expect(
        mapped('unavailable', 'load books').message,
        contains('while offline'),
      );
    },
  );
}
