import '../widgets/readuo_image_cache.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../features/feature_services.dart';
import 'profile_photo_draft.dart';
import 'profile_photo_sheet.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';
export 'profile_photo_draft.dart'
    show ProfilePhotoPicker, DeviceProfilePhotoPicker;

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.repository,
    this.photoPicker = const DeviceProfilePhotoPicker(),
    this.draftStore,
    this.draftFlow = 'edit',
    super.key,
  });
  final String uid;
  final String name;
  final String? photoUrl;
  final ProfileRepository repository;
  final ProfilePhotoPicker photoPicker;
  final ProfilePhotoDraftStore? draftStore;
  final String draftFlow;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: widget.name);
  late final _draft = ProfilePhotoDraft(
    uid: widget.uid,
    flow: widget.draftFlow,
    name: widget.name,
    picker: widget.photoPicker,
    store: widget.draftStore,
    isCurrentUser: () =>
        mounted &&
        (_services == null || _services!.auth.currentUser?.uid == widget.uid),
  );
  FeatureServices? _services;
  String? _error;
  bool _busy = true;
  bool _restoreFailed = false;
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
      _busy = true;
      _restoreFailed = false;
      _error = null;
    });
    try {
      await _draft.restore();
      if (mounted) setState(() => _name.text = _draft.name);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    FocusScope.of(context).unfocus();
    final source = await chooseProfilePhoto(context);
    if (source == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _draft.name = _name.text;
      await _draft.pick(source);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ProfileFailure
              ? error.message
              : 'Your photos are unavailable. Your details have been kept.',
        );
        if (error is! ProfileFailure)
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ProfilePhotoAccessScreen(),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _draft.name = validatedDisplayName(_name.text);
      if (_draft.photo != null) await _draft.persist();
      if (!mounted || !_draft.active) return;
      final result = await widget.repository.save(
        uid: widget.uid,
        displayName: _draft.name,
        photo: _draft.photo,
      );
      await _draft.clear();
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is ProfileFailure
              ? error.message
              : 'Could not finish saving your profile and clearing its draft. Please retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ProfilePage(
      title: 'Edit profile',
      children: [
        Column(
          children: [
            ProfileAvatar(
              name: _name.text,
              singleInitial: true,
              image: _draft.photo != null
                  ? MemoryImage(_draft.photo!.bytes)
                  : widget.photoUrl == null
                  ? null
                  : ReaduoImageCache.image(widget.photoUrl!),
            ),
            TextButton.icon(
              onPressed: _busy || _restoreFailed ? null : _pick,
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('Change photo'),
            ),
          ],
        ),
        ProfileField(
          label: 'Display name',
          controller: _name,
          limit: 80,
          enabled: !_busy && !_restoreFailed,
        ),
        if (_error != null) profileError(_error),
        if (_restoreFailed)
          TextButton(
            onPressed: _busy ? null : _restore,
            child: const Text('Retry draft recovery'),
          ),
        FilledButton(
          onPressed: _busy || _restoreFailed ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save profile'),
        ),
      ],
    ),
  );
}
