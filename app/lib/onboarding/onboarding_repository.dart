import 'package:cloud_firestore/cloud_firestore.dart';

enum FirstBookOnboardingStatus { notStarted, pending, skipped, completed }

class OnboardingFailure implements Exception {
  const OnboardingFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class OnboardingRepository {
  Future<FirstBookOnboardingStatus> loadFirstBookStatus(String ownerId);

  Future<void> beginFirstBook(String ownerId);

  Future<void> skipFirstBook(String ownerId);

  Future<void> completeFirstBook(String ownerId);
}

class FirebaseOnboardingRepository implements OnboardingRepository {
  FirebaseOnboardingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _reference(String ownerId) =>
      _firestore
          .collection('users')
          .doc(ownerId)
          .collection('onboarding')
          .doc('firstBook');

  @override
  Future<FirstBookOnboardingStatus> loadFirstBookStatus(String ownerId) async {
    try {
      final snapshot = await _reference(ownerId).get();
      final value = snapshot.data()?['status'] as String?;
      return switch (value) {
        'pending' => FirstBookOnboardingStatus.pending,
        'skipped' => FirstBookOnboardingStatus.skipped,
        'completed' => FirstBookOnboardingStatus.completed,
        _ => FirstBookOnboardingStatus.notStarted,
      };
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'restore first-book setup');
    }
  }

  @override
  Future<void> beginFirstBook(String ownerId) async {
    final reference = _reference(ownerId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (snapshot.exists) return;
        transaction.set(reference, {
          'ownerId': ownerId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'start first-book setup');
    }
  }

  @override
  Future<void> skipFirstBook(String ownerId) =>
      _finish(ownerId, status: 'skipped');

  @override
  Future<void> completeFirstBook(String ownerId) =>
      _finish(ownerId, status: 'completed');

  Future<void> _finish(String ownerId, {required String status}) async {
    final reference = _reference(ownerId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (snapshot.exists) {
          transaction.update(reference, {
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        transaction.set(reference, {
          'ownerId': ownerId,
          'status': status,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'finish first-book setup');
    }
  }

  OnboardingFailure _mapError(
    FirebaseException error, {
    required String action,
  }) => switch (error.code) {
    'unauthenticated' => const OnboardingFailure(
      'Your session expired. Sign in again to continue.',
    ),
    'permission-denied' => OnboardingFailure(
      'Readuo could not $action because access was denied. Please retry.',
    ),
    'unavailable' => OnboardingFailure(
      'Readuo cannot $action while offline. Check your connection and retry.',
    ),
    _ => OnboardingFailure('Readuo could not $action. Please retry.'),
  };
}

class EmptyOnboardingRepository implements OnboardingRepository {
  const EmptyOnboardingRepository();

  @override
  Future<void> beginFirstBook(String ownerId) async {}

  @override
  Future<void> completeFirstBook(String ownerId) async {}

  @override
  Future<FirstBookOnboardingStatus> loadFirstBookStatus(String ownerId) async =>
      FirstBookOnboardingStatus.notStarted;

  @override
  Future<void> skipFirstBook(String ownerId) async {}
}
