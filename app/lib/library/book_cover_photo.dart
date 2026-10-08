import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

bool isStoredBookCover(String? path) =>
    path != null &&
    RegExp(
      r'^bookCovers/[A-Za-z0-9_-]{1,128}/[A-Za-z0-9_-]{1,128}/[A-Za-z0-9]{20,64}$',
    ).hasMatch(path);

class BookCoverPhoto {
  BookCoverPhoto(this.bytes) {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024)
      throw ArgumentError('Choose a photo smaller than 5 MB.');
    if (contentType == null) throw ArgumentError('Choose a JPEG or PNG photo.');
  }
  final Uint8List bytes;
  String? get contentType {
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255)
      return 'image/jpeg';
    if (bytes.length >= 8 &&
        base64Encode(bytes.sublist(0, 8)) == 'iVBORw0KGgo=')
      return 'image/png';
    return null;
  }
}

abstract interface class BookCoverStore {
  Future<Uint8List> load(String path);
  Future<void> upload(String path, BookCoverPhoto photo);
  Future<void> delete(String path);
}

class FirebaseBookCoverStore implements BookCoverStore {
  FirebaseBookCoverStore();
  @override
  Future<Uint8List> load(String path) async {
    if (!isStoredBookCover(path)) throw ArgumentError('Invalid cover path.');
    final response = await FirebaseFunctions.instance
        .httpsCallable('loadBookCover')
        .call<Map<String, dynamic>>({'path': path});
    return base64Decode(response.data['bytes'] as String);
  }

  @override
  Future<void> upload(String path, BookCoverPhoto photo) async {
    if (!isStoredBookCover(path)) throw ArgumentError('Invalid cover path.');
    await FirebaseStorage.instance
        .ref(path)
        .putData(
          photo.bytes,
          SettableMetadata(
            contentType: photo.contentType,
            customMetadata: {'ownerId': path.split('/')[1]},
          ),
        );
  }

  @override
  Future<void> delete(String path) async {
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }
}
