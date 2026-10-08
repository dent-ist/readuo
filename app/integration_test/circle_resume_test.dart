import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:readuo/offline/offline_library_controller.dart';
import 'package:readuo/offline/offline_library_cache.dart';
import 'package:readuo/offline/offline_library_screens.dart';
import 'package:readuo/theme/readuo_theme.dart';
import '../test/circle_test.dart' show runCircleEdgeChecks;
import '../test/offline_resume_test.dart' show ResumeProbe;
import '../test/p1_19_21_test.dart' show MemoryCache, shelf;

class ResumeObserver extends WidgetsBindingObserver {
  ResumeObserver(this.controller);
  final OfflineLibraryController controller;
  final events = <String>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    events.add(state.name);
    if (state == AppLifecycleState.resumed) unawaited(controller.resume());
    if (state == AppLifecycleState.paused) controller.suspend();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Circle card edges and native background resume recovery', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final states = <Map<String, Object?>>[];
    Future<void> bridge(String action) async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:8790/$action'),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      states.add({
        'name': name,
        'width': tester.view.physicalSize.width,
        'height': tester.view.physicalSize.height,
      });
      binding.reportData ??= {};
      binding.reportData!['states'] = states;
      await binding.takeScreenshot(name);
      await bridge('capture-$name');
    }

    await runCircleEdgeChecks(tester, capture: capture);
    final probe = ResumeProbe();
    final controller = OfflineLibraryController(
      cache: OfflineLibraryCache(MemoryCache()),
      probe: probe,
      networkRefresh: () => const MethodChannel(
        'com.zipdosa.readuo/settings',
      ).invokeMethod<bool>('networkAvailable'),
    );
    final observer = ResumeObserver(controller);
    binding.addObserver(observer);
    try {
      await controller.selectUser('owner');
      await controller.captureShelves(
        'owner',
        [shelf],
        serverConfirmed: true,
        hasPendingWrites: false,
        complete: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: OfflineLibraryBoundary(
            controller: controller,
            onlineBuilder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Resume verification')),
              body: const Center(
                child: Text(
                  'Online session restored',
                  key: Key('online-session'),
                ),
              ),
            ),
          ),
        ),
      );
      await capture('resume-online-before');
      final old = Completer<void>();
      probe.action = (_) => old.future;
      final pending = controller.checkConnection();
      await tester.pump();
      probe.action = (_) async {};
      await bridge('background-resume');
      await tester.pumpAndSettle();
      old.completeError(TimeoutException('stale suspended request'));
      await pending;
      await tester.pumpAndSettle();
      expect(observer.events, containsAllInOrder(['paused', 'resumed']));
      expect(controller.connection, OfflineConnection.online);
      await capture('resume-online-after');
      probe.action = (_) => throw TimeoutException('transport unavailable');
      controller.networkChanged(false);
      await tester.pump(
        controller.offlineDelay + const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();
      expect(controller.connection, OfflineConnection.offline);
      expect(find.byKey(const Key('online-session')), findsNothing);
      await capture('resume-confirmed-offline');
      probe.action = (_) async {};
      await bridge('background-resume');
      await tester.pumpAndSettle();
      expect(controller.connection, OfflineConnection.online);
      await capture('resume-offline-recovered');
      probe.action = (_) => throw StateError('backend transient');
      await controller.checkConnection();
      expect(controller.connection, OfflineConnection.online);
      await controller.checkConnection();
      expect(controller.connection, OfflineConnection.unavailable);
      await capture('resume-check-delayed');
      probe.action = (_) async {};
      await controller.checkConnection();
      await capture('resume-check-recovered');
      binding.reportData!['lifecycleEvents'] = observer.events;
    } finally {
      binding.removeObserver(observer);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
}
