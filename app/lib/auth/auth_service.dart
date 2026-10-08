import '../widgets/readuo_image_cache.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

enum AuthProviderKind { google, apple }

enum AuthFailureKind {
  cancelled,
  accountConflict,
  providerDisabled,
  network,
  unavailable,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind, this.message);

  final AuthFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

class AuthUser {
  const AuthUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.providerIds,
  });

  factory AuthUser.fromFirebase(User user) {
    return AuthUser(
      uid: user.uid,
      displayName: user.displayName?.trim(),
      email: user.email,
      photoUrl: user.photoURL,
      providerIds: user.providerData
          .map((provider) => provider.providerId)
          .toSet(),
    );
  }

  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final Set<String> providerIds;

  bool get hasDisplayName => displayName?.isNotEmpty ?? false;
}

class AuthSignInResult {
  const AuthSignInResult({required this.isNewUser});

  final bool isNewUser;
}

abstract interface class AuthService {
  Stream<AuthUser?> get userChanges;
  AuthUser? get currentUser;

  bool needsDisplayName(AuthUser user);
  bool shouldStartFirstBookOnboarding(AuthUser user);
  String? suggestedDisplayName(String uid);
  Future<AuthSignInResult> signIn(AuthProviderKind provider);
  Future<void> updateDisplayName(String displayName);
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService._(this._auth, this._googleSignIn);

  static Future<FirebaseAuthService> create() async {
    GoogleSignIn? googleSignIn;
    if (!kIsWeb) {
      googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();
    }
    return FirebaseAuthService._(FirebaseAuth.instance, googleSignIn);
  }

  final FirebaseAuth _auth;
  final GoogleSignIn? _googleSignIn;
  Future<void> Function()? beforeSignOut;
  final Set<String> _onboardingUserIds = {};
  final Map<String, String> _suggestedNames = {};

  @override
  AuthUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : AuthUser.fromFirebase(user);
  }

  @override
  Stream<AuthUser?> get userChanges => _auth.userChanges().map(
    (user) => user == null ? null : AuthUser.fromFirebase(user),
  );

  @override
  bool needsDisplayName(AuthUser user) {
    return !user.hasDisplayName || _onboardingUserIds.contains(user.uid);
  }

  @override
  bool shouldStartFirstBookOnboarding(AuthUser user) {
    return !user.hasDisplayName || _onboardingUserIds.contains(user.uid);
  }

  @override
  String? suggestedDisplayName(String uid) => _suggestedNames[uid];

  @override
  Future<AuthSignInResult> signIn(AuthProviderKind provider) async {
    try {
      final credential = switch (provider) {
        AuthProviderKind.google => await _signInWithGoogle(),
        AuthProviderKind.apple => throw const AuthFailure(
          AuthFailureKind.providerDisabled,
          'Apple sign-in is deferred until iOS setup is completed.',
        ),
      };
      final isNewUser = credential.additionalUserInfo?.isNewUser ?? false;
      final user = credential.user;
      if (isNewUser && user != null) {
        _onboardingUserIds.add(user.uid);
        final providerName = user.displayName?.trim();
        if (providerName != null && providerName.isNotEmpty) {
          _suggestedNames[user.uid] = providerName;
        }
        await user.updateDisplayName(null);
        await user.reload();
      }
      return AuthSignInResult(isNewUser: isNewUser);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthFailure(
          AuthFailureKind.cancelled,
          'Sign-in was canceled.',
        );
      }
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw const AuthFailure(
          AuthFailureKind.unavailable,
          'Google sign-in is not configured correctly for this app build.',
        );
      }
      throw const AuthFailure(
        AuthFailureKind.unknown,
        'Google sign-in could not be completed. Please try again.',
      );
    } on FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } catch (_) {
      throw const AuthFailure(
        AuthFailureKind.unknown,
        'Sign-in could not be completed. Please try again.',
      );
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    if (kIsWeb) {
      return _auth.signInWithPopup(GoogleAuthProvider());
    }
    final googleUser = await _googleSignIn!.authenticate();
    final googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw const AuthFailure(
        AuthFailureKind.unavailable,
        'Google did not return an identity token. Please try again.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        AuthFailureKind.unavailable,
        'Your session expired. Please sign in again.',
      );
    }
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) {
      throw const AuthFailure(
        AuthFailureKind.unknown,
        'Enter a display name to continue.',
      );
    }
    try {
      await user.updateDisplayName(normalizedName);
      _suggestedNames.remove(user.uid);
      _onboardingUserIds.remove(user.uid);
      await user.reload();
    } on FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      try {
        await beforeSignOut?.call();
      } catch (_) {}
      await _auth.signOut();
      try {
        await ReaduoImageCache.clear();
      } catch (_) {
        // Cache cleanup must not interrupt provider sign-out.
      }
      if (!kIsWeb && _googleSignIn != null) {
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
      }
    } on FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  AuthFailure _mapFirebaseError(FirebaseAuthException error) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return const AuthFailure(
          AuthFailureKind.accountConflict,
          'An account already exists for this email through another provider. '
          'Sign in with that provider first. Readuo never links accounts '
          'automatically.',
        );
      case 'operation-not-allowed':
        return const AuthFailure(
          AuthFailureKind.providerDisabled,
          'This sign-in provider is not enabled for Readuo yet.',
        );
      case 'network-request-failed':
        return const AuthFailure(
          AuthFailureKind.network,
          'Check your connection and try again.',
        );
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'web-context-cancelled':
      case 'canceled':
        return const AuthFailure(
          AuthFailureKind.cancelled,
          'Sign-in was canceled.',
        );
      case 'popup-blocked':
        return const AuthFailure(
          AuthFailureKind.unavailable,
          'Your browser blocked the sign-in window. Allow popups and retry.',
        );
      case 'user-disabled':
        return const AuthFailure(
          AuthFailureKind.unavailable,
          'This account has been disabled. Contact Readuo support.',
        );
      default:
        return const AuthFailure(
          AuthFailureKind.unknown,
          'Authentication failed. Please try again.',
        );
    }
  }
}
