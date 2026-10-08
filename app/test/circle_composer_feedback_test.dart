import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:readuo/circle/circle_repository.dart';
import 'package:readuo/circle/photo_repository.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/main.dart';
import 'package:readuo/screens/circle_post_composer_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/readuo_tab_header.dart';

import 'memory_preferences.dart';
import 'phone_feedback_test.dart'
    show PhoneCircleRepository, PhoneFriendRepository;
import 'widget_test.dart' show FakeAuthService, user;

void main() {
  for (final small in [false, true]) {
    testWidgets(
      'Circle FAB and pinned composer ${small ? 'small' : 'normal'}',
      (tester) async {
        tester.view.physicalSize = small
            ? const Size(360, 640)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = const FakeViewPadding(bottom: 48, top: 24);
        tester.view.padding = const FakeViewPadding(bottom: 48, top: 24);
        tester.platformDispatcher.textScaleFactorTestValue = small ? 1.3 : 1;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await runCircleComposerFeedbackChecks(
          tester,
          capture: (name) async {
            if (name.endsWith('-keyboard')) {
              tester.view.viewInsets = const FakeViewPadding(bottom: 280);
              tester.view.padding = const FakeViewPadding(top: 24);
              await tester.pumpAndSettle();
            } else if (tester.view.viewInsets.bottom > 0) {
              tester.view.resetViewInsets();
              tester.view.padding = const FakeViewPadding(bottom: 48, top: 24);
              await tester.pumpAndSettle();
            }
          },
        );
      },
    );
  }
}

void expectPinnedCircleSubmit(WidgetTester tester) {
  final button = find.byKey(const Key('circle-submit-post'));
  final bounds = tester.getRect(button);
  final bottomInset = tester.view.viewInsets.bottom > 0
      ? tester.view.viewInsets.bottom
      : tester.view.viewPadding.bottom;
  final safeBottom =
      (tester.view.physicalSize.height - bottomInset) /
      tester.view.devicePixelRatio;
  expect(bounds.bottom, closeTo(safeBottom - 16, 1));
  expect(bounds.height, greaterThanOrEqualTo(48));
  expect(button.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> runCircleComposerFeedbackChecks(
  WidgetTester tester, {
  required Future<void> Function(String) capture,
}) async {
  Future<void> reveal(Key key) async {
    final control = find.byKey(key);
    if (control.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        control,
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
    } else {
      await tester.ensureVisible(control);
    }
    await tester.pumpAndSettle();
  }

  useMemoryPreferences();
  await tester.pumpWidget(
    ReaduoApp(
      authService: FakeAuthService(current: user(displayName: 'Maya')),
      friendRepository: PhoneFriendRepository(),
      circleRepository: PhoneCircleRepository(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-circle')));
  await tester.pumpAndSettle();
  final fab = find.byKey(const Key('circle-thought-composer'));
  expect(tester.widget(fab), isA<FloatingActionButton>());
  final composeButton = tester.widget<FloatingActionButton>(fab);
  expect(composeButton.shape, isA<CircleBorder>());
  expect(composeButton.backgroundColor, const Color(0xFF3D7A1A));
  expect(find.descendant(of: fab, matching: find.byType(Text)), findsNothing);
  expect(tester.getSize(fab).width, tester.getSize(fab).height);
  expect(
    find.descendant(
      of: find.byType(ReaduoTabHeader),
      matching: find.text('Post'),
    ),
    findsNothing,
  );
  expect(find.text('Friends only · newest first'), findsNothing);
  expect(
    tester.getRect(fab).bottom,
    lessThan(
      tester
          .getRect(find.byKey(const Key('authenticated-bottom-navigation')))
          .top,
    ),
  );
  await capture('circle-fab');
  await tester.tap(fab);
  await tester.pumpAndSettle();
  expect(
    find.byKey(const Key('authenticated-bottom-navigation')),
    findsNothing,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await capture('composer-empty');
  expectPinnedCircleSubmit(tester);
  await tester.enterText(
    find.byKey(const Key('circle-post-text')),
    'A quiet Sunday with a good book.',
  );
  await tester.pumpAndSettle();
  await capture('composer-keyboard');
  expectPinnedCircleSubmit(tester);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();

  final circle = _PhotoDrafts();
  final photos = _CameraPhotos();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: CirclePostComposerScreen(
        ownerId: 'owner',
        circleRepository: circle,
        bookRepository: const EmptyBookRepository(),
        photoRepository: photos,
        pickPhoto: (source) async {
          expect(source, ImageSource.camera);
          return XFile.fromData(png, name: 'camera.png', mimeType: 'image/png');
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('circle-post-text')),
    'Keep my photo post draft.',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await capture('composer-draft');
  await reveal(const Key('circle-add-photo'));
  await tester.tap(find.byKey(const Key('circle-add-photo')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('circle-photo-camera')));
  await tester.pump(const Duration(seconds: 1));
  expect(
    tester
        .widget<FilledButton>(find.byKey(const Key('circle-submit-post')))
        .onPressed,
    isNull,
  );
  photos.uploadGate.completeError(
    const CirclePhotoFailure(
      'Readuo could not verify permission to upload this photo. Please retry.',
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Keep my photo post draft.'), findsOneWidget);
  expect(circle.published, isNull);
  await capture('composer-photo-denied');
  expectPinnedCircleSubmit(tester);
  expect(
    find.byKey(const Key('circle-post-error')).hitTestable(),
    findsOneWidget,
  );
  await reveal(const Key('circle-add-photo'));
  await tester.tap(find.byKey(const Key('circle-add-photo')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('circle-photo-camera')));
  await tester.pumpAndSettle();
  expect(photos.uploadCount, 2);
  expect(find.byKey(const Key('circle-post-error')), findsNothing);
  await reveal(const Key('circle-remove-photo'));
  await capture('composer-photo-attached');
  expectPinnedCircleSubmit(tester);
  final beforeScroll = tester.getRect(
    find.byKey(const Key('circle-submit-post')),
  );
  await tester.drag(find.byType(ListView).first, const Offset(0, -220));
  await tester.pumpAndSettle();
  expect(
    tester.getRect(find.byKey(const Key('circle-submit-post'))),
    beforeScroll,
  );
  await tester.tap(find.byKey(const Key('circle-submit-post')));
  await tester.pumpAndSettle();
  expect(circle.published?.text, 'Keep my photo post draft.');
  expect(circle.published?.photoPath, 'circlePosts/owner/post-one/photo-1');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    MaterialApp(
      theme: ReaduoTheme.modern,
      home: CirclePostComposerScreen(
        ownerId: 'owner',
        circleRepository: circle,
        bookRepository: const EmptyBookRepository(),
        post: CirclePost(
          id: 'existing',
          authorId: 'owner',
          text: 'A book worth sharing.',
          attachment: null,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await capture('composer-edit');
  expect(find.text('Save changes'), findsOneWidget);
  expectPinnedCircleSubmit(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

class _PhotoDrafts extends EmptyCircleRepository {
  CirclePostDraft? published;
  @override
  String newPostId() => 'post-one';
  @override
  Future<void> publishPostDraft({
    required String authorId,
    required CirclePostDraft draft,
  }) async {
    published = draft;
  }
}

class _CameraPhotos extends EmptyCirclePhotoRepository {
  final uploadGate = Completer<String>();
  int uploadCount = 0;
  @override
  Future<String> upload({
    required String ownerId,
    required String postId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadCount++;
    expect(contentType, 'image/png');
    expect(ownerId, 'owner');
    expect(postId, 'post-one');
    if (uploadCount == 1) return uploadGate.future;
    return 'circlePosts/$ownerId/$postId/photo-1';
  }
}
