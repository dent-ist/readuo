import 'dart:typed_data';

class ProfileFailure implements Exception {
  const ProfileFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProfilePhoto {
  ProfilePhoto(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;

  void validate() {
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    final png =
        bytes.length >= 8 &&
        bytes.take(8).join(',') == '137,80,78,71,13,10,26,10';
    if (bytes.isEmpty ||
        bytes.length > 5 * 1024 * 1024 ||
        !(contentType == 'image/jpeg' && jpeg ||
            contentType == 'image/png' && png)) {
      throw const ProfileFailure(
        'Choose a JPEG or PNG photo smaller than 5 MB.',
      );
    }
  }
}

String validatedDisplayName(String value) {
  final name = value.trim();
  if (name.isEmpty || name.length > 80) {
    throw const ProfileFailure('Enter a display name of 1–80 characters.');
  }
  return name;
}

class ProfileSaveResult {
  const ProfileSaveResult(this.displayName, this.photoUrl, {this.warning});
  final String displayName;
  final String? photoUrl;
  final String? warning;
}

abstract interface class ProfileRepository {
  Future<ProfileSaveResult> save({
    required String uid,
    required String displayName,
    ProfilePhoto? photo,
  });
}

class UnavailableProfileRepository implements ProfileRepository {
  const UnavailableProfileRepository();
  @override
  Future<ProfileSaveResult> save({
    required String uid,
    required String displayName,
    ProfilePhoto? photo,
  }) async {
    throw const ProfileFailure(
      'Profile editing is currently unavailable. Please try again later.',
    );
  }
}
