import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../circle/photo_repository.dart';
import '../theme/readuo_theme.dart';
import '../profile/profile_widgets.dart';
import 'content_filter.dart';
import 'moderation_repository.dart';

const _danger = Color(0xFFBD3548);

class ModerationPage extends StatelessWidget {
  const ModerationPage({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      ProfilePage(title: title, children: children);
}

Widget _note(
  TextEditingController controller,
  String label,
  String hint, {
  bool enabled = true,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
    const SizedBox(height: 8),
    TextField(
      controller: controller,
      enabled: enabled,
      minLines: 4,
      maxLines: 8,
      maxLength: 2000,
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ReaduoColors.line),
        ),
      ),
    ),
  ],
);

Widget _badge(String text) => Align(
  alignment: Alignment.centerLeft,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: ReaduoColors.accentTint,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.shield_outlined, size: 14, color: ReaduoColors.accent),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(color: ReaduoColors.accent, fontSize: 12),
          ),
        ),
      ],
    ),
  ),
);

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    required this.repository,
    required this.target,
    required this.onDone,
    this.onBlockReader,
    super.key,
  });
  final ModerationRepository repository;
  final ReportTarget target;
  final VoidCallback onDone;
  final void Function(String readerId)? onBlockReader;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _noteController = TextEditingController();
  String _requestId = newReportRequestId();
  String? _submittedPayload;
  String _reason = reportReasons.first;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final payload = '$_reason\n${_noteController.text}';
    if (_submittedPayload != null && _submittedPayload != payload)
      _requestId = newReportRequestId();
    _submittedPayload = payload;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository.submit(
        requestId: _requestId,
        target: widget.target,
        reason: _reason,
        note: _noteController.text,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReportSentScreen(
            support: widget.target.kind == 'support',
            onDone: widget.onDone,
            onBlock: receipt.readerId != null && widget.onBlockReader != null
                ? () => widget.onBlockReader!(receipt.readerId!)
                : null,
          ),
        ),
      );
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error.toString();
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => ModerationPage(
    title: 'Report a concern',
    children: [
      const Text(
        'Tell us what’s wrong. Your report is not shown to the person you’re reporting.',
        style: TextStyle(fontSize: 14, height: 1.6, color: ReaduoColors.muted),
      ),
      RadioGroup<String>(
        groupValue: _reason,
        onChanged: (value) {
          if (!_busy && value != null) setState(() => _reason = value);
        },
        child: Column(
          children: [
            for (final reason in reportReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: ReaduoColors.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RadioListTile<String>(
                    value: reason,
                    enabled: !_busy,
                    title: Text(reason, style: const TextStyle(fontSize: 14)),
                  ),
                ),
              ),
          ],
        ),
      ),
      _note(
        _noteController,
        'Additional details (optional)',
        'Anything else we should know?',
        enabled: !_busy,
      ),
      if (_error != null) Text(_error!, style: const TextStyle(color: _danger)),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Submitting…' : 'Submit report'),
      ),
    ],
  );
}

class ReportSentScreen extends StatelessWidget {
  const ReportSentScreen({
    required this.support,
    required this.onDone,
    this.onBlock,
    super.key,
  });
  final bool support;
  final VoidCallback onDone;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) => ModerationPage(
    title: 'Report received',
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(5, 50, 5, 12),
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
                Icons.flag_outlined,
                size: 30,
                color: ReaduoColors.accent,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Thanks for letting us know',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              onBlock == null
                  ? 'Your report is ready for operator review.'
                  : 'Your report is ready for review. You can also block this reader to stop further interactions.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: ReaduoColors.muted,
              ),
            ),
          ],
        ),
      ),
      FilledButton(
        onPressed: onDone,
        child: Text(support ? 'Back to support' : 'Back to Circle'),
      ),
      if (onBlock != null)
        OutlinedButton(
          onPressed: onBlock,
          child: const Text('Block this reader'),
        ),
    ],
  );
}

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({
    required this.repository,
    this.photoRepository = const EmptyCirclePhotoRepository(),
    super.key,
  });
  final ModerationRepository repository;
  final CirclePhotoRepository photoRepository;
  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  final List<ModerationReport> _reports = [];
  bool _busy = true;
  String? _error;
  String? _cursor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      if (!more) _reports.clear();
    });
    try {
      if (!await widget.repository.isModerator())
        throw const ModerationFailure('Moderator access required.');
      final page = await widget.repository.list(afterId: more ? _cursor : null);
      if (mounted)
        setState(() {
          _reports.addAll(page.reports);
          _cursor = page.nextCursor;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _reports.clear();
          _error = error.toString();
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ModerationPage(
    title: 'Reports',
    children: [
      _badge('Moderator access only'),
      if (_busy) const Center(child: CircularProgressIndicator()),
      if (_error != null) Text(_error!, style: const TextStyle(color: _danger)),
      if (!_busy && _error == null)
        Text(
          'Awaiting review · ${_reports.length}${_cursor != null ? '+' : ''}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      if (!_busy && _error == null && _reports.isEmpty)
        const Text('No reports awaiting review.'),
      for (final report in _reports)
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: ReaduoColors.line)),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Reported ${report.kind}'),
            subtitle: Text(report.reason),
            trailing: const Icon(Icons.flag_outlined),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportDetailScreen(
                    repository: widget.repository,
                    report: report,
                    photoRepository: widget.photoRepository,
                  ),
                ),
              );
              if (mounted) _load();
            },
          ),
        ),
      if (_cursor != null && !_busy)
        OutlinedButton(
          onPressed: () => _load(more: true),
          child: const Text('Load more'),
        ),
      if (!_busy)
        OutlinedButton(onPressed: _load, child: const Text('Refresh')),
    ],
  );
}

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({
    required this.repository,
    required this.report,
    this.photoRepository = const EmptyCirclePhotoRepository(),
    super.key,
  });
  final ModerationRepository repository;
  final ModerationReport report;
  final CirclePhotoRepository photoRepository;
  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late final _controller = TextEditingController(
    text: widget.report.reviewNote,
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decide(String decision) async {
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = 'Record your decision in a review note.');
      return;
    }
    if (decision == 'remove' && widget.report.status != 'processing') {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const ModerationActionSheet(),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.decide(
        reportId: widget.report.id,
        decision: decision,
        note: _controller.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = error.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => ModerationPage(
    title: 'Review report',
    children: [
      _badge(
        widget.report.status == 'processing'
            ? 'Action needs retry'
            : 'Pending review',
      ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: ReaduoColors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reason',
              style: TextStyle(fontSize: 12, color: ReaduoColors.muted),
            ),
            const SizedBox(height: 6),
            Text(widget.report.reason),
            const Divider(height: 32),
            const Text(
              'Reported content',
              style: TextStyle(fontSize: 12, color: ReaduoColors.muted),
            ),
            const SizedBox(height: 6),
            Text(widget.report.content),
            if (widget.report.photoPath != null ||
                widget.report.photoUrl != null) ...[
              const SizedBox(height: 12),
              ReportPhotoSnapshot(
                report: widget.report,
                repository: widget.photoRepository,
              ),
            ],
            const Divider(height: 32),
            const Text(
              'Reporter’s note',
              style: TextStyle(fontSize: 12, color: ReaduoColors.muted),
            ),
            const SizedBox(height: 6),
            Text(
              widget.report.note.isEmpty
                  ? 'No additional details.'
                  : widget.report.note,
            ),
          ],
        ),
      ),
      _note(
        _controller,
        'Review note',
        'Record your decision.',
        enabled: !_busy && widget.report.status != 'processing',
      ),
      if (_error != null) Text(_error!, style: const TextStyle(color: _danger)),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: _danger),
        onPressed: _busy
            ? null
            : () => _decide(
                widget.report.decision ??
                    (widget.report.kind == 'support' ? 'resolve' : 'remove'),
              ),
        child: Text(
          _busy
              ? 'Saving…'
              : widget.report.status == 'processing'
              ? 'Retry action'
              : widget.report.kind == 'support'
              ? 'Resolve concern'
              : 'Remove content',
        ),
      ),
      if (widget.report.status != 'processing')
        OutlinedButton(
          onPressed: _busy ? null : () => _decide('dismiss'),
          child: const Text('Dismiss report'),
        ),
    ],
  );
}

class ReportPhotoSnapshot extends StatefulWidget {
  const ReportPhotoSnapshot({
    required this.report,
    required this.repository,
    super.key,
  });
  final ModerationReport report;
  final CirclePhotoRepository repository;

  @override
  State<ReportPhotoSnapshot> createState() => _ReportPhotoSnapshotState();
}

class _ReportPhotoSnapshotState extends State<ReportPhotoSnapshot> {
  late final Future<Uint8List?>? _bytes = widget.report.photoPath == null
      ? null
      : widget.repository
            .load(widget.report.photoPath!)
            .timeout(const Duration(seconds: 20));

  Widget get _unavailable => const Padding(
    padding: EdgeInsets.all(12),
    child: Text(
      'The reported image is unavailable. It may have been removed or access may have changed.',
      style: TextStyle(fontSize: 14, color: ReaduoColors.muted),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Loading reported image…'),
            );
          if (snapshot.hasError || snapshot.data == null) return _unavailable;
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
            semanticLabel: 'Reported image',
            errorBuilder: (_, error, stack) => _unavailable,
          );
        },
      );
    }
    final uri = Uri.tryParse(widget.report.photoUrl ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty)
      return _unavailable;
    return Image.network(
      uri.toString(),
      fit: BoxFit.contain,
      semanticLabel: 'Reported profile image',
      errorBuilder: (_, error, stack) => _unavailable,
    );
  }
}

class ModerationActionSheet extends StatelessWidget {
  const ModerationActionSheet({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        ReaduoSpacing.screenHorizontal,
        24,
        ReaduoSpacing.screenHorizontal,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Remove reported content?',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          const Text(
            'The content will be hidden from readers and the report will be marked as resolved.',
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove & resolve'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back to report'),
          ),
        ],
      ),
    ),
  );
}

class ContentFilteredScreen extends StatelessWidget {
  const ContentFilteredScreen({
    required this.draftController,
    required this.onEdit,
    required this.onGuidelines,
    this.explanation = BasicContentFilter.explanation,
    super.key,
  });
  final TextEditingController draftController;
  final VoidCallback onEdit;
  final VoidCallback onGuidelines;
  final String explanation;

  @override
  Widget build(BuildContext context) => ModerationPage(
    title: 'Review your post',
    children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'This post may break the community guidelines. It has not been shared.',
          style: TextStyle(color: _danger, fontSize: 14),
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your draft'),
          const SizedBox(height: 8),
          TextField(
            controller: draftController,
            minLines: 5,
            maxLines: 12,
            maxLength: 5000,
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      Text(
        explanation,
        style: const TextStyle(fontSize: 12, color: ReaduoColors.muted),
      ),
      OutlinedButton(
        onPressed: onGuidelines,
        child: const Text('View community guidelines'),
      ),
      FilledButton(onPressed: onEdit, child: const Text('Edit draft')),
    ],
  );
}
