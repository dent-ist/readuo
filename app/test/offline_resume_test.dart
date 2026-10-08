import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/offline/offline_library_cache.dart';
import 'package:readuo/offline/offline_library_controller.dart';
import 'package:readuo/offline/offline_library_screens.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'p1_19_21_test.dart' show MemoryCache, shelf;

class ResumeProbe implements OfflineServerProbe {
  Future<void> Function(String) action = (_) async {};
  int calls = 0;
  @override
  Future<void> check(String uid) {
    calls++;
    return action(uid);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('handoff preserves editor and delays the reconnect notice', (
    tester,
  ) async {
    await runReconnectChecks(tester);
  });
  testWidgets(
    'overlapping network checks and UID switch discard late authorization results',
    (tester) async {
      final probe = ResumeProbe();
      final controller = OfflineLibraryController(
        cache: OfflineLibraryCache(MemoryCache()),
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
      final stale = Completer<void>();
      probe.action = (_) => stale.future;
      final old = controller.checkConnection();
      await tester.pump();
      probe.action = (_) async {};
      controller.networkChanged(false);
      controller.networkChanged(true);
      await controller.checkConnection();
      stale.completeError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await old;
      expect(controller.connection, OfflineConnection.online);
      expect(controller.snapshot!.shelves, hasLength(1));
      final formerUser = Completer<void>();
      probe.action = (uid) =>
          uid == 'owner' ? formerUser.future : Future.value();
      final former = controller.checkConnection();
      await tester.pump();
      await controller.selectUser('next');
      formerUser.complete();
      await former;
      expect(controller.snapshot!.userId, 'next');
      expect(controller.snapshot!.shelves, isEmpty);
      expect(controller.connection, OfflineConnection.online);
      controller.dispose();
    },
  );
  testWidgets(
    'resume replaces hung checks and stale permission failure cannot erase cache',
    (tester) async {
      final probe = ResumeProbe();
      final memory = MemoryCache();
      var refreshes = 0;
      final controller = OfflineLibraryController(
        cache: OfflineLibraryCache(memory),
        probe: probe,
        networkRefresh: () async {
          refreshes++;
          return true;
        },
      );
      await controller.selectUser('owner');
      await controller.captureShelves(
        'owner',
        [shelf],
        serverConfirmed: true,
        hasPendingWrites: false,
        complete: true,
      );
      final old = Completer<void>();
      probe.action = (_) => old.future;
      final pending = controller.checkConnection();
      await tester.pump();
      controller.suspend();
      final count = probe.calls;
      await tester.pump(const Duration(seconds: 30));
      expect(probe.calls, count);
      probe.action = (_) async {};
      await controller.resume();
      expect(refreshes, 1);
      expect(controller.connection, OfflineConnection.online);
      old.completeError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await pending;
      expect(controller.snapshot!.shelves.single.id, shelf.id);
      expect(memory.values, isNotEmpty);
      controller.dispose();
    },
  );

  testWidgets(
    'timeouts and backend errors are not offline and synchronous failures do not latch',
    (tester) async {
      final probe = ResumeProbe();
      final memory = MemoryCache();
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
      for (final error in [
        TimeoutException('delayed'),
        StateError('backend'),
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded'),
      ]) {
        probe.action = (_) => throw error;
        expect(
          await controller.checkConnection(),
          OfflineConnection.unavailable,
        );
        expect(controller.connection, OfflineConnection.online);
        expect(
          await controller.checkConnection(),
          OfflineConnection.unavailable,
        );
        expect(controller.connection, OfflineConnection.online);
        await tester.pump(controller.offlineDelay);
        expect(controller.connection, OfflineConnection.unavailable);
        expect(controller.snapshot!.shelves, hasLength(1));
        expect(memory.values, isNotEmpty);
        await expectLater(
          controller.requireOnline(),
          throwsA(isA<OfflineActionException>()),
        );
        probe.action = (_) async {};
        await tester.pump(controller.retryDelay);
        await tester.pump();
        expect(controller.connection, OfflineConnection.online);
      }
      controller.dispose();
    },
  );

  testWidgets(
    'hung foreground probe times out neutrally and retries without restart',
    (tester) async {
      final probe = ResumeProbe();
      final controller = OfflineLibraryController(
        cache: OfflineLibraryCache(MemoryCache()),
        probe: probe,
      );
      await controller.selectUser('owner');
      final hang = Completer<void>();
      probe.action = (_) => hang.future;
      final check = controller.checkConnection();
      await tester.pump();
      await tester.pump(controller.probeTimeout);
      expect(await check, OfflineConnection.unavailable);
      expect(controller.connection, OfflineConnection.online);
      probe.action = (_) async {};
      await tester.pump(controller.retryDelay);
      await tester.pump();
      expect(controller.connection, OfflineConnection.online);
      hang.complete();
      controller.dispose();
    },
  );

  testWidgets(
    'brief false signal does not flash offline; settled loss removes social then actively recovers',
    (tester) async {
      final probe = ResumeProbe();
      final controller = OfflineLibraryController(
        cache: OfflineLibraryCache(MemoryCache()),
        probe: probe,
      );
      await controller.selectUser('owner');
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineLibraryBoundary(
            controller: controller,
            onlineBuilder: (_) => const Text('Social online'),
          ),
        ),
      );
      controller.networkChanged(false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Social online'), findsOneWidget);
      controller.networkChanged(true);
      await tester.pumpAndSettle();
      expect(find.text('Social online'), findsOneWidget);
      probe.action = (_) =>
          Future.error(TimeoutException('network disconnected'));
      controller.networkChanged(false);
      await tester.pump(controller.offlineDelay);
      await tester.pumpAndSettle();
      expect(controller.connection, OfflineConnection.offline);
      expect(find.text('Social online'), findsNothing);
      probe.action = (_) async {};
      await tester.pump(controller.retryDelay);
      await tester.pumpAndSettle();
      expect(controller.connection, OfflineConnection.online);
      expect(find.text('Social online'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'permission/auth block immediately, generic failure retains cache, logout cancels refresh',
    (tester) async {
      final probe = ResumeProbe();
      final refresh = Completer<bool?>();
      final controller = OfflineLibraryController(
        cache: OfflineLibraryCache(MemoryCache()),
        probe: probe,
        networkRefresh: () => refresh.future,
      );
      await controller.selectUser('owner');
      for (final code in ['permission-denied', 'unauthenticated']) {
        probe.action = (_) => Future.error(
          FirebaseException(plugin: 'cloud_firestore', code: code),
        );
        expect(await controller.checkConnection(), OfflineConnection.blocked);
        expect(controller.canShowOnline, isFalse);
        probe.action = (_) async {};
        await controller.checkConnection();
      }
      final pending = controller.resume();
      await controller.clearSession();
      refresh.complete(true);
      await pending;
      expect(controller.userId, isNull);
      expect(controller.snapshot, isNull);
      expect(controller.connection, OfflineConnection.blocked);
      controller.suspend();
      await controller.resume();
      await controller.selectUser('different-user');
      expect(controller.connection, OfflineConnection.online);
      expect(controller.snapshot!.userId, 'different-user');
      controller.dispose();
    },
  );
}

Future<void> runReconnectChecks(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  final probe = ResumeProbe();
  final controller = OfflineLibraryController(
    cache: OfflineLibraryCache(MemoryCache()),
    probe: probe,
  );
  await controller.selectUser('owner');
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: OfflineLibraryBoundary(
        controller: controller,
        onlineBuilder: (_) => Scaffold(
          appBar: AppBar(title: const Text('New post')),
          body: const Padding(
            padding: EdgeInsets.all(16),
            child: TextField(key: Key('handoff-draft'), maxLines: 5),
          ),
        ),
      ),
    ),
  );
  await tester.enterText(
    find.byKey(const Key('handoff-draft')),
    'Keep my draft while reconnecting.',
  );
  final editor = tester.element(find.byKey(const Key('handoff-draft')));
  probe.action = (_) => Future.error(TimeoutException('handoff'));
  controller.networkChanged(false);
  await tester.pump(const Duration(seconds: 4));
  expect(find.text('Reconnecting…'), findsNothing);
  await expectLater(
    controller.requireOnline(),
    throwsA(isA<OfflineActionException>()),
  );
  probe.action = (_) async {};
  controller.networkChanged(true);
  await tester.pumpAndSettle();
  expect(find.text('Reconnecting…'), findsNothing);
  expect(tester.element(find.byKey(const Key('handoff-draft'))), same(editor));
  if (capture != null) await capture('handoff-recovered-silently');
  probe.action = (_) => Future.error(TimeoutException('longer outage'));
  controller.networkChanged(false);
  await tester.pump(controller.reconnectNoticeDelay);
  await tester.pump();
  expect(find.text('Reconnecting…'), findsOneWidget);
  expect(find.text('Keep my draft while reconnecting.'), findsOneWidget);
  expect(tester.element(find.byKey(const Key('handoff-draft'))), same(editor));
  if (capture != null) await capture('handoff-reconnecting');
  controller.networkChanged(true);
  await tester.pump();
  expect(find.text('Reconnecting…'), findsOneWidget);
  probe.action = (_) async {};
  await controller.checkConnection();
  await tester.pumpAndSettle();
  expect(find.text('Reconnecting…'), findsNothing);
  expect(tester.element(find.byKey(const Key('handoff-draft'))), same(editor));
  if (capture != null) await capture('handoff-restored');
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
}
