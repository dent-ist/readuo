import '../widgets/readuo_image_cache.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/auth_service.dart';
import '../features/feature_services.dart';
import '../friends/friend_repository.dart';
import '../onboarding/onboarding_repository.dart';
import '../profile/profile_photo_draft.dart';
import '../profile/profile_photo_sheet.dart';
import '../profile/profile_repository.dart';
import '../profile/profile_widgets.dart';
import '../theme/readuo_theme.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    required this.authService,
    required this.user,
    required this.onboardingRepository,
    this.friendRepository = const EmptyFriendRepository(),
    this.profileRepository,
    this.photoPicker = const DeviceProfilePhotoPicker(),
    this.draftStore,
    this.suggestedName,
    super.key,
  });
  final AuthService authService;
  final AuthUser user;
  final OnboardingRepository onboardingRepository;
  final FriendRepository friendRepository;
  final ProfileRepository? profileRepository;
  final ProfilePhotoPicker photoPicker;
  final ProfilePhotoDraftStore? draftStore;
  final String? suggestedName;
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final _nameController = TextEditingController(
    text: widget.suggestedName ?? '',
  );
  late final _draft = ProfilePhotoDraft(
    uid: widget.user.uid,
    flow: 'setup',
    name: _nameController.text,
    picker: widget.photoPicker,
    store: widget.draftStore,
    isCurrentUser: () =>
        mounted && widget.authService.currentUser?.uid == widget.user.uid,
  );
  FeatureServices? _services;
  bool _saving = true;
  bool _restoreFailed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = FeatureServices.maybeOf(context);
  }

  Future<void> _restore() async {
    setState(() {
      _saving = true;
      _restoreFailed = false;
      _error = null;
    });
    try {
      await _draft.restore();
      if (mounted) setState(() => _nameController.text = _draft.name);
    } catch (error) {
      _restoreFailed = error is! ProfileFailure;
      if (mounted) {
        setState(
          () => _error = error is ProfileFailure
              ? error.message
              : 'Could not restore your saved photo draft. Please reopen this screen to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    FocusScope.of(context).unfocus();
    final source = await chooseProfilePhoto(context);
    if (source == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _draft.name = _nameController.text;
      await _draft.pick(source);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ProfileFailure
              ? error.message
              : 'Photo access is unavailable. Your name is still here.',
        );
        if (error is PlatformException)
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ProfilePhotoAccessScreen(),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(
        () => _error = 'Enter a display name of 1–80 characters to continue.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _draft.name = name;
      if (widget.authService.shouldStartFirstBookOnboarding(widget.user))
        await widget.onboardingRepository.beginFirstBook(widget.user.uid);
      if (_draft.photo != null) {
        await _draft.persist();
        final repository = widget.profileRepository ?? _services?.profile;
        if (repository == null)
          throw const ProfileFailure(
            'Photo saving is unavailable. Please retry.',
          );
        await widget.friendRepository.ensureProfile(
          AuthUser(
            uid: widget.user.uid,
            displayName: name,
            email: widget.user.email,
            photoUrl: widget.user.photoUrl,
            providerIds: widget.user.providerIds,
          ),
        );
        if (!mounted || !_draft.active) return;
        await repository.save(
          uid: widget.user.uid,
          displayName: name,
          photo: _draft.photo,
        );
      }
      await _draft.clear();
      if (!mounted || !_draft.active) return;
      await widget.authService.updateDisplayName(name);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = switch (error) {
            OnboardingFailure() => error.message,
            AuthFailure() => error.message,
            ProfileFailure() => error.message,
            FriendFailure() => error.message,
            _ =>
              'Could not save your profile. Your details have been kept. Please retry.',
          },
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _draft.clear();
      await widget.authService.signOut();
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = 'Could not clear this draft and sign out. Please retry.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: ProfilePage(
      title: 'Make yourself at home',
      subtitle: 'Welcome to Readuo',
      onBack: _saving ? () {} : _leave,
      children: [
        const Text('Choose how you appear to your friends.'),
        Column(
          children: [
            ProfileAvatar(
              name: _nameController.text,
              singleInitial: true,
              image: _draft.photo != null
                  ? MemoryImage(_draft.photo!.bytes)
                  : widget.user.photoUrl == null
                  ? null
                  : ReaduoImageCache.image(widget.user.photoUrl!),
            ),
            TextButton.icon(
              onPressed: _saving || _restoreFailed ? null : _pick,
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('Add a photo'),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Display name',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 7),
            TextField(
              key: const Key('display-name-field'),
              controller: _nameController,
              enabled: !_saving && !_restoreFailed,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(80)],
              decoration: const InputDecoration(
                hintText: 'Your name',
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.all(12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                  borderSide: BorderSide(color: ReaduoColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                  borderSide: BorderSide(color: ReaduoColors.accent),
                ),
              ),
              onSubmitted: _saving || _restoreFailed ? null : (_) => _save(),
            ),
            const SizedBox(height: 7),
            const Text(
              'You can change this later.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ReaduoColors.accentTint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Your email stays out of your profile.')),
            ],
          ),
        ),
        if (_error != null) profileError(_error),
        if (_restoreFailed)
          TextButton(
            onPressed: _saving ? null : _restore,
            child: const Text('Retry draft recovery'),
          ),
        FilledButton(
          key: const Key('save-profile-button'),
          onPressed: _saving || _restoreFailed ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Continue'),
        ),
      ],
    ),
  );
}
