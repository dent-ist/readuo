import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/batch_book_entry_test.dart' show runBatchBookEntryChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('batch book entry on Android', (tester) async {
    await binding.convertFlutterSurfaceToImage();
    await runBatchBookEntryChecks(
      tester,
      capture: (name) async {
        await tester.pumpAndSettle();
        await binding.takeScreenshot(name);
      },
    );
  });
}
