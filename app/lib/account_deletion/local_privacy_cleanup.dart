import 'deletion_models.dart';

Future<void> clearPrivateData(
  Iterable<Future<void> Function()> operations,
) async {
  var failed = false;
  for (final operation in operations) {
    try {
      await operation();
    } catch (_) {
      failed = true;
    }
  }
  if (failed) {
    throw const DeletionFailure(
      'This device could not remove all private local data. Free some storage and retry. Local cleanup is not complete.',
    );
  }
}
