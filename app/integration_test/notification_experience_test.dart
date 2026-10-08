import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/notification_experience_test.dart'
    show runNotificationExperienceChecks;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('notification experience and round shelf action on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final states = <Map<String, Object?>>[];
    await runNotificationExperienceChecks(
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
