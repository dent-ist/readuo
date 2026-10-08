import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/screens/login_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'widget_test.dart' show FakeAuthService;

void main() {
  testWidgets('login uses supplied logo asset with accessible brand label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: LoginScreen(authService: FakeAuthService()),
      ),
    );
    await tester.pumpAndSettle();
    final logo = tester.widget<Image>(
      find.byKey(const Key('readuo-brand-logo')),
    );
    expect(
      (logo.image as AssetImage).assetName,
      'assets/brand/readuo-logo.png',
    );
    expect(find.bySemanticsLabel('Readuo logo'), findsOneWidget);
    expect(tester.takeException(), isNull);
      semantics.dispose();
  });
}
