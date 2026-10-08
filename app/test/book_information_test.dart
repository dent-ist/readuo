import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/library/book.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/book_information.dart';

void main() {
  LibraryBook edition(Map<String, dynamic> extra) =>
      LibraryBook.fromFirestore('book', 'shelf', {
        'ownerId': 'reader',
        'title': 'A sample book',
        'author': 'A sample author',
        ...extra,
      });

  test(
    'stored optional metadata survives model decoding with legacy defaults',
    () {
      final book = edition({
        'description': 'Paragraph one.\n\nParagraph two.',
        'publisher': 'Sample publisher',
        'publishedYear': '2024',
      });
      expect(book.description, 'Paragraph one.\n\nParagraph two.');
      expect(book.publisher, 'Sample publisher');
      expect(book.publishedYear, '2024');
      expect(edition({}).description, isEmpty);
      expect(edition({}).publisher, isEmpty);
    },
  );

  testWidgets(
    'full description and ISBN copy do not replace unknown metadata with fiction',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final book = edition({
        'description': 'First paragraph.\n\nSecond paragraph.',
        'isbn': '9780306406157',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: Scaffold(
            body: Column(
              children: [
                BookIsbnRow(book: book),
                BookDescription(book: book),
              ],
            ),
          ),
        ),
      );
      expect(find.text(book.description), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('book-description'))).maxLines,
        isNull,
      );
      await tester.tap(find.byTooltip('Copy ISBN'));
      await tester.pumpAndSettle();
      expect(copied, book.isbn);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                BookIsbnRow(book: edition({})),
                BookDescription(book: edition({})),
              ],
            ),
          ),
        ),
      );
      expect(find.text('ISBN not available'), findsOneWidget);
      expect(find.byTooltip('Copy ISBN'), findsNothing);
      expect(
        find.text('No description is available for this edition.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'compact description hides missing data and limits excerpts to three lines',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: BookDescription(book: edition({}), compact: true)),
      );
      expect(find.byType(Text), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: BookDescription(
            book: edition({'description': 'A sample description.'}),
            compact: true,
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('A sample description.')).maxLines,
        3,
      );
    },
  );
}
