import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/book_addition_notifications_test.dart'
    show runBookAdditionChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('grouped book notification settings and activity on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final states = <Map<String, Object?>>[];
    await runBookAdditionChecks(
      tester,
      capture: (name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        states.add({
          'name': name,
          'width': tester.view.physicalSize.width,
          'height': tester.view.physicalSize.height,
          'textScale': tester.platformDispatcher.textScaleFactor,
        });
        await binding.takeScreenshot(name);
      },
    );
    binding.reportData ??= {};
    binding.reportData!['states'] = states;
  });
}
