import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_repository.dart';

const supportEmail = String.fromEnvironment(
  'SUPPORT_EMAIL',
  defaultValue: 'plogramer.dev@gmail.com',
);

class SupportDraft {
  SupportDraft({
    required String subject,
    required String message,
    required this.requestId,
  }) : subject = subject.trim(),
       message = message.trim();
  final String subject;
  final String message;
  final String requestId;
  void validate() {
    if (subject.isEmpty ||
        subject.length > 120 ||
        message.isEmpty ||
        message.length > 5000) {
      throw const ProfileFailure(
        'Add a subject (1–120 characters) and message (1–5000 characters).',
      );
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId))
      throw const ProfileFailure('Please reopen the support form.');
  }

  static String newRequestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

abstract interface class SupportRepository {
  Future<void> submit(SupportDraft draft);
}

class UnavailableSupportRepository implements SupportRepository {
  const UnavailableSupportRepository();
  @override
  Future<void> submit(SupportDraft draft) async => throw const ProfileFailure(
    'Support submission is currently unavailable. Your message has not been sent.',
  );
}

class SupportRequest {
  const SupportRequest({
    required this.id,
    required this.ownerId,
    required this.subject,
    required this.message,
    required this.status,
    this.createdAt,
  });
  final String id;
  final String ownerId;
  final String subject;
  final String message;
  final String status;
  final DateTime? createdAt;
  factory SupportRequest.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;
    return SupportRequest(
      id: document.id,
      ownerId: data['ownerId'] as String,
      subject: data['subject'] as String,
      message: data['message'] as String,
      status: data['status'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

abstract interface class SupportOperatorRepository {
  Stream<List<SupportRequest>> watchPending();
  Future<void> resolve(String requestId);
}

class FirestoreSupportRepository
    implements SupportRepository, SupportOperatorRepository {
  FirestoreSupportRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) : _auth = auth,
       _firestore = firestore;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  @override
  Future<void> submit(SupportDraft draft) async {
    draft.validate();
    final uid = _auth.currentUser?.uid;
    if (uid == null)
      throw const ProfileFailure(
        'Please sign in again before contacting support.',
      );
    final reference = _firestore
        .collection('supportRequests')
        .doc('$uid--${draft.requestId}');
    try {
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(reference);
        if (existing.exists) {
          final data = existing.data()!;
          if (data['ownerId'] != uid ||
              data['subject'] != draft.subject ||
              data['message'] != draft.message) {
            throw const ProfileFailure(
              'This request already exists with different content. Reopen the support form.',
            );
          }
          return;
        }
        transaction.set(reference, {
          'ownerId': uid,
          'subject': draft.subject,
          'message': draft.message,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } on ProfileFailure {
      rethrow;
    } catch (_) {
      throw const ProfileFailure(
        'Submission could not be confirmed. Check your connection and retry.',
      );
    }
  }

  @override
  Stream<List<SupportRequest>> watchPending() => _firestore
      .collection('supportRequests')
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt')
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(SupportRequest.fromDocument).toList(),
      );
  @override
  Future<void> resolve(String requestId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const ProfileFailure('Please sign in again.');
    final reference = _firestore.collection('supportRequests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final data = (await transaction.get(reference)).data();
      if (data == null)
        throw const ProfileFailure('This request no longer exists.');
      if (data['status'] == 'resolved') return;
      transaction.update(reference, {
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': uid,
        'resolutionNote': 'Handled by support',
      });
    });
  }
}
