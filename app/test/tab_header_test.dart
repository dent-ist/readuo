import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/main.dart';
import 'package:readuo/profile/profile_widgets.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_tab_header.dart';

import 'memory_preferences.dart';
import 'phone_feedback_test.dart'
    show PhoneFriendRepository, PhoneCircleRepository;
import 'widget_test.dart'
    show FakeAuthService, FakeShelfRepository, user, shelf;

void main() {
  testWidgets(
    'tab switches and reselection reset details but honor pop guards',
    (tester) async {
      await tester.pumpWidget(
        ReaduoApp(
          authService: FakeAuthService(current: user(displayName: 'Reader')),
          shelfRepository: FakeShelfRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-circle')));
      await tester.pumpAndSettle();
      final navigator = Navigator.of(
        tester.element(find.byKey(const ValueKey('circle-tab-root'))),
      );
      void openDetail({bool guarded = false}) {
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => PopScope(
              canPop: !guarded,
              child: const Scaffold(body: Text('Test detail')),
            ),
          ),
        );
      }

      openDetail();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-library')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-circle')));
      await tester.pumpAndSettle();
      expect(find.text('Test detail'), findsNothing);
      openDetail();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-circle')));
      await tester.pumpAndSettle();
      expect(find.text('Test detail'), findsNothing);
      openDetail(guarded: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-library')));
      await tester.pumpAndSettle();
      expect(find.text('Test detail'), findsOneWidget);
    },
  );

  for (final scale in [1.0, 1.3]) {
    testWidgets('main tab headers share layout at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await runTabHeaderChecks(tester);
    });
  }

  testWidgets('long title wraps without clipping and action remains usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pressed = false;
    const title = 'Meine persönliche Bibliothek und Lesefreunde';
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: ReaduoTabHeader(
                context: context,
                title: title,
                actions: [
                  ReaduoTabHeaderAction(
                    tooltip: 'Open action',
                    icon: Icons.notifications_none,
                    onPressed: () => pressed = true,
                  ),
                ],
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = tester.getRect(find.byType(ReaduoTabHeader));
    final text = tester.getRect(find.text(title));
    expect(text.top, greaterThanOrEqualTo(header.top));
    expect(text.bottom, lessThanOrEqualTo(header.bottom));
    expect(text.height, greaterThan(64));
    expect(
      tester.getSize(find.byType(ReaduoTabHeaderAction)),
      const Size(48, 48),
    );
    await tester.tap(find.byTooltip('Open action'));
    expect(pressed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested ProfilePage keeps its existing header', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfilePage(title: 'Settings', subtitle: 'Shelf settings'),
      ),
    );
    expect(find.byType(ReaduoTabHeader), findsNothing);
    expect(find.text('Shelf settings'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });
}

Future<void> runTabHeaderChecks(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  useMemoryPreferences();
  final reader = user(displayName: 'Reader');
  await tester.pumpWidget(
    ReaduoApp(
      authService: FakeAuthService(current: reader),
      friendRepository: PhoneFriendRepository(),
      circleRepository: PhoneCircleRepository(),
      shelfRepository: FakeShelfRepository(
        initialShelves: {
          reader.uid: [
            shelf(id: 'header-shelf', ownerId: reader.uid, name: 'Quiet reads'),
          ],
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  for (final title in ['Circle', 'Library', 'Friends', 'Profile']) {
    await tester.tap(find.byKey(Key('nav-${title.toLowerCase()}')));
    await tester.pumpAndSettle();
    final headerFinder = find.byType(ReaduoTabHeader);
    expect(headerFinder, findsOneWidget);
    final header = tester.widget<ReaduoTabHeader>(headerFinder);
    final titleFinder = find.descendant(
      of: headerFinder,
      matching: find.text(title),
    );
    expect(tester.widget<Text>(titleFinder).style, ReaduoTabHeader.titleStyle);
    expect(tester.getTopLeft(titleFinder).dx, 16);
    expect(header.backgroundColor, ReaduoColors.background);
    expect(header.scrolledUnderElevation, 0);
    final bounds = tester.getRect(headerFinder);
    final titleBounds = tester.getRect(titleFinder);
    expect(titleBounds.top, greaterThanOrEqualTo(bounds.top));
    expect(titleBounds.bottom, lessThanOrEqualTo(bounds.bottom));
    expect(
      find.descendant(
        of: headerFinder,
        matching: find.textContaining('Friends only'),
      ),
      findsNothing,
    );
    if (capture != null) await capture('header-${title.toLowerCase()}');
    expect(tester.takeException(), isNull);
  }
  await tester.tap(find.byKey(const Key('nav-library')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-profile')));
  await tester.pumpAndSettle();
  expect(
    find.descendant(
      of: find.byType(ReaduoTabHeader),
      matching: find.text('Profile'),
    ),
    findsOneWidget,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
