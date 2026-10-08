import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:readuo/profile/profile_photo_draft.dart';
import 'package:readuo/profile/profile_repository.dart';
import 'p1_19_21_test.dart' show MemoryCache;

class Picker implements ProfilePhotoPicker, RecoverableProfilePhotoPicker {
  ProfilePhoto? result;
  Completer<ProfilePhoto?>? pending;
  Object? failure;
  int recoveries = 0;
  @override
  Future<ProfilePhoto?> pick(ImageSource source) async {
    if (failure != null) throw failure!;
    return pending == null ? result : pending!.future;
  }

  @override
  Future<ProfilePhoto?> recover() async {
    recoveries++;
    return result;
  }
}

void main() {
  final photo = ProfilePhoto(Uint8List.fromList([255, 216, 255]), 'image/jpeg');
  test(
    'camera checkpoint recovers name and lost bytes after process recreation',
    () async {
      final memory = MemoryCache();
      final store = ProfilePhotoDraftStore(storage: memory);
      await store.write('owner', {
        'flow': 'setup',
        'name': 'Maya',
        'pickerPending': true,
      });
      final picker = Picker()..result = photo;
      final draft = ProfilePhotoDraft(
        uid: 'owner',
        flow: 'setup',
        name: '',
        picker: picker,
        store: store,
      );
      await draft.restore();
      expect(draft.name, 'Maya');
      expect(draft.photo!.bytes, photo.bytes);
      expect(picker.recoveries, 1);
      expect((await store.read('owner'))!['pickerPending'], false);
      draft.dispose();
      final recreated = ProfilePhotoDraft(
        uid: 'owner',
        flow: 'setup',
        name: '',
        picker: picker,
        store: store,
      );
      await recreated.restore();
      expect(recreated.photo!.bytes, photo.bytes);
      expect(picker.recoveries, 1);
      recreated.dispose();
    },
  );
  test('cancelled and denied picker preserve prior photo and name', () async {
    final store = ProfilePhotoDraftStore(storage: MemoryCache());
    final picker = Picker()..result = photo;
    final draft = ProfilePhotoDraft(
      uid: 'owner',
      flow: 'edit',
      name: 'Maya',
      picker: picker,
      store: store,
    );
    await draft.pick(ImageSource.gallery);
    picker.result = null;
    await draft.pick(ImageSource.camera);
    expect(draft.photo, photo);
    picker.failure = const ProfileFailure('Denied');
    await expectLater(
      draft.pick(ImageSource.gallery),
      throwsA(isA<ProfileFailure>()),
    );
    expect(draft.name, 'Maya');
    expect((await store.read('owner'))!['photo'], isNotNull);
    draft.dispose();
  });
  test(
    'late picker result cannot recreate old UID draft after account switch',
    () async {
      final memory = MemoryCache();
      final store = ProfilePhotoDraftStore(storage: memory);
      final picker = Picker()..pending = Completer<ProfilePhoto?>();
      var uid = 'first';
      final draft = ProfilePhotoDraft(
        uid: 'first',
        flow: 'edit',
        name: 'Private',
        picker: picker,
        store: store,
        isCurrentUser: () => uid == 'first',
      );
      final picking = draft.pick(ImageSource.camera);
      await Future<void>.delayed(Duration.zero);
      uid = 'second';
      await store.clearExcept('second');
      picker.pending!.complete(photo);
      await picking;
      expect(await store.read('first'), isNull);
      expect(await store.read('second'), isNull);
      expect(memory.values, isEmpty);
      draft.dispose();
    },
  );
  test(
    'draft scopes isolate onboarding and edit recovery; explicit clear erases bytes',
    () async {
      final store = ProfilePhotoDraftStore(storage: MemoryCache());
      final picker = Picker()..result = photo;
      final setup = ProfilePhotoDraft(
        uid: 'owner',
        flow: 'setup',
        name: 'Maya',
        picker: picker,
        store: store,
      );
      await setup.pick(ImageSource.gallery);
      final edit = ProfilePhotoDraft(
        uid: 'owner',
        flow: 'edit',
        name: 'Current',
        picker: picker,
        store: store,
      );
      await edit.restore();
      expect(edit.photo, isNull);
      expect(edit.name, 'Current');
      await setup.clear();
      expect(await store.read('owner'), isNull);
      setup.dispose();
      edit.dispose();
    },
  );
}
