import 'dart:async';
import '../library/manual_book_draft.dart';
import '../profile/profile_photo_draft.dart';
import '../profile/edit_profile_screen.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_service.dart';
import '../circle/circle_repository.dart';
import '../circle/engagement_repository.dart';
import '../circle/photo_repository.dart';
import '../circle/review_repository.dart';
import '../friends/friend_repository.dart';
import '../friends/invite_link_screen.dart';
import '../features/feature_services.dart';
import '../features/account_session_boundary.dart';
import '../notifications/notification.dart';
import '../notifications/notification_client.dart';
import '../notifications/notification_screens.dart';
import '../notifications/notification_presentation.dart';
import '../notifications/book_addition_screen.dart';
import '../moderation/moderation_screens.dart';
import '../moderation/moderation_repository.dart';
import '../profile/profile_repository.dart';
import '../profile/support_repository.dart';
import '../profile/support_requests_screen.dart';
import '../profile/information_screen.dart';
import '../library/book.dart';
import '../library/book_lookup.dart';
import '../library/book_repository.dart';
import '../library/catalogue_repository.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../widgets/readuo_bottom_navigation.dart';
import '../widgets/readuo_tab_activity.dart';
import 'account_screen.dart';
import 'circle_screen.dart';
import 'friends_screen.dart';
import 'isbn_scanner_screen.dart';
import 'my_library_screen.dart';
import 'shelf_details_screen.dart';

class AuthenticatedShell extends StatefulWidget {
  const AuthenticatedShell({
    required this.authService,
    required this.shelfRepository,
    required this.bookRepository,
    required this.bookLookupRepository,
    this.catalogueRepository = const EmptyCatalogueRepository(),
    this.circleRepository = const EmptyCircleRepository(),
    this.reviewRepository = const EmptyReviewRepository(),
    this.engagementRepository = const EmptyCircleEngagementRepository(),
    this.photoRepository = const EmptyCirclePhotoRepository(),
    required this.friendRepository,
    required this.user,
    super.key,
  });

  final AuthService authService;
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
  State<AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<AuthenticatedShell>
    with WidgetsBindingObserver {
  FeatureServices? _features;
  NotificationClient? _notifications;
  bool _isModerator = false;
  int? _bookCount;
  int? _shelfCount;
  int? _friendCount;
  StreamSubscription<List<LibraryBook>>? _profileBooks;
  StreamSubscription<List<Shelf>>? _profileShelves;
  StreamSubscription<List<ReaderProfile>>? _profileFriends;
  final _navigatorKeys = <ReaduoNavDestination, GlobalKey<NavigatorState>>{
    ReaduoNavDestination.circle: GlobalKey<NavigatorState>(),
    ReaduoNavDestination.library: GlobalKey<NavigatorState>(),
    ReaduoNavDestination.friends: GlobalKey<NavigatorState>(),
    ReaduoNavDestination.profile: GlobalKey<NavigatorState>(),
  };
  late final ReaduoNavDestination _homeDestination;
  late final Set<ReaduoNavDestination> _visited;
  late ReaduoNavDestination _active;
  late final PageController _pageController;
  bool _allowTabSwipe = true;
  bool _navigationVisible = true;
  bool _inviteOpening = false;
  final _notificationBanner = NotificationBannerOverlay();
  late final _permissionOpportunity = NotificationPermissionOpportunity(
    SharedPreferencesAsync(),
    widget.user.uid,
  );
  bool _foreground = true;
  bool _permissionOpening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _homeDestination = widget.circleRepository is EmptyCircleRepository
        ? ReaduoNavDestination.library
        : ReaduoNavDestination.circle;
    _active = _homeDestination;
    _visited = ReaduoNavDestination.values.toSet();
    _pageController = PageController(initialPage: _tabIndex(_homeDestination));
    _profileBooks = widget.bookRepository
        .watchLibraryBooks(widget.user.uid)
        .listen((books) {
          if (mounted) setState(() => _bookCount = books.length);
        }, onError: (Object _) {});
    _profileFriends = widget.friendRepository
        .watchFriends(widget.user.uid)
        .listen((friends) {
          if (mounted) setState(() => _friendCount = friends.length);
          unawaited(_maybeExplainNotifications());
        }, onError: (Object _) {});
    _profileShelves = widget.shelfRepository
        .watchShelves(widget.user.uid)
        .listen(
          (shelves) {
            if (mounted) setState(() => _shelfCount = shelves.length);
          },
          onError: (Object _) {
            if (mounted) setState(() => _shelfCount = null);
          },
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = FeatureServices.maybeOf(context);
    if (services == null) return;
    if (_features == services) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_maybeExplainNotifications()),
      );
      return;
    }
    _features?.invites.removeListener(_openPendingInvite);
    _features?.offline.removeListener(_notificationConnectionChanged);
    _features = services;
    services.offline.addListener(_notificationConnectionChanged);
    services.invites.addListener(_openPendingInvite);
    final client = NotificationClient(
      userId: widget.user.uid,
      installationId: services.installationId,
      repository: services.notifications,
      messaging: services.messaging,
      openDestination: _openNotificationDestination,
      onError: _notificationError,
      canPresent: _canPresentNotification,
      destinationAvailable: (destination) async =>
          await _openNotificationDestination(
            widget.user.uid,
            destination,
            previewOnly: true,
          ) ==
          NotificationOpenResult.opened,
      isViewing: NotificationDestinationMarker.isViewing,
      onForeground: (item) => _notificationBanner.show(context, () {
        unawaited(
          _notifications!
              .open(item.id)
              .then<void>((result) {
                if (result == NotificationOpenResult.unavailable)
                  _notificationError(StateError('Unavailable'));
              })
              .catchError(_notificationError),
        );
      }),
    );
    _notifications = client;
    if (widget.authService case final FirebaseAuthService auth) {
      auth.beforeSignOut = () async {
        _notificationBanner.dismiss();
        await services.offline.clearSession();
        await client.beforeSignOut();
      };
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _openPendingInvite();
      unawaited(_resumeManualPhoto());
      unawaited(client.start().catchError(_notificationError));
      unawaited(_maybeExplainNotifications());
      try {
        await widget.friendRepository.ensureProfile(widget.user);
        final moderator = await services.moderation.isModerator();
        if (mounted) setState(() => _isModerator = moderator);
      } catch (error) {
        _notificationError(error);
      }
    });
  }

  void _notificationError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not refresh account services. Check your connection and try again.',
        ),
      ),
    );
  }

  bool _canPresentNotification() =>
      mounted &&
      _foreground &&
      _notifications?.isActive == true &&
      _features?.offline.canShowOnline == true &&
      _features?.auth.currentUser?.uid == widget.user.uid;

  void _notificationConnectionChanged() {
    if (!_canPresentNotification()) {
      _notificationBanner.dismiss();
      _notifications?.invalidateForeground();
    } else {
      unawaited(_maybeExplainNotifications());
    }
  }

  Future<void> _maybeExplainNotifications() async {
    final client = _notifications;
    if (client == null ||
        _permissionOpening ||
        (_friendCount ?? 0) == 0 ||
        !_canPresentNotification())
      return;
    bool eligible() =>
        _canPresentNotification() &&
        ModalRoute.of(context)?.isCurrent == true &&
        _navigatorKeys[_active]?.currentState?.canPop() != true &&
        !_inviteOpening &&
        !_draftOpening;
    if (!eligible()) return;
    _permissionOpening = true;
    try {
      final permission = await client.messaging.permission();
      if (!await _permissionOpportunity.claim(
        friendCount: _friendCount ?? 0,
        permission: permission,
        isCurrent: eligible,
      ))
        return;
      if (!eligible()) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (pageContext) => NotificationPermissionScreen(
            client: client,
            onDone: () => Navigator.of(pageContext).pop(),
          ),
        ),
      );
    } catch (_) {
    } finally {
      _permissionOpening = false;
    }
  }

  Future<void> _resumeManualPhoto() async {
    if (_draftOpening || _inviteOpening || !mounted) return;
    _draftOpening = true;
    try {
      final profileDraft = await ProfilePhotoDraftStore().read(widget.user.uid);
      if (!mounted ||
          _features?.auth.currentUser?.uid != widget.user.uid ||
          _inviteOpening)
        return;
      if (profileDraft != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EditProfileScreen(
              uid: widget.user.uid,
              name: widget.user.displayName ?? '',
              photoUrl: widget.user.photoUrl,
              repository: _features!.profile,
              draftFlow: profileDraft['flow'] as String,
            ),
          ),
        );
        return;
      }
      final draft = await ManualBookDraftStore().read(widget.user.uid);
      if (draft == null || !mounted || _inviteOpening) return;
      final shelves = await widget.shelfRepository
          .watchShelves(widget.user.uid)
          .firstWhere(
            (items) => items.any((shelf) => shelf.id == draft['shelfId']),
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted || _features?.auth.currentUser?.uid != widget.user.uid)
        return;
      final shelf = shelves.firstWhere((shelf) => shelf.id == draft['shelfId']);
      await _openManualAdd(shelf, const IsbnManualSeed());
    } catch (_) {
    } finally {
      _draftOpening = false;
    }
  }

  bool _draftOpening = false;

  void _openPendingInvite() {
    final features = _features;
    final code = features?.invites.pendingCode;
    if (!mounted ||
        _inviteOpening ||
        code == null ||
        features!.auth.currentUser?.uid != widget.user.uid)
      return;
    _inviteOpening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || features.auth.currentUser?.uid != widget.user.uid) {
        _inviteOpening = false;
        return;
      }
      features.invites.consume(code);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => InviteLinkScreen(
            repository: widget.friendRepository,
            userId: widget.user.uid,
            code: code,
          ),
        ),
      );
      _inviteOpening = false;
      if (mounted) {
        _openPendingInvite();
        unawaited(_resumeManualPhoto());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _notificationBanner.dismiss();
      _notifications?.invalidateForeground();
    }
    if (state == AppLifecycleState.resumed) {
      final client = _notifications;
      if (client != null)
        unawaited(() async {
          try {
            await client.start();
            await client.synchronizePermission();
            await _maybeExplainNotifications();
          } catch (error) {
            _notificationError(error);
          }
        }());
    }
  }

  @override
  void dispose() {
    _notificationBanner.dismiss();
    _features?.offline.removeListener(_notificationConnectionChanged);
    _pageController.dispose();
    _features?.invites.removeListener(_openPendingInvite);
    _profileBooks?.cancel();
    _profileShelves?.cancel();
    _profileFriends?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final client = _notifications;
    if (client != null) unawaited(client.dispose());
    super.dispose();
  }

  void _notificationSettings() async {
    final client = _notifications;
    if (client == null) return;
    NotificationPermission permission;
    try {
      permission = await client.messaging.permission();
    } catch (error) {
      _notificationError(error);
      return;
    }
    if (!mounted || !client.isActive) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotificationSettingsScreen(
          userId: widget.user.uid,
          repository: client.repository,
          enableLabel: permission == NotificationPermission.granted
              ? 'Phone notification settings'
              : 'Enable notifications',
          openSettings: () async {
            if (await client.messaging.permission() ==
                NotificationPermission.notDetermined) {
              if (!mounted) return;
              await _permissionOpportunity.recordShown();
              if (!mounted || !client.isActive) return;
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (pageContext) => NotificationPermissionScreen(
                    client: client,
                    onDone: () => Navigator.of(pageContext).pop(),
                  ),
                ),
              );
            } else {
              await client.messaging.openSettings();
            }
          },
        ),
      ),
    );
  }

  void _openNotifications() {
    final client = _notifications;
    if (client == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          client: client,
          onSettings: _notificationSettings,
        ),
      ),
    );
  }

  Future<void> _profileDestination(String destination) async {
    if (destination == 'report') {
      await FeatureServices.report(context, const ReportTarget.support());
      return;
    }
    Widget screen;
    if (destination == 'invite') {
      try {
        final profile = await widget.friendRepository.ensureProfile(
          widget.user,
        );
        if (!mounted) return;
        screen = InviteFriendScreen(
          repository: widget.friendRepository,
          user: widget.user,
          profile: profile,
        );
      } catch (error) {
        _notificationError(error);
        return;
      }
    } else if (destination == 'blocked-users') {
      screen = BlockedReadersScreen(
        repository: widget.friendRepository,
        userId: widget.user.uid,
      );
    } else {
      screen = InformationScreen(topic: destination);
    }
    if (mounted)
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => screen));
  }

  Future<NotificationOpenResult> _openNotificationDestination(
    String recipientId,
    NotificationDestination destination, {
    bool previewOnly = false,
  }) async {
    final features = _features;
    if (features == null ||
        _notifications?.isActive != true ||
        recipientId != widget.user.uid ||
        features.auth.currentUser?.uid != recipientId)
      return NotificationOpenResult.unavailable;
    Widget? screen;
    try {
      if (destination.kind == NotificationDestinationKind.bookAddition) {
        screen = BookAdditionScreen(
          userId: recipientId,
          groupId: destination.id,
          repository: features.notifications,
          onOpenBook: (item) async {
            final profile = await features.firestore
                .collection('readerProfiles')
                .doc(item.book.ownerId)
                .get(const GetOptions(source: Source.server));
            if (!mounted ||
                features.auth.currentUser?.uid != recipientId ||
                !profile.exists)
              return;
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => FriendBookSheet(
                viewerId: recipientId,
                friend: ReaderProfile.fromFirestore(
                  profile.id,
                  profile.data()!,
                ),
                sourceShelf: item.shelf,
                book: item.book,
                ownedOnly: true,
                friendRepository: widget.friendRepository,
                shelfRepository: widget.shelfRepository,
                bookRepository: widget.bookRepository,
              ),
            );
          },
        );
      } else if (destination.kind == NotificationDestinationKind.request) {
        final requests = await widget.friendRepository
            .watchIncomingRequests(recipientId)
            .first
            .timeout(const Duration(seconds: 15));
        final request = requests
            .where((request) => request.pairId == destination.id)
            .firstOrNull;
        if (request == null) return NotificationOpenResult.unavailable;
        screen = FriendRequestDetailScreen(
          repository: widget.friendRepository,
          userId: recipientId,
          request: request,
          incoming: true,
        );
      } else if (destination.kind == NotificationDestinationKind.reader) {
        final friends = await widget.friendRepository
            .watchFriends(recipientId)
            .first
            .timeout(const Duration(seconds: 15));
        final reader = friends
            .where((reader) => reader.uid == destination.id)
            .firstOrNull;
        if (reader == null) return NotificationOpenResult.unavailable;
        screen = FriendProfileScreen(
          repository: widget.friendRepository,
          shelfRepository: widget.shelfRepository,
          bookRepository: widget.bookRepository,
          userId: recipientId,
          friend: reader,
        );
      } else {
        final collection = destination.isReview
            ? 'circleReviews'
            : 'circlePosts';
        final reference = features.firestore
            .collection(collection)
            .doc(destination.id);
        final snapshot = await reference.get(
          const GetOptions(source: Source.server),
        );
        if (!snapshot.exists) return NotificationOpenResult.unavailable;
        final data = snapshot.data()!;
        if (data['moderationState'] == 'removed')
          return NotificationOpenResult.unavailable;
        if (destination.commentId != null) {
          final comment = await reference
              .collection('comments')
              .doc(destination.commentId)
              .get(const GetOptions(source: Source.server));
          if (!comment.exists) return NotificationOpenResult.unavailable;
        }
        final author = await features.firestore
            .collection('readerProfiles')
            .doc(data['authorId'] as String)
            .get(const GetOptions(source: Source.server));
        if (!author.exists) return NotificationOpenResult.unavailable;
        final reader = ReaderProfile.fromFirestore(author.id, author.data()!);
        screen = destination.isReview
            ? CircleReviewDetailScreen(
                review: CircleReview.fromFirestore(snapshot.id, data),
                viewerId: recipientId,
                repository: widget.reviewRepository,
                engagementRepository: widget.engagementRepository,
                displayName: reader.displayName,
                photoUrl: reader.photoUrl,
                viewerDisplayName: widget.user.displayName ?? 'You',
                viewerPhotoUrl: widget.user.photoUrl,
              )
            : CirclePostDetailScreen(
                post: CirclePost.fromFirestore(snapshot.id, data),
                viewerId: recipientId,
                displayName: reader.displayName,
                photoUrl: reader.photoUrl,
                viewerDisplayName: widget.user.displayName ?? 'You',
                viewerPhotoUrl: widget.user.photoUrl,
                engagementRepository: widget.engagementRepository,
                photoRepository: widget.photoRepository,
              );
      }
    } catch (_) {
      return NotificationOpenResult.unavailable;
    }
    if (!mounted ||
        _notifications?.isActive != true ||
        !features.offline.canShowOnline ||
        features.auth.currentUser?.uid != recipientId)
      return NotificationOpenResult.unavailable;
    if (previewOnly) return NotificationOpenResult.opened;
    _notificationBanner.dismiss();
    unawaited(
      Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => screen!)),
    );
    return NotificationOpenResult.opened;
  }

  final _tabRoutes = {
    for (final destination in ReaduoNavDestination.values)
      destination: _TabRouteObserver(),
  };
  bool _selectingTab = false;

  Future<void> _select(ReaduoNavDestination destination) async {
    if (_selectingTab) return;
    _selectingTab = true;
    try {
      _notificationBanner.dismiss();
      FocusManager.instance.primaryFocus?.unfocus();
      final navigator = _navigatorKeys[_active]?.currentState;
      final observer = _tabRoutes[_active]!;
      while (navigator != null && navigator.canPop()) {
        final previous = observer.top;
        await navigator.maybePop();
        if (!mounted || identical(previous, observer.top)) return;
      }
      if (_active == destination) return;
      setState(() {
        _visited.add(destination);
        _active = destination;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_tabIndex(destination));
      }
    } finally {
      _selectingTab = false;
    }
  }

  void _setNavigationVisible(bool visible) {
    if (!mounted || _navigationVisible == visible) return;
    setState(() => _navigationVisible = visible);
  }

  Future<void> _openManualAdd(Shelf shelf, IsbnManualSeed seed) =>
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AddBookSheet(
          ownerId: widget.user.uid,
          shelf: shelf,
          shelfRepository: widget.shelfRepository,
          bookRepository: widget.bookRepository,
          initialTitle: seed.title,
          initialAuthor: seed.author,
          initialIsbn: seed.isbn,
        ),
      );

  Future<void> _handleBack(bool didPop, Object? result) async {
    if (didPop) return;
    final navigator = _navigatorKeys[_active]?.currentState;
    if (navigator != null && await navigator.maybePop()) return;
    if (_active != _homeDestination) {
      _select(_homeDestination);
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        body: NotificationListener<NavigationNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => unawaited(_maybeExplainNotifications()),
            );
            const NavigationNotification(canHandlePop: true).dispatch(context);
            return true;
          },
          child: Listener(
            onPointerDown: (event) {
              final width = MediaQuery.sizeOf(context).width;
              final allowed =
                  event.localPosition.dx > 24 &&
                  event.localPosition.dx < width - 24;
              if (_allowTabSwipe != allowed)
                setState(() => _allowTabSwipe = allowed);
            },
            child: PageView(
              key: const Key('main-tab-pages'),
              controller: _pageController,
              physics: _navigationVisible && _allowTabSwipe
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                final destination = ReaduoNavDestination.values[index];
                if (destination == _active) return;
                _pageController.jumpToPage(_tabIndex(_active));
                unawaited(_select(destination));
              },
              children: [
                _tabNavigator(
                  ReaduoNavDestination.circle,
                  CircleScreen(
                    key: const ValueKey('circle-tab-root'),
                    viewerId: widget.user.uid,
                    friendRepository: widget.friendRepository,
                    shelfRepository: widget.shelfRepository,
                    bookRepository: widget.bookRepository,
                    circleRepository: widget.circleRepository,
                    reviewRepository: widget.reviewRepository,
                    engagementRepository: widget.engagementRepository,
                    photoRepository: widget.photoRepository,
                    viewerDisplayName: widget.user.displayName ?? 'You',
                    viewerPhotoUrl: widget.user.photoUrl,
                    onNotifications: _openNotifications,
                    onInviteFriend: () => _select(ReaduoNavDestination.friends),
                    onOpenLibrary: () => _select(ReaduoNavDestination.library),
                  ),
                ),
                _tabNavigator(
                  ReaduoNavDestination.library,
                  MyLibraryScreen(
                    key: const ValueKey('library-tab-root'),
                    authService: widget.authService,
                    shelfRepository: widget.shelfRepository,
                    bookRepository: widget.bookRepository,
                    bookLookupRepository: widget.bookLookupRepository,
                    catalogueRepository: widget.catalogueRepository,
                    reviewRepository: widget.reviewRepository,
                    friendRepository: widget.friendRepository,
                    user: widget.user,
                    showBottomNavigation: false,
                    onSelectDestination: _select,
                    onNavigationBarVisibilityChanged: _setNavigationVisible,
                  ),
                ),
                _tabNavigator(
                  ReaduoNavDestination.friends,
                  FriendsScreen(
                    key: const ValueKey('friends-tab-root'),
                    authService: widget.authService,
                    repository: widget.friendRepository,
                    shelfRepository: widget.shelfRepository,
                    bookRepository: widget.bookRepository,
                    user: widget.user,
                    showBottomNavigation: false,
                    onSelectDestination: _select,
                    onNavigationBarVisibilityChanged: _setNavigationVisible,
                  ),
                ),
                _tabNavigator(
                  ReaduoNavDestination.profile,
                  AccountScreen(
                    key: const ValueKey('profile-tab-root'),
                    authService: widget.authService,
                    user: widget.user,
                    profileRepository:
                        _features?.profile ??
                        const UnavailableProfileRepository(),
                    supportRepository: _features == null
                        ? const UnavailableSupportRepository()
                        : FirestoreSupportRepository(
                            auth: _features!.auth,
                            firestore: _features!.firestore,
                          ),
                    onNotifications: _notificationSettings,
                    onDestination: _profileDestination,
                    bookCount: _bookCount,
                    shelfCount: _shelfCount,
                    friendCount: _friendCount,
                    isModerator: _isModerator,
                    onDeleteAccount: AccountActions.of(context)?.deleteAccount,
                    onSupportQueue: _features == null
                        ? null
                        : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => SupportRequestsScreen(
                                repository: FirestoreSupportRepository(
                                  auth: _features!.auth,
                                  firestore: _features!.firestore,
                                ),
                              ),
                            ),
                          ),
                    onModeration: _features == null
                        ? null
                        : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => ModerationScreen(
                                repository: _features!.moderation,
                                photoRepository: widget.photoRepository,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _navigationVisible
            ? ReaduoBottomNavigation(
                key: const Key('authenticated-bottom-navigation'),
                active: _active,
                onCircle: () => _select(ReaduoNavDestination.circle),
                onLibrary: () => _select(ReaduoNavDestination.library),
                onFriends: () => _select(ReaduoNavDestination.friends),
                onProfile: () => _select(ReaduoNavDestination.profile),
              )
            : null,
      ),
    );
  }

  Widget _tabNavigator(ReaduoNavDestination destination, Widget root) {
    if (!_visited.contains(destination)) return const SizedBox.shrink();
    return _KeepAliveTab(
      child: ReaduoTabActivity(
        active: _active == destination,
        child: NotificationRouteVisibility(
          visible: ModalRoute.of(context)?.isCurrent ?? true,
          child: Navigator(
            key: _navigatorKeys[destination],
            observers: [_tabRoutes[destination]!],
            pages: [
              MaterialPage<void>(
                key: ValueKey('authenticated-${destination.name}-root'),
                child: root,
              ),
            ],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    );
  }
}

class _TabRouteObserver extends NavigatorObserver {
  Route<dynamic>? top;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    top = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    top = previousRoute;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(top, route)) top = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (identical(top, oldRoute)) top = newRoute;
  }
}

class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});
  final Widget child;
  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

int _tabIndex(ReaduoNavDestination destination) => switch (destination) {
  ReaduoNavDestination.circle => 0,
  ReaduoNavDestination.library => 1,
  ReaduoNavDestination.friends => 2,
  ReaduoNavDestination.profile => 3,
};
