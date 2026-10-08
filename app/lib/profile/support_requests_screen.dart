import 'package:flutter/material.dart';
import 'profile_widgets.dart';
import 'support_repository.dart';

class SupportRequestsScreen extends StatefulWidget {
  const SupportRequestsScreen({required this.repository, super.key});
  final SupportOperatorRepository repository;
  @override
  State<SupportRequestsScreen> createState() => _SupportRequestsScreenState();
}

class _SupportRequestsScreenState extends State<SupportRequestsScreen> {
  late Stream<List<SupportRequest>> _requests = widget.repository
      .watchPending();
  final Set<String> _busy = {};
  String? _error;
  Future<void> _resolve(String id) async {
    setState(() {
      _busy.add(id);
      _error = null;
    });
    try {
      await widget.repository.resolve(id);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Could not resolve this request. Please retry.',
        );
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SupportRequest>>(
    stream: _requests,
    builder: (context, snapshot) => ProfilePage(
      title: 'Support requests',
      children: [
        if (snapshot.hasError) ...[
          profileError(
            'Could not load support requests. Moderator access is required.',
          ),
          TextButton(
            onPressed: () =>
                setState(() => _requests = widget.repository.watchPending()),
            child: const Text('Retry'),
          ),
        ] else if (!snapshot.hasData)
          const Center(child: CircularProgressIndicator())
        else if (snapshot.data!.isEmpty)
          const Text('No pending support requests.')
        else ...[
          const Text(
            'Oldest pending requests first · up to 100 at a time',
            style: TextStyle(fontSize: 12),
          ),
          for (final request in snapshot.data!)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE3E8F0)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    request.subject,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'Reader: ${request.ownerId}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (request.createdAt != null)
                    Text(
                      request.createdAt!.toLocal().toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  const SizedBox(height: 16),
                  SelectableText(request.message),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _busy.contains(request.id)
                        ? null
                        : () => _resolve(request.id),
                    child: Text(
                      _busy.contains(request.id)
                          ? 'Resolving…'
                          : 'Mark resolved',
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (_error != null) profileError(_error),
      ],
    ),
  );
}
