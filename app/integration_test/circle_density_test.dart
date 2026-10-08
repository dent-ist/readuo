import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/circle_test.dart' show runCircleEdgeChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('compact Circle cards and doubled book covers on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final states = <Map<String, Object?>>[];
    await runCircleEdgeChecks(
      tester,
      capture: (name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
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
