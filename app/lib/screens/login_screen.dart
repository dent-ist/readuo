import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../profile/information_screen.dart';
import '../theme/readuo_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.authService, super.key});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  AuthProviderKind? _busyProvider;
  String? _error;

  Future<void> _signIn(AuthProviderKind provider) async {
    setState(() {
      _busyProvider = provider;
      _error = null;
    });
    try {
      await widget.authService.signIn(provider);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.kind == AuthFailureKind.cancelled) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Sign-in canceled.')));
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Sign-in failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _busyProvider = null);
      }
    }
  }

  void _showDocumentMessage(String document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InformationScreen(topic: document == 'Terms' ? 'terms' : 'privacy'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalPadding = ReaduoSpacing.screenHorizontal;
            final compact = constraints.maxHeight < 650;
            final dense = constraints.maxHeight < 850;
            final verticalPadding = compact ? 6.0 : (dense ? 10.0 : 24.0);
            final minimumHeight = math.max(
              0.0,
              constraints.maxHeight - (verticalPadding * 2),
            );

            return Center(
              child: SingleChildScrollView(
                key: const Key('login-scroll-view'),
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  verticalPadding,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 390,
                    minHeight: minimumHeight,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WelcomeHeader(compact: compact, dense: dense),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: compact ? 6 : (dense ? 8 : 28),
                        ),
                        child: _BookArrangement(
                          bookHeight: compact ? 46 : (dense ? 70 : 120),
                        ),
                      ),
                      _LoginActions(
                        dense: dense,
                        busyProvider: _busyProvider,
                        error: _error,
                        onSignIn: _signIn,
                        onDocument: _showDocumentMessage,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.compact, required this.dense});

  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      key: const Key('login-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          image: true,
          label: 'Readuo logo',
          child: ExcludeSemantics(
            child: Image.asset(
              'assets/brand/readuo-logo.png',
              key: const Key('readuo-brand-logo'),
              width: compact ? 44 : (dense ? 48 : 56),
              height: compact ? 44 : (dense ? 48 : 56),
              fit: BoxFit.contain,
            ),
          ),
        ),
        SizedBox(height: compact ? 8 : (dense ? 12 : 20)),
        Text(
          'READUO',
          style: textTheme.labelLarge?.copyWith(
            color: ReaduoColors.accent,
            fontSize: 13,
            letterSpacing: 2.4,
          ),
        ),
        SizedBox(height: compact ? 6 : (dense ? 10 : 14)),
        Text(
          'Your books.\nYour people.',
          style: textTheme.displaySmall?.copyWith(
            fontSize: compact ? 24 : (dense ? 28 : null),
            height: compact ? 1.06 : null,
          ),
        ),
        SizedBox(height: compact ? 6 : (dense ? 10 : 14)),
        Text(
          'A home for your books.\nA circle for your reading life.',
          style: textTheme.bodyLarge?.copyWith(
            fontSize: compact ? 12 : (dense ? 13 : null),
            height: dense ? 1.3 : null,
          ),
        ),
      ],
    );
  }
}

class _BookArrangement extends StatelessWidget {
  const _BookArrangement({required this.bookHeight});

  final double bookHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('login-art'),
      image: true,
      label: 'A small arrangement of three book covers',
      child: ExcludeSemantics(
        child: SizedBox(
          height: bookHeight + (bookHeight < 60 ? 12 : 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TiltedBook(
                height: bookHeight,
                angle: -0.12,
                offset: Offset(0, bookHeight < 60 ? 4 : 10),
                title: 'Dune',
                author: 'Frank Herbert',
                color: const Color(0xFFAB5834),
              ),
              SizedBox(width: bookHeight < 100 ? 10 : 14),
              _TiltedBook(
                height: bookHeight,
                title: 'Piranesi',
                author: 'Susanna Clarke',
                color: const Color(0xFF184B61),
              ),
              SizedBox(width: bookHeight < 100 ? 10 : 14),
              _TiltedBook(
                height: bookHeight,
                angle: 0.11,
                offset: Offset(0, bookHeight < 60 ? 4 : 10),
                title: 'Small Things\nLike These',
                author: 'Claire Keegan',
                color: const Color(0xFF1F6558),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TiltedBook extends StatelessWidget {
  const _TiltedBook({
    required this.title,
    required this.author,
    required this.color,
    required this.height,
    this.angle = 0,
    this.offset = Offset.zero,
  });

  final String title;
  final String author;
  final Color color;
  final double height;
  final double angle;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: height < 100 ? height * 0.72 : height * 0.633,
          height: height,
          padding: EdgeInsets.all(height < 100 ? 7 : 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F172237),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                textScaler: TextScaler.noScaling,
                maxLines: height < 100 ? 3 : null,
                overflow: height < 100 ? TextOverflow.fade : null,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: height < 100 ? 7.5 : 11,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (height >= 60) ...[
                const Spacer(),
                Text(
                  author,
                  textScaler: TextScaler.noScaling,
                  maxLines: 2,
                  style: TextStyle(
                    color: const Color(0xD9FFFFFF),
                    fontSize: height < 100 ? 6.5 : 8,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginActions extends StatelessWidget {
  const _LoginActions({
    required this.busyProvider,
    required this.error,
    required this.dense,
    required this.onSignIn,
    required this.onDocument,
  });

  final AuthProviderKind? busyProvider;
  final String? error;
  final bool dense;
  final ValueChanged<AuthProviderKind> onSignIn;
  final ValueChanged<String> onDocument;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('login-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Container(
            key: const Key('auth-error'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(ReaduoRadii.button),
            ),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          SizedBox(height: dense ? 8 : ReaduoSpacing.medium),
        ],
        Semantics(
          button: true,
          label: 'Continue with Google',
          child: ExcludeSemantics(
            child: OutlinedButton.icon(
              key: const Key('google-sign-in-button'),
              onPressed: busyProvider == null
                  ? () => onSignIn(AuthProviderKind.google)
                  : null,
              icon: busyProvider == AuthProviderKind.google
                  ? const _ButtonSpinner()
                  : const _GoogleMark(),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(
                minimumSize: Size.fromHeight(dense ? 44 : 52),
              ),
            ),
          ),
        ),
        SizedBox(height: dense ? 6 : ReaduoSpacing.small),
        Semantics(
          button: true,
          enabled: false,
          label: 'Apple sign-in is not available yet. iOS setup is deferred.',
          child: ExcludeSemantics(
            child: FilledButton.icon(
              key: const Key('apple-sign-in-button'),
              onPressed: null,
              icon: const Icon(Icons.apple, size: 20),
              label: const Text('Apple sign-in coming later'),
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(dense ? 44 : 52),
              ),
            ),
          ),
        ),
        SizedBox(height: dense ? 6 : ReaduoSpacing.medium),
        Text(
          'Sign-in is required for personal and public browsing.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: dense ? 6 : ReaduoSpacing.medium),
        Text(
          'By continuing, you agree to our',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: [
            TextButton(
              onPressed: () => onDocument('Terms'),
              child: const Text('Terms'),
            ),
            Text('and', style: Theme.of(context).textTheme.bodySmall),
            TextButton(
              onPressed: () => onDocument('Privacy notice'),
              child: const Text('Privacy notice'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: ReaduoColors.accent,
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ReaduoColors.paper,
        border: Border.all(color: ReaduoColors.line),
        shape: BoxShape.circle,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
