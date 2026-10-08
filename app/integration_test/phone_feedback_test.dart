import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/phone_feedback_test.dart' show runPhoneNavigationChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('phone feedback rendered navigation and native Android Back', (
    tester,
  ) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await binding.convertFlutterSurfaceToImage();
    final states = <Map<String, Object?>>[];
    var backCount = 0;
    Future<void> capture(String id) async {
      if (id.endsWith('-keyboard')) {
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pump(const Duration(milliseconds: 500));
        await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        for (
          var attempt = 0;
          tester.view.viewInsets.bottom == 0 && attempt < 30;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.view.viewInsets.bottom, greaterThan(0));
      }
      await tester.pumpAndSettle();
      if (id.endsWith('-keyboard-action')) {
        expect(tester.view.viewInsets.bottom, greaterThan(0));
      }
      expect(tester.takeException(), isNull);
      states.add({
        'id': id,
        'error': null,
        'width': tester.view.physicalSize.width,
        'height': tester.view.physicalSize.height,
        'systemBottom': tester.view.viewPadding.bottom,
        'keyboardBottom': tester.view.viewInsets.bottom,
      });
      binding.reportData ??= {};
      binding.reportData!['phoneStates'] = states;
      await binding.takeScreenshot(id);
      if (id.contains('-keyboard')) {
        final kind = id.contains('friends')
            ? 'friends'
            : id.endsWith('-action')
            ? 'compose-action'
            : 'compose';
        final client = HttpClient();
        try {
          final request = await client.postUrl(
            Uri.parse('http://127.0.0.1:8789/keyboard-$kind'),
          );
          final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
          expect(response.statusCode, 200);
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      }
    }

    await runPhoneNavigationChecks(
      tester,
      capture: capture,
      nativeBack: () async {
        await capture('native-back-trigger-${backCount++}');
        final client = HttpClient();
        try {
          final request = await client.postUrl(
            Uri.parse('http://127.0.0.1:8789/native-back'),
          );
          final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
          expect(response.statusCode, 200);
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      },
    );
  });
}
