import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory(
    'test/artifacts/notification-experience${Platform.environment['NOTIFICATION_QA_SUFFIX'] ?? ''}',
  );
  await directory.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async =>
        File('${directory.path}/manifest.json').writeAsString(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({'states': data?['states']}),
        ),
    onScreenshot: (name, bytes, [args]) async {
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
