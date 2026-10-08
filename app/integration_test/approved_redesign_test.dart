import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/approved_redesign_test.dart' show runApprovedRedesignChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('approved redesign rendered on Android', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await binding.convertFlutterSurfaceToImage();
    await runApprovedRedesignChecks(
      tester,
      capture: (name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(name);
      },
    );
  });
}
