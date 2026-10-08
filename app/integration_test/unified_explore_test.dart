import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/unified_explore_test.dart' show runUnifiedExploreChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('unified Explore on Android', (tester) async {
    await binding.convertFlutterSurfaceToImage();
    await runUnifiedExploreChecks(
      tester,
      capture: (name) async {
        await tester.pumpAndSettle();
        await binding.takeScreenshot(name);
      },
    );
  });
}
