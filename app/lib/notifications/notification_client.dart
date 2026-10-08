import 'dart:async';

import 'notification.dart';
import 'notification_repository.dart';

enum NotificationPermission { notDetermined, granted, denied }

enum NotificationOpenResult { opened, unavailable }

typedef OpenNotificationDestination =
    Future<NotificationOpenResult> Function(
      String recipientId,
      NotificationDestination destination,
    );

abstract interface class NotificationMessaging {
  Future<NotificationPermission> permission();
  Future<NotificationPermission> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get tokenRefresh;
  Stream<String> get openedNotificationIds;
  Future<String?> initialNotificationId();
  Future<void> openSettings();
}

class NotificationEnvelope {
  const NotificationEnvelope(this.notificationId, this.recipientId);
  final String notificationId;
  final String recipientId;

  static NotificationEnvelope? fromData(Map<String, dynamic> data) {
    final id = data['notificationId'];
    final recipient = data['recipientId'];
    if (id is! String ||
        id.isEmpty ||
        id.contains('/') ||
        recipient is! String ||
        recipient.isEmpty ||
        recipient.contains('/'))
      return null;
    return NotificationEnvelope(id, recipient);
  }
}

abstract interface class ForegroundNotificationMessaging {
  Stream<NotificationEnvelope> get foregroundMessages;
}

class NotificationClient {
  NotificationClient({
    required this.userId,
    required this.installationId,
    required this.repository,
    required this.messaging,
    required this.openDestination,
    required this.onError,
    this.cleanupTimeout = const Duration(seconds: 5),
    this.canPresent,
    this.destinationAvailable,
    this.isViewing,
    this.onForeground,
  });

  final String userId;
  final String installationId;
  final NotificationRepository repository;
  final NotificationMessaging messaging;
  final OpenNotificationDestination openDestination;
  final void Function(Object error) onError;
  final Duration cleanupTimeout;
  final bool Function()? canPresent;
  final Future<bool> Function(NotificationDestination)? destinationAvailable;
  final bool Function(NotificationDestination)? isViewing;
  final void Function(ReaduoNotification)? onForeground;
  final Set<String> _foregroundSeen = {};
  final Map<String, int> _foregroundInFlight = {};
  int _foregroundEpoch = 0;
  void invalidateForeground() {
    _foregroundEpoch++;
    _foregroundInFlight.clear();
  }

  StreamSubscription<NotificationEnvelope>? _foreground;
  StreamSubscription<String>? _refresh;
  StreamSubscription<String>? _opened;
  Future<void> _tokenWork = Future.value();
  Future<void> _sdkTokenWork = Future.value();
  bool _stopped = false;
  bool _started = false;
  bool _tokenInvalidated = false;
  Future<void>? _starting;
  Future<void>? _signingOut;
  String? _initialId;
  bool _initialLoaded = false;

  bool get isActive => !_stopped;

  void _report(Object error) {
    try {
      onError(error);
    } catch (_) {}
  }

  Future<T> _tokenSdk<T>(
    Future<T> Function() operation, {
    bool cleanup = false,
  }) {
    final result = _sdkTokenWork.then<T>((_) {
      if (_stopped && !cleanup)
        throw StateError('Notification session has ended.');
      return operation();
    });
    _sdkTokenWork = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _queueToken(String token) {
    final operation = _tokenWork.then<void>((_) async {
      if (!_stopped &&
          await messaging.permission() == NotificationPermission.granted &&
          !_stopped) {
        await repository.saveToken(userId, installationId, token);
      }
    });
    _tokenWork = operation.catchError(
      (Object error) =>
          _report(StateError('Could not register notification token.')),
    );
    return operation;
  }

  Future<void> start() async {
    if (_started || _stopped) return;
    final pending = _starting;
    if (pending != null) return pending;
    final operation = _start();
    _starting = operation;
    try {
      await operation;
      if (!_stopped) _started = true;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start() async {
    if (!_tokenInvalidated) {
      await _tokenSdk(messaging.deleteToken);
      _tokenInvalidated = true;
    }
    if (_stopped) return;
    if (messaging case final ForegroundNotificationMessaging foreground) {
      _foreground ??= foreground.foregroundMessages.listen(
        (message) => unawaited(presentForeground(message)),
        onError: (Object _) {},
      );
    }
    _refresh ??= messaging.tokenRefresh.listen(
      (token) {
        unawaited(_queueToken(token).catchError((Object _) {}));
      },
      onError: (Object _) =>
          _report(StateError('Notification token refresh failed.')),
    );
    _opened ??= messaging.openedNotificationIds.listen(
      (id) {
        unawaited(
          open(id)
              .then<void>((result) {
                if (result == NotificationOpenResult.unavailable && !_stopped) {
                  _report(
                    StateError('This notification is no longer available.'),
                  );
                }
              })
              .catchError(
                (Object _) =>
                    _report(StateError('Could not open notification.')),
              ),
        );
      },
      onError: (Object _) =>
          _report(StateError('Notification listener failed.')),
    );
    await synchronizePermission();
    if (_stopped) return;
    if (!_initialLoaded) {
      _initialId = await messaging.initialNotificationId();
      _initialLoaded = true;
    }
    final initial = _initialId;
    if (initial != null && !_stopped) {
      final result = await open(initial);
      _initialId = null;
      if (result == NotificationOpenResult.unavailable) {
        _report(StateError('This notification is no longer available.'));
      }
    }
  }

  Future<NotificationPermission> synchronizePermission() async {
    final permission = await messaging.permission();
    if (_stopped) return permission;
    if (permission == NotificationPermission.granted) {
      final token = await _tokenSdk(messaging.getToken);
      if (token != null && token.isNotEmpty) await _queueToken(token);
    } else {
      await _tokenWork;
      if (!_stopped) await repository.removeToken(userId, installationId);
    }
    return permission;
  }

  Future<NotificationPermission> enableAfterRationale() async {
    if (_stopped) throw StateError('Notification session has ended.');
    final existing = await messaging.permission();
    if (existing == NotificationPermission.notDetermined) {
      await messaging.requestPermission();
    }
    final result = await messaging.permission();
    try {
      await synchronizePermission();
    } catch (error) {
      _report(StateError('Could not synchronize notification permission.'));
      if (result == NotificationPermission.granted) rethrow;
    }
    return result;
  }

  Future<NotificationOpenResult> open(String notificationId) async {
    if (_stopped) return NotificationOpenResult.unavailable;
    final item = await repository.getNotification(userId, notificationId);
    if (_stopped || item == null || item.recipientId != userId) {
      return NotificationOpenResult.unavailable;
    }
    final result = await openDestination(userId, item.destination);
    if (result == NotificationOpenResult.opened && !_stopped) {
      await repository.markRead(userId, item.id);
    }
    return result;
  }

  Future<void> presentForeground(NotificationEnvelope message) async {
    final epoch = _foregroundEpoch;
    if (_stopped ||
        message.recipientId != userId ||
        canPresent?.call() != true ||
        _foregroundSeen.contains(message.notificationId) ||
        _foregroundInFlight.containsKey(message.notificationId))
      return;
    _foregroundInFlight[message.notificationId] = epoch;
    try {
      final item = await repository
          .getNotification(userId, message.notificationId)
          .timeout(const Duration(seconds: 8));
      if (_stopped ||
          item == null ||
          item.recipientId != userId ||
          item.readAt != null ||
          DateTime.now().difference(item.createdAt) >
              const Duration(hours: 1) ||
          canPresent?.call() != true)
        return;
      final preferences = await repository
          .getPreferences(userId)
          .timeout(const Duration(seconds: 8));
      if (!preferences.enabled(item.type) ||
          await destinationAvailable
                  ?.call(item.destination)
                  .timeout(const Duration(seconds: 8)) !=
              true)
        return;
      if (!_stopped &&
          epoch == _foregroundEpoch &&
          canPresent?.call() == true) {
        _foregroundSeen.add(message.notificationId);
        if (_foregroundSeen.length > 256)
          _foregroundSeen.remove(_foregroundSeen.first);
        if (isViewing?.call(item.destination) != true) onForeground?.call(item);
      }
    } catch (_) {
    } finally {
      if (_foregroundInFlight[message.notificationId] == epoch)
        _foregroundInFlight.remove(message.notificationId);
    }
  }

  Future<void> beforeSignOut() async {
    _stopped = true;
    final pending = _signingOut;
    if (pending != null) return pending;
    final operation = _cleanupForSignOut();
    _signingOut = operation;
    try {
      await operation;
    } finally {
      _signingOut = null;
    }
  }

  Future<void> _cleanupForSignOut() async {
    await _cancelListeners();
    try {
      await _tokenSdk(
        messaging.deleteToken,
        cleanup: true,
      ).timeout(cleanupTimeout);
    } catch (_) {
      final failure = StateError(
        'Could not invalidate the notification token.',
      );
      _report(failure);
      throw failure;
    }
    if (!await _drainTokens()) return;
    try {
      await repository
          .removeToken(userId, installationId)
          .timeout(cleanupTimeout);
    } catch (_) {
      _report(
        StateError(
          'Notification token invalidated; remote unregister is pending server cleanup.',
        ),
      );
    }
  }

  Future<void> _cancelListeners() async {
    final refresh = _refresh;
    final opened = _opened;
    final foreground = _foreground;
    _refresh = null;
    _opened = null;
    _foreground = null;
    for (final subscription in <StreamSubscription<dynamic>?>[
      refresh,
      opened,
      foreground,
    ]) {
      try {
        await subscription?.cancel().timeout(cleanupTimeout);
      } catch (_) {
        _report(StateError('Could not stop a notification listener.'));
      }
    }
  }

  Future<bool> _drainTokens() async {
    try {
      await _tokenWork.timeout(cleanupTimeout);
      return true;
    } catch (_) {
      _report(
        StateError(
          'Notification registration is still pending; stale token requires server cleanup.',
        ),
      );
      return false;
    }
  }

  Future<void> dispose() async {
    _stopped = true;
    await _cancelListeners();
    await _drainTokens();
  }
}
