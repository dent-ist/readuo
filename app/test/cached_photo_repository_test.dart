import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/circle/cached_photo_repository.dart';
import 'package:readuo/circle/photo_repository.dart';
import 'package:readuo/widgets/circle_photo.dart';

class PhotoSource extends EmptyCirclePhotoRepository {
  int loads = 0;
  Future<Uint8List?> Function() response = () async => Uint8List(2);

  @override
  Future<Uint8List?> load(String storagePath) {
    loads++;
    return response();
  }
}

void main() {
  testWidgets('recycled photo returns without another download or spinner', (
    tester,
  ) async {
    final source = PhotoSource()
      ..response = () async => base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
    final cache = CachedCirclePhotoRepository(source);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 20,
          itemExtent: 400,
          itemBuilder: (context, index) => index == 0
              ? CirclePhoto(storagePath: 'photo', repository: cache)
              : const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.loads, 1);
    controller.jumpTo(2400);
    await tester.pumpAndSettle();
    expect(find.byType(CirclePhoto), findsNothing);
    controller.jumpTo(0);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(source.loads, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('reuses completed and concurrent loads, prunes revoked paths', () async {
    final source = PhotoSource();
    final cache = CachedCirclePhotoRepository(source);
    final first = cache.load('photo');
    expect(identical(first, cache.load('photo')), isTrue);
    await first;
    await cache.load('photo');
    expect(source.loads, 1);
    cache.retainPaths({});
    await cache.load('photo');
    expect(source.loads, 2);
  });

  test('clear prevents in-flight downloads from repopulating cache', () async {
    final pending = Completer<Uint8List?>();
    final source = PhotoSource()..response = () => pending.future;
    final cache = CachedCirclePhotoRepository(source);
    final first = cache.load('photo');
    cache.clear();
    pending.complete(Uint8List(2));
    await first;
    await cache.load('photo');
    expect(source.loads, 2);
  });

  test(
    'bounded LRU evicts oldest photo and failures remain retryable',
    () async {
      final source = PhotoSource();
      final cache = CachedCirclePhotoRepository(source, maxBytes: 4);
      await cache.load('first');
      await cache.load('second');
      await cache.load('first');
      await cache.load('third');
      await cache.load('second');
      expect(source.loads, 4);
      source.response = () async => throw StateError('offline');
      await expectLater(cache.load('retry'), throwsStateError);
      source.response = () async => null;
      expect(await cache.load('retry'), isNull);
      source.response = () async => Uint8List(2);
      expect(await cache.load('retry'), isNotNull);
    },
  );

  testWidgets('rebuild keeps download and missing image stops spinner', (
    tester,
  ) async {
    final source = PhotoSource()..response = () async => null;
    Widget photo() => MaterialApp(
      home: CirclePhoto(storagePath: 'photo', repository: source),
    );
    await tester.pumpWidget(photo());
    await tester.pumpAndSettle();
    await tester.pumpWidget(photo());
    await tester.pumpAndSettle();
    expect(source.loads, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });
}
