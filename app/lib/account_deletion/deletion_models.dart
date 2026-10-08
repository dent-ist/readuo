import 'dart:math';

enum DeletionStage {
  acknowledgement,
  verification,
  processing,
  paused,
  completed,
}

class DeletionFailure implements Exception {
  const DeletionFailure(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

class DeletionCheckpoint {
  const DeletionCheckpoint({
    required this.uid,
    required this.requestId,
    required this.resumeToken,
    this.completed = false,
  });
  final String uid;
  final String requestId;
  final String resumeToken;
  final bool completed;

  factory DeletionCheckpoint.create(String uid) {
    final random = Random.secure();
    String token(int length) => List.generate(
      length,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return DeletionCheckpoint(
      uid: uid,
      requestId: token(16),
      resumeToken: token(32),
    );
  }
  DeletionCheckpoint complete() => DeletionCheckpoint(
    uid: uid,
    requestId: requestId,
    resumeToken: resumeToken,
    completed: true,
  );
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'requestId': requestId,
    'resumeToken': resumeToken,
    'completed': completed,
  };
  factory DeletionCheckpoint.fromJson(Map<String, dynamic> data) {
    final uid = data['uid'];
    final requestId = data['requestId'];
    final token = data['resumeToken'];
    if (uid is! String ||
        uid.isEmpty ||
        requestId is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId) ||
        token is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        data['completed'] is! bool) {
      throw const DeletionFailure(
        'The saved deletion request could not be read. Contact support before trying again.',
      );
    }
    return DeletionCheckpoint(
      uid: uid,
      requestId: requestId,
      resumeToken: token,
      completed: data['completed'] as bool,
    );
  }
}

class DeletionResult {
  const DeletionResult(this.stage, {this.message});
  final DeletionStage stage;
  final String? message;
}

abstract interface class DeletionBackend {
  Future<DeletionResult> start(DeletionCheckpoint checkpoint);
  Future<DeletionResult> status(DeletionCheckpoint checkpoint);
  Future<DeletionResult> retry(DeletionCheckpoint checkpoint);
}

abstract interface class DeletionCheckpointStore {
  Future<DeletionCheckpoint?> read();
  Future<void> write(DeletionCheckpoint checkpoint);
  Future<void> clear();
}

abstract interface class DeletionReauthentication {
  Future<void> verifyGoogle(String expectedUid);
}
