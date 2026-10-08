import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'profile_repository.dart';

class CallableProfileRepository implements ProfileRepository {
  CallableProfileRepository({
    required FirebaseAuth auth,
    required FirebaseStorage storage,
    FirebaseFunctions? functions,
  }) : _auth = auth,
       _storage = storage,
       _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  bool _saving = false;
  void _requireUser(String uid) {
    if (_auth.currentUser?.uid != uid)
      throw const ProfileFailure('Your session changed. Sign in again.');
  }

  @override
  Future<ProfileSaveResult> save({
    required String uid,
    required String displayName,
    ProfilePhoto? photo,
  }) async {
    final name = validatedDisplayName(displayName);
    photo?.validate();
    _requireUser(uid);
    if (_saving)
      throw const ProfileFailure('A profile update is already in progress.');
    _saving = true;
    try {
      String? path;
      if (photo != null) {
        final reservation = await _functions
            .httpsCallable('reserveProfilePhoto')
            .call<Map<String, dynamic>>({});
        path = reservation.data['path'] as String;
        if (!RegExp(
          '^profilePhotos/${RegExp.escape(uid)}/[A-Za-z0-9]{20,64}\$',
        ).hasMatch(path))
          throw const ProfileFailure('Invalid upload destination.');
        _requireUser(uid);
        await _storage
            .ref(path)
            .putData(
              photo.bytes,
              SettableMetadata(
                contentType: photo.contentType,
                customMetadata: {'ownerId': uid, 'readuoManaged': 'v2'},
              ),
            );
      }
      _requireUser(uid);
      final response = await _functions
          .httpsCallable(
            'saveReaderProfile',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
          )
          .call<Map<String, dynamic>>({
            'displayName': name,
            if (path != null) 'path': path,
          });
      _requireUser(uid);
      await _auth.currentUser!.reload();
      return ProfileSaveResult(
        response.data['displayName'] as String,
        response.data['photoUrl'] as String?,
      );
    } on FirebaseException catch (error) {
      throw ProfileFailure(
        error.code == 'permission-denied' || error.code == 'unauthenticated'
            ? 'This account is unavailable. Sign in again.'
            : 'Your profile could not finish syncing. Your draft is retained; retry to recover.',
      );
    } finally {
      _saving = false;
    }
  }
}
