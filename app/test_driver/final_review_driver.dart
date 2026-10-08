import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

final reviewDirectory =
    Platform.environment['READUO_REVIEW_OUTPUT'] ??
    'test/artifacts/final-review';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final states = data?['reviewStates'];
    if (states == null) return;
    final suffix =
        (states as List).isNotEmpty &&
            (states.first as Map)['physicalWidth'] == 360
        ? '-small-large-text'
        : '';
    await File(
      '$reviewDirectory/manifest${data?['reviewBatch'] == 'refinements' ? '-refinements' : ''}$suffix.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(states));
  },
  onScreenshot: (name, bytes, [args]) async {
    final directory = Directory(reviewDirectory);
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
);
