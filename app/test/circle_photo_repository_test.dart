import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/circle/photo_repository.dart';

void main() {
  test(
    'camera JPEG uploads with owner/post metadata and the rules path',
    () async {
      final storage = _Storage();
      final repository = FirebaseCirclePhotoRepository(storage);
      final bytes = Uint8List.fromList([255, 216, 255]);
      final path = await repository.upload(
        ownerId: 'owner',
        postId: 'new-post',
        bytes: bytes,
        contentType: 'image/jpeg',
      );
      expect(path, matches(r'^circlePosts/owner/new-post/photo-[0-9]+$'));
      expect(storage.metadata?.contentType, 'image/jpeg');
      expect(storage.metadata?.customMetadata, {
        'ownerId': 'owner',
        'postId': 'new-post',
      });
      expect(storage.bytes, bytes);
    },
  );

  test(
    'server permission denial is not misreported as revoked user access',
    () async {
      final storage = _Storage()..errorCode = 'unauthorized';
      await expectLater(
        FirebaseCirclePhotoRepository(storage).upload(
          ownerId: 'owner',
          postId: 'new-post',
          bytes: Uint8List.fromList([1]),
          contentType: 'image/jpeg',
        ),
        throwsA(
          isA<CirclePhotoFailure>().having(
            (error) => error.message,
            'message',
            'Readuo could not verify permission to upload this photo. Please retry.',
          ),
        ),
      );
    },
  );

  test('expired authentication gets a specific sign-in instruction', () async {
    final storage = _Storage()..errorCode = 'unauthenticated';
    await expectLater(
      FirebaseCirclePhotoRepository(storage).upload(
        ownerId: 'owner',
        postId: 'new-post',
        bytes: Uint8List.fromList([1]),
        contentType: 'image/jpeg',
      ),
      throwsA(
        isA<CirclePhotoFailure>().having(
          (error) => error.message,
          'message',
          'Sign in again to upload this photo.',
        ),
      ),
    );
  });
}

class _Storage implements FirebaseStorage {
  String? errorCode;
  Uint8List? bytes;
  SettableMetadata? metadata;
  @override
  Reference ref([String? path]) => _Reference(this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reference implements Reference {
  _Reference(this.storage);
  @override
  final _Storage storage;
  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    storage.bytes = data;
    storage.metadata = metadata;
    return _Upload(storage.errorCode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Upload implements UploadTask {
  _Upload(this.errorCode);
  final String? errorCode;
  @override
  Future<Result> then<Result>(
    FutureOr<Result> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) =>
      (errorCode == null
              ? Future<TaskSnapshot>.value(_Snapshot())
              : Future<TaskSnapshot>.error(
                  FirebaseException(
                    plugin: 'firebase_storage',
                    code: errorCode!,
                  ),
                ))
          .then(onValue, onError: onError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshot implements TaskSnapshot {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
