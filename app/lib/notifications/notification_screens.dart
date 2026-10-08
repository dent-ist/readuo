import 'package:flutter/material.dart';

import '../theme/readuo_theme.dart';
import 'notification.dart';
import 'notification_client.dart';
import 'notification_repository.dart';
import 'notification_features.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    required this.client,
    required this.onSettings,
    super.key,
  });
  final NotificationClient client;
  final VoidCallback onSettings;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Stream<List<ReaduoNotification>> _items;
  String? _opening;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _items = widget.client.repository.watchNotifications(widget.client.userId);
  }

  Future<void> _open(ReaduoNotification item) async {
    setState(() {
      _opening = item.id;
      _error = null;
    });
    try {
      final result = await widget.client.open(item.id);
      if (mounted && result == NotificationOpenResult.unavailable) {
        setState(() => _error = 'This notification is no longer available.');
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Couldn’t open this notification. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ReaduoNotification>>(
    stream: _items,
    builder: (context, snapshot) => _NotificationPage(
      title: 'Notifications',
      action: snapshot.hasData && snapshot.data!.isNotEmpty
          ? _HeaderButton(
              icon: Icons.tune_rounded,
              label: 'Notification settings',
              onPressed: widget.onSettings,
            )
          : null,
      children: [
        if (_error != null) _Notice(_error!, error: true),
        if (snapshot.hasError) ...[
          const _Notice(
            'Couldn’t load notifications. Please try again.',
            error: true,
          ),
          OutlinedButton(
            onPressed: () => setState(_load),
            child: const Text('Try again'),
          ),
        ] else if (!snapshot.hasData)
          const Center(child: CircularProgressIndicator())
        else if (snapshot.data!.isEmpty)
          const _EmptyNotification(
            title: 'You’re all caught up',
            message:
                'Friend requests and responses to your posts will appear here.',
          )
        else
          for (final item in snapshot.data!)
            Semantics(
              label: item.readAt == null
                  ? 'Unread notification'
                  : 'Read notification',
              child: InkWell(
                onTap: _opening == null ? () => _open(item) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: ReaduoColors.line),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: ReaduoColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _subtitle(item),
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: ReaduoColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_opening == item.id)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          switch (item.type) {
                            NotificationType.friendRequest =>
                              Icons.person_add_alt_outlined,
                            NotificationType.requestAccepted =>
                              Icons.people_outline,
                            NotificationType.like => Icons.favorite_border,
                            NotificationType.comment =>
                              Icons.chat_bubble_outline,
                            NotificationType.booksAdded =>
                              Icons.library_books_outlined,
                          },
                          size: 20,
                          color: ReaduoColors.ink,
                        ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    ),
  );

  String _subtitle(ReaduoNotification item) {
    final age = DateTime.now().difference(item.createdAt);
    final time = age.inMinutes < 1
        ? 'Just now'
        : age.inHours < 1
        ? '${age.inMinutes}m ago'
        : age.inHours < 24
        ? '${age.inHours}h ago'
        : age.inDays == 1
        ? 'Yesterday'
        : '${age.inDays}d ago';
    final prefix = item.type == NotificationType.requestAccepted
        ? 'You’re now connected'
        : item.preview;
    return prefix.isEmpty ? time : '$prefix · $time';
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    required this.userId,
    required this.repository,
    required this.openSettings,
    this.enableLabel = 'Phone notification settings',
    this.bookAdditionsEnabled = bookAdditionNotificationsEnabled,
    super.key,
  });
  final String userId;
  final NotificationRepository repository;
  final Future<void> Function() openSettings;
  final String enableLabel;
  final bool bookAdditionsEnabled;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late Stream<NotificationPreferences> _preferences;
  final Set<NotificationType> _saving = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _preferences = widget.repository.watchPreferences(widget.userId);
  }

  Future<void> _save(NotificationType type, bool enabled) async {
    setState(() {
      _saving.add(type);
      _error = null;
    });
    try {
      await widget.repository.setPreference(widget.userId, type, enabled);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Couldn’t save your preference. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _saving.remove(type));
    }
  }

  Future<void> _settings() async {
    try {
      await widget.openSettings();
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Couldn’t open phone settings. Please try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => _NotificationPage(
    title: 'Notifications',
    children: [
      const _Notice(
        'Push notifications are also controlled in your phone settings.',
      ),
      if (_error != null) _Notice(_error!, error: true),
      StreamBuilder<NotificationPreferences>(
        key: const ValueKey('notification-preferences'),
        stream: _preferences,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Column(
              children: [
                const _Notice(
                  'Couldn’t load preferences. Please try again.',
                  error: true,
                ),
                OutlinedButton(
                  onPressed: () => setState(_load),
                  child: const Text('Try again'),
                ),
              ],
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          return Column(
            children: [
              for (final type in NotificationType.values.where(
                (type) =>
                    widget.bookAdditionsEnabled ||
                    type != NotificationType.booksAdded,
              ))
                Padding(
                  padding: EdgeInsets.only(
                    top: type == NotificationType.friendRequest ? 0 : 16,
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 54),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: ReaduoColors.line),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _label(type),
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: ReaduoColors.ink,
                            ),
                          ),
                        ),
                        Semantics(
                          label: _label(type),
                          child: SizedBox(
                            width: 54,
                            height: 34,
                            child: FittedBox(
                              child: Switch(
                                value: snapshot.data!.enabled(type),
                                activeTrackColor: ReaduoColors.accent,
                                activeThumbColor: Colors.white,
                                inactiveTrackColor: const Color(0xFFCAD3E1),
                                inactiveThumbColor: Colors.white,
                                trackOutlineColor: const WidgetStatePropertyAll(
                                  Colors.transparent,
                                ),
                                onChanged: _saving.contains(type)
                                    ? null
                                    : (value) => _save(type, value),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      Text(
        widget.bookAdditionsEnabled
            ? 'Friends’ new owned books are grouped after two quiet minutes. Reading-status updates stay in Circle without pushes.'
            : 'Book additions and reading updates appear in Circle without individual push notifications.',
        style: const TextStyle(
          fontSize: 12,
          height: 1.5,
          color: ReaduoColors.muted,
        ),
      ),
      OutlinedButton(
        onPressed: _settings,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(widget.enableLabel),
      ),
    ],
  );

  String _label(NotificationType type) => switch (type) {
    NotificationType.friendRequest => 'Friend requests',
    NotificationType.requestAccepted => 'Request accepted',
    NotificationType.like => 'Likes on my posts',
    NotificationType.comment => 'Comments on my posts',
    NotificationType.booksAdded => 'Friends add books',
  };
}

class NotificationPermissionScreen extends StatefulWidget {
  const NotificationPermissionScreen({
    required this.client,
    required this.onDone,
    super.key,
  });
  final NotificationClient client;
  final VoidCallback onDone;

  @override
  State<NotificationPermissionScreen> createState() =>
      _NotificationPermissionScreenState();
}

class _NotificationPermissionScreenState
    extends State<NotificationPermissionScreen> {
  bool _busy = false;
  bool _denied = false;
  String? _error;

  Future<void> _enable() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final permission = await widget.client.enableAfterRationale();
      if (!mounted) return;
      if (permission == NotificationPermission.granted) {
        widget.onDone();
      } else {
        setState(() => _denied = true);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Couldn’t enable notifications. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    try {
      await widget.client.messaging.openSettings();
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Couldn’t open phone settings. Please try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => _NotificationPage(
    title: 'Stay in the loop',
    children: [
      _EmptyNotification(
        title: 'Hear from your circle',
        message: bookAdditionNotificationsEnabled
            ? 'Get friend requests, acceptances, likes, comments and grouped alerts when friends add owned books. No reading-status alerts.'
            : 'Get friend requests, acceptances, likes and comments from your circle.',
        action: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          onPressed: _busy || _denied ? null : _enable,
          child: Text(_busy ? 'Enabling…' : 'Enable notifications'),
        ),
      ),
      if (_denied) ...[
        const _Notice(
          'Notifications are off in your phone settings. Your preferences are saved.',
        ),
        OutlinedButton(
          onPressed: _settings,
          child: const Text('Phone notification settings'),
        ),
      ],
      if (_error != null) _Notice(_error!, error: true),
      TextButton(
        onPressed: _busy ? null : widget.onDone,
        child: const Text('Not now'),
      ),
    ],
  );
}

class _NotificationPage extends StatelessWidget {
  const _NotificationPage({
    required this.title,
    required this.children,
    this.action,
  });
  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReaduoColors.background,
    body: SafeArea(
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              14,
              ReaduoSpacing.screenHorizontal,
              16,
            ),
            child: Row(
              children: [
                _HeaderButton(
                  icon: Icons.arrow_back,
                  label: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1.15,
                      letterSpacing: -.7,
                      fontWeight: FontWeight.w500,
                      color: ReaduoColors.ink,
                    ),
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 10), action!],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                ReaduoSpacing.screenHorizontal,
                18,
                ReaduoSpacing.screenHorizontal,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    if (index > 0) const SizedBox(height: 16),
                    children[index],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton.outlined(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: ReaduoColors.ink,
        side: const BorderSide(color: ReaduoColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
  );
}

class _EmptyNotification extends StatelessWidget {
  const _EmptyNotification({
    required this.title,
    required this.message,
    this.action,
  });
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(5, 50, 5, 28),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: ReaduoColors.accentTint,
            borderRadius: BorderRadius.circular(23),
          ),
          child: const Icon(
            Icons.notifications_none,
            size: 30,
            color: ReaduoColors.accent,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 21,
            height: 1.25,
            letterSpacing: -.4,
            fontWeight: FontWeight.w500,
            color: ReaduoColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: ReaduoColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 23),
        if (action != null) action!,
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFF0F1) : ReaduoColors.accentTint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline : Icons.info_outline,
          size: 18,
          color: error ? const Color(0xFFA6283B) : const Color(0xFF304E9F),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: error ? const Color(0xFFA6283B) : const Color(0xFF304E9F),
            ),
          ),
        ),
      ],
    ),
  );
}
