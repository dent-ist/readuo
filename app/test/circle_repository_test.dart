import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/circle/circle_repository.dart';

void main() {
  for (final text in [
    'Trailing space ',
    '\nLeading newline',
    '  Both ends\n',
    'First\n\nSecond\n',
  ]) {
    test(
      'draft round trip and publication preserve input: ${text.replaceAll('\n', r'\n')}',
      () async {
        final firestore = _Firestore();
        final repository = FirebaseCircleRepository(firestore);
        final draft = CirclePostDraft(
          postId: 'post',
          text: text,
          attachment: null,
        );
        await repository.savePostDraft(ownerId: 'owner', draft: draft);
        final restored = await repository.loadPostDraft('owner');
        await repository.publishPostDraft(authorId: 'owner', draft: draft);
        expect(restored!.text, text);
        expect(firestore.documents['circlePosts/post']!['text'], text.trim());
        expect(
          firestore.documents.containsKey('users/owner/circleDrafts/newPost'),
          false,
        );
        await repository.publishPostDraft(authorId: 'owner', draft: draft);
        expect(firestore.documents.length, 1);
      },
    );
  }

  test(
    'a genuinely changed remote draft is not published or deleted',
    () async {
      final firestore = _Firestore();
      final repository = FirebaseCircleRepository(firestore);
      const original = CirclePostDraft(
        postId: 'post',
        text: 'Original ',
        attachment: null,
      );
      const changed = CirclePostDraft(
        postId: 'post',
        text: 'Changed elsewhere ',
        attachment: null,
      );
      await repository.savePostDraft(ownerId: 'owner', draft: original);
      await repository.savePostDraft(ownerId: 'owner', draft: changed);
      await expectLater(
        repository.publishPostDraft(authorId: 'owner', draft: original),
        throwsA(isA<CircleFailure>()),
      );
      expect(firestore.documents.containsKey('circlePosts/post'), false);
      expect((await repository.loadPostDraft('owner'))!.text, changed.text);
    },
  );
}

class _Firestore implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async => handler(_Transaction(this));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.firestore, this.path);
  @override
  final _Firestore firestore;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(firestore, '${this.path}/${path ?? 'post'}');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.firestore, this.path);
  @override
  final _Firestore firestore;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(firestore, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot(id, firestore.documents[path]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Snapshot<T> implements DocumentSnapshot<T> {
  _Snapshot(this.id, this.value);
  @override
  final String id;
  final T? value;
  @override
  T? data() => value;
  @override
  bool get exists => value != null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transaction implements Transaction {
  _Transaction(this.firestore);
  final _Firestore firestore;
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async => _Snapshot(reference.id, firestore.documents[reference.path] as T?);
  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    firestore.documents[reference.path] = Map<String, dynamic>.from(
      data as Map,
    );
    return this;
  }

  @override
  Transaction delete(DocumentReference reference) {
    firestore.documents.remove(reference.path);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
