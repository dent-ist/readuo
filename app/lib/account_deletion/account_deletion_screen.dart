import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/readuo_theme.dart';
import 'deletion_controller.dart';
import 'deletion_models.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({
    required this.controller,
    required this.onReturnToSignIn,
    this.onContactSupport,
    this.onCancel,
    super.key,
  });
  final AccountDeletionController controller;
  final Future<void> Function() onReturnToSignIn;
  final VoidCallback? onContactSupport;
  final VoidCallback? onCancel;
  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  bool _accepted = false;
  Timer? _poll;
  AccountDeletionController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    unawaited(controller.initialize());
    _poll = Timer.periodic(
      const Duration(seconds: 3),
      (_) => controller.refresh(),
    );
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    controller.removeListener(_changed);
    super.dispose();
  }

  void _cancel() {
    if (controller.canCancel) {
      if (widget.onCancel != null) {
        widget.onCancel!();
      } else {
        Navigator.maybePop(context);
      }
    }
  }

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    bool danger = false,
    bool secondary = false,
  }) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      backgroundColor: danger
          ? const WidgetStatePropertyAll(Color(0xFFBD3548))
          : null,
    );
    return secondary
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton(onPressed: onPressed, style: style, child: Text(label));
  }

  Widget _banner(String text, {bool error = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFF0F1) : const Color(0xFFFFF4DF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline : Icons.warning_amber,
          size: 18,
          color: error ? const Color(0xFFA6283B) : const Color(0xFF7A5117),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: error ? const Color(0xFFA6283B) : const Color(0xFF7A5117),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _empty(
    IconData icon,
    String title,
    String description, {
    Widget? action,
  }) => Padding(
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
          child: Icon(icon, size: 30, color: ReaduoColors.accent),
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
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: ReaduoColors.muted,
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 23), action],
      ],
    ),
  );
  List<Widget> _content() {
    final busy = controller.busy;
    switch (controller.stage) {
      case DeletionStage.acknowledgement:
        return [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F1),
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Icon(
                Icons.delete_outline,
                size: 28,
                color: Color(0xFFAC2C40),
              ),
            ),
          ),
          const Text(
            'Leave Readuo?',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
          ),
          const Text(
            'Your profile, library entries, shelves, posts, reviews, comments, uploaded photos, likes, connections, reports, and security records will be permanently removed. No data is retained.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: ReaduoColors.muted,
            ),
          ),
          _banner(
            'This is permanent. Your friends will no longer see your profile or shared content.',
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: ReaduoColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CheckboxListTile(
              key: const Key('delete-account-acknowledgement'),
              value: _accepted,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              onChanged: busy
                  ? null
                  : (value) => setState(() => _accepted = value ?? false),
              title: const Text(
                'I understand that my account and associated data will be deleted.',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
          if (controller.error != null) _error(),
          _button(
            'Continue to verification',
            busy ? null : () => controller.acknowledge(_accepted),
            danger: true,
          ),
          _button(
            'Keep my account',
            controller.canCancel ? _cancel : null,
            secondary: true,
          ),
        ];
      case DeletionStage.verification:
        return [
          _empty(
            Icons.verified_user_outlined,
            'One last verification',
            'Sign in again with Google to confirm that you want to delete this account.',
            action: _button(
              busy ? 'Verifying…' : 'Verify with Google',
              busy ? null : controller.verifyAndDelete,
              danger: true,
            ),
          ),
          if (controller.error != null) _error(),
          TextButton(
            onPressed: controller.canCancel ? _cancel : null,
            child: const Text('Cancel deletion'),
          ),
        ];
      case DeletionStage.processing:
        return [
          _empty(
            Icons.hourglass_empty,
            'Removing your Readuo account',
            'Your account is closed to new activity while deletion is processed.',
          ),
          const LinearProgressIndicator(
            minHeight: 12,
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          const FractionallySizedBox(
            widthFactor: .6,
            alignment: Alignment.centerLeft,
            child: LinearProgressIndicator(
              minHeight: 12,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
          ),
        ];
      case DeletionStage.paused:
        return [
          _banner(
            'We could not confirm deletion status. If processing has started, the server continues securely even while this screen is closed.',
            error: true,
          ),
          _empty(
            Icons.refresh,
            'Deletion needs your attention',
            controller.canCancel
                ? 'Try again, cancel, or contact support if this keeps happening.'
                : 'Try again or contact support. Deletion may already have started and cannot be cancelled.',
            action: _button(
              'Try deletion again',
              busy ? null : controller.retry,
              danger: true,
            ),
          ),
          if (controller.error != null) _error(),
          if (controller.canCancel)
            _button('Cancel deletion', _cancel, secondary: true),
          TextButton(
            onPressed: widget.onContactSupport,
            child: const Text('Contact support'),
          ),
        ];
      case DeletionStage.completed:
        return [
          _empty(
            Icons.check,
            'Your account has been deleted',
            'Your Readuo account and associated content have been removed.',
            action: _button(
              busy ? 'Returning…' : 'Return to sign-in',
              busy
                  ? null
                  : () => controller.returnToSignIn(widget.onReturnToSignIn),
            ),
          ),
          if (controller.error != null) _error(),
        ];
    }
  }

  Widget _error() => Semantics(
    liveRegion: true,
    child: Text(
      controller.error!,
      style: const TextStyle(
        color: Color(0xFFAC2C40),
        fontSize: 13,
        height: 1.5,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final title = switch (controller.stage) {
      DeletionStage.acknowledgement => 'Delete your account',
      DeletionStage.verification => 'Confirm it’s you',
      DeletionStage.processing => 'Deleting account',
      DeletionStage.paused => 'Deletion paused',
      DeletionStage.completed => 'Account deleted',
    };
    return PopScope(
      canPop: controller.canCancel && widget.onCancel == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && controller.canCancel) _cancel();
      },
      child: Scaffold(
        backgroundColor: ReaduoColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 76,
          titleSpacing: ReaduoSpacing.screenHorizontal,
          title: Row(
            children: [
              if (controller.canCancel) ...[
                SizedBox.square(
                  dimension: 44,
                  child: IconButton.outlined(
                    onPressed: _cancel,
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, size: 20),
                    style: IconButton.styleFrom(
                      side: const BorderSide(color: ReaduoColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
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
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              18,
              ReaduoSpacing.screenHorizontal,
              24,
            ),
            children: [
              for (final child in _content()) ...[
                child,
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
