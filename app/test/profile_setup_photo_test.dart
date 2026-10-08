import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/auth/auth_service.dart';
import 'package:readuo/profile/profile_photo_draft.dart';
import 'package:readuo/profile/profile_repository.dart';
import 'package:readuo/screens/profile_setup_screen.dart';
import 'package:readuo/theme/readuo_theme.dart';
import 'profile_photo_draft_test.dart' show Picker;
import 'p1_19_21_test.dart' show MemoryCache;
import 'widget_test.dart' show FakeAuthService, FakeOnboardingRepository;

class SetupProfiles implements ProfileRepository {
  final photos = <ProfilePhoto?>[];
  bool fail = true;
  @override
  Future<ProfileSaveResult> save({
    required String uid,
    required String displayName,
    ProfilePhoto? photo,
  }) async {
    photos.add(photo);
    if (fail) throw const ProfileFailure('Photo save failed. Retry.');
    return ProfileSaveResult(displayName, null);
  }
}

void main() {
  testWidgets(
    'onboarding photo failure retains draft and retries before completing name setup',
    (tester) async {
      const user = AuthUser(
        uid: 'setup-reader',
        displayName: null,
        email: 'reader@example.test',
        photoUrl: null,
        providerIds: {'google.com'},
      );
      final auth = FakeAuthService(current: user);
      final onboarding = FakeOnboardingRepository();
      final repository = SetupProfiles();
      final store = ProfilePhotoDraftStore(storage: MemoryCache());
      final picker = Picker()
        ..result = ProfilePhoto(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM1sAAAAASUVORK5CYII=',
          ),
          'image/png',
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaduoTheme.modern,
          home: ProfileSetupScreen(
            authService: auth,
            user: user,
            onboardingRepository: onboarding,
            profileRepository: repository,
            photoPicker: picker,
            draftStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('display-name-field')),
        'Maya',
      );
      await tester.tap(find.text('Add a photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from library'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save-profile-button')));
      await tester.tap(find.byKey(const Key('save-profile-button')));
      await tester.pumpAndSettle();
      expect(auth.savedDisplayName, isNull);
      expect((await store.read(user.uid))!['photo'], isNotEmpty);
      expect(onboarding.beginOwnerIds, [user.uid]);
      repository.fail = false;
      await tester.ensureVisible(find.byKey(const Key('save-profile-button')));
      await tester.tap(find.byKey(const Key('save-profile-button')));
      await tester.pumpAndSettle();
      expect(auth.savedDisplayName, 'Maya');
      expect(repository.photos.length, 2);
      expect(repository.photos.last!.bytes, picker.result!.bytes);
      expect(await store.read(user.uid), isNull);
    },
  );
}
