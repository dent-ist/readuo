import '../widgets/readuo_image_cache.dart';
import 'package:flutter/material.dart';
import '../theme/readuo_theme.dart';
import '../auth/auth_service.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/profile_repository.dart';
import '../profile/profile_widgets.dart';
import '../profile/support_repository.dart';
import '../profile/support_screens.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    required this.authService,
    required this.user,
    this.profileRepository = const UnavailableProfileRepository(),
    this.supportRepository = const UnavailableSupportRepository(),
    this.photoPicker = const DeviceProfilePhotoPicker(),
    this.bookCount,
    this.shelfCount,
    this.friendCount,
    this.onDestination,
    this.onNotifications,
    this.onModeration,
    this.onSupportQueue,
    this.onDeleteAccount,
    this.isModerator = false,
    super.key,
  });
  final AuthService authService;
  final AuthUser user;
  final ProfileRepository profileRepository;
  final SupportRepository supportRepository;
  final ProfilePhotoPicker photoPicker;
  final int? bookCount;
  final int? shelfCount;
  final int? friendCount;
  final ValueChanged<String>? onDestination;
  final VoidCallback? onNotifications;
  final VoidCallback? onModeration;
  final VoidCallback? onSupportQueue;
  final VoidCallback? onDeleteAccount;
  final bool isModerator;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  ProfileSaveResult? _saved;
  String get _name =>
      _saved?.displayName ?? widget.user.displayName ?? 'Reader';
  String? get _photoUrl => _saved?.photoUrl ?? widget.user.photoUrl;
  @override
  void didUpdateWidget(covariant AccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.user.displayName != widget.user.displayName ||
        oldWidget.user.photoUrl != widget.user.photoUrl)
      _saved = null;
  }

  void _destination(String id) => widget.onDestination == null
      ? profileUnavailable(context)
      : widget.onDestination!(id);
  Future<void> _edit() async {
    final result = await openProfilePage<ProfileSaveResult>(
      context,
      EditProfileScreen(
        uid: widget.user.uid,
        name: _name,
        photoUrl: _photoUrl,
        repository: widget.profileRepository,
        photoPicker: widget.photoPicker,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saved = result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.warning ?? 'Profile updated')),
    );
  }

  Future<void> _signOut() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    showDragHandle: true,
    builder: (_) => _SignOutSheet(authService: widget.authService),
  );
  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Profile',
    mainTab: true,
    back: false,
    children: [
      Row(
        children: [
          ProfileAvatar(
            name: _name,
            image: _photoUrl == null ? null : ReaduoImageCache.image(_photoUrl!),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.25,
                    letterSpacing: -.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _edit,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit profile'),
                ),
              ],
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _ProfileCount(value: widget.bookCount, label: 'Books'),
              const VerticalDivider(width: 1, color: ReaduoColors.line),
              _ProfileCount(value: widget.shelfCount, label: 'Shelves'),
              const VerticalDivider(width: 1, color: ReaduoColors.line),
              _ProfileCount(value: widget.friendCount, label: 'Friends'),
            ],
          ),
        ),
      ),
      Material(
        color: ReaduoColors.accentTint,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          onTap: () => _destination('invite'),
          leading: const Icon(
            Icons.person_add_alt,
            color: ReaduoColors.accent,
            size: 28,
          ),
          title: const Text(
            'Invite a friend',
            style: TextStyle(
              color: ReaduoColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: const Text(
            'Bring your reading circle closer',
            style: TextStyle(fontSize: 12, color: ReaduoColors.muted),
          ),
          trailing: const Icon(Icons.chevron_right, color: ReaduoColors.accent),
        ),
      ),
      _SettingsGroup(
        title: 'PREFERENCES',
        children: [
          ProfileRow(
            'Notifications',
            Icons.notifications_none,
            leadingIcon: true,
            subtitle: 'Requests, likes, and comments',
            onTap: widget.onNotifications ?? () => profileUnavailable(context),
          ),
          ProfileRow(
            'Shelf privacy',
            Icons.verified_user_outlined,
            leadingIcon: true,
            onTap: () => _destination('privacy'),
          ),
          ProfileRow(
            'Blocked readers',
            Icons.block,
            leadingIcon: true,
            onTap: () => _destination('blocked-users'),
          ),
        ],
      ),
      _SettingsGroup(
        title: 'ACCOUNT & SUPPORT',
        children: [
          ProfileRow(
            'Account & sign-in',
            Icons.key_outlined,
            leadingIcon: true,
            subtitle: '${_provider(widget.user)} sign-in',
            onTap: () => openProfilePage(
              context,
              AccountSignInScreen(
                name: _name,
                provider: _provider(widget.user),
                onDeleteAccount: widget.onDeleteAccount,
              ),
            ),
          ),
          ProfileRow(
            'Help & support',
            Icons.help_outline,
            leadingIcon: true,
            onTap: () => openProfilePage(
              context,
              SupportScreen(
                repository: widget.supportRepository,
                onDestination: widget.onDestination,
              ),
            ),
          ),
          ProfileRow(
            'Community guidelines',
            Icons.menu_book_outlined,
            leadingIcon: true,
            onTap: () => _destination('terms'),
          ),
          if (widget.isModerator) ...[
            ProfileRow(
              'Reports',
              Icons.flag_outlined,
              leadingIcon: true,
              onTap: widget.onModeration ?? () => profileUnavailable(context),
            ),
            ProfileRow(
              'Support requests',
              Icons.support_agent,
              leadingIcon: true,
              onTap: widget.onSupportQueue ?? () => profileUnavailable(context),
            ),
          ],
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _destination('privacy'),
          child: const Text('Privacy notice'),
        ),
      ),
      TextButton(
        key: const Key('sign-out-button'),
        onPressed: _signOut,
        child: const Text('Sign out'),
      ),
    ],
  );
}

class _ProfileCount extends StatelessWidget {
  const _ProfileCount({required this.value, required this.label});
  final int? value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '${value ?? '—'}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: ReaduoColors.muted),
        ),
      ],
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: .5,
            fontWeight: FontWeight.w700,
            color: ReaduoColors.muted,
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: ReaduoColors.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ReaduoColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(children: children),
        ),
      ),
    ],
  );
}

String _provider(AuthUser user) =>
    user.providerIds.contains('google.com') ? 'Google' : 'your provider';

class AccountSignInScreen extends StatelessWidget {
  const AccountSignInScreen({
    required this.name,
    required this.provider,
    this.onDeleteAccount,
    super.key,
  });
  final String name;
  final String provider;
  final VoidCallback? onDeleteAccount;
  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Account & sign-in',
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE3E8F0)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Text(
              'Signed in with $provider',
              style: const TextStyle(fontSize: 13, color: Color(0xFF58667B)),
            ),
          ],
        ),
      ),
      const ProfileBanner(
        'Use the same sign-in method when returning on another device.',
      ),
      ProfileRow(
        'Delete account',
        Icons.delete_outline,
        subtitle: 'Permanently remove your Readuo account',
        onTap: onDeleteAccount ?? () => profileUnavailable(context),
      ),
    ],
  );
}

class _SignOutSheet extends StatefulWidget {
  const _SignOutSheet({required this.authService});
  final AuthService authService;
  @override
  State<_SignOutSheet> createState() => _SignOutSheetState();
}

class _SignOutSheetState extends State<_SignOutSheet> {
  bool _busy = false;
  String? _error;
  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.authService.signOut();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is AuthFailure
              ? error.message
              : 'Could not sign out. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          0,
          ReaduoSpacing.screenHorizontal,
          22 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sign out of Readuo?',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Your library will be waiting when you sign in again. Saved account data on this device will be cleared.',
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              profileError(_error),
            ],
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('confirm-sign-out'),
              onPressed: _busy ? null : _confirm,
              child: Text(_busy ? 'Signing out…' : 'Sign out'),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Stay signed in'),
            ),
          ],
        ),
      ),
    ),
  );
}
