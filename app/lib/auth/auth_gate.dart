import 'package:flutter/material.dart';

import '../circle/circle_repository.dart';
import '../circle/engagement_repository.dart';
import '../circle/photo_repository.dart';
import '../circle/review_repository.dart';
import '../library/book_lookup.dart';
import '../friends/friend_repository.dart';
import '../library/book_repository.dart';
import '../library/catalogue_repository.dart';
import '../library/shelf_repository.dart';
import '../onboarding/onboarding_repository.dart';
import '../screens/login_screen.dart';
import '../screens/authenticated_shell.dart';
import '../screens/first_book_onboarding_screen.dart';
import '../screens/profile_setup_screen.dart';
import '../theme/readuo_theme.dart';
import 'auth_service.dart';
import '../features/feature_services.dart';
import '../features/account_session_boundary.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    required this.authService,
    required this.shelfRepository,
    required this.bookRepository,
    required this.bookLookupRepository,
    required this.onboardingRepository,
    this.catalogueRepository = const EmptyCatalogueRepository(),
    this.circleRepository = const EmptyCircleRepository(),
    this.reviewRepository = const EmptyReviewRepository(),
    this.engagementRepository = const EmptyCircleEngagementRepository(),
    this.photoRepository = const EmptyCirclePhotoRepository(),
    required this.friendRepository,
    super.key,
  });

  final AuthService authService;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final BookLookupRepository bookLookupRepository;
  final OnboardingRepository onboardingRepository;
  final CatalogueRepository catalogueRepository;
  final CircleRepository circleRepository;
  final ReviewRepository reviewRepository;
  final CircleEngagementRepository engagementRepository;
  final CirclePhotoRepository photoRepository;
  final FriendRepository friendRepository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: authService.userChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        late final Widget home;
        late final String sessionKey;
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          home = const _SessionLoadingScreen();
          sessionKey = 'loading';
        } else if (snapshot.data == null) {
          home = LoginScreen(authService: authService);
          sessionKey = 'signed-out';
        } else if (authService.needsDisplayName(snapshot.data!)) {
          final user = snapshot.data!;
          home = ProfileSetupScreen(
            authService: authService,
            user: user,
            suggestedName: authService.suggestedDisplayName(user.uid),
            onboardingRepository: onboardingRepository,
            friendRepository: friendRepository,
          );
          sessionKey = 'user:${user.uid}';
        } else {
          final user = snapshot.data!;
          home = _SignedInOnboardingGate(
            key: ValueKey(user.uid),
            authService: authService,
            onboardingRepository: onboardingRepository,
            shelfRepository: shelfRepository,
            bookRepository: bookRepository,
            bookLookupRepository: bookLookupRepository,
            catalogueRepository: catalogueRepository,
            circleRepository: circleRepository,
            reviewRepository: reviewRepository,
            engagementRepository: engagementRepository,
            photoRepository: photoRepository,
            friendRepository: friendRepository,
            user: user,
          );
          sessionKey = 'user:${user.uid}';
        }
        return MaterialApp(
          key: ValueKey(sessionKey),
          debugShowCheckedModeBanner: false,
          title: 'Readuo',
          theme: ReaduoTheme.modern,
          builder: (context, child) {
            if (sessionKey == 'loading') return child!;
            final services = FeatureServices.maybeOf(context);
            if (services == null) return child!;
            return AccountSessionBoundary(
              key: ValueKey(sessionKey),
              services: services,
              authService: authService,
              user: snapshot.data,
              child: child!,
            );
          },
          home: home,
        );
      },
    );
  }
}

class _SignedInOnboardingGate extends StatefulWidget {
  const _SignedInOnboardingGate({
    required this.authService,
    required this.onboardingRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.bookLookupRepository,
    required this.catalogueRepository,
    required this.circleRepository,
    required this.reviewRepository,
    required this.engagementRepository,
    required this.photoRepository,
    required this.friendRepository,
    required this.user,
    super.key,
  });

  final AuthService authService;
  final OnboardingRepository onboardingRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final BookLookupRepository bookLookupRepository;
  final CatalogueRepository catalogueRepository;
  final CircleRepository circleRepository;
  final ReviewRepository reviewRepository;
  final CircleEngagementRepository engagementRepository;
  final CirclePhotoRepository photoRepository;
  final FriendRepository friendRepository;
  final AuthUser user;

  @override
  State<_SignedInOnboardingGate> createState() =>
      _SignedInOnboardingGateState();
}

class _SignedInOnboardingGateState extends State<_SignedInOnboardingGate> {
  late Future<FirstBookOnboardingStatus> _status;
  bool _finishedLocally = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SignedInOnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.onboardingRepository != widget.onboardingRepository) {
      _finishedLocally = false;
      _load();
    }
  }

  void _load() {
    _status = widget.onboardingRepository.loadFirstBookStatus(widget.user.uid);
  }

  void _retry() {
    setState(() {
      _finishedLocally = false;
      _load();
    });
  }

  void _finish() => setState(() => _finishedLocally = true);

  Widget _shell() => AuthenticatedShell(
    authService: widget.authService,
    shelfRepository: widget.shelfRepository,
    bookRepository: widget.bookRepository,
    bookLookupRepository: widget.bookLookupRepository,
    catalogueRepository: widget.catalogueRepository,
    circleRepository: widget.circleRepository,
    reviewRepository: widget.reviewRepository,
    engagementRepository: widget.engagementRepository,
    photoRepository: widget.photoRepository,
    friendRepository: widget.friendRepository,
    user: widget.user,
  );

  @override
  Widget build(BuildContext context) {
    if (_finishedLocally) return _shell();
    return FutureBuilder<FirstBookOnboardingStatus>(
      future: _status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final message = snapshot.error is OnboardingFailure
              ? (snapshot.error! as OnboardingFailure).message
              : 'Readuo could not restore first-book setup.';
          return Scaffold(
            key: const Key('onboarding-load-error'),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ReaduoSpacing.screenHorizontal,
                    vertical: 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 48),
                      const SizedBox(height: 16),
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final status = snapshot.data;
        if (status == null) {
          return Scaffold(
            body: Center(
              child: Semantics(
                label: 'Restoring first-book setup',
                child: const CircularProgressIndicator(),
              ),
            ),
          );
        }
        if (status == FirstBookOnboardingStatus.pending) {
          return FirstBookOnboardingScreen(
            ownerId: widget.user.uid,
            onboardingRepository: widget.onboardingRepository,
            shelfRepository: widget.shelfRepository,
            bookRepository: widget.bookRepository,
            bookLookupRepository: widget.bookLookupRepository,
            catalogueRepository: widget.catalogueRepository,
            onFinished: _finish,
          );
        }
        return _shell();
      },
    );
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          label: 'Restoring your session',
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
