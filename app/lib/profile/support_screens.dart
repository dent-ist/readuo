import 'package:flutter/material.dart';

import 'profile_repository.dart';
import 'profile_widgets.dart';
import 'support_repository.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({
    this.repository = const UnavailableSupportRepository(),
    this.onDestination,
    super.key,
  });
  final SupportRepository repository;
  final ValueChanged<String>? onDestination;
  @override
  Widget build(BuildContext context) {
    void destination(String id) => onDestination == null
        ? profileUnavailable(context)
        : onDestination!(id);
    return ProfilePage(
      title: 'Help & support',
      children: [
        ProfileRow(
          'I can’t scan a book',
          Icons.camera_alt_outlined,
          subtitle: 'Camera permissions and alternatives',
          onTap: () => destination('camera-denied'),
        ),
        ProfileRow(
          'My book isn’t in the catalogue',
          Icons.search,
          subtitle: 'Search or add a book manually',
          onTap: () => destination('isbn-not-found'),
        ),
        ProfileRow(
          'Who can see my shelves?',
          Icons.shield_outlined,
          subtitle: 'Private, Friends, and Public',
          onTap: () => destination('privacy'),
        ),
        ProfileRow(
          'Report a concern',
          Icons.flag_outlined,
          subtitle: 'Posts, comments, or profiles',
          onTap: () => destination('report'),
        ),
        ProfileRow(
          'Contact support',
          Icons.mail_outline,
          subtitle: 'Get help with your account',
          onTap: () => openProfilePage(
            context,
            SupportMessageScreen(repository: repository),
          ),
        ),
      ],
    );
  }
}

class SupportMessageScreen extends StatefulWidget {
  const SupportMessageScreen({required this.repository, super.key});
  final SupportRepository repository;
  @override
  State<SupportMessageScreen> createState() => _SupportMessageScreenState();
}

class _SupportMessageScreenState extends State<SupportMessageScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _requestId = SupportDraft.newRequestId();
  SupportDraft? _submittedDraft;
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft =
          _submittedDraft ??
          SupportDraft(
            subject: _subject.text,
            message: _message.text,
            requestId: _requestId,
          );
      draft.validate();
      _submittedDraft = draft;
      await widget.repository.submit(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support request received.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is ProfileFailure
              ? error.message
              : 'Could not submit your request. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ProfilePage(
      title: 'Contact support',
      children: [
        ProfileField(
          label: 'Subject',
          controller: _subject,
          limit: 120,
          hint: 'What can we help with?',
          enabled: !_busy && _submittedDraft == null,
        ),
        ProfileField(
          label: 'Message',
          controller: _message,
          limit: 5000,
          lines: 5,
          hint: 'Describe what happened.',
          enabled: !_busy && _submittedDraft == null,
        ),
        if (_error != null) profileError(_error),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Sending…' : 'Send message'),
        ),
      ],
    ),
  );
}
