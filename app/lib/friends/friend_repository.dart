import 'dart:math';
import '../features/online_writes.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/auth_service.dart';

class FriendFailure implements Exception {
  const FriendFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReaderProfile {
  const ReaderProfile({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.inviteCode,
  });

  factory ReaderProfile.fromFirestore(String uid, Map<String, dynamic> data) {
    return ReaderProfile(
      uid: uid,
      displayName: (data['displayName'] as String? ?? 'Reader').trim(),
      photoUrl: (data['photoUrl'] as String?)?.trim(),
      inviteCode: data['inviteCode'] as String? ?? '',
    );
  }

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String inviteCode;

  String get formattedInviteCode => formatInviteCode(inviteCode);
}

class FriendRequestRecord {
  const FriendRequestRecord({
    required this.pairId,
    required this.requesterId,
    required this.recipientId,
    required this.reader,
    required this.createdAt,
  });

  final String pairId;
  final String requesterId;
  final String recipientId;
  final ReaderProfile reader;
  final DateTime? createdAt;
}

class BlockedReader {
  const BlockedReader({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
}

enum InviteLookupKind {
  available,
  self,
  unknown,
  alreadyFriend,
  alreadySent,
  incomingRequest,
  blocked,
}

class InviteLookupResult {
  const InviteLookupResult(this.kind, {this.profile, this.request});

  final InviteLookupKind kind;
  final ReaderProfile? profile;
  final FriendRequestRecord? request;
}

enum SendRequestOutcome { sent, alreadyFriend, alreadySent, incomingRequest }

abstract interface class FriendRepository {
  Future<ReaderProfile> ensureProfile(AuthUser user);
  Stream<List<ReaderProfile>> watchFriends(String userId);
  Stream<List<FriendRequestRecord>> watchIncomingRequests(String userId);
  Stream<List<FriendRequestRecord>> watchSentRequests(String userId);
  Stream<List<BlockedReader>> watchBlockedReaders(String userId);
  Future<InviteLookupResult> findByInviteCode({
    required String userId,
    required String code,
  });
  Future<SendRequestOutcome> sendRequest({
    required String userId,
    required ReaderProfile recipient,
    required String inviteCode,
  });
  Future<void> acceptRequest({
    required String userId,
    required FriendRequestRecord request,
  });
  Future<void> declineRequest({
    required String userId,
    required FriendRequestRecord request,
  });
  Future<void> cancelRequest({
    required String userId,
    required FriendRequestRecord request,
  });
  Future<void> removeFriend({
    required String userId,
    required ReaderProfile friend,
  });
  Future<void> blockReader({
    required String userId,
    required ReaderProfile reader,
  });
  Future<void> unblockReader({
    required String userId,
    required String blockedUserId,
  });
}

abstract interface class PublicReaderQuerySource {
  Stream<ReaderProfile?> watchPublicReaderProfile({
    required String viewerId,
    required String readerId,
  });
}

extension PublicReaderQueries on FriendRepository {
  Stream<ReaderProfile?> watchPublicReaderProfile({
    required String viewerId,
    required String readerId,
  }) {
    final repository = this;
    if (repository is PublicReaderQuerySource) {
      return (repository as PublicReaderQuerySource).watchPublicReaderProfile(
        viewerId: viewerId,
        readerId: readerId,
      );
    }
    return watchFriends(viewerId).map(
      (friends) =>
          friends.where((friend) => friend.uid == readerId).firstOrNull,
    );
  }
}

class FirebaseFriendRepository
    implements FriendRepository, PublicReaderQuerySource {
  FirebaseFriendRepository(this._firestore, {Random? random})
    : _random = random ?? Random.secure();

  final FirebaseFirestore _firestore;

  @override
  Stream<ReaderProfile?> watchPublicReaderProfile({
    required String viewerId,
    required String readerId,
  }) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('readerProfiles')
              .doc(readerId)
              .snapshots(includeMetadataChanges: true)) {
        if (snapshot.metadata.isFromCache) continue;
        final data = snapshot.data();
        yield data == null
            ? null
            : ReaderProfile.fromFirestore(snapshot.id, data);
      }
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'load this reader');
    }
  }

  final Random _random;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection('readerProfiles');
  CollectionReference<Map<String, dynamic>> get _codes =>
      _firestore.collection('inviteCodes');
  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('friendRequests');
  CollectionReference<Map<String, dynamic>> get _friendships =>
      _firestore.collection('friendships');

  @override
  Future<ReaderProfile> ensureProfile(AuthUser user) async {
    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isEmpty) {
      throw const FriendFailure('Add a display name before using Friends.');
    }
    final profileReference = _profiles.doc(user.uid);
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final code = _newCode();
      final codeReference = _codes.doc(code);
      try {
        final profile = await _firestore.runTransaction((transaction) async {
          final existing = await transaction.get(profileReference);
          if (existing.exists) {
            final data = existing.data()!;
            if (data['displayName'] != displayName ||
                data['photoUrl'] != user.photoUrl) {
              transaction.update(profileReference, {
                'displayName': displayName,
                'photoUrl': user.photoUrl,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
            return ReaderProfile.fromFirestore(user.uid, data);
          }
          final reservedCode = await transaction.get(codeReference);
          if (reservedCode.exists) throw const _InviteCodeCollision();
          final profileData = {
            'ownerId': user.uid,
            'displayName': displayName,
            'photoUrl': user.photoUrl,
            'inviteCode': code,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          transaction.set(profileReference, profileData);
          transaction.set(codeReference, {
            'ownerId': user.uid,
            'code': code,
            'createdAt': FieldValue.serverTimestamp(),
          });
          return ReaderProfile(
            uid: user.uid,
            displayName: displayName,
            photoUrl: user.photoUrl,
            inviteCode: code,
          );
        });
        return profile;
      } on _InviteCodeCollision {
        continue;
      } on FirebaseException catch (error) {
        throw _mapError(error, action: 'prepare Friends');
      }
    }
    throw const FriendFailure(
      'Readuo could not reserve an invite code. Please retry.',
    );
  }

  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) async* {
    try {
      await for (final snapshot
          in _friendships
              .where('memberIds', arrayContains: userId)
              .snapshots()) {
        final profiles = await Future.wait(
          snapshot.docs.map((document) async {
            final members = List<String>.from(
              document.data()['memberIds'] as List? ?? const [],
            );
            final friendId = members.firstWhere(
              (member) => member != userId,
              orElse: () => '',
            );
            if (friendId.isEmpty) return null;
            return _loadProfile(friendId);
          }),
        );
        final friends = profiles.whereType<ReaderProfile>().toList()
          ..sort(
            (left, right) => left.displayName.toLowerCase().compareTo(
              right.displayName.toLowerCase(),
            ),
          );
        yield friends;
      }
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'load friends');
    }
  }

  @override
  Stream<List<FriendRequestRecord>> watchIncomingRequests(String userId) =>
      _watchRequests(userId: userId, incoming: true);

  @override
  Stream<List<FriendRequestRecord>> watchSentRequests(String userId) =>
      _watchRequests(userId: userId, incoming: false);

  Stream<List<FriendRequestRecord>> _watchRequests({
    required String userId,
    required bool incoming,
  }) async* {
    final field = incoming ? 'recipientId' : 'requesterId';
    try {
      await for (final snapshot
          in _requests.where(field, isEqualTo: userId).snapshots()) {
        final records = await Future.wait(
          snapshot.docs.map((document) async {
            final data = document.data();
            final otherId = incoming
                ? data['requesterId'] as String? ?? ''
                : data['recipientId'] as String? ?? '';
            final profile = await _loadProfile(otherId);
            if (profile == null) return null;
            return FriendRequestRecord(
              pairId: document.id,
              requesterId: data['requesterId'] as String? ?? '',
              recipientId: data['recipientId'] as String? ?? '',
              reader: profile,
              createdAt: _readDate(data['createdAt']),
            );
          }),
        );
        final requests = records.whereType<FriendRequestRecord>().toList()
          ..sort(
            (left, right) => (right.createdAt ?? DateTime(1970)).compareTo(
              left.createdAt ?? DateTime(1970),
            ),
          );
        yield requests;
      }
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'load friend requests');
    }
  }

  @override
  Stream<List<BlockedReader>> watchBlockedReaders(String userId) async* {
    try {
      await for (final snapshot
          in _firestore
              .collection('blocks')
              .doc(userId)
              .collection('blocked')
              .snapshots()) {
        final readers =
            snapshot.docs
                .map(
                  (document) => BlockedReader(
                    uid: document.id,
                    displayName:
                        document.data()['blockedDisplayName'] as String? ??
                        'Reader',
                    photoUrl: document.data()['blockedPhotoUrl'] as String?,
                  ),
                )
                .toList()
              ..sort(
                (left, right) => left.displayName.toLowerCase().compareTo(
                  right.displayName.toLowerCase(),
                ),
              );
        yield readers;
      }
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'load blocked readers');
    }
  }

  @override
  Future<InviteLookupResult> findByInviteCode({
    required String userId,
    required String code,
  }) async {
    final normalizedCode = normalizeInviteCode(code);
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizedCode)) {
      return const InviteLookupResult(InviteLookupKind.unknown);
    }
    try {
      final codeSnapshot = await _codes.doc(normalizedCode).get();
      if (!codeSnapshot.exists) {
        return const InviteLookupResult(InviteLookupKind.unknown);
      }
      final recipientId = codeSnapshot.data()!['ownerId'] as String? ?? '';
      if (recipientId == userId) {
        return const InviteLookupResult(InviteLookupKind.self);
      }
      final profile = await _loadProfile(recipientId);
      if (profile == null) {
        return const InviteLookupResult(InviteLookupKind.unknown);
      }
      final pair = pairId(userId, recipientId);
      final documents = await Future.wait([
        _friendships.doc(pair).get(),
        _requests.doc(pair).get(),
      ]);
      if (documents[0].exists) {
        return InviteLookupResult(
          InviteLookupKind.alreadyFriend,
          profile: profile,
        );
      }
      if (documents[1].exists) {
        final requestData = documents[1].data()!;
        final incoming = requestData['recipientId'] == userId;
        return InviteLookupResult(
          incoming
              ? InviteLookupKind.incomingRequest
              : InviteLookupKind.alreadySent,
          profile: profile,
          request: FriendRequestRecord(
            pairId: pair,
            requesterId: requestData['requesterId'] as String? ?? '',
            recipientId: requestData['recipientId'] as String? ?? '',
            reader: profile,
            createdAt: _readDate(requestData['createdAt']),
          ),
        );
      }
      return InviteLookupResult(InviteLookupKind.available, profile: profile);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return const InviteLookupResult(InviteLookupKind.blocked);
      }
      throw _mapError(error, action: 'find this reader');
    }
  }

  @override
  Future<SendRequestOutcome> sendRequest({
    required String userId,
    required ReaderProfile recipient,
    required String inviteCode,
  }) async {
    if (recipient.uid == userId) {
      throw const FriendFailure('You cannot send a request to yourself.');
    }
    final normalizedCode = normalizeInviteCode(inviteCode);
    final pair = pairId(userId, recipient.uid);
    final requestReference = _requests.doc(pair);
    try {
      return await _firestore.runTransaction((transaction) async {
        final documents = await Future.wait([
          transaction.get(_friendships.doc(pair)),
          transaction.get(requestReference),
          transaction.get(_codes.doc(normalizedCode)),
        ]);
        if (documents[2].data()?['ownerId'] != recipient.uid) {
          throw const FriendFailure('That invite code is no longer available.');
        }
        if (documents[0].exists) return SendRequestOutcome.alreadyFriend;
        if (documents[1].exists) {
          return documents[1].data()?['recipientId'] == userId
              ? SendRequestOutcome.incomingRequest
              : SendRequestOutcome.alreadySent;
        }
        transaction.set(requestReference, {
          'pairId': pair,
          'requesterId': userId,
          'recipientId': recipient.uid,
          'inviteCode': normalizedCode,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return SendRequestOutcome.sent;
      });
    } on FriendFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'send this request');
    }
  }

  @override
  Future<void> acceptRequest({
    required String userId,
    required FriendRequestRecord request,
  }) async {
    if (request.recipientId != userId) {
      throw const FriendFailure('Only the recipient can accept this request.');
    }
    final requestReference = _requests.doc(request.pairId);
    final friendshipReference = _friendships.doc(request.pairId);
    try {
      await _firestore.runTransaction((transaction) async {
        final currentRequest = await transaction.get(requestReference);
        final friendship = await transaction.get(friendshipReference);
        if (friendship.exists) {
          if (currentRequest.exists) transaction.delete(requestReference);
          return;
        }
        if (!currentRequest.exists) return;
        final data = currentRequest.data()!;
        if (data['recipientId'] != userId) {
          throw const FriendFailure(
            'Only the recipient can accept this request.',
          );
        }
        transaction.delete(requestReference);
        transaction.set(friendshipReference, {
          'pairId': request.pairId,
          'memberIds': [data['requesterId'], data['recipientId']],
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } on FriendFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'accept this request');
    }
  }

  @override
  Future<void> declineRequest({
    required String userId,
    required FriendRequestRecord request,
  }) => _deleteRequest(userId: userId, request: request, incoming: true);

  @override
  Future<void> cancelRequest({
    required String userId,
    required FriendRequestRecord request,
  }) => _deleteRequest(userId: userId, request: request, incoming: false);

  Future<void> _deleteRequest({
    required String userId,
    required FriendRequestRecord request,
    required bool incoming,
  }) async {
    final allowedId = incoming ? request.recipientId : request.requesterId;
    if (allowedId != userId) {
      throw const FriendFailure('This request is no longer available.');
    }
    try {
      await _requests.doc(request.pairId).deleteOnline();
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') return;
      throw _mapError(error, action: 'update this request');
    }
  }

  @override
  Future<void> removeFriend({
    required String userId,
    required ReaderProfile friend,
  }) async {
    try {
      await _friendships.doc(pairId(userId, friend.uid)).deleteOnline();
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') return;
      throw _mapError(error, action: 'remove this friend');
    }
  }

  @override
  Future<void> blockReader({
    required String userId,
    required ReaderProfile reader,
  }) async {
    if (userId == reader.uid) {
      throw const FriendFailure('You cannot block yourself.');
    }
    final pair = pairId(userId, reader.uid);
    try {
      await _firestore.runTransaction((transaction) async {
        final requestReference = _requests.doc(pair);
        final friendshipReference = _friendships.doc(pair);
        final blockReference = _blockReference(userId, reader.uid);
        final documents = await Future.wait([
          transaction.get(requestReference),
          transaction.get(friendshipReference),
          transaction.get(blockReference),
        ]);
        if (documents[0].exists) transaction.delete(requestReference);
        if (documents[1].exists) transaction.delete(friendshipReference);
        if (!documents[2].exists) {
          transaction.set(blockReference, {
            'blockerId': userId,
            'blockedId': reader.uid,
            'pairId': pair,
            'blockedDisplayName': reader.displayName,
            'blockedPhotoUrl': reader.photoUrl,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on FirebaseException catch (error) {
      throw _mapError(error, action: 'block this reader');
    }
  }

  @override
  Future<void> unblockReader({
    required String userId,
    required String blockedUserId,
  }) async {
    try {
      await _blockReference(userId, blockedUserId).deleteOnline();
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') return;
      throw _mapError(error, action: 'unblock this reader');
    }
  }

  Future<ReaderProfile?> _loadProfile(String userId) async {
    if (userId.isEmpty) return null;
    final snapshot = await _profiles.doc(userId).get();
    return snapshot.exists
        ? ReaderProfile.fromFirestore(snapshot.id, snapshot.data()!)
        : null;
  }

  DocumentReference<Map<String, dynamic>> _blockReference(
    String blockerId,
    String blockedId,
  ) => _firestore
      .collection('blocks')
      .doc(blockerId)
      .collection('blocked')
      .doc(blockedId);

  String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(
      6,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  FriendFailure _mapError(FirebaseException error, {required String action}) {
    return switch (error.code) {
      'unauthenticated' => const FriendFailure(
        'Your sign-in session has ended. Sign in again and retry.',
      ),
      'permission-denied' => FriendFailure(
        'Readuo could not $action because access was denied.',
      ),
      'failed-precondition' => const FriendFailure(
        'Friends setup is still preparing. Please retry shortly.',
      ),
      'unavailable' => FriendFailure(
        'Readuo cannot $action while offline. Check your connection.',
      ),
      _ => FriendFailure('Readuo could not $action. Please retry.'),
    };
  }
}

class EmptyFriendRepository implements FriendRepository {
  const EmptyFriendRepository();
  @override
  Future<ReaderProfile> ensureProfile(AuthUser user) async => ReaderProfile(
    uid: user.uid,
    displayName: user.displayName ?? 'Reader',
    photoUrl: user.photoUrl,
    inviteCode: 'ABC123',
  );
  @override
  Stream<List<ReaderProfile>> watchFriends(String userId) =>
      Stream.value(const []);
  @override
  Stream<List<FriendRequestRecord>> watchIncomingRequests(String userId) =>
      Stream.value(const []);
  @override
  Stream<List<FriendRequestRecord>> watchSentRequests(String userId) =>
      Stream.value(const []);
  @override
  Stream<List<BlockedReader>> watchBlockedReaders(String userId) =>
      Stream.value(const []);
  @override
  Future<InviteLookupResult> findByInviteCode({
    required String userId,
    required String code,
  }) async => const InviteLookupResult(InviteLookupKind.unknown);
  @override
  Future<SendRequestOutcome> sendRequest({
    required String userId,
    required ReaderProfile recipient,
    required String inviteCode,
  }) => throw const FriendFailure('Friends storage is unavailable.');
  @override
  Future<void> acceptRequest({
    required String userId,
    required FriendRequestRecord request,
  }) => throw const FriendFailure('Friends storage is unavailable.');
  @override
  Future<void> declineRequest({
    required String userId,
    required FriendRequestRecord request,
  }) => throw const FriendFailure('Friends storage is unavailable.');
  @override
  Future<void> cancelRequest({
    required String userId,
    required FriendRequestRecord request,
  }) => throw const FriendFailure('Friends storage is unavailable.');
  @override
  Future<void> removeFriend({
    required String userId,
    required ReaderProfile friend,
  }) => throw const FriendFailure('Friends storage is unavailable.');
  @override
  Future<void> blockReader({
    required String userId,
    required ReaderProfile reader,
  }) => throw const FriendFailure('Friends storage is unavailable.');
  @override
  Future<void> unblockReader({
    required String userId,
    required String blockedUserId,
  }) => throw const FriendFailure('Friends storage is unavailable.');
}

String pairId(String firstUserId, String secondUserId) {
  final users = [firstUserId, secondUserId]..sort();
  return '${users[0]}--${users[1]}';
}

String normalizeInviteCode(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String formatInviteCode(String value) {
  final normalized = normalizeInviteCode(value);
  if (normalized.length <= 3) return normalized;
  return '${normalized.substring(0, 3)}-${normalized.substring(3)}';
}

DateTime? _readDate(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

class _InviteCodeCollision implements Exception {
  const _InviteCodeCollision();
}
