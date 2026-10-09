import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/features/account_service_retry.dart';

void main() {
  testWidgets('retries silently and reports once at one minute', (
    tester,
  ) async {
    var attempts = 0;
    var errors = 0;
    final retry = AccountServiceRetry(
      refresh: () async {
        attempts++;
        throw StateError('offline');
      },
      onFailure: () => errors++,
    );
    retry.start();
    await tester.pump();
    for (var i = 0; i < 11; i++) {
      await tester.pump(const Duration(seconds: 5));
      retry.start(); // Duplicate errors must not reset the deadline.
    }
    expect(attempts, 12);
    expect(errors, 0);
    await tester.pump(const Duration(seconds: 4));
    expect(errors, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(errors, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(errors, 1);
    retry.dispose();
  });

  testWidgets('successful recovery cancels the error', (tester) async {
    var attempts = 0;
    var errors = 0;
    final retry = AccountServiceRetry(
      refresh: () async {
        if (++attempts < 3) throw StateError('offline');
      },
      onFailure: () => errors++,
    );
    retry.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(minutes: 1));
    expect(attempts, 3);
    expect(errors, 0);
    retry.dispose();
  });

  testWidgets('hung refresh reports at deadline without overlapping work', (
    tester,
  ) async {
    final pending = Completer<void>();
    var attempts = 0;
    var errors = 0;
    final retry = AccountServiceRetry(
      refresh: () {
        attempts++;
        return pending.future;
      },
      onFailure: () => errors++,
    );
    retry.start();
    await tester.pump(const Duration(minutes: 1));
    retry.start();
    expect(attempts, 1);
    expect(errors, 1);
    retry.dispose();
    pending.complete();
    await tester.pump();
  });

  testWidgets('disposal cancels retries and delayed messages', (tester) async {
    var attempts = 0;
    var errors = 0;
    final retry = AccountServiceRetry(
      refresh: () async {
        attempts++;
        throw StateError('offline');
      },
      onFailure: () => errors++,
    );
    retry.start();
    await tester.pump();
    retry.dispose();
    retry.start();
    await tester.pump(const Duration(minutes: 1));
    expect(attempts, 1);
    expect(errors, 0);
  });
}
