import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:readuo/circle/circle_repository.dart';
import 'package:readuo/circle/engagement_repository.dart';
import 'package:readuo/circle/photo_repository.dart';
import 'package:readuo/library/book_repository.dart';
import 'package:readuo/screens/circle_post_composer_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'package:readuo/widgets/circle_engagement.dart';

void main() {
  Widget app(Widget child) =>
      MaterialApp(theme: ReaduoTheme.modern, home: child);

  testWidgets('likes are deterministic and can be removed', (tester) async {
    final repository = _EngagementFake();
    const content = CircleContentRef(
      kind: CircleContentKind.post,
      id: 'post-one',
      authorId: 'author',
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CircleEngagementBar(
            viewerId: 'viewer',
            content: content,
            repository: repository,
            onOpenComments: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('circle-like-post-one')));
    await tester.pump();
    expect(repository.likeWrites, [true]);

    repository.likes = {'viewer'};
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CircleEngagementBar(
            viewerId: 'viewer',
            content: content,
            repository: repository,
            onOpenComments: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('circle-like-post-one')));
    await tester.pump();
    expect(repository.likeWrites, [true, false]);
  });

  testWidgets('empty comments stay clean and Comment focuses the input', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: CircleCommentsSection(
              viewerId: 'viewer',
              viewerDisplayName: 'Reader',
              viewerPhotoUrl: null,
              content: const CircleContentRef(
                kind: CircleContentKind.post,
                id: 'post-one',
                authorId: 'author',
              ),
              repository: _EngagementFake(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('No comments yet. Start the conversation.'), findsNothing);
    final send = find.byKey(const Key('circle-send-comment'));
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('circle-comments-post-one')));
    await tester.pumpAndSettle();
    final input = find.byKey(const Key('circle-comment-text'));
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
    await tester.enterText(input, '   ');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(input, 'A thoughtful reply');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
  });

  testWidgets(
    'comment send shows progress and preserves a failed draft for retry',
    (tester) async {
      final repository = _EngagementFake()..pendingComment = Completer<void>();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: CircleCommentsSection(
                viewerId: 'viewer',
                viewerDisplayName: 'Reader',
                viewerPhotoUrl: null,
                content: const CircleContentRef(
                  kind: CircleContentKind.post,
                  id: 'post-one',
                  authorId: 'author',
                ),
                repository: repository,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('circle-comment-text'));
      final send = find.byKey(const Key('circle-send-comment'));
      await tester.enterText(input, 'A thoughtful reply');
      await tester.pump();
      await tester.tap(send);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      repository.pendingComment!.completeError(Exception('Please retry'));
      await tester.pumpAndSettle();
      expect(find.text('A thoughtful reply'), findsOneWidget);
      expect(find.textContaining('Please retry'), findsOneWidget);
      repository.pendingComment = Completer<void>();
      await tester.tap(send);
      await tester.pump();
      repository.pendingComment!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      expect(repository.sentComments, [
        'A thoughtful reply',
        'A thoughtful reply',
      ]);
    },
  );

  testWidgets('post owner confirms removal of another reader comment', (
    tester,
  ) async {
    final repository = _EngagementFake()
      ..comments = [
        const CircleComment(
          id: 'comment-one',
          authorId: 'friend',
          authorDisplayName: 'Friend Reader',
          authorPhotoUrl: null,
          text: 'Thoughtful comment',
          createdAt: null,
          updatedAt: null,
        ),
      ];
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: CircleCommentsSection(
              viewerId: 'owner',
              viewerDisplayName: 'Owner Reader',
              viewerPhotoUrl: null,
              content: const CircleContentRef(
                kind: CircleContentKind.post,
                id: 'post-one',
                authorId: 'owner',
              ),
              repository: repository,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    expect(find.text('Remove comment'), findsOneWidget);
    expect(find.text('Edit comment'), findsNothing);
    await tester.tap(find.text('Remove comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-confirm-delete-comment')));
    await tester.pumpAndSettle();
    expect(repository.deletedCommentIds, ['comment-one']);
  });

  testWidgets('photo-only post uploads and publishes its durable path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final circleRepository = _PhotoCircleRepository();
    final photoRepository = _PhotoRepository();
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      app(
        CirclePostComposerScreen(
          ownerId: 'owner',
          circleRepository: circleRepository,
          bookRepository: const EmptyBookRepository(),
          photoRepository: photoRepository,
          pickPhoto: (_) async =>
              XFile.fromData(png, name: 'circle.png', mimeType: 'image/png'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('circle-photo-library')));
    await tester.pumpAndSettle();
    expect(photoRepository.uploadedBytes, isNotNull);
    await tester.tap(find.byKey(const Key('circle-submit-post')));
    await tester.pumpAndSettle();
    expect(circleRepository.published?.text, '');
    expect(
      circleRepository.published?.photoPath,
      'circlePosts/owner/post-one/photo-1',
    );
    expect(photoRepository.uploadedBytes, png);
  });

  testWidgets('restores a durable photo draft from private storage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final circleRepository = _PhotoCircleRepository(
      draft: const CirclePostDraft(
        postId: 'post-one',
        text: 'Restored words',
        attachment: null,
        photoPath: 'circlePosts/owner/post-one/photo-1',
      ),
    );
    final photoRepository = _PhotoRepository()..loadedBytes = png;
    await tester.pumpWidget(
      app(
        CirclePostComposerScreen(
          ownerId: 'owner',
          circleRepository: circleRepository,
          bookRepository: const EmptyBookRepository(),
          photoRepository: photoRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restored words'), findsOneWidget);
    expect(find.byKey(const Key('circle-remove-photo')), findsOneWidget);
    expect(photoRepository.loadedPaths, ['circlePosts/owner/post-one/photo-1']);
  });
}

class _EngagementFake extends EmptyCircleEngagementRepository {
  Completer<void>? pendingComment;
  final sentComments = <String>[];
  @override
  Future<void> addComment({
    required CircleContentRef content,
    required String authorId,
    required String authorDisplayName,
    required String? authorPhotoUrl,
    required String text,
  }) async {
    sentComments.add(text);
    await pendingComment?.future;
  }

  Set<String> likes = {};
  List<CircleComment> comments = [];
  final List<bool> likeWrites = [];
  final List<String> deletedCommentIds = [];

  @override
  Stream<Set<String>> watchLikeUserIds(CircleContentRef content) =>
      Stream.value(likes);

  @override
  Future<void> setLiked({
    required CircleContentRef content,
    required String userId,
    required bool liked,
  }) async {
    likeWrites.add(liked);
  }

  @override
  Stream<List<CircleComment>> watchComments(CircleContentRef content) =>
      Stream.value(comments);

  @override
  Future<void> deleteComment({
    required CircleContentRef content,
    required String commentId,
  }) async {
    deletedCommentIds.add(commentId);
  }
}

class _PhotoCircleRepository extends EmptyCircleRepository {
  _PhotoCircleRepository({this.draft});

  final CirclePostDraft? draft;
  CirclePostDraft? published;

  @override
  String newPostId() => 'post-one';

  @override
  Future<CirclePostDraft?> loadPostDraft(String ownerId) async => draft;

  @override
  Future<void> publishPostDraft({
    required String authorId,
    required CirclePostDraft draft,
  }) async {
    published = draft;
  }
}

class _PhotoRepository extends EmptyCirclePhotoRepository {
  Uint8List? uploadedBytes;
  Uint8List? loadedBytes;
  final List<String> loadedPaths = [];

  @override
  Future<String> upload({
    required String ownerId,
    required String postId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadedBytes = bytes;
    return 'circlePosts/$ownerId/$postId/photo-1';
  }

  @override
  Future<Uint8List?> load(String storagePath) async {
    loadedPaths.add(storagePath);
    return loadedBytes;
  }
}
