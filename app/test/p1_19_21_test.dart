import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/account_deletion/deletion_controller.dart';
import 'package:readuo/account_deletion/deletion_models.dart';
import 'package:readuo/account_deletion/account_deletion_screen.dart';
import 'package:readuo/offline/offline_library_cache.dart';
import 'package:readuo/offline/offline_library_controller.dart';
import 'package:readuo/offline/offline_library_screens.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/library/shelf.dart';
import 'package:readuo/friends/invite_links.dart';

class MemoryCache implements OfflineCacheStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<Set<String>> keys() async => values.keys.toSet();
}

class Probe implements OfflineServerProbe {
  bool online = true;
  Completer<void>? pending;
  @override
  Future<void> check(String uid) async {
    if (pending != null) return pending!.future;
    if (!online) throw TimeoutException('offline');
  }
}

class Checkpoints implements DeletionCheckpointStore {
  DeletionCheckpoint? value;
  @override
  Future<DeletionCheckpoint?> read() async => value;
  @override
  Future<void> write(DeletionCheckpoint checkpoint) async {
    value = checkpoint;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class Verification implements DeletionReauthentication {
  bool cancelled = false;
  int count = 0;
  @override
  Future<void> verifyGoogle(String uid) async {
    count++;
    if (cancelled) throw const DeletionFailure('Cancelled', cancelled: true);
  }
}

class Backend implements DeletionBackend {
  DeletionStage current = DeletionStage.acknowledgement;
  int starts = 0;
  bool failure = false;
  @override
  Future<DeletionResult> start(DeletionCheckpoint checkpoint) async {
    starts++;
    if (failure) throw const DeletionFailure('Offline');
    current = DeletionStage.processing;
    return DeletionResult(current);
  }

  @override
  Future<DeletionResult> status(DeletionCheckpoint checkpoint) async =>
      DeletionResult(current);
  @override
  Future<DeletionResult> retry(DeletionCheckpoint checkpoint) =>
      current == DeletionStage.acknowledgement
      ? start(checkpoint)
      : status(checkpoint);
}

const shelf = Shelf(
  id: 'shelf',
  ownerId: 'owner',
  name: 'Quiet reads',
  visibility: ShelfVisibility.private,
  autoShareActivity: false,
  bookCount: 1,
  createdAt: null,
  updatedAt: null,
);
const book = LibraryBook(
  id: 'book',
  ownerId: 'owner',
  shelfId: 'shelf',
  title: 'Dune',
  author: 'Frank Herbert',
  isbn: null,
  isOwned: true,
  readingStatus: ReadingStatus.reading,
  coverUrl: 'https://example.test/private-photo',
  createdAt: null,
);
Future<OfflineLibraryController> loaded(MemoryCache memory, Probe probe) async {
  final controller = OfflineLibraryController(
    cache: OfflineLibraryCache(memory),
    probe: probe,
  );
  await controller.selectUser('owner');
  await controller.captureShelves(
    'owner',
    [shelf],
    serverConfirmed: true,
    hasPendingWrites: false,
    complete: true,
  );
  await controller.captureBooks(
    'owner',
    [book],
    serverConfirmed: true,
    hasPendingWrites: false,
    complete: true,
  );
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('duplicate available events preserve the online subtree', () async {
    final controller = await loaded(MemoryCache(), Probe());
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.networkChanged(true);
    expect(controller.connection, OfflineConnection.online);
    expect(notifications, 0);
    controller.dispose();
  });
  test(
    'invite parser accepts only the verified host and strict six-character path',
    () {
      expect(inviteCodeFromLink(inviteLink('ABC123')), 'ABC123');
      for (final url in [
        'http://readuo-b2f24.web.app/invite/ABC123',
        'https://evil.test/invite/ABC123',
        'https://readuo-b2f24.web.app/invite/ABC123?uid=other',
        'https://readuo-b2f24.web.app/invite/ABC123#extra',
        'https://readuo-b2f24.web.app/invite/abc123',
        'https://readuo-b2f24.web.app/invite/ABC123/',
        'https://name@readuo-b2f24.web.app/invite/ABC123',
      ]) {
        expect(inviteCodeFromLink(url), isNull);
      }
    },
  );
  test(
    'invite waits through login, duplicate events coalesce, consuming cannot lose newer link',
    () {
      final links = InviteLinks();
      links.accept(inviteLink('ABC123'));
      links.accept(inviteLink('ABC123'));
      expect(links.pendingCode, 'ABC123');
      links.accept(inviteLink('DEF456'));
      links.consume('ABC123');
      expect(links.pendingCode, 'DEF456');
      links.consume('DEF456');
      expect(links.pendingCode, isNull);
      links.dispose();
    },
  );
  test('cache contains only own metadata, never network image URLs', () async {
    final memory = MemoryCache();
    final controller = await loaded(memory, Probe());
    expect(controller.snapshot!.books.single.coverUrl, isNull);
    expect(memory.values.values.single, isNot(contains('https://')));
    await expectLater(
      controller.captureBooks(
        'owner',
        [
          const LibraryBook(
            id: 'foreign',
            ownerId: 'other',
            shelfId: 'shelf',
            title: 'Secret',
            author: 'Other',
            isbn: null,
            isOwned: true,
            readingStatus: ReadingStatus.reading,
            coverUrl: null,
            createdAt: null,
          ),
        ],
        serverConfirmed: true,
        hasPendingWrites: false,
        complete: true,
      ),
      throwsArgumentError,
    );
    controller.dispose();
  });
  test(
    'cached and pending server snapshots never replace verified own library',
    () async {
      final controller = await loaded(MemoryCache(), Probe());
      await controller.captureBooks(
        'owner',
        [],
        serverConfirmed: false,
        hasPendingWrites: false,
        complete: true,
      );
      await controller.captureBooks(
        'owner',
        [],
        serverConfirmed: true,
        hasPendingWrites: true,
        complete: true,
      );
      expect(controller.snapshot!.books.length, 1);
      controller.dispose();
    },
  );
  test(
    'offline restart restores own cache; user switch and signout erase it',
    () async {
      final memory = MemoryCache();
      final first = await loaded(memory, Probe());
      first.dispose();
      final restored = OfflineLibraryController(
        cache: OfflineLibraryCache(memory),
        probe: Probe()..online = false,
      );
      restored.networkChanged(false);
      await restored.selectUser('owner');
      expect(restored.connection, OfflineConnection.offline);
      expect(restored.snapshot!.books.single.title, 'Dune');
      await expectLater(
        restored.requireOnline(),
        throwsA(isA<OfflineActionException>()),
      );
      await restored.selectUser('other');
      expect(restored.snapshot!.books, isEmpty);
      expect(memory.values, isEmpty);
      await restored.clearSession();
      expect(restored.snapshot, isNull);
      restored.dispose();
    },
  );
  test('late connection result cannot resurrect a cleared session', () async {
    final probe = Probe()..pending = Completer<void>();
    final controller = OfflineLibraryController(
      cache: OfflineLibraryCache(MemoryCache()),
      probe: probe,
    );
    final pending = controller.selectUser('owner');
    await Future<void>.delayed(Duration.zero);
    await controller.clearSession();
    probe.pending!.complete();
    await pending;
    expect(controller.canShowOnline, false);
    controller.dispose();
  });
  test(
    'deletion requires acknowledgement and verification, then cannot cancel; completion clears checkpoint',
    () async {
      final store = Checkpoints();
      final backend = Backend();
      final verify = Verification();
      final controller = AccountDeletionController(
        uid: 'owner',
        backend: backend,
        store: store,
        reauthentication: verify,
      );
      await controller.initialize();
      controller.acknowledge(false);
      expect(controller.stage, DeletionStage.acknowledgement);
      controller.acknowledge(true);
      await controller.verifyAndDelete();
      expect(verify.count, 1);
      expect(backend.starts, 1);
      expect(controller.canCancel, false);
      expect(store.value, isNotNull);
      backend.current = DeletionStage.completed;
      await controller.refresh();
      expect(controller.stage, DeletionStage.completed);
      await controller.returnToSignIn(() async {});
      expect(store.value, isNull);
      controller.dispose();
    },
  );
  test(
    'cancelled verification never starts deletion or writes a checkpoint',
    () async {
      final store = Checkpoints();
      final backend = Backend();
      final controller = AccountDeletionController(
        uid: 'owner',
        backend: backend,
        store: store,
        reauthentication: Verification()..cancelled = true,
      );
      await controller.initialize();
      controller.acknowledge(true);
      await controller.verifyAndDelete();
      expect(backend.starts, 0);
      expect(store.value, isNull);
      expect(controller.canCancel, true);
      controller.dispose();
    },
  );
  test(
    'processing marker from another device resumes instead of showing destructive confirmation',
    () async {
      final controller = AccountDeletionController(
        uid: 'owner',
        backend: Backend()..current = DeletionStage.processing,
        store: Checkpoints(),
        reauthentication: Verification(),
      );
      await controller.initialize();
      expect(controller.stage, DeletionStage.processing);
      expect(controller.canCancel, false);
      controller.dispose();
    },
  );
  testWidgets(
    'offline boundary removes social subtree and shows read-only own library',
    (tester) async {
      final probe = Probe();
      final controller = await loaded(MemoryCache(), probe);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineLibraryBoundary(
            controller: controller,
            onlineBuilder: (_) => const Text('Social content'),
          ),
        ),
      );
      expect(find.text('Social content'), findsOneWidget);
      probe.online = false;
      controller.networkChanged(false);
      await tester.pump(controller.offlineDelay);
      await tester.pumpAndSettle();
      expect(find.text('Social content'), findsNothing);
      expect(find.text('Quiet reads'), findsOneWidget);
      await tester.tap(find.text('Quiet reads'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dune'));
      await tester.pumpAndSettle();
      expect(find.text('Offline · Read-only'), findsOneWidget);
      await tester.tap(find.text('Change status'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to make changes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets(
    'deletion warning stays disabled until initial status is restored',
    (tester) async {
      final controller = AccountDeletionController(
        uid: 'owner',
        backend: Backend(),
        store: Checkpoints(),
        reauthentication: Verification(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AccountDeletionScreen(
            controller: controller,
            onReturnToSignIn: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Leave Readuo?'), findsOneWidget);
      expect(find.textContaining('No data is retained'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
