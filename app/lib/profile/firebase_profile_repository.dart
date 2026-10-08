import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'profile_repository.dart';

class FirebaseProfileRepository implements ProfileRepository {
  FirebaseProfileRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  }) : _auth = auth,
       _firestore = firestore,
       _storage = storage;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  bool _saving = false;

  bool _isOwnerPath(String path, String uid) =>
      RegExp('^profilePhotos/${RegExp.escape(uid)}/[^/]+\$').hasMatch(path);

  Reference? _existingPhoto(String? url, String uid) {
    if (url == null) return null;
    try {
      final reference = _storage.refFromURL(url);
      return reference.bucket == _storage.ref().bucket &&
              _isOwnerPath(reference.fullPath, uid)
          ? reference
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ProfileSaveResult> save({
    required String uid,
    required String displayName,
    ProfilePhoto? photo,
  }) async {
    final name = validatedDisplayName(displayName);
    photo?.validate();
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw const ProfileFailure('Your session expired. Please sign in again.');
    }
    if (_saving)
      throw const ProfileFailure('A profile update is already in progress.');
    _saving = true;
    Reference? uploaded;
    var authChanged = false;
    var committed = false;
    final oldUrl = user.photoURL;
    try {
      final reference = _firestore.collection('readerProfiles').doc(uid);
      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );
      final previous = snapshot.data();
      if (previous == null) {
        throw const ProfileFailure(
          'Your reader profile is not ready. Please reopen your profile and try again.',
        );
      }
      var url = oldUrl;
      Reference? activePhoto = _existingPhoto(oldUrl, uid);
      if (photo != null) {
        final photoId = _firestore.collection('readerProfiles').doc().id;
        uploaded = _storage.ref('profilePhotos/$uid/$photoId');
        await uploaded.putData(
          photo.bytes,
          SettableMetadata(contentType: photo.contentType),
        );
        url = await uploaded.getDownloadURL();
        activePhoto = uploaded;
      }
      if (_auth.currentUser?.uid != uid)
        throw const ProfileFailure(
          'Your session changed. Please sign in again.',
        );
      authChanged = true;
      await user.updateProfile(displayName: name, photoURL: url);
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await _firestore.runTransaction((transaction) async {
            final current = (await transaction.get(reference)).data();
            if (current == null ||
                (current['displayName'] != previous['displayName'] &&
                    current['displayName'] != name) ||
                (current['photoUrl'] != previous['photoUrl'] &&
                    current['photoUrl'] != url) ||
                (current['photoStoragePath'] != previous['photoStoragePath'] &&
                    current['photoStoragePath'] != activePhoto?.fullPath)) {
              throw const ProfileFailure(
                'Your profile changed on another device. Reopen it and try again.',
              );
            }
            transaction.update(reference, {
              'displayName': name,
              'photoUrl': url,
              if (activePhoto != null) 'photoStoragePath': activePhoto.fullPath,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          });
          break;
        } on FirebaseException catch (error) {
          if (attempt == 2 ||
              ![
                'unavailable',
                'deadline-exceeded',
                'aborted',
              ].contains(error.code))
            rethrow;
        }
      }
      committed = true;
      String? warning;
      final previousPath = previous['photoStoragePath'];
      if (activePhoto != null &&
          previousPath is String &&
          _isOwnerPath(previousPath, uid) &&
          previousPath != activePhoto.fullPath) {
        try {
          await _storage.ref(previousPath).delete();
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found')
            warning =
                'Profile saved. The previous photo could not be removed yet.';
        }
      }
      return ProfileSaveResult(name, url, warning: warning);
    } catch (error) {
      if (!committed) {
        if (authChanged) {
          throw const ProfileFailure(
            'Your profile could not finish syncing. Reopen your profile and retry; your photo has been retained.',
          );
        }
        if (uploaded != null) {
          try {
            await uploaded.delete();
          } catch (_) {
            throw const ProfileFailure(
              'Profile was not saved. Photo cleanup is pending; please try again.',
            );
          }
        }
      }
      if (error is ProfileFailure) rethrow;
      throw const ProfileFailure(
        'Could not save your profile. Check your connection and try again.',
      );
    } finally {
      _saving = false;
    }
  }
}
