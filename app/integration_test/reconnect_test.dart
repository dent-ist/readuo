import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/offline_resume_test.dart' show runReconnectChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('silent network handoff and delayed reconnect notice', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    await runReconnectChecks(
      tester,
      capture: (name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(name);
      },
    );
  });
}
