import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/tab_header_test.dart' show runTabHeaderChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('four main tab headers render consistently on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final states = <Map<String, Object?>>[];
    await runTabHeaderChecks(
      tester,
      capture: (name) async {
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
