import 'package:flutter/foundation.dart';

import 'deletion_models.dart';

class AccountDeletionController extends ChangeNotifier {
  AccountDeletionController({
    required this.uid,
    required this.backend,
    required this.store,
    required this.reauthentication,
    this.clearLocalData,
  });
  final String uid;
  final DeletionBackend backend;
  final DeletionCheckpointStore store;
  final DeletionReauthentication reauthentication;
  final Future<void> Function()? clearLocalData;
  DeletionStage stage = DeletionStage.acknowledgement;
  String? error;
  bool busy = false;
  bool initialized = false;
  DeletionCheckpoint? _checkpoint;
  bool _disposed = false;
  bool get canCancel =>
      initialized &&
      !busy &&
      _checkpoint == null &&
      stage != DeletionStage.completed;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (initialized || busy) return;
    busy = true;
    _emit();
    try {
      _checkpoint = await store.read();
      if (_checkpoint != null && _checkpoint!.uid != uid) {
        await store.clear();
        _checkpoint = null;
      }
      initialized = true;
      if (_checkpoint != null) {
        if (_checkpoint!.uid != uid)
          throw const DeletionFailure(
            'A deletion request for another account is pending. Restore that request before continuing.',
          );
        stage = DeletionStage.processing;
        if (_checkpoint!.completed) {
          await _finishLocalCleanup();
        } else {
          await _apply(await backend.status(_checkpoint!));
        }
      } else {
        final checkpoint = DeletionCheckpoint.create(uid);
        final result = await backend.status(checkpoint);
        if (result.stage == DeletionStage.processing ||
            result.stage == DeletionStage.completed) {
          await store.write(checkpoint);
          _checkpoint = checkpoint;
          await _apply(result);
        }
      }
      initialized = true;
    } catch (failure) {
      stage = DeletionStage.paused;
      error = _message(failure);
    } finally {
      busy = false;
      _emit();
    }
  }

  void acknowledge(bool accepted) {
    if (!canCancel) return;
    if (!accepted) {
      error = 'Please confirm that you understand before continuing.';
    } else {
      stage = DeletionStage.verification;
      error = null;
    }
    _emit();
  }

  Future<void> verifyAndDelete() async {
    if (busy ||
        !initialized ||
        stage != DeletionStage.verification ||
        _checkpoint != null)
      return;
    busy = true;
    error = null;
    _emit();
    try {
      await reauthentication.verifyGoogle(uid);
      final checkpoint = DeletionCheckpoint.create(uid);
      await store.write(checkpoint);
      _checkpoint = checkpoint;
      stage = DeletionStage.processing;
      _emit();
      await _apply(await backend.start(checkpoint));
    } catch (failure) {
      stage = _checkpoint == null
          ? DeletionStage.verification
          : DeletionStage.paused;
      error = _message(failure);
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> refresh() async {
    if (busy || _checkpoint == null || stage != DeletionStage.processing)
      return;
    await _request(() => backend.status(_checkpoint!));
  }

  Future<void> retry() async {
    if (busy || stage != DeletionStage.paused) return;
    if (_checkpoint?.completed == true) {
      busy = true;
      error = null;
      stage = DeletionStage.processing;
      _emit();
      try {
        await _finishLocalCleanup();
      } catch (failure) {
        stage = DeletionStage.paused;
        error = _message(failure);
      } finally {
        busy = false;
        _emit();
      }
      return;
    }
    if (!initialized) {
      await initialize();
      return;
    }
    if (_checkpoint == null) {
      stage = DeletionStage.acknowledgement;
      error = null;
      _emit();
      return;
    }
    await _request(() => backend.retry(_checkpoint!));
  }

  Future<void> _request(Future<DeletionResult> Function() action) async {
    busy = true;
    error = null;
    stage = DeletionStage.processing;
    _emit();
    try {
      await _apply(await action());
    } catch (failure) {
      stage = DeletionStage.paused;
      error = _message(failure);
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> _apply(DeletionResult result) async {
    if (result.stage == DeletionStage.acknowledgement) {
      await store.clear();
      _checkpoint = null;
      stage = DeletionStage.verification;
      error = 'Deletion has not started. Verify with Google to continue.';
      return;
    }
    if (![
      DeletionStage.processing,
      DeletionStage.paused,
      DeletionStage.completed,
    ].contains(result.stage))
      throw const DeletionFailure(
        'Deletion status could not be confirmed. Please retry.',
      );
    if (result.stage == DeletionStage.completed) {
      final completed = _checkpoint!.complete();
      await store.write(completed);
      _checkpoint = completed;
      await _finishLocalCleanup();
      return;
    }
    stage = result.stage;
    error = result.message;
  }

  Future<void> _finishLocalCleanup() async {
    await clearLocalData?.call();
    stage = DeletionStage.completed;
    error = null;
  }

  Future<void> returnToSignIn(Future<void> Function() onReturnToSignIn) async {
    if (busy || stage != DeletionStage.completed) return;
    busy = true;
    error = null;
    _emit();
    try {
      await onReturnToSignIn();
      await store.clear();
    } catch (_) {
      error =
          'Your account is deleted, but this device could not finish signing out. Please retry.';
    } finally {
      busy = false;
      _emit();
    }
  }

  String _message(Object failure) => failure is DeletionFailure
      ? failure.message
      : 'We could not confirm deletion status. Please retry or contact support.';
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
