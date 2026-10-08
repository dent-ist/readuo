import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const adb = 'C:/Users/realp/AppData/Local/Android/Sdk/platform-tools/adb.exe';
  final directory = Directory(
    'test/artifacts/shelf-controls${Platform.environment['SHELF_QA_SUFFIX'] ?? ''}',
  );
  await directory.create(recursive: true);
  Future<ProcessResult> device(List<String> args) =>
      Process.run(adb, ['-s', 'emulator-5554', ...args]);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8788);
  await device([
    'shell',
    'pm',
    'grant',
    'com.zipdosa.readuo',
    'android.permission.CAMERA',
  ]);
  final reverse = await device(['reverse', 'tcp:8788', 'tcp:8788']);
  if (reverse.exitCode != 0) throw StateError('Native test bridge unavailable');
  server.listen((request) async {
    if (request.method == 'POST' && request.uri.path == '/back') {
      final result = await device(['shell', 'input', 'keyevent', '4']);
      request.response.statusCode = result.exitCode == 0 ? 200 : 500;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } else if (request.method == 'POST' &&
        RegExp(r'^/capture-[a-z-]+$').hasMatch(request.uri.path)) {
      await device([
        'shell',
        'screencap',
        '-p',
        '/sdcard/readuo-shelf-proof.png',
      ]);
      final name = request.uri.path.substring('/capture-'.length);
      final result = await device([
        'pull',
        '/sdcard/readuo-shelf-proof.png',
        '${directory.path}/$name-native.png',
      ]);
      request.response.statusCode = result.exitCode == 0 ? 200 : 500;
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  });
  try {
    await integrationDriver(
      writeResponseOnFailure: true,
      responseDataCallback: (data) async =>
          File('${directory.path}/manifest.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert(data?['states']),
          ),
      onScreenshot: (name, bytes, [args]) async {
        await File('${directory.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
    );
  } finally {
    await server.close(force: true);
    await device(['reverse', '--remove', 'tcp:8788']);
  }
}
