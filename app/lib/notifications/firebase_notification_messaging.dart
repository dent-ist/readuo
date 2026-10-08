import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_client.dart';

abstract interface class NotificationLocalStore {
  Future<String> installationId();
  Future<bool> wasPermissionRequested();
  Future<void> recordPermissionRequest();
}

class SharedPreferencesNotificationStore implements NotificationLocalStore {
  SharedPreferencesNotificationStore(this.preferences);
  final SharedPreferencesAsync preferences;
  Future<String>? _installation;

  @override
  Future<String> installationId() => _installation ??= _loadInstallation();

  Future<String> _loadInstallation() async {
    const key = 'readuo.notifications.installationId';
    final saved = await preferences.getString(key);
    if (saved != null && saved.isNotEmpty) return saved;
    final random = Random.secure();
    final id = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    await preferences.setString(key, id);
    return id;
  }

  @override
  Future<bool> wasPermissionRequested() async =>
      await preferences.getBool('readuo.notifications.permissionRequested') ??
      false;

  @override
  Future<void> recordPermissionRequest() =>
      preferences.setBool('readuo.notifications.permissionRequested', true);
}

class FirebaseNotificationMessaging
    implements NotificationMessaging, ForegroundNotificationMessaging {
  FirebaseNotificationMessaging({required this.messaging, required this.store});
  final FirebaseMessaging messaging;
  final NotificationLocalStore store;

  @override
  Stream<NotificationEnvelope> get foregroundMessages => FirebaseMessaging
      .onMessage
      .map((message) => NotificationEnvelope.fromData(message.data))
      .where((message) => message != null)
      .cast<NotificationEnvelope>();

  @override
  Future<NotificationPermission> permission() async {
    final status =
        (await messaging.getNotificationSettings()).authorizationStatus;
    if (status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      return NotificationPermission.granted;
    }
    return await store.wasPermissionRequested()
        ? NotificationPermission.denied
        : NotificationPermission.notDetermined;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    if (await permission() != NotificationPermission.notDetermined)
      return permission();
    await store.recordPermissionRequest();
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    return permission();
  }

  @override
  Future<String?> getToken() => messaging.getToken();
  @override
  Future<void> deleteToken() => messaging.deleteToken();
  @override
  Stream<String> get tokenRefresh => messaging.onTokenRefresh;
  @override
  Stream<String> get openedNotificationIds => FirebaseMessaging
      .onMessageOpenedApp
      .map((message) => message.data['notificationId'])
      .where((id) => id is String && id.isNotEmpty && !id.contains('/'))
      .cast<String>();
  @override
  Future<String?> initialNotificationId() async {
    final id = (await messaging.getInitialMessage())?.data['notificationId'];
    return id is String && id.isNotEmpty && !id.contains('/') ? id : null;
  }

  @override
  Future<void> openSettings() =>
      AppSettings.openAppSettings(type: AppSettingsType.notification);
}
