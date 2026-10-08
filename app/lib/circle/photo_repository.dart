import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class CirclePhotoFailure implements Exception {
  const CirclePhotoFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class CirclePhotoRepository {
  Future<String> upload({
    required String ownerId,
    required String postId,
    required Uint8List bytes,
    required String contentType,
  });

  Future<Uint8List?> load(String storagePath);

  Future<void> delete(String storagePath);
}

class FirebaseCirclePhotoRepository implements CirclePhotoRepository {
  FirebaseCirclePhotoRepository(this._storage);

  static const maxBytes = 10 * 1024 * 1024;

  final FirebaseStorage _storage;

  @override
  Future<String> upload({
    required String ownerId,
    required String postId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const CirclePhotoFailure(
        'Choose a photo smaller than 10 MB and try again.',
      );
    }
    if (!const [
      'image/jpeg',
      'image/png',
      'image/webp',
    ].contains(contentType)) {
      throw const CirclePhotoFailure('Choose a JPEG, PNG, or WebP photo.');
    }
    final version = DateTime.now().microsecondsSinceEpoch;
    final path = 'circlePosts/$ownerId/$postId/photo-$version';
    try {
      await _storage
          .ref(path)
          .putData(
            bytes,
            SettableMetadata(
              contentType: contentType,
              customMetadata: {'ownerId': ownerId, 'postId': postId},
            ),
          );
      return path;
    } on FirebaseException catch (error) {
      throw _failure(error, 'upload this photo');
    }
  }

  @override
  Future<Uint8List?> load(String storagePath) async {
    try {
      return await _storage.ref(storagePath).getData(maxBytes);
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return null;
      throw _failure(error, 'load this photo');
    }
  }

  @override
  Future<void> delete(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return;
      throw _failure(error, 'remove this photo');
    }
  }

  CirclePhotoFailure _failure(FirebaseException error, String action) =>
      CirclePhotoFailure(switch (error.code) {
        'unauthorized' =>
          'Readuo could not verify permission to $action. Please retry.',
        'unauthenticated' => 'Sign in again to $action.',
        'canceled' => 'The photo upload was canceled.',
        'retry-limit-exceeded' || 'unknown' =>
          'Readuo could not $action. Check your connection and retry.',
        _ => 'Readuo could not $action. Please retry.',
      });
}

class EmptyCirclePhotoRepository implements CirclePhotoRepository {
  const EmptyCirclePhotoRepository();

  @override
  Future<String> upload({
    required String ownerId,
    required String postId,
    required Uint8List bytes,
    required String contentType,
  }) async => 'circlePosts/$ownerId/$postId/photo';

  @override
  Future<Uint8List?> load(String storagePath) async => null;

  @override
  Future<void> delete(String storagePath) async {}
}
