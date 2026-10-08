import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/readuo_theme.dart';
import '../widgets/readuo_tab_activity.dart';
import 'notification.dart';
import 'notification_client.dart';

class NotificationRouteVisibility extends InheritedWidget {
  const NotificationRouteVisibility({
    required this.visible,
    required super.child,
    super.key,
  });
  final bool visible;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NotificationRouteVisibility>()
          ?.visible ??
      true;
  @override
  bool updateShouldNotify(NotificationRouteVisibility oldWidget) =>
      visible != oldWidget.visible;
}

class NotificationDestinationMarker extends StatefulWidget {
  const NotificationDestinationMarker({
    required this.destination,
    required this.child,
    super.key,
  });
  final NotificationDestination? destination;
  final Widget child;
  static final Set<_NotificationDestinationMarkerState> _views = {};

  static bool isViewing(NotificationDestination destination) =>
      _views.any((view) {
        final current = view.widget.destination;
        return view.mounted &&
            view._active &&
            view._ticker &&
            view._route?.isCurrent == true &&
            current?.kind == destination.kind &&
            current?.id == destination.id &&
            current?.isReview == destination.isReview;
      });

  @override
  State<NotificationDestinationMarker> createState() =>
      _NotificationDestinationMarkerState();
}

class _NotificationDestinationMarkerState
    extends State<NotificationDestinationMarker> {
  ModalRoute<dynamic>? _route;
  bool _active = false;
  bool _ticker = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _active =
        ReaduoTabActivity.isActive(context) &&
        NotificationRouteVisibility.of(context);
    _ticker = TickerMode.valuesOf(context).enabled;
    NotificationDestinationMarker._views.add(this);
  }

  @override
  void dispose() {
    NotificationDestinationMarker._views.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class NotificationPermissionOpportunity {
  NotificationPermissionOpportunity(this.preferences, this.userId);
  final SharedPreferencesAsync preferences;
  final String userId;
  bool _busy = false;
  bool _finished = false;

  Future<void> recordShown() async {
    await preferences.setBool(
      'readuo.notifications.friendRationale.$userId',
      true,
    );
    _finished = true;
  }

  Future<void> clear() =>
      preferences.remove('readuo.notifications.friendRationale.$userId');

  Future<bool> claim({
    required int friendCount,
    required NotificationPermission permission,
    required bool Function() isCurrent,
  }) async {
    if (_busy || _finished || friendCount == 0 || !isCurrent()) return false;
    _busy = true;
    try {
      final key = 'readuo.notifications.friendRationale.$userId';
      if (await preferences.getBool(key) == true ||
          permission != NotificationPermission.notDetermined) {
        _finished = true;
        return false;
      }
      if (!isCurrent()) return false;
      await recordShown();
      return isCurrent();
    } finally {
      _busy = false;
    }
  }
}

class QuietNotificationBanner extends StatelessWidget {
  const QuietNotificationBanner({
    required this.onOpen,
    required this.onDismiss,
    super.key,
  });
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: ReaduoColors.paper,
          elevation: 4,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpen,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          color: ReaduoColors.accent,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Readuo',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: ReaduoColors.ink,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'New activity in your circle. Tap to view.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: ReaduoColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss notification',
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class NotificationBannerOverlay {
  OverlayEntry? _entry;
  Timer? _timer;
  void dismiss() {
    _timer?.cancel();
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void show(BuildContext context, VoidCallback onOpen) {
    dismiss();
    _entry = OverlayEntry(
      builder: (_) => QuietNotificationBanner(
        onOpen: () {
          dismiss();
          onOpen();
        },
        onDismiss: dismiss,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _timer = Timer(const Duration(seconds: 6), dismiss);
  }
}
