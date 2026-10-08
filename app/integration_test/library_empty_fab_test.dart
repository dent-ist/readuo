import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/library_empty_fab_test.dart' show runEmptyLibraryFabChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('empty Library and contextual actions on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    await runEmptyLibraryFabChecks(
      tester,
      capture: (name) async {
        await tester.pumpAndSettle();
        await binding.takeScreenshot(name);
      },
    );
  });
}
