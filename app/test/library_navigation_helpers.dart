import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openLibraryScanner(WidgetTester tester) async {
  final shelfAdd = find.byKey(const Key('add-book-button'));
  if (shelfAdd.evaluate().isNotEmpty) {
    await tester.tap(shelfAdd);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-isbn-button')));
  } else {
    final libraryAdd = find.byKey(const Key('library-add-fab'));
    if (libraryAdd.evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('nav-library')));
      await tester.pumpAndSettle();
    }
    await tester.tap(libraryAdd);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-add-book-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-books-scan')));
  }
  await tester.pumpAndSettle();
}
