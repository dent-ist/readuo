import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/account_deletion/deletion_controller.dart';
import 'package:readuo/account_deletion/deletion_models.dart';
import 'package:readuo/account_deletion/local_privacy_cleanup.dart';
import 'p1_19_21_test.dart' show Checkpoints, Backend, Verification;

void main() {
  test(
    'cleanup attempts every private store and reports any failure',
    () async {
      final attempted = <int>[];
      await expectLater(
        clearPrivateData([
          () async {
            attempted.add(1);
            throw StateError('disk full');
          },
          () async {
            attempted.add(2);
          },
          () async {
            attempted.add(3);
            throw StateError('plugin failed');
          },
        ]),
        throwsA(isA<DeletionFailure>()),
      );
      expect(attempted, [1, 2, 3]);
    },
  );

  test(
    'remote deletion cannot show completion before local cleanup succeeds',
    () async {
      final store = Checkpoints();
      final backend = Backend();
      var failCleanup = true;
      final controller = AccountDeletionController(
        uid: 'owner',
        backend: backend,
        store: store,
        reauthentication: Verification(),
        clearLocalData: () => clearPrivateData([
          () async {
            if (failCleanup) throw StateError('disk full');
          },
        ]),
      );
      await controller.initialize();
      controller.acknowledge(true);
      await controller.verifyAndDelete();
      backend.current = DeletionStage.completed;
      await controller.refresh();
      expect(controller.stage, DeletionStage.paused);
      expect(store.value!.completed, true);
      expect(controller.canCancel, false);
      expect(controller.error, contains('Local cleanup is not complete'));
      failCleanup = false;
      await controller.retry();
      expect(controller.stage, DeletionStage.completed);
      expect(backend.starts, 1);
      controller.dispose();
    },
  );

  test(
    'restart retries completed checkpoint cleanup without a new deletion',
    () async {
      final store = Checkpoints()
        ..value = DeletionCheckpoint.create('owner').complete();
      var attempts = 0;
      final controller = AccountDeletionController(
        uid: 'owner',
        backend: Backend(),
        store: store,
        reauthentication: Verification(),
        clearLocalData: () async {
          attempts++;
          if (attempts == 1)
            throw const DeletionFailure('Local cleanup failed.');
        },
      );
      await controller.initialize();
      expect(controller.stage, DeletionStage.paused);
      await controller.retry();
      expect(controller.stage, DeletionStage.completed);
      expect(attempts, 2);
      controller.dispose();
    },
  );
}
