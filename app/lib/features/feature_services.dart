import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/firebase_notification_messaging.dart';
import '../notifications/notification_repository.dart';
import '../profile/callable_profile_repository.dart';
import '../profile/profile_repository.dart';
import '../moderation/moderation_repository.dart';
import '../moderation/moderation_screens.dart';
import '../friends/friend_repository.dart';
import '../friends/invite_links.dart';
import 'package:flutter/services.dart';
import '../offline/offline_library_cache.dart';
import '../offline/offline_library_controller.dart';

class FeatureServices extends InheritedWidget {
  const FeatureServices({
    required this.firestore,
    required this.auth,
    required this.profile,
    required this.notifications,
    required this.messaging,
    required this.installationId,
    required this.moderation,
    required this.invites,
    required this.offline,
    required super.child,
    super.key,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ProfileRepository profile;
  final NotificationRepository notifications;
  final FirebaseNotificationMessaging messaging;
  final String installationId;
  final ModerationRepository moderation;
  final InviteLinks invites;
  final OfflineLibraryController offline;

  static FeatureServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeatureServices>();

  static Future<void> report(BuildContext context, ReportTarget target) async {
    final services = maybeOf(context);
    if (services == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (reportContext) => ReportScreen(
          repository: services.moderation,
          target: target,
          onDone: () => Navigator.of(reportContext).pop(),
          onBlockReader: (readerId) async {
            final confirmed = await showDialog<bool>(
              context: reportContext,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Block this reader?'),
                content: const Text(
                  'This removes your friendship and prevents further interactions. Unblocking does not restore the friendship.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Block reader'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            final user = services.auth.currentUser;
            if (user == null) throw StateError('Sign in again.');
            final snapshot = await services.firestore
                .collection('readerProfiles')
                .doc(readerId)
                .get(const GetOptions(source: Source.server));
            if (!snapshot.exists)
              throw StateError('This reader is unavailable.');
            await FirebaseFriendRepository(services.firestore).blockReader(
              userId: user.uid,
              reader: ReaderProfile.fromFirestore(readerId, snapshot.data()!),
            );
            if (reportContext.mounted) Navigator.of(reportContext).pop();
          },
        ),
      ),
    );
  }

  @override
  bool updateShouldNotify(FeatureServices oldWidget) =>
      firestore != oldWidget.firestore || auth != oldWidget.auth;

  static Future<FeatureServices Function(Widget)> initialize() async {
    final invites = InviteLinks();
    await invites.initialize();
    final store = SharedPreferencesNotificationStore(SharedPreferencesAsync());
    final installationId = await store.installationId();
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    final offline = OfflineLibraryController(
      cache: OfflineLibraryCache(
        PreferencesOfflineCacheStorage(SharedPreferencesAsync()),
      ),
      probe: FirestoreOfflineServerProbe(firestore),
      networkRefresh: () => const MethodChannel(
        'com.zipdosa.readuo/settings',
      ).invokeMethod<bool>('networkAvailable'),
      networkAvailable: const EventChannel(
        'com.zipdosa.readuo/connectivity',
      ).receiveBroadcastStream().where((event) => event is bool).cast<bool>(),
    );
    final profile = CallableProfileRepository(
      auth: auth,
      storage: FirebaseStorage.instance,
    );
    final notifications = FirestoreNotificationRepository(firestore);
    final messaging = FirebaseNotificationMessaging(
      messaging: FirebaseMessaging.instance,
      store: store,
    );
    final moderation = CallableModerationRepository(
      call: (name, data) async {
        try {
          final result = await FirebaseFunctions.instance
              .httpsCallable(name)
              .call<Map<String, dynamic>>(data);
          return result.data;
        } on FirebaseFunctionsException catch (error) {
          throw ModerationFailure(
            error.message ?? 'Please try again.',
            code: error.code,
          );
        }
      },
      checkModerator: () async =>
          (await auth.currentUser?.getIdTokenResult(
            true,
          ))?.claims?['moderator'] ==
          true,
    );
    return (child) => FeatureServices(
      firestore: firestore,
      auth: auth,
      profile: profile,
      notifications: notifications,
      messaging: messaging,
      installationId: installationId,
      moderation: moderation,
      invites: invites,
      offline: offline,
      child: child,
    );
  }
}
