import '../widgets/readuo_image_cache.dart';
import '../theme/readuo_theme.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../notifications/notification_presentation.dart';
import '../auth/auth_service.dart';
import '../library/manual_book_draft.dart';
import '../profile/profile_photo_draft.dart';
import '../account_deletion/account_deletion_screen.dart';
import '../account_deletion/deletion_controller.dart';
import '../account_deletion/deletion_checkpoint_store.dart';
import '../account_deletion/firebase_deletion_backend.dart';
import '../account_deletion/google_deletion_reauthentication.dart';
import '../account_deletion/local_privacy_cleanup.dart';
import '../offline/firebase_offline_capture.dart';
import '../offline/offline_library_screens.dart';
import '../profile/information_screen.dart';
import 'feature_services.dart';

class AccountActions extends InheritedWidget {
  const AccountActions({
    required this.deleteAccount,
    required super.child,
    super.key,
  });
  final VoidCallback deleteAccount;
  static AccountActions? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountActions>();
  @override
  bool updateShouldNotify(AccountActions oldWidget) => false;
}

class AccountSessionBoundary extends StatefulWidget {
  const AccountSessionBoundary({
    required this.services,
    required this.authService,
    required this.user,
    required this.child,
    super.key,
  });
  final FeatureServices services;
  final AuthService authService;
  final AuthUser? user;
  final Widget child;
  @override
  State<AccountSessionBoundary> createState() => _AccountSessionBoundaryState();
}

class _AccountSessionBoundaryState extends State<AccountSessionBoundary>
    with WidgetsBindingObserver {
  late final _capture = FirebaseOfflineCapture(
    widget.services.firestore,
    widget.services.offline,
  );
  final _store = SharedPreferencesDeletionCheckpointStore(
    SharedPreferencesAsync(),
  );
  AccountDeletionController? _deletion;
  bool _ready = false;
  bool _capturing = false;
  String? _restoreError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.services.offline.addListener(_connectionChanged);
    unawaited(_restore());
  }

  Future<void> _restore() async {
    if (mounted)
      setState(() {
        _restoreError = null;
        _ready = false;
      });
    try {
      await _restoreSession();
    } catch (_) {
      if (mounted)
        setState(
          () => _restoreError =
              'Private device data could not be cleared. Free some storage and retry before continuing.',
        );
    }
  }

  Future<void> _restoreSession() async {
    final user = widget.user;
    await ManualBookDraftStore().clearExcept(user?.uid);
    await ProfilePhotoDraftStore().clearExcept(user?.uid);
    if (user == null) {
      await _clearPrivateImages();
      await widget.services.offline.clearSession();
      await _store.clear();
      if (mounted) setState(() => _ready = true);
      return;
    }
    try {
      final checkpoint = await _store.read();
      if (checkpoint?.uid == user.uid) {
        if (mounted) _openDeletion();
        return;
      }
      final marker = await widget.services.firestore
          .collection('accountDeletions')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      if (marker.exists) {
        if (mounted) _openDeletion();
        return;
      }
      await FirebaseFunctions.instance
          .httpsCallable('ensureActiveAccount')
          .call<void>()
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (!mounted) return;
    await widget.services.offline.selectUser(user.uid);
    if (mounted) {
      setState(() => _ready = true);
      _connectionChanged();
    }
  }

  void _connectionChanged() {
    if (!mounted || widget.user == null) return;
    final online = widget.services.offline.canShowOnline && _deletion == null;
    if (online == _capturing) return;
    _capturing = online;
    if (online) {
      _capture.start(widget.user!.uid);
    } else {
      _capture.stop();
    }
  }

  Future<void> _clearPrivateImages() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final cleared = await const MethodChannel(
      'com.zipdosa.readuo/settings',
    ).invokeMethod<bool>('clearPrivateCache');
    if (cleared != true) throw StateError('Private image cleanup failed.');
  }

  Future<void> _clearLocalData() => clearPrivateData([
    () async {
      final uid = _deletion?.uid ?? widget.user?.uid;
      if (uid != null)
        await NotificationPermissionOpportunity(
          SharedPreferencesAsync(),
          uid,
        ).clear();
    },
    _clearPrivateImages,
    ReaduoImageCache.clear,
    () => ManualBookDraftStore().clearExcept(null),
    () => ProfilePhotoDraftStore().clearExcept(null),
    widget.services.offline.clearSession,
  ]);

  void _openDeletion() {
    if (_deletion != null || widget.user == null) return;
    final reauth = FirebaseGoogleDeletionReauthentication(
      auth: widget.services.auth,
    );
    setState(() {
      _ready = true;
      _deletion = AccountDeletionController(
        uid: widget.user!.uid,
        backend: FirebaseDeletionBackend(FirebaseFunctions.instance, reauth),
        store: _store,
        reauthentication: reauth,
        clearLocalData: _clearLocalData,
      );
    });
    _capture.stop();
    _capturing = false;
  }

  void _cancelDeletion() {
    final deletion = _deletion;
    if (deletion == null || !deletion.canCancel) return;
    setState(() => _deletion = null);
    deletion.dispose();
    unawaited(_restore());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _deletion == null)
      unawaited(widget.services.offline.resume());
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.services.offline.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.services.offline.removeListener(_connectionChanged);
    _capture.stop();
    _deletion?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deletion = _deletion;
    if (deletion != null)
      return Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (pageContext) => AccountDeletionScreen(
            controller: deletion,
            onCancel: _cancelDeletion,
            onContactSupport: () => Navigator.of(pageContext).push(
              MaterialPageRoute<void>(
                builder: (_) => const InformationScreen(topic: 'terms'),
              ),
            ),
            onReturnToSignIn: () async {
              await _clearLocalData();
              await widget.authService.signOut();
            },
          ),
        ),
      );
    if (_restoreError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ReaduoSpacing.screenHorizontal,
                vertical: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_restoreError!, key: const Key('privacy-cleanup-error')),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _restore,
                    child: const Text('Retry cleanup'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (!_ready)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (widget.user == null) return widget.child;
    return AccountActions(
      deleteAccount: _openDeletion,
      child: OfflineLibraryBoundary(
        controller: widget.services.offline,
        onlineBuilder: (_) => widget.child,
        onSignOut: () async {
          await widget.services.offline.clearSession();
          await widget.authService.signOut();
        },
      ),
    );
  }
}
