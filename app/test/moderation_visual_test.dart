import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/moderation/moderation_repository.dart';
import 'package:readuo/moderation/moderation_screens.dart';
import 'package:readuo/theme/readuo_theme.dart';

import 'moderation_test.dart' show FakeModerationRepository;

void main() {
  testWidgets(
    'render all six moderation handoff states',
    (tester) async {
      await tester.runAsync(() async {
        final loader = FontLoader('ReaduoVisual');
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
            ),
          ),
        );
        await loader.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                'C:/users/realp/.flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        );
        await icons.load();
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const report = ModerationReport(
        id: 'report',
        kind: 'post',
        reason: 'Harassment or bullying',
        note: 'This comment was directed at me after I asked them to stop.',
        content: 'A reported post is displayed here for moderator review.',
      );
      final repository = FakeModerationRepository()
        ..reports = [
          report,
          const ModerationReport(
            id: 'comment',
            kind: 'comment',
            reason: 'Inappropriate content',
            note: '',
            content: 'Comment',
          ),
        ];
      final controller = TextEditingController(
        text: 'Draft text stays here so it can be revised.',
      );
      addTearDown(controller.dispose);
      final screens = <String, Widget>{
        'report': ReportScreen(
          repository: repository,
          target: const ReportTarget(kind: 'post', id: 'post'),
          onDone: () {},
        ),
        'report-sent': ReportSentScreen(
          support: false,
          onDone: () {},
          onBlock: () {},
        ),
        'moderation': ModerationScreen(repository: repository),
        'report-detail': ReportDetailScreen(
          repository: repository,
          report: report,
        ),
        'moderation-action': const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.white,
              child: ModerationActionSheet(),
            ),
          ),
        ),
        'content-filtered': ContentFilteredScreen(
          draftController: controller,
          onEdit: () {},
          onGuidelines: () {},
        ),
      };
      for (final entry in screens.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ReaduoTheme.modern.copyWith(
              textTheme: ReaduoTheme.modern.textTheme.apply(
                fontFamily: 'ReaduoVisual',
              ),
            ),
            home: RepaintBoundary(key: ValueKey(entry.key), child: entry.value),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(ValueKey(entry.key)),
          matchesGoldenFile('artifacts/p1-15-review/${entry.key}.png'),
        );
      }
    },
    skip: !const bool.fromEnvironment('MODERATION_VISUALS'),
  );
}
