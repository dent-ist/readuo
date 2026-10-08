import 'package:cloud_functions/cloud_functions.dart';
import 'deletion_models.dart';

class FirebaseDeletionBackend implements DeletionBackend {
  FirebaseDeletionBackend(this.functions, this.reauthentication);
  final FirebaseFunctions functions;
  final DeletionReauthentication reauthentication;

  Future<DeletionResult> _call(String name, Map<String, Object> data) async {
    try {
      final result = await functions
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data)
          .timeout(const Duration(seconds: 20));
      return switch (result.data['status']) {
        'complete' => const DeletionResult(DeletionStage.completed),
        'processing' => const DeletionResult(DeletionStage.processing),
        'not-started' => const DeletionResult(DeletionStage.acknowledgement),
        _ => throw const DeletionFailure(
          'Deletion status is unavailable. Please retry.',
        ),
      };
    } on FirebaseFunctionsException {
      throw const DeletionFailure(
        'Could not confirm deletion. Check your connection and retry.',
      );
    }
  }

  @override
  Future<DeletionResult> start(DeletionCheckpoint checkpoint) =>
      _call('startAccountDeletion', {'confirmed': true});
  @override
  Future<DeletionResult> status(DeletionCheckpoint checkpoint) =>
      _call('getAccountDeletionStatus', {});
  @override
  Future<DeletionResult> retry(DeletionCheckpoint checkpoint) async {
    final current = await status(checkpoint);
    if (current.stage != DeletionStage.acknowledgement) return current;
    await reauthentication.verifyGoogle(checkpoint.uid);
    return start(checkpoint);
  }
}
