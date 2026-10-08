import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'auth/auth_gate.dart';
import 'auth/auth_service.dart';
import 'circle/circle_repository.dart';
import 'circle/engagement_repository.dart';
import 'circle/photo_repository.dart';
import 'circle/review_repository.dart';
import 'friends/friend_repository.dart';
import 'features/feature_services.dart';
import 'library/book_lookup.dart';
import 'library/book_repository.dart';
import 'library/catalogue_repository.dart';
import 'library/shelf_repository.dart';
import 'onboarding/onboarding_repository.dart';
import 'theme/readuo_theme.dart';

const _googleBooksApiKey = String.fromEnvironment('GOOGLE_BOOKS_API_KEY');

void main() {
  runApp(const ReaduoApp());
}

class ReaduoApp extends StatefulWidget {
  const ReaduoApp({
    this.authService,
    this.shelfRepository,
    this.bookRepository,
    this.bookLookupRepository,
    this.catalogueRepository,
    this.circleRepository,
    this.reviewRepository,
    this.engagementRepository,
    this.photoRepository,
    this.friendRepository,
    this.onboardingRepository,
    super.key,
  });

  final AuthService? authService;
  final ShelfRepository? shelfRepository;
  final BookRepository? bookRepository;
  final BookLookupRepository? bookLookupRepository;
  final CatalogueRepository? catalogueRepository;
  final CircleRepository? circleRepository;
  final ReviewRepository? reviewRepository;
  final CircleEngagementRepository? engagementRepository;
  final CirclePhotoRepository? photoRepository;
  final FriendRepository? friendRepository;
  final OnboardingRepository? onboardingRepository;

  @override
  State<ReaduoApp> createState() => _ReaduoAppState();
}

class _ReaduoAppState extends State<ReaduoApp> {
  late Future<_AppServices> _services;
  Widget Function(Widget)? _featureScope;

  @override
  void initState() {
    super.initState();
    _services = widget.authService == null
        ? _initializeServices()
        : Future.value(
            _AppServices(
              auth: widget.authService!,
              shelves: widget.shelfRepository ?? const EmptyShelfRepository(),
              books: widget.bookRepository ?? const EmptyBookRepository(),
              bookLookup:
                  widget.bookLookupRepository ??
                  const EmptyBookLookupRepository(),
              catalogue:
                  widget.catalogueRepository ??
                  const EmptyCatalogueRepository(),
              circle: widget.circleRepository ?? const EmptyCircleRepository(),
              reviews: widget.reviewRepository ?? const EmptyReviewRepository(),
              engagement:
                  widget.engagementRepository ??
                  const EmptyCircleEngagementRepository(),
              photos:
                  widget.photoRepository ?? const EmptyCirclePhotoRepository(),
              friends: widget.friendRepository ?? const EmptyFriendRepository(),
              onboarding:
                  widget.onboardingRepository ??
                  const EmptyOnboardingRepository(),
            ),
          );
  }

  Future<_AppServices> _initializeServices() async {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        final rawConfig = await rootBundle.loadString(
          'assets/firebase-web-config.json',
        );
        final config = jsonDecode(rawConfig) as Map<String, dynamic>;
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: config['apiKey'] as String,
            appId: config['appId'] as String,
            messagingSenderId: config['messagingSenderId'] as String,
            projectId: config['projectId'] as String,
            authDomain: config['authDomain'] as String?,
            storageBucket: config['storageBucket'] as String?,
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
    }
    if (!kIsWeb) {
      try {
        await FirebaseFirestore.instance.clearPersistence();
      } on FirebaseException catch (_) {}
    }
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    _featureScope = await FeatureServices.initialize();
    final lookupClient = http.Client();
    final bookLookup = OpenLibraryThenGoogleBooksRepository(
      openLibrary: OpenLibraryBookLookupRepository(lookupClient),
      googleBooks: GoogleBooksBookLookupRepository(
        lookupClient,
        apiKey: _googleBooksApiKey,
      ),
    );
    return _AppServices(
      auth: await FirebaseAuthService.create(),
      shelves: FirebaseShelfRepository(FirebaseFirestore.instance),
      books: FirebaseBookRepository(FirebaseFirestore.instance),
      bookLookup: bookLookup,
      catalogue: OpenLibraryThenGoogleCatalogueRepository(
        openLibrary: OpenLibraryCatalogueRepository(lookupClient),
        googleBooks: GoogleBooksCatalogueRepository(
          lookupClient,
          apiKey: _googleBooksApiKey,
        ),
        isbnLookup: bookLookup,
      ),
      circle: FirebaseCircleRepository(FirebaseFirestore.instance),
      reviews: FirebaseReviewRepository(FirebaseFirestore.instance),
      engagement: FirebaseCircleEngagementRepository(
        FirebaseFirestore.instance,
      ),
      photos: FirebaseCirclePhotoRepository(FirebaseStorage.instance),
      friends: FirebaseFriendRepository(FirebaseFirestore.instance),
      onboarding: FirebaseOnboardingRepository(FirebaseFirestore.instance),
    );
  }

  void _retryInitialization() {
    setState(() => _services = _initializeServices());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppServices>(
      future: _services,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootstrapApp(
            home: _InitializationErrorScreen(onRetry: _retryInitialization),
          );
        }
        final services = snapshot.data;
        if (services == null) {
          return const _BootstrapApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        final gate = AuthGate(
          authService: services.auth,
          shelfRepository: services.shelves,
          bookRepository: services.books,
          bookLookupRepository: services.bookLookup,
          catalogueRepository: services.catalogue,
          circleRepository: services.circle,
          reviewRepository: services.reviews,
          engagementRepository: services.engagement,
          photoRepository: services.photos,
          friendRepository: services.friends,
          onboardingRepository: services.onboarding,
        );
        return _featureScope?.call(gate) ?? gate;
      },
    );
  }
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Readuo',
      theme: ReaduoTheme.modern,
      home: home,
    );
  }
}

class _AppServices {
  const _AppServices({
    required this.auth,
    required this.shelves,
    required this.books,
    required this.bookLookup,
    required this.catalogue,
    required this.circle,
    required this.reviews,
    required this.engagement,
    required this.photos,
    required this.friends,
    required this.onboarding,
  });

  final AuthService auth;
  final ShelfRepository shelves;
  final BookRepository books;
  final BookLookupRepository bookLookup;
  final CatalogueRepository catalogue;
  final CircleRepository circle;
  final ReviewRepository reviews;
  final CircleEngagementRepository engagement;
  final CirclePhotoRepository photos;
  final FriendRepository friends;
  final OnboardingRepository onboarding;
}

class _InitializationErrorScreen extends StatelessWidget {
  const _InitializationErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ReaduoSpacing.screenHorizontal,
            vertical: 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Readuo could not connect to authentication services.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
