import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readuo/notifications/firebase_notification_messaging.dart';
import 'package:readuo/notifications/notification_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestPreferences implements SharedPreferencesAsync {
  final Map<String, Object> values = {};
  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSettings implements NotificationSettings {
  TestSettings(this.authorizationStatus);
  @override
  final AuthorizationStatus authorizationStatus;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestFirebaseMessaging implements FirebaseMessaging {
  AuthorizationStatus status = AuthorizationStatus.denied;
  int requests = 0;
  Future<void> Function()? beforeRequest;
  @override
  Future<NotificationSettings> getNotificationSettings() async =>
      TestSettings(status);
  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    await beforeRequest?.call();
    requests++;
    return TestSettings(status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'installation ID survives new store instances and concurrent reads',
    () async {
      final preferences = TestPreferences();
      final store = SharedPreferencesNotificationStore(preferences);
      final ids = await Future.wait([
        store.installationId(),
        store.installationId(),
      ]);
      expect(ids.first, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(ids.last, ids.first);
      expect(
        await SharedPreferencesNotificationStore(preferences).installationId(),
        ids.first,
      );
    },
  );

  test(
    'Android first denied status permits exactly one explicit request',
    () async {
      final preferences = TestPreferences();
      final store = SharedPreferencesNotificationStore(preferences);
      final sdk = TestFirebaseMessaging();
      sdk.beforeRequest = () async {
        expect(await store.wasPermissionRequested(), isTrue);
      };
      final adapter = FirebaseNotificationMessaging(
        messaging: sdk,
        store: store,
      );
      expect(await adapter.permission(), NotificationPermission.notDetermined);
      expect(sdk.requests, 0);
      expect(await adapter.requestPermission(), NotificationPermission.denied);
      expect(sdk.requests, 1);
      final restarted = FirebaseNotificationMessaging(
        messaging: sdk,
        store: SharedPreferencesNotificationStore(preferences),
      );
      expect(await restarted.permission(), NotificationPermission.denied);
      await restarted.requestPermission();
      expect(sdk.requests, 1);
      sdk.status = AuthorizationStatus.authorized;
      expect(await restarted.permission(), NotificationPermission.granted);
    },
  );
}
