import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/circle_composer_feedback_test.dart'
    show runCircleComposerFeedbackChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Circle compose feedback on Android', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await binding.convertFlutterSurfaceToImage();
    await runCircleComposerFeedbackChecks(
      tester,
      capture: (name) async {
        if (name.endsWith('-keyboard')) {
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
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(name);
        if (name.endsWith('-keyboard')) {
          final client = HttpClient();
          try {
            final request = await client.postUrl(
              Uri.parse('http://127.0.0.1:8792/keyboard'),
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
      },
    );
  });
}
