import '../theme/readuo_theme.dart';
import 'package:flutter/material.dart';

import '../screens/friends_screen.dart';
import 'friend_repository.dart';

class InviteLinkScreen extends StatefulWidget {
  const InviteLinkScreen({
    required this.repository,
    required this.userId,
    required this.code,
    super.key,
  });

  final FriendRepository repository;
  final String userId;
  final String code;

  @override
  State<InviteLinkScreen> createState() => _InviteLinkScreenState();
}

class _InviteLinkScreenState extends State<InviteLinkScreen> {
  late Future<InviteLookupResult> _lookup;

  @override
  void initState() {
    super.initState();
    _lookup = _find();
  }

  Future<InviteLookupResult> _find() => widget.repository
      .findByInviteCode(userId: widget.userId, code: widget.code)
      .timeout(const Duration(seconds: 15));

  @override
  Widget build(BuildContext context) => FutureBuilder<InviteLookupResult>(
    future: _lookup,
    builder: (context, snapshot) {
      final result = snapshot.data;
      if (result?.profile != null &&
          result!.kind != InviteLookupKind.self &&
          result.kind != InviteLookupKind.blocked &&
          result.kind != InviteLookupKind.unknown) {
        return RequestPreviewScreen(
          repository: widget.repository,
          userId: widget.userId,
          code: widget.code,
          result: result,
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Connect with a reader')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ReaduoSpacing.screenHorizontal,
                vertical: 24,
              ),
              child: snapshot.connectionState != ConnectionState.done
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_search_outlined, size: 44),
                        const SizedBox(height: 16),
                        Text(
                          snapshot.hasError
                              ? 'Connect to the internet to open this invitation.'
                              : result?.kind == InviteLookupKind.self
                              ? 'That is your own invite code.'
                              : 'This invitation is no longer available.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        if (snapshot.hasError)
                          FilledButton(
                            onPressed: () => setState(() => _lookup = _find()),
                            child: const Text('Retry'),
                          ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => EnterInviteCodeScreen(
                                    repository: widget.repository,
                                    userId: widget.userId,
                                  ),
                                ),
                              ),
                          child: const Text('Enter a friend’s code'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );
}
