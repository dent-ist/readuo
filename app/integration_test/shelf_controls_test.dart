import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/shelf_controls_test.dart' show runShelfControlsChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native shelf controls and exact destinations', (tester) async {
    await binding.convertFlutterSurfaceToImage();
    final states = <Map<String, Object?>>[];
    Future<void> bridge(String action) async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:8788/$action'),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
    }

    await runShelfControlsChecks(
      tester,
      capture: (name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        states.add({
          'name': name,
          'width': tester.view.physicalSize.width,
          'height': tester.view.physicalSize.height,
          'keyboardBottom': tester.view.viewInsets.bottom,
        });
        binding.reportData ??= {};
        binding.reportData!['states'] = states;
        await binding.takeScreenshot(name);
        await bridge('capture-$name');
      },
      back: () async {
        await bridge('back');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      },
    );
  });
}
