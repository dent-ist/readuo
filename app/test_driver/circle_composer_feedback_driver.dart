import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory(
    'test/artifacts/circle-composer-feedback${Platform.environment['CIRCLE_QA_SUFFIX'] ?? ''}',
  );
  await directory.create(recursive: true);
  const adb = 'C:/Users/realp/AppData/Local/Android/Sdk/platform-tools/adb.exe';
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8792);
  try {
    final reverse = await Process.run(adb, ['reverse', 'tcp:8792', 'tcp:8792']);
    if (reverse.exitCode != 0)
      throw StateError('Could not connect keyboard capture bridge.');
    server.listen((request) async {
      if (request.method != 'POST' || request.uri.path != '/keyboard') {
        request.response.statusCode = 404;
      } else {
        await Process.run(adb, [
          'shell',
          'screencap',
          '-p',
          '/sdcard/readuo-compose-keyboard.png',
        ]);
        final result = await Process.run(adb, [
          'pull',
          '/sdcard/readuo-compose-keyboard.png',
          '${directory.path}/composer-keyboard-native.png',
        ]);
        request.response.statusCode = result.exitCode == 0 ? 200 : 500;
      }
      await request.response.close();
    });
    await integrationDriver(
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        await writeResponseData(data);
        await server.close(force: true);
        await Process.run(adb, ['reverse', '--remove', 'tcp:8792']);
      },
      onScreenshot: (name, bytes, [args]) async {
        await File('${directory.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
    );
  } finally {
    await server.close(force: true);
    await Process.run(adb, ['reverse', '--remove', 'tcp:8792']);
  }
}
