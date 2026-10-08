import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'deletion_models.dart';

class GoogleDeletionCredential {
  const GoogleDeletionCredential({
    required this.providerUid,
    required this.credential,
  });
  final String providerUid;
  final AuthCredential credential;
}

class FirebaseGoogleDeletionReauthentication
    implements DeletionReauthentication {
  FirebaseGoogleDeletionReauthentication({
    required FirebaseAuth auth,
    Future<GoogleDeletionCredential> Function()? acquireCredential,
  }) : _auth = auth,
       _acquireCredential = acquireCredential ?? _googleCredential;
  final FirebaseAuth _auth;
  final Future<GoogleDeletionCredential> Function() _acquireCredential;

  static Future<GoogleDeletionCredential> _googleCredential() async {
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null)
      throw const DeletionFailure(
        'Google verification did not complete. Please try again.',
      );
    return GoogleDeletionCredential(
      providerUid: account.id,
      credential: GoogleAuthProvider.credential(idToken: token),
    );
  }

  @override
  Future<void> verifyGoogle(String expectedUid) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != expectedUid)
      throw const DeletionFailure(
        'Your account changed. Return to your account and try again.',
      );
    final googleProfiles = user.providerData.where(
      (provider) => provider.providerId == 'google.com',
    );
    if (googleProfiles.isEmpty)
      throw const DeletionFailure(
        'This account is not linked to Google. Contact support for help.',
      );
    try {
      final UserCredential result;
      if (kIsWeb) {
        result = await user.reauthenticateWithPopup(
          GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}),
        );
      } else {
        final selected = await _acquireCredential();
        if (!googleProfiles.any(
              (profile) => profile.uid == selected.providerUid,
            ) ||
            _auth.currentUser?.uid != expectedUid) {
          throw const DeletionFailure(
            'Choose the Google account already linked to this Readuo account.',
          );
        }
        result = await user.reauthenticateWithCredential(selected.credential);
      }
      if (result.user?.uid != expectedUid ||
          _auth.currentUser?.uid != expectedUid)
        throw const DeletionFailure(
          'Verification returned a different account. Deletion has not started.',
        );
      await user.getIdToken(true);
      if (_auth.currentUser?.uid != expectedUid)
        throw const DeletionFailure(
          'Your account changed. Deletion has not started.',
        );
    } on DeletionFailure {
      rethrow;
    } on GoogleSignInException catch (failure) {
      final cancelled =
          failure.code == GoogleSignInExceptionCode.canceled ||
          failure.code == GoogleSignInExceptionCode.interrupted;
      throw DeletionFailure(
        cancelled
            ? 'Verification was cancelled. Your account has not been deleted.'
            : 'Google verification failed. Please try again.',
        cancelled: cancelled,
      );
    } on FirebaseAuthException catch (failure) {
      if (failure.code == 'user-mismatch')
        throw const DeletionFailure(
          'Choose the Google account already linked to this Readuo account.',
        );
      throw const DeletionFailure(
        'Could not verify your account. Check your connection and try again.',
      );
    } catch (_) {
      throw const DeletionFailure(
        'Google verification is currently unavailable. Please try again.',
      );
    }
  }
}
