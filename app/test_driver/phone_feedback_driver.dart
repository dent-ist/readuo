import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const adb = 'C:/Users/realp/AppData/Local/Android/Sdk/platform-tools/adb.exe';
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8789);
  await Process.run(adb, [
    '-s',
    'emulator-5554',
    'shell',
    'pm',
    'grant',
    'com.zipdosa.readuo',
    'android.permission.CAMERA',
  ]);
  final reverse = await Process.run(adb, [
    '-s',
    'emulator-5554',
    'reverse',
    'tcp:8789',
    'tcp:8789',
  ]);
  if (reverse.exitCode != 0)
    throw StateError('Could not connect native Back test bridge');
  server.listen((request) async {
    if (request.method == 'POST' &&
        const [
          '/keyboard-compose',
          '/keyboard-compose-action',
          '/keyboard-friends',
        ].contains(request.uri.path)) {
      final directory = Directory(
        'test/artifacts/phone-feedback${Platform.environment['PHONE_QA_SUFFIX'] ?? ''}',
      );
      await directory.create(recursive: true);
      await Process.run(adb, [
        '-s',
        'emulator-5554',
        'shell',
        'screencap',
        '-p',
        '/sdcard/readuo-keyboard-proof.png',
      ]);
      final result = await Process.run(adb, [
        '-s',
        'emulator-5554',
        'pull',
        '/sdcard/readuo-keyboard-proof.png',
        '${directory.path}/${request.uri.path.substring(1)}-native.png',
      ]);
      request.response.statusCode = result.exitCode == 0 ? 200 : 500;
    } else if (request.method != 'POST' || request.uri.path != '/native-back') {
      request.response.statusCode = 404;
    } else {
      final result = await Process.run(adb, [
        '-s',
        'emulator-5554',
        'shell',
        'input',
        'keyevent',
        '4',
      ]);
      request.response.statusCode = result.exitCode == 0 ? 200 : 500;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await request.response.close();
  });
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final directory = Directory(
        'test/artifacts/phone-feedback${Platform.environment['PHONE_QA_SUFFIX'] ?? ''}',
      );
      await directory.create(recursive: true);
      await File('${directory.path}/manifest.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(data?['phoneStates']),
      );
    },
    onScreenshot: (name, bytes, [args]) async {
      final directory = Directory(
        'test/artifacts/phone-feedback${Platform.environment['PHONE_QA_SUFFIX'] ?? ''}',
      );
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
