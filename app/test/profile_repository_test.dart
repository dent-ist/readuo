import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/profile/firebase_profile_repository.dart';
import 'package:readuo/profile/profile_repository.dart';
import 'package:readuo/profile/support_repository.dart';

void main() {
  late _Firestore firestore;
  late _User user;
  late _Auth auth;
  late _Storage storage;
  late FirebaseProfileRepository profiles;
  late FirestoreSupportRepository support;
  final photo = ProfilePhoto(Uint8List.fromList([255, 216, 255]), 'image/jpeg');

  setUp(() {
    firestore = _Firestore();
    user = _User();
    auth = _Auth(user);
    storage = _Storage();
    profiles = FirebaseProfileRepository(
      auth: auth,
      firestore: firestore,
      storage: storage,
    );
    support = FirestoreSupportRepository(auth: auth, firestore: firestore);
    firestore.documents['readerProfiles/owner'] = {
      'displayName': 'Old name',
      'photoUrl': 'https://old.test/photo',
      'photoStoragePath': 'profilePhotos/owner/old',
      'inviteCode': 'KEEP',
    };
  });

  test(
    'name-only retry repairs retained photo path and cleans previous photo',
    () async {
      firestore.failures = 3;
      await expectLater(
        profiles.save(uid: 'owner', displayName: 'New name', photo: photo),
        throwsA(isA<ProfileFailure>()),
      );
      firestore.failures = 0;
      await profiles.save(uid: 'owner', displayName: 'New name');
      expect(storage.uploads, hasLength(1));
      expect(storage.deleted, ['profilePhotos/owner/old']);
      expect(
        firestore.documents['readerProfiles/owner']!['photoStoragePath'],
        'profilePhotos/owner/generated',
      );
    },
  );

  test(
    'replacement writes Auth first, accepts ensureProfile sync, preserves fields and cleans old owner photo',
    () async {
      user.onUpdate = () {
        firestore.documents['readerProfiles/owner']!.addAll({
          'displayName': user.displayName,
          'photoUrl': user.photoURL,
        });
      };
      final result = await profiles.save(
        uid: 'owner',
        displayName: ' New name ',
        photo: photo,
      );
      expect(result.displayName, 'New name');
      expect(user.displayName, 'New name');
      expect(storage.uploads, ['profilePhotos/owner/generated']);
      expect(storage.deleted, ['profilePhotos/owner/old']);
      final data = firestore.documents['readerProfiles/owner']!;
      expect(data['photoStoragePath'], 'profilePhotos/owner/generated');
      expect(data['photoUrl'], user.photoURL);
      expect(data['inviteCode'], 'KEEP');
    },
  );

  test(
    'transient Firestore failures retry without repeating Auth or upload',
    () async {
      firestore.failures = 2;
      await profiles.save(uid: 'owner', displayName: 'New name', photo: photo);
      expect(firestore.attempts, 3);
      expect(user.updates, 1);
      expect(storage.uploads, hasLength(1));
    },
  );

  test(
    'ambiguous sync failure retains live uploaded photo and new Auth values',
    () async {
      firestore.failures = 3;
      await expectLater(
        profiles.save(uid: 'owner', displayName: 'New name', photo: photo),
        throwsA(isA<ProfileFailure>()),
      );
      expect(user.displayName, 'New name');
      expect(storage.deleted, isEmpty);
      expect(
        firestore.documents['readerProfiles/owner']!['displayName'],
        'Old name',
      );
    },
  );

  test(
    'failed upload URL cleans uploaded object before any Auth mutation',
    () async {
      storage.failUrl = true;
      await expectLater(
        profiles.save(uid: 'owner', displayName: 'New name', photo: photo),
        throwsA(isA<ProfileFailure>()),
      );
      expect(user.updates, 0);
      expect(storage.deleted, ['profilePhotos/owner/generated']);
    },
  );

  test('replacement never deletes another owner path', () async {
    firestore.documents['readerProfiles/owner']!['photoStoragePath'] =
        'profilePhotos/other/old';
    await profiles.save(uid: 'owner', displayName: 'New name', photo: photo);
    expect(storage.deleted, isEmpty);
  });

  test(
    'failed replacement cleanup surfaces warning while keeping saved identity',
    () async {
      storage.failDelete = true;
      final result = await profiles.save(
        uid: 'owner',
        displayName: 'New name',
        photo: photo,
      );
      expect(result.warning, contains('previous photo could not be removed'));
      expect(
        firestore.documents['readerProfiles/owner']!['displayName'],
        'New name',
      );
    },
  );

  test('wrong user and missing profile do not write Auth or Storage', () async {
    await expectLater(
      profiles.save(uid: 'other', displayName: 'Name', photo: photo),
      throwsA(isA<ProfileFailure>()),
    );
    firestore.documents.clear();
    await expectLater(
      profiles.save(uid: 'owner', displayName: 'Name', photo: photo),
      throwsA(isA<ProfileFailure>()),
    );
    expect(user.updates, 0);
    expect(storage.uploads, isEmpty);
  });

  test(
    'support create is immutable and exact-content retry is idempotent',
    () async {
      final draft = SupportDraft(
        subject: ' Help ',
        message: ' Details ',
        requestId: 'a' * 32,
      );
      await support.submit(draft);
      final path = 'supportRequests/owner--${draft.requestId}';
      final created = Map<String, dynamic>.from(firestore.documents[path]!);
      expect(created.keys.toSet(), {
        'ownerId',
        'subject',
        'message',
        'status',
        'createdAt',
      });
      expect(created['subject'], 'Help');
      expect(created['status'], 'pending');
      await support.submit(draft);
      expect(firestore.documents[path], created);
      await expectLater(
        support.submit(
          SupportDraft(
            subject: 'Changed',
            message: 'Details',
            requestId: draft.requestId,
          ),
        ),
        throwsA(isA<ProfileFailure>()),
      );
      expect(firestore.documents[path], created);
    },
  );

  test(
    'explicit operator resolution adds required audit fields and preserves original content',
    () async {
      final draft = SupportDraft(
        subject: 'Help',
        message: 'Details',
        requestId: 'b' * 32,
      );
      await support.submit(draft);
      final id = 'owner--${draft.requestId}';
      await support.resolve(id);
      final data = firestore.documents['supportRequests/$id']!;
      expect(data['status'], 'resolved');
      expect(data['resolvedAt'], isA<FieldValue>());
      expect(data['resolvedBy'], 'owner');
      expect(data['resolutionNote'], 'Handled by support');
      expect(data['subject'], 'Help');
      await support.submit(draft);
      expect(data['status'], 'resolved');
    },
  );
}

class _Auth implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  final User? currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  @override
  String get uid => 'owner';
  @override
  String? displayName = 'Old name';
  @override
  String? photoURL = 'https://old.test/photo';
  int updates = 0;
  void Function()? onUpdate;
  @override
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    updates++;
    this.displayName = displayName;
    this.photoURL = photoURL;
    onUpdate?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> documents = {};
  int failures = 0;
  int attempts = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(this, collectionPath);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    attempts++;
    if (failures-- > 0)
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    return transactionHandler(_Transaction(this));
  }

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
      _Document(firestore, '${this.path}/${path ?? 'generated'}');
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
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot(
    firestore.documents[path] == null
        ? null
        : Map<String, dynamic>.from(firestore.documents[path]!),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Snapshot<T> implements DocumentSnapshot<T> {
  _Snapshot(this.value);
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
    DocumentReference<T> documentReference,
  ) async => _Snapshot(firestore.documents[documentReference.path] as T?);
  @override
  Transaction update(
    DocumentReference documentReference,
    Map<Object, Object?> data,
  ) {
    firestore.documents[documentReference.path]!.addAll(
      data.cast<String, dynamic>(),
    );
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    firestore.documents[documentReference.path] = Map<String, dynamic>.from(
      data as Map,
    );
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements FirebaseStorage {
  final List<String> uploads = [];
  final List<String> deleted = [];
  bool failUrl = false;
  bool failDelete = false;
  @override
  Reference ref([String? path]) => _Reference(this, path ?? '');
  @override
  Reference refFromURL(String url) {
    if (!url.startsWith('https://storage.test/'))
      throw ArgumentError('External URL');
    return ref(url.substring('https://storage.test/'.length));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reference implements Reference {
  _Reference(this.storage, this.fullPath);
  @override
  final _Storage storage;
  @override
  final String fullPath;
  @override
  String get bucket => 'test-bucket';
  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    storage.uploads.add(fullPath);
    return _Upload();
  }

  @override
  Future<String> getDownloadURL() async {
    if (storage.failUrl)
      throw FirebaseException(plugin: 'firebase_storage', code: 'unavailable');
    return 'https://storage.test/$fullPath';
  }

  @override
  Future<void> delete() async {
    if (storage.failDelete)
      throw FirebaseException(plugin: 'firebase_storage', code: 'unauthorized');
    storage.deleted.add(fullPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Upload implements UploadTask {
  @override
  Future<T> then<T>(
    FutureOr<T> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => Future<TaskSnapshot>.value(
    _TaskSnapshot(),
  ).then(onValue, onError: onError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TaskSnapshot implements TaskSnapshot {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
