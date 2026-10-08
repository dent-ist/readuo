import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/moderation/content_filter.dart';
import 'package:readuo/moderation/moderation_repository.dart';
import 'package:readuo/moderation/moderation_screens.dart';
import 'package:readuo/theme/readuo_theme.dart';

class FakeModerationRepository implements ModerationRepository {
  bool moderator = true;
  bool fail = false;
  int listCalls = 0;
  int submissions = 0;
  final requestIds = <String>[];
  final decisions = <String>[];
  Completer<ReportReceipt>? pending;
  List<ModerationReport> reports = [];

  @override
  Future<bool> isModerator() async => moderator;
  @override
  Future<ReportPage> list({String? afterId}) async {
    listCalls++;
    return ReportPage(reports, null);
  }

  @override
  Future<ReportReceipt> submit({
    required String requestId,
    required ReportTarget target,
    required String reason,
    required String note,
  }) async {
    submissions++;
    requestIds.add(requestId);
    if (fail) throw const ModerationFailure('Please retry.');
    return pending?.future ??
        Future.value(
          ReportReceipt(
            'report',
            target.kind == 'support' ? null : 'server-author',
          ),
        );
  }

  @override
  Future<void> decide({
    required String reportId,
    required String decision,
    required String note,
  }) async {
    if (fail) throw const ModerationFailure('Please retry.');
    decisions.add(decision);
  }
}

Future<void> pumpModeration(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: ReaduoTheme.modern, home: screen));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reported photo failure displays an explicit warning', (
    tester,
  ) async {
    await pumpModeration(
      tester,
      ReportDetailScreen(
        repository: FakeModerationRepository(),
        report: const ModerationReport(
          id: 'report',
          kind: 'post',
          reason: 'Inappropriate content',
          note: '',
          content: '',
          photoPath: 'circlePosts/author/post/photo-1',
        ),
      ),
    );
    expect(
      find.textContaining('The reported image is unavailable.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('report models preserve post and profile image snapshots', () {
    final report = ModerationReport.fromJson({
      'id': 'report',
      'target': {'kind': 'profile'},
      'reason': 'Privacy concern',
      'contentSnapshot': 'Reader name',
      'status': 'pending',
      'photoPath': 'profilePhotos/author/photo-1',
      'photoUrl': 'https://example.com/photo.png',
    });
    expect(report.photoPath, 'profilePhotos/author/photo-1');
    expect(report.photoUrl, 'https://example.com/photo.png');
  });
  test(
    'filter parity includes case, ASCII whitespace and documented boundaries',
    () {
      for (final text in [
        'I WILL KILL YOU',
        'Please, kill yourself.',
        'line\nI\twill\r\nkill you!',
      ]) {
        expect(BasicContentFilter.check(text).allowed, false);
        expect(BasicContentFilter.check(text).explanation, isNotNull);
      }
      for (final text in [
        'A thoughtful review',
        'skill yourself',
        'I will kill your weeds',
        'kill yourselfish',
        'I will kill you_',
        'i will kіll you',
      ]) {
        expect(BasicContentFilter.check(text).allowed, true);
      }
    },
  );

  testWidgets(
    'submit waits for server, prevents double submit, then uses resolved reader',
    (tester) async {
      final repository = FakeModerationRepository()
        ..pending = Completer<ReportReceipt>();
      String? blocked;
      await pumpModeration(
        tester,
        ReportScreen(
          repository: repository,
          target: const ReportTarget(kind: 'post', id: 'post'),
          onDone: () {},
          onBlockReader: (uid) => blocked = uid,
        ),
      );
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pump();
      expect(find.text('Report received'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(repository.submissions, 1);
      repository.pending!.complete(
        const ReportReceipt('report', 'server-author'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Report received'), findsOneWidget);
      await tester.tap(find.text('Block this reader'));
      expect(blocked, 'server-author');
    },
  );

  testWidgets(
    'failed submission retains editable note and retries same payload id',
    (tester) async {
      final repository = FakeModerationRepository()..fail = true;
      await pumpModeration(
        tester,
        ReportScreen(
          repository: repository,
          target: const ReportTarget.support(),
          onDone: () {},
        ),
      );
      await tester.enterText(find.byType(TextField), 'Please help');
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text('Please help'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(repository.requestIds[0], repository.requestIds[1]);
      await tester.enterText(find.byType(TextField), 'Updated concern');
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(repository.requestIds.last, isNot(repository.requestIds.first));
    },
  );

  testWidgets('support receipt never offers block', (tester) async {
    await pumpModeration(
      tester,
      ReportSentScreen(support: true, onDone: () {}),
    );
    expect(find.text('Back to support'), findsOneWidget);
    expect(find.text('Block this reader'), findsNothing);
  });

  testWidgets('operator gate denies before querying report queue', (
    tester,
  ) async {
    final repository = FakeModerationRepository()..moderator = false;
    await pumpModeration(tester, ModerationScreen(repository: repository));
    expect(repository.listCalls, 0);
    expect(find.text('Moderator access required.'), findsOneWidget);
    expect(find.textContaining('Reported post'), findsNothing);
  });

  testWidgets(
    'operator remove requires note and confirmation; cancel makes no mutation',
    (tester) async {
      final repository = FakeModerationRepository();
      await pumpModeration(
        tester,
        ReportDetailScreen(
          repository: repository,
          report: const ModerationReport(
            id: 'report',
            kind: 'post',
            reason: 'Harassment or bullying',
            note: 'Please review',
            content: 'Reported text',
          ),
        ),
      );
      await tester.ensureVisible(find.text('Remove content'));
      await tester.tap(find.text('Remove content'));
      await tester.pumpAndSettle();
      expect(
        find.text('Record your decision in a review note.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField),
        'Reviewed against the rule.',
      );
      await tester.ensureVisible(find.text('Remove content'));
      await tester.tap(find.text('Remove content'));
      await tester.pumpAndSettle();
      expect(find.text('Remove reported content?'), findsOneWidget);
      await tester.tap(find.text('Back to report'));
      await tester.pumpAndSettle();
      expect(repository.decisions, isEmpty);
      await tester.tap(find.text('Remove content'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove & resolve'));
      await tester.pumpAndSettle();
      expect(repository.decisions, ['remove']);
    },
  );

  testWidgets(
    'filtered draft stays editable and retains changes after edit navigation',
    (tester) async {
      final controller = TextEditingController(text: 'Original draft');
      addTearDown(controller.dispose);
      var edited = false;
      await pumpModeration(
        tester,
        ContentFilteredScreen(
          draftController: controller,
          onEdit: () => edited = true,
          onGuidelines: () {},
        ),
      );
      await tester.enterText(find.byType(TextField), 'Revised draft');
      await tester.ensureVisible(find.text('Edit draft'));
      await tester.tap(find.text('Edit draft'));
      expect(controller.text, 'Revised draft');
      expect(edited, true);
    },
  );

  testWidgets('confirmation respects system inset and keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ReaduoTheme.modern,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(360, 640),
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
            viewInsets: EdgeInsets.only(bottom: 200),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ModerationActionSheet(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(find.text('Back to report')).dy,
      lessThan(440),
    );
    expect(tester.takeException(), isNull);
  });
}
