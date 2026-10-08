import '../widgets/readuo_image_cache.dart';
import '../widgets/book_information.dart';
import '../widgets/book_cover_image.dart';
import '../widgets/generated_book_cover.dart';
import '../profile/profile_widgets.dart';
import 'package:flutter/material.dart';
import '../notifications/notification.dart';
import '../features/feature_services.dart';
import '../moderation/moderation_repository.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_service.dart';
import '../friends/friend_repository.dart';
import '../friends/invite_links.dart';
import '../library/book.dart';
import '../library/book_repository.dart';
import '../library/shelf.dart';
import '../library/shelf_repository.dart';
import '../theme/readuo_theme.dart';
import '../widgets/readuo_bottom_navigation.dart';
import '../widgets/readuo_tab_header.dart';
import '../widgets/readuo_section_tabs.dart';
import 'account_screen.dart';
import 'my_library_screen.dart' show LibraryShelfCard;
import 'book_details_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    required this.authService,
    required this.repository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.user,
    this.showBottomNavigation = true,
    this.onSelectDestination,
    this.onNavigationBarVisibilityChanged,
    super.key,
  });

  final AuthService authService;
  final FriendRepository repository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final AuthUser user;
  final bool showBottomNavigation;
  final ValueChanged<ReaduoNavDestination>? onSelectDestination;
  final ValueChanged<bool>? onNavigationBarVisibilityChanged;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchController = TextEditingController();
  late Future<ReaderProfile> _profile;
  late Stream<List<ReaderProfile>> _friends;
  late Stream<List<FriendRequestRecord>> _incoming;
  late Stream<List<FriendRequestRecord>> _sent;
  String _query = '';
  bool _showRequests = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    _profile = widget.repository.ensureProfile(widget.user);
    _friends = widget.repository.watchFriends(widget.user.uid);
    _incoming = widget.repository.watchIncomingRequests(widget.user.uid);
    _sent = widget.repository.watchSentRequests(widget.user.uid);
  }

  void _retry() => setState(_load);

  Future<T?> _pushFullscreen<T>(Route<T> route) async {
    widget.onNavigationBarVisibilityChanged?.call(false);
    try {
      return await Navigator.of(context).push<T>(route);
    } finally {
      widget.onNavigationBarVisibilityChanged?.call(true);
    }
  }

  Future<void> _openInvite() async {
    ReaderProfile profile;
    try {
      profile = await _profile;
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message(error, 'prepare your invite'))),
        );
      return;
    }
    if (!mounted) return;
    await _pushFullscreen<void>(
      MaterialPageRoute<void>(
        builder: (_) => InviteFriendScreen(
          repository: widget.repository,
          user: widget.user,
          profile: profile,
        ),
      ),
    );
  }

  void _openRequests({required bool incoming}) {
    _pushFullscreen<void>(
      MaterialPageRoute<void>(
        builder: (_) => FriendRequestsScreen(
          repository: widget.repository,
          userId: widget.user.uid,
          incoming: incoming,
        ),
      ),
    );
  }

  void _openFriend(ReaderProfile friend) {
    _pushFullscreen<void>(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(
          repository: widget.repository,
          shelfRepository: widget.shelfRepository,
          bookRepository: widget.bookRepository,
          userId: widget.user.uid,
          friend: friend,
        ),
      ),
    );
  }

  void _openAccount() {
    final select = widget.onSelectDestination;
    if (select != null) {
      select(ReaduoNavDestination.profile);
      return;
    }
    _pushFullscreen<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            AccountScreen(authService: widget.authService, user: widget.user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProfilePage(
      title: 'Friends',
      mainTab: true,
      back: false,
      tabActions: [
        ReaduoTabHeaderAction(
          key: const Key('invite-friend-button'),
          tooltip: 'Invite a friend',
          label: 'Invite',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: _openInvite,
        ),
      ],
      bottomNavigationBar: widget.showBottomNavigation
          ? ReaduoBottomNavigation(
              active: ReaduoNavDestination.friends,
              onLibrary: () => Navigator.of(context).pop(),
              onProfile: _openAccount,
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<ReaderProfile>(
          future: _profile,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.hasError) {
              return _ErrorView(
                message: _message(profileSnapshot.error, 'prepare Friends'),
                onRetry: _retry,
              );
            }
            if (!profileSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder<List<ReaderProfile>>(
              stream: _friends,
              builder: (context, friendsSnapshot) {
                if (friendsSnapshot.hasError) {
                  return _ErrorView(
                    message: _message(friendsSnapshot.error, 'load friends'),
                    onRetry: _retry,
                  );
                }
                if (!friendsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return StreamBuilder<List<FriendRequestRecord>>(
                  stream: _incoming,
                  builder: (context, incomingSnapshot) {
                    if (incomingSnapshot.hasError) {
                      return _ErrorView(
                        message: _message(
                          incomingSnapshot.error,
                          'load requests',
                        ),
                        onRetry: _retry,
                      );
                    }
                    if (!incomingSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return StreamBuilder<List<FriendRequestRecord>>(
                      stream: _sent,
                      builder: (context, sentSnapshot) {
                        if (sentSnapshot.hasError) {
                          return _ErrorView(
                            message: _message(
                              sentSnapshot.error,
                              'load requests',
                            ),
                            onRetry: _retry,
                          );
                        }
                        if (!sentSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return _FriendsContent(
                          repository: widget.repository,
                          viewerId: widget.user.uid,
                          shelfRepository: widget.shelfRepository,
                          bookRepository: widget.bookRepository,
                          friends: friendsSnapshot.data!,
                          incoming: incomingSnapshot.data!,
                          sent: sentSnapshot.data!,
                          query: _query,
                          showRequests: _showRequests,
                          onShowRequests: (value) =>
                              setState(() => _showRequests = value),
                          searchController: _searchController,
                          onQueryChanged: (value) => setState(
                            () => _query = value.trim().toLowerCase(),
                          ),
                          onInvite: _openInvite,
                          onEnterCode: () => _openEnterCode(
                            context,
                            widget.repository,
                            widget.user.uid,
                          ),
                          onIncoming: () => _openRequests(incoming: true),
                          onSent: () => _openRequests(incoming: false),
                          onFriend: _openFriend,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FriendsContent extends StatelessWidget {
  const _FriendsContent({
    required this.repository,
    required this.viewerId,
    required this.shelfRepository,
    required this.bookRepository,
    required this.friends,
    required this.incoming,
    required this.sent,
    required this.query,
    required this.showRequests,
    required this.onShowRequests,
    required this.searchController,
    required this.onQueryChanged,
    required this.onInvite,
    required this.onEnterCode,
    required this.onIncoming,
    required this.onSent,
    required this.onFriend,
  });

  final FriendRepository repository;
  final List<ReaderProfile> friends;
  final String viewerId;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final List<FriendRequestRecord> incoming;
  final List<FriendRequestRecord> sent;
  final String query;
  final bool showRequests;
  final ValueChanged<bool> onShowRequests;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onInvite;
  final VoidCallback onEnterCode;
  final VoidCallback onIncoming;
  final VoidCallback onSent;
  final ValueChanged<ReaderProfile> onFriend;

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty && incoming.isEmpty && sent.isEmpty) {
      return _EmptyFriends(onInvite: onInvite, onEnterCode: onEnterCode);
    }
    if (friends.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PendingRequests(
            repository: repository,
            viewerId: viewerId,
            incoming: incoming,
            sent: sent,
          ),
        ],
      );
    }
    final visible = friends
        .where((friend) => friend.displayName.toLowerCase().contains(query))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const Text(
          'Good books are better together.',
          style: TextStyle(color: ReaduoColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('friend-search-field'),
          controller: searchController,
          onChanged: onQueryChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          decoration: InputDecoration(
            hintText: 'Search friends by name',
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      searchController.clear();
                      onQueryChanged('');
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
            isDense: true,
            filled: true,
            fillColor: ReaduoColors.paper,
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: ReaduoColors.line),
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: ReaduoColors.line),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ReaduoSectionTabs(
          labels: [
            'Your friends · ${friends.length}',
            'Requests · ${incoming.length + sent.length}',
          ],
          selected: showRequests ? 1 : 0,
          tabKeys: const [Key('your-friends-tab'), Key('friend-requests-tab')],
          onSelected: (index) => onShowRequests(index == 1),
        ),
        const SizedBox(height: 12),
        if (showRequests) ...[
          _PendingRequests(
            repository: repository,
            viewerId: viewerId,
            incoming: incoming,
            sent: sent,
          ),
        ] else ...[
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'No friends match that name.',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...visible.map(
              (friend) => _FriendReadingTile(
                key: ValueKey('friend-reading-${friend.uid}'),
                friend: friend,
                viewerId: viewerId,
                shelfRepository: shelfRepository,
                bookRepository: bookRepository,
                onTap: () => onFriend(friend),
              ),
            ),
        ],
      ],
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends({required this.onInvite, required this.onEnterCode});

  final VoidCallback onInvite;
  final VoidCallback onEnterCode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: ReaduoSpacing.screenHorizontal,
          vertical: 28,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              Text(
                'Reading is better together',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: ReaduoColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Connect with friends to discover their books and share what you're reading.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 26),
              FilledButton(
                key: const Key('empty-invite-button'),
                onPressed: onInvite,
                child: const Text('Invite a friend'),
              ),
              const SizedBox(height: 10),
              TextButton(
                key: const Key('empty-enter-code-button'),
                onPressed: onEnterCode,
                child: const Text('Enter friend code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InviteFriendScreen extends StatelessWidget {
  const InviteFriendScreen({
    required this.repository,
    required this.user,
    required this.profile,
    super.key,
  });

  final FriendRepository repository;
  final AuthUser user;
  final ReaderProfile profile;

  void _copied(BuildContext context) {
    Clipboard.setData(ClipboardData(text: profile.formattedInviteCode));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Invite code copied.')));
  }

  Future<void> _share(BuildContext context) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Join me on Readuo: ${inviteLink(profile.inviteCode)}\nFriend code: ${profile.formattedInviteCode}. Send a request to connect.',
        ),
      );
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open sharing. You can copy the invite code instead.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(
            left: ReaduoSpacing.screenHorizontal,
            top: 10,
            bottom: 10,
          ),
          child: IconButton.outlined(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, size: 20),
            style: IconButton.styleFrom(
              side: const BorderSide(color: ReaduoColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ),
        titleSpacing: 10,
        title: const Text(
          'Invite a friend',
          style: TextStyle(
            fontSize: 20,
            letterSpacing: -.7,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: ReaduoSpacing.screenHorizontal,
            vertical: 20,
          ),
          children: [
            _Surface(
              child: Column(
                children: [
                  const Text(
                    'Your invite code',
                    style: TextStyle(fontSize: 12, color: ReaduoColors.muted),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    profile.formattedInviteCode,
                    key: const Key('invite-code'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: ReaduoColors.accent,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Friends can use this code to send you a request.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ReaduoColors.muted,
                      height: 1.6,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copied(context),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy code'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _share(context),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share link'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _InfoBanner(
              icon: Icons.verified_user_outlined,
              text:
                  'You’ll both get access to friends-only shelves after the request is accepted.',
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => _openEnterCode(context, repository, user.uid),
              child: const Text("Enter a friend's code instead"),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openEnterCode(
  BuildContext context,
  FriendRepository repository,
  String userId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) =>
        EnterInviteCodeScreen(repository: repository, userId: userId),
  ),
);

class EnterInviteCodeScreen extends StatefulWidget {
  const EnterInviteCodeScreen({
    required this.repository,
    required this.userId,
    super.key,
  });

  final FriendRepository repository;
  final String userId;

  @override
  State<EnterInviteCodeScreen> createState() => _EnterInviteCodeScreenState();
}

class _EnterInviteCodeScreenState extends State<EnterInviteCodeScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final code = normalizeInviteCode(_controller.text);
    if (code.length != 6) {
      setState(() => _error = 'Enter a 6-character friend code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.findByInviteCode(
        userId: widget.userId,
        code: code,
      );
      if (!mounted) return;
      if (result.kind == InviteLookupKind.unknown ||
          result.kind == InviteLookupKind.blocked) {
        setState(() => _error = 'No reader was found for that code.');
        return;
      }
      if (result.kind == InviteLookupKind.self) {
        setState(() => _error = 'That is your own invite code.');
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RequestPreviewScreen(
            repository: widget.repository,
            userId: widget.userId,
            code: code,
            result: result,
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error, 'find this reader'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProfilePage(
      title: 'Enter friend code',
      compactHeader: true,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ReaduoSpacing.screenHorizontal,
                  vertical: 24,
                ),
                child: Align(
                  alignment: const Alignment(0, -.3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Friend code',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) => Stack(
                          alignment: Alignment.center,
                          children: [
                            ExcludeSemantics(
                              child: Row(
                                children: [
                                  for (var index = 0; index < 6; index++) ...[
                                    if (index == 3)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        child: Text(
                                          '-',
                                          style: TextStyle(
                                            fontSize: 22,
                                            color: ReaduoColors.muted,
                                          ),
                                        ),
                                      )
                                    else if (index > 0)
                                      const SizedBox(width: 6),
                                    Expanded(
                                      child: Container(
                                        height: 56,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: ReaduoColors.paper,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: _error != null
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.error
                                                : index == value.text.length
                                                ? ReaduoColors.accent
                                                : ReaduoColors.line,
                                            width: index == value.text.length
                                                ? 2
                                                : 1,
                                          ),
                                        ),
                                        child: Text(
                                          index < value.text.length
                                              ? value.text[index]
                                              : '',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                            color: ReaduoColors.ink,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            TextField(
                              key: const Key('invite-code-field'),
                              controller: _controller,
                              autofocus: true,
                              enabled: !_loading,
                              showCursor: false,
                              style: const TextStyle(
                                color: Colors.transparent,
                                fontSize: 22,
                              ),
                              cursorColor: Colors.transparent,
                              autocorrect: false,
                              enableSuggestions: false,
                              textCapitalization: TextCapitalization.characters,
                              textInputAction: TextInputAction.done,
                              onTap: () => _controller.selection =
                                  TextSelection.collapsed(
                                    offset: _controller.text.length,
                                  ),
                              onChanged: (_) {
                                if (_error != null)
                                  setState(() => _error = null);
                              },
                              onSubmitted: (_) => _loading ? null : _find(),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp('[a-zA-Z0-9]'),
                                ),
                                LengthLimitingTextInputFormatter(6),
                                TextInputFormatter.withFunction(
                                  (oldValue, newValue) => newValue.copyWith(
                                    text: newValue.text.toUpperCase(),
                                  ),
                                ),
                              ],
                              decoration: const InputDecoration(
                                hintText: '',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error ?? 'Codes have 6 letters or numbers.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _error != null
                              ? Theme.of(context).colorScheme.error
                              : ReaduoColors.muted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('find-friend-button'),
                        onPressed: _loading ? null : _find,
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Find friend'),
                      ),
                      const SizedBox(height: 24),
                      const _InfoBanner(
                        icon: Icons.info_outline_rounded,
                        text:
                            'Entering a code does not connect you automatically. The reader must accept your request.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RequestPreviewScreen extends StatefulWidget {
  const RequestPreviewScreen({
    required this.repository,
    required this.userId,
    required this.code,
    required this.result,
    super.key,
  });

  final FriendRepository repository;
  final String userId;
  final String code;
  final InviteLookupResult result;

  @override
  State<RequestPreviewScreen> createState() => _RequestPreviewScreenState();
}

class _RequestPreviewScreenState extends State<RequestPreviewScreen> {
  bool _loading = false;
  String? _status;
  String? _error;

  Future<void> _send() async {
    final profile = widget.result.profile;
    if (profile == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final outcome = await widget.repository.sendRequest(
        userId: widget.userId,
        recipient: profile,
        inviteCode: widget.code,
      );
      if (!mounted) return;
      setState(() {
        _status = switch (outcome) {
          SendRequestOutcome.sent => 'Request sent',
          SendRequestOutcome.alreadyFriend => 'You are already friends',
          SendRequestOutcome.alreadySent => 'Request already sent',
          SendRequestOutcome.incomingRequest =>
            'This reader already sent you a request',
        };
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error, 'send request'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.result.profile!;
    if (_status == 'Request sent') {
      final firstName = profile.displayName.trim().split(RegExp(r'\s+')).first;
      return ProfilePage(
        title: 'Request sent',
        children: [
          const SizedBox(height: 34),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ReaduoColors.accentTint,
                  borderRadius: BorderRadius.circular(23),
                ),
                child: const Icon(
                  Icons.send_outlined,
                  size: 30,
                  color: ReaduoColors.accent,
                ),
              ),
            ),
          ),
          Text(
            'Over to $firstName',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
          Text(
            'You’ll be notified when $firstName accepts. Friends-only shelves remain private until then.',
            textAlign: TextAlign.center,
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Back to Friends'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => FriendRequestsScreen(
                  repository: widget.repository,
                  userId: widget.userId,
                  incoming: false,
                ),
              ),
            ),
            child: const Text('View sent requests'),
          ),
        ],
      );
    }
    final initialStatus = switch (widget.result.kind) {
      InviteLookupKind.alreadyFriend => 'You are already friends',
      InviteLookupKind.alreadySent => 'Request already sent',
      InviteLookupKind.incomingRequest =>
        'This reader already sent you a request',
      _ => null,
    };
    final status = _status ?? initialStatus;
    final canSend =
        widget.result.kind == InviteLookupKind.available && _status == null;
    return ProfilePage(
      title: 'Send a request',
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: ReaduoSpacing.screenHorizontal,
              vertical: 28,
            ),
            child: Column(
              children: [
                _ReaderAvatar(profile: profile, radius: 38),
                const SizedBox(height: 18),
                Text(
                  profile.displayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: ReaduoColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status ??
                      'Send a request to connect with this reader on Readuo.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_error != null) profileError(_error),
                if (canSend)
                  FilledButton(
                    key: const Key('send-friend-request-button'),
                    onPressed: _loading ? null : _send,
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Send friend request'),
                  )
                else
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                const SizedBox(height: 20),
                const _InfoBanner(
                  icon: Icons.info_outline,
                  text:
                      'The reader must accept before either of you can browse friends-only shelves.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FriendRequestsScreen extends StatelessWidget {
  const FriendRequestsScreen({
    required this.repository,
    required this.userId,
    required this.incoming,
    super.key,
  });

  final FriendRepository repository;
  final String userId;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final stream = incoming
        ? repository.watchIncomingRequests(userId)
        : repository.watchSentRequests(userId);
    return ProfilePage(
      title: incoming ? 'Friend requests' : 'Sent requests',
      body: SafeArea(
        child: StreamBuilder<List<FriendRequestRecord>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorView(
                message: _message(snapshot.error, 'load requests'),
                onRetry: () =>
                    Navigator.of(context).pushReplacement<void, void>(
                      MaterialPageRoute<void>(
                        builder: (_) => FriendRequestsScreen(
                          repository: repository,
                          userId: userId,
                          incoming: incoming,
                        ),
                      ),
                    ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final requests = snapshot.data!;
            if (requests.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ReaduoSpacing.screenHorizontal,
                    vertical: 28,
                  ),
                  child: Text(
                    incoming ? 'No received requests.' : 'No sent requests.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: ReaduoSpacing.screenHorizontal,
                vertical: 20,
              ),
              itemCount: requests.length + (incoming ? 0 : 1),
              separatorBuilder: (_, _) =>
                  incoming ? const Divider(height: 1) : const SizedBox.shrink(),
              itemBuilder: (context, index) {
                if (index == requests.length)
                  return const Text(
                    'Friends-only access begins only after acceptance.',
                    style: TextStyle(fontSize: 12, color: ReaduoColors.muted),
                  );
                final request = requests[index];
                if (!incoming)
                  return _SentRequestCard(
                    key: ValueKey(request.pairId),
                    repository: repository,
                    userId: userId,
                    request: request,
                  );
                return _ReaderTile(
                  profile: request.reader,
                  subtitle: incoming
                      ? 'Wants to connect'
                      : 'Waiting for a response',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => FriendRequestDetailScreen(
                        repository: repository,
                        userId: userId,
                        request: request,
                        incoming: incoming,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PendingRequests extends StatelessWidget {
  const _PendingRequests({
    required this.repository,
    required this.viewerId,
    required this.incoming,
    required this.sent,
  });
  final FriendRepository repository;
  final String viewerId;
  final List<FriendRequestRecord> incoming;
  final List<FriendRequestRecord> sent;
  @override
  Widget build(BuildContext context) {
    if (incoming.isEmpty && sent.isEmpty)
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 64),
        child: Column(
          children: [
            Text(
              'No pending requests',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Text(
              'Friend requests you receive or send will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ReaduoColors.muted, height: 1.5),
            ),
          ],
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (incoming.isNotEmpty) ...[
          const Text('Received', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (final request in incoming)
            _IncomingRequestCard(
              key: ValueKey('received-${request.pairId}'),
              repository: repository,
              userId: viewerId,
              request: request,
            ),
        ],
        if (sent.isNotEmpty) ...[
          const Text('Sent', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (final request in sent)
            _SentRequestCard(
              key: ValueKey('sent-${request.pairId}'),
              repository: repository,
              userId: viewerId,
              request: request,
            ),
        ],
      ],
    );
  }
}

class _IncomingRequestCard extends StatefulWidget {
  const _IncomingRequestCard({
    super.key,
    required this.repository,
    required this.userId,
    required this.request,
  });
  final FriendRepository repository;
  final String userId;
  final FriendRequestRecord request;
  @override
  State<_IncomingRequestCard> createState() => _IncomingRequestCardState();
}

class _IncomingRequestCardState extends State<_IncomingRequestCard> {
  bool _busy = false;
  bool _done = false;
  String? _error;
  Future<void> _act(bool accept) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (accept) {
        await widget.repository.acceptRequest(
          userId: widget.userId,
          request: widget.request,
        );
      } else {
        await widget.repository.declineRequest(
          userId: widget.userId,
          request: widget.request,
        );
      }
      if (mounted) setState(() => _done = true);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error, 'update request'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _done
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _ReaderAvatar(profile: widget.request.reader, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.request.reader.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _act(true),
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: _busy ? null : () => _act(false),
                      child: const Text('Decline'),
                    ),
                  ),
                  if (_busy)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              if (_error != null) profileError(_error),
              const Divider(),
            ],
          ),
        );
}

class _SentRequestCard extends StatefulWidget {
  const _SentRequestCard({
    super.key,
    required this.repository,
    required this.userId,
    required this.request,
  });
  final FriendRepository repository;
  final String userId;
  final FriendRequestRecord request;
  @override
  State<_SentRequestCard> createState() => _SentRequestCardState();
}

class _SentRequestCardState extends State<_SentRequestCard> {
  bool _busy = false;
  bool _cancelled = false;
  String? _error;
  Future<void> _cancel() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.cancelRequest(
        userId: widget.userId,
        request: widget.request,
      );
      if (mounted) setState(() => _cancelled = true);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error, 'cancel request'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _cancelled
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: ReaduoColors.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _ReaderAvatar(profile: widget.request.reader),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.request.reader.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const Text(
                          'Awaiting response',
                          style: TextStyle(
                            fontSize: 12,
                            color: ReaduoColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_error != null) profileError(_error),
              TextButton(
                onPressed: _busy ? null : _cancel,
                child: Text(_busy ? 'Cancelling…' : 'Cancel request'),
              ),
            ],
          ),
        );
}

class FriendRequestDetailScreen extends StatefulWidget {
  const FriendRequestDetailScreen({
    required this.repository,
    required this.userId,
    required this.request,
    required this.incoming,
    super.key,
  });

  final FriendRepository repository;
  final String userId;
  final FriendRequestRecord request;
  final bool incoming;

  @override
  State<FriendRequestDetailScreen> createState() =>
      _FriendRequestDetailScreenState();
}

class _FriendRequestDetailScreenState extends State<FriendRequestDetailScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error, 'update request'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.request.reader;
    return ProfilePage(
      title: widget.incoming ? 'Friend request' : 'Sent request',
      notificationDestination: NotificationDestination(
        NotificationDestinationKind.request,
        widget.request.pairId,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              32,
              ReaduoSpacing.screenHorizontal,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _ReaderAvatar(profile: profile, radius: 38)),
                const SizedBox(height: 18),
                Text(
                  profile.displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: ReaduoColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.incoming
                      ? 'Sent you a friend request.'
                      : 'Your request is waiting for a response.',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                if (widget.incoming) ...[
                  const _InfoBanner(
                    icon: Icons.info_outline,
                    text:
                        'Accepting shares your Friends shelves and Circle posts with each other. Private shelves stay private.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('accept-request-button'),
                    onPressed: _loading
                        ? null
                        : () => _act(
                            () => widget.repository.acceptRequest(
                              userId: widget.userId,
                              request: widget.request,
                            ),
                          ),
                    child: const Text('Accept request'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const Key('decline-request-button'),
                    onPressed: _loading
                        ? null
                        : () => _act(
                            () => widget.repository.declineRequest(
                              userId: widget.userId,
                              request: widget.request,
                            ),
                          ),
                    child: const Text('Decline'),
                  ),
                ] else
                  OutlinedButton(
                    key: const Key('cancel-request-button'),
                    onPressed: _loading
                        ? null
                        : () => _act(
                            () => widget.repository.cancelRequest(
                              userId: widget.userId,
                              request: widget.request,
                            ),
                          ),
                    child: const Text('Cancel request'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({
    required this.repository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.userId,
    required this.friend,
    super.key,
  });

  final FriendRepository repository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final String userId;
  final ReaderProfile friend;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  bool _loading = false;

  Future<void> _options() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            ReaduoSpacing.screenHorizontal,
            0,
            ReaduoSpacing.screenHorizontal,
            22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Connection options',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              ProfileRow(
                'Remove friend',
                Icons.person_remove_outlined,
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
              ProfileRow(
                'Block this reader',
                Icons.block,
                onTap: () => Navigator.pop(sheetContext, 'block'),
              ),
              ProfileRow(
                'Report profile',
                Icons.flag_outlined,
                onTap: () => Navigator.pop(sheetContext, 'report'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'report') {
      FeatureServices.report(
        context,
        ReportTarget(kind: 'profile', id: widget.friend.uid),
      );
    } else {
      await _confirm(block: action == 'block');
    }
  }

  Future<void> _confirm({required bool block}) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          8,
          ReaduoSpacing.screenHorizontal,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              block ? 'Block ${widget.friend.displayName}?' : 'Remove friend?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              block
                  ? 'Blocking removes this friendship and any pending request. You can unblock them later, but the friendship will not return.'
                  : 'You can reconnect later with a new invite request.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(block ? 'Block reader' : 'Remove friend'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep friend'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      if (block) {
        await widget.repository.blockReader(
          userId: widget.userId,
          reader: widget.friend,
        );
      } else {
        await widget.repository.removeFriend(
          userId: widget.userId,
          friend: widget.friend,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _message(error, block ? 'block reader' : 'remove friend'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProfilePage(
      title: 'Reader profile',
      notificationDestination: NotificationDestination(
        NotificationDestinationKind.reader,
        widget.friend.uid,
      ),
      actions: [
        IconButton.outlined(
          tooltip: 'Connection options',
          onPressed: _loading ? null : _options,
          icon: const Icon(Icons.more_horiz),
        ),
      ],
      body: SafeArea(
        child: StreamBuilder<List<ReaderProfile>>(
          stream: widget.repository.watchFriends(widget.userId),
          builder: (context, friendSnapshot) {
            if (friendSnapshot.hasError ||
                (friendSnapshot.hasData &&
                    !friendSnapshot.data!.any(
                      (friend) => friend.uid == widget.friend.uid,
                    ))) {
              return _ErrorView(
                message:
                    'This reader is no longer connected to you. Shared content has been cleared.',
                onRetry: () => Navigator.of(context).pop(),
              );
            }
            if (!friendSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: ReaduoSpacing.screenHorizontal,
                vertical: 24,
              ),
              children: [
                Row(
                  children: [
                    _ReaderAvatar(profile: widget.friend, radius: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.friend.displayName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Your friend',
                            style: TextStyle(color: ReaduoColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                StreamBuilder<List<Shelf>>(
                  stream: widget.shelfRepository.watchSharedShelves(
                    viewerId: widget.userId,
                    ownerId: widget.friend.uid,
                  ),
                  builder: (context, snapshot) {
                    final shelves = snapshot.data ?? const <Shelf>[];
                    if (snapshot.hasError)
                      return const Text(
                        'Shared shelves are no longer available.',
                      );
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    if (shelves.isEmpty)
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No shared bookshelves yet.'),
                        ),
                      );
                    return _FriendLibraryContent(
                      viewerId: widget.userId,
                      friend: widget.friend,
                      shelves: shelves,
                      friendRepository: widget.repository,
                      shelfRepository: widget.shelfRepository,
                      bookRepository: widget.bookRepository,
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FriendLibraryContent extends StatefulWidget {
  const _FriendLibraryContent({
    required this.viewerId,
    required this.friend,
    required this.shelves,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
  });
  final String viewerId;
  final ReaderProfile friend;
  final List<Shelf> shelves;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  @override
  State<_FriendLibraryContent> createState() => _FriendLibraryContentState();
}

class _FriendLibraryContentState extends State<_FriendLibraryContent> {
  ReadingStatus? _status;
  bool _showAll = false;
  final Map<String, Stream<List<LibraryBook>>> _streams = {};

  Widget _load(int index, Map<String, List<LibraryBook>> books) {
    if (index == widget.shelves.length) return _content(books);
    final shelf = widget.shelves[index];
    return StreamBuilder<List<LibraryBook>>(
      key: ValueKey(shelf.id),
      stream: _streams.putIfAbsent(
        shelf.id,
        () => widget.bookRepository.watchSharedBooks(
          viewerId: widget.viewerId,
          ownerId: widget.friend.uid,
          shelfId: shelf.id,
        ),
      ),
      builder: (context, snapshot) => _load(index + 1, {
        ...books,
        shelf.id: snapshot.hasError
            ? <LibraryBook>[]
            : snapshot.data ?? <LibraryBook>[],
      }),
    );
  }

  void _openShelf(Shelf shelf) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SharedShelfScreen(
        viewerId: widget.viewerId,
        friend: widget.friend,
        shelf: shelf,
        friendRepository: widget.friendRepository,
        shelfRepository: widget.shelfRepository,
        bookRepository: widget.bookRepository,
      ),
    ),
  );

  Widget _content(Map<String, List<LibraryBook>> books) {
    final entries = [
      for (final shelf in widget.shelves)
        for (final book in books[shelf.id] ?? <LibraryBook>[])
          if (_status == null || book.readingStatus == _status)
            (shelf: shelf, book: book),
    ];
    final visible = _showAll ? entries : entries.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Bookshelves',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final shelf in widget.shelves)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 42) / 2,
                    child: LibraryShelfCard(
                      shelf: shelf,
                      books: books[shelf.id] ?? [],
                      onTap: () => _openShelf(shelf),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Books',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            if (entries.length > 6)
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? 'Show less' : 'View all'),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final status in ReadingStatus.values)
              ChoiceChip(
                label: Text(status.label),
                selected: _status == status,
                onSelected: (selected) => setState(() {
                  _status = selected ? status : null;
                  _showAll = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _status == null
                  ? 'No shared books yet.'
                  : 'No books with this reading status.',
              textAlign: TextAlign.center,
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 14,
            runSpacing: 18,
            children: [
              for (final entry in visible)
                SizedBox(
                  width: (constraints.maxWidth - 28) / 3,
                  child: InkWell(
                    key: ValueKey(
                      'friend-library-book-${entry.shelf.id}-${entry.book.id}',
                    ),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (_) => FriendBookSheet(
                        viewerId: widget.viewerId,
                        friend: widget.friend,
                        sourceShelf: entry.shelf,
                        book: entry.book,
                        friendRepository: widget.friendRepository,
                        shelfRepository: widget.shelfRepository,
                        bookRepository: widget.bookRepository,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: .68,
                          child: _SharedBookCover(book: entry.book),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: ReaduoColors.muted,
                          ),
                        ),
                        Text(
                          entry.book.readingStatus.label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: ReaduoColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _load(0, {});
}

class SharedShelfScreen extends StatelessWidget {
  const SharedShelfScreen({
    required this.viewerId,
    required this.friend,
    required this.shelf,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    this.ownedOnly = false,
    this.publicAccess = false,
    this.onCreateShelf,
    this.onOpenOwnedBook,
    super.key,
  });

  final String viewerId;
  final ReaderProfile friend;
  final Shelf shelf;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final bool ownedOnly;
  final bool publicAccess;
  final Future<Shelf?> Function()? onCreateShelf;
  final ValueChanged<LibraryBook>? onOpenOwnedBook;

  @override
  Widget build(BuildContext context) {
    return _FriendShelfAccessBoundary(
      friendRepository: friendRepository,
      shelfRepository: shelfRepository,
      viewerId: viewerId,
      friendId: friend.uid,
      shelfId: shelf.id,
      requireFriendship: !publicAccess,
      publicOnly: publicAccess,
      builder: (context, liveShelf) => Scaffold(
        appBar: AppBar(title: Text(liveShelf.name)),
        body: SafeArea(
          child: StreamBuilder<List<LibraryBook>>(
            stream: ownedOnly
                ? bookRepository.watchOwnedSharedBooks(
                    viewerId: viewerId,
                    ownerId: friend.uid,
                    shelfId: liveShelf.id,
                  )
                : bookRepository.watchSharedBooks(
                    viewerId: viewerId,
                    ownerId: friend.uid,
                    shelfId: liveShelf.id,
                  ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorView(
                  message:
                      'This shelf is no longer available. Its privacy or your connection may have changed.',
                  onRetry: () => Navigator.of(context).pop(),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final books = snapshot.data!
                  .where((book) => !ownedOnly || book.isOwned)
                  .toList();
              return ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: ReaduoSpacing.screenHorizontal,
                  vertical: 20,
                ),
                children: [
                  Row(
                    children: [
                      _ReaderAvatar(profile: friend, radius: 18),
                      const SizedBox(width: 10),
                      Text(
                        friend.displayName,
                        style: TextStyle(
                          color: ownedOnly
                              ? ReaduoColors.accent
                              : ReaduoColors.ink,
                          fontWeight: ownedOnly
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                      if (ownedOnly) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            publicAccess ? 'Public' : 'Shared with friends',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ReaduoColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!ownedOnly) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(
                            liveShelf.visibility == ShelfVisibility.public
                                ? Icons.public_rounded
                                : Icons.people_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            liveShelf.visibility == ShelfVisibility.public
                                ? 'Public'
                                : 'Shared with friends',
                          ),
                        ),
                        const Chip(label: Text('Read-only')),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    ownedOnly
                        ? publicAccess
                              ? 'Owned books · Read-only for signed-in users'
                              : 'Owned books · Read-only'
                        : '${books.length} ${books.length == 1 ? 'book' : 'books'}',
                  ),
                  const SizedBox(height: 18),
                  if (books.isEmpty)
                    const _InfoBanner(
                      icon: Icons.menu_book_outlined,
                      text: 'No books are saved on this shelf.',
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: ownedOnly ? 3 : 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 18,
                        childAspectRatio: .58,
                      ),
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final book = books[index];
                        return InkWell(
                          key: Key('shared-book-${book.id}'),
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            showDragHandle: true,
                            builder: (_) => FriendBookSheet(
                              viewerId: viewerId,
                              friend: friend,
                              sourceShelf: liveShelf,
                              book: book,
                              friendRepository: friendRepository,
                              shelfRepository: shelfRepository,
                              bookRepository: bookRepository,
                              ownedOnly: ownedOnly,
                              publicAccess: publicAccess,
                              onCreateShelf: onCreateShelf,
                              onOpenOwnedBook: onOpenOwnedBook,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _SharedBookCover(book: book)),
                              const SizedBox(height: 8),
                              Text(
                                book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: ReaduoColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (!ownedOnly)
                                Text(
                                  book.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                ownedOnly
                                    ? book.readingStatus ==
                                              ReadingStatus.wantToRead
                                          ? 'Owned'
                                          : book.readingStatus.label
                                    : '${book.isOwned ? 'Owned' : 'Not owned'} · ${book.readingStatus.label}',
                                maxLines: 1,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class FriendBookSheet extends StatelessWidget {
  const FriendBookSheet({
    required this.viewerId,
    required this.friend,
    required this.sourceShelf,
    required this.book,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    this.ownedOnly = false,
    this.publicAccess = false,
    this.onCreateShelf,
    this.onOpenOwnedBook,
    this.onSeeShelf,
    super.key,
  });

  final String viewerId;
  final ReaderProfile friend;
  final Shelf sourceShelf;
  final LibraryBook book;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final bool ownedOnly;
  final bool publicAccess;
  final Future<Shelf?> Function()? onCreateShelf;
  final ValueChanged<LibraryBook>? onOpenOwnedBook;
  final VoidCallback? onSeeShelf;

  @override
  Widget build(BuildContext context) {
    return _FriendShelfAccessBoundary(
      friendRepository: friendRepository,
      shelfRepository: shelfRepository,
      viewerId: viewerId,
      friendId: friend.uid,
      shelfId: sourceShelf.id,
      requireFriendship: !publicAccess,
      publicOnly: publicAccess,
      dismissOnRevoked: true,
      builder: (context, liveShelf) => StreamBuilder<List<LibraryBook>>(
        stream: ownedOnly
            ? bookRepository.watchOwnedSharedBooks(
                viewerId: viewerId,
                ownerId: friend.uid,
                shelfId: liveShelf.id,
              )
            : bookRepository.watchSharedBooks(
                viewerId: viewerId,
                ownerId: friend.uid,
                shelfId: liveShelf.id,
              ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _SheetUnavailable(
              message:
                  'This book is no longer available. Its shelf privacy or your connection may have changed.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final liveBook = snapshot.data!
              .where(
                (item) => item.id == book.id && (!ownedOnly || item.isOwned),
              )
              .firstOrNull;
          if (liveBook == null) {
            return const _SheetUnavailable(
              message: 'This book is no longer available on this shelf.',
            );
          }
          return _FriendBookSheetContent(
            viewerId: viewerId,
            friend: friend,
            liveShelf: liveShelf,
            book: liveBook,
            friendRepository: friendRepository,
            shelfRepository: shelfRepository,
            bookRepository: bookRepository,
            ownedOnly: ownedOnly,
            publicAccess: publicAccess,
            onCreateShelf: onCreateShelf,
            onOpenOwnedBook: onOpenOwnedBook,
            onSeeShelf: onSeeShelf,
          );
        },
      ),
    );
  }
}

class _FriendBookSheetContent extends StatelessWidget {
  const _FriendBookSheetContent({
    required this.viewerId,
    required this.friend,
    required this.liveShelf,
    required this.book,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    required this.ownedOnly,
    required this.publicAccess,
    required this.onCreateShelf,
    required this.onOpenOwnedBook,
    required this.onSeeShelf,
  });

  final String viewerId;
  final ReaderProfile friend;
  final Shelf liveShelf;
  final LibraryBook book;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final bool ownedOnly;
  final bool publicAccess;
  final Future<Shelf?> Function()? onCreateShelf;
  final ValueChanged<LibraryBook>? onOpenOwnedBook;
  final VoidCallback? onSeeShelf;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .9,
    child: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ReaduoSpacing.screenHorizontal,
              4,
              ReaduoSpacing.screenHorizontal,
              24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Book details',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: ReaduoColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 116,
                      height: 172,
                      child: _SharedBookCover(book: book),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: ReaduoColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(book.author),
                          const SizedBox(height: 8),
                          BookEditionMetadata(book: book),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                BookIsbnRow(book: book),
                const SizedBox(height: 8),
                Text(
                  '${book.isOwned ? 'Owned' : 'Not owned'} · ${book.readingStatus.label}',
                  key: const Key('live-shared-book-state'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _Surface(
                  child: Row(
                    children: [
                      _ReaderAvatar(profile: friend, radius: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${friend.displayName}’s bookshelf\n${liveShelf.name} · ${liveShelf.visibility.label}',
                        ),
                      ),
                      TextButton(
                        key: const Key('friend-book-see-more'),
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          if (publicAccess && onSeeShelf != null) {
                            onSeeShelf!();
                          } else {
                            navigator.push(
                              MaterialPageRoute<void>(
                                builder: (_) => FriendProfileScreen(
                                  repository: friendRepository,
                                  shelfRepository: shelfRepository,
                                  bookRepository: bookRepository,
                                  userId: viewerId,
                                  friend: friend,
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('See more ›'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                BookDescription(book: book),
                const SizedBox(height: 12),
                const SizedBox(height: 8),
                Text(
                  'Saving defaults to Want to read and not owned. The friend’s entry stays unchanged.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            key: const Key('add-shared-book-button'),
            onPressed: () async {
              final existing = await showModalBottomSheet<Object>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => SaveFriendBookSheet(
                  viewerId: viewerId,
                  friendId: friend.uid,
                  sourceShelfId: liveShelf.id,
                  book: book,
                  friendRepository: friendRepository,
                  shelfRepository: shelfRepository,
                  bookRepository: bookRepository,
                  publicAccess: publicAccess,
                  onCreateShelf: onCreateShelf,
                  canOpenExisting: onOpenOwnedBook != null,
                ),
              );
              if (existing == null || !context.mounted) return;
              final navigator = Navigator.of(context);
              navigator.pop();
              await WidgetsBinding.instance.endOfFrame;
              if (existing is _SavedSharedBook && navigator.mounted) {
                await navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => SharedBookSavedScreen(
                      title: book.title,
                      shelf: existing.shelf,
                      bookId: existing.bookId,
                      viewerId: viewerId,
                      shelfRepository: shelfRepository,
                      bookRepository: bookRepository,
                    ),
                  ),
                );
              } else if (existing is LibraryBook) {
                onOpenOwnedBook?.call(existing);
              }
            },
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Add to my library'),
          ),
        ),
      ],
    ),
  );
}

class _SheetUnavailable extends StatelessWidget {
  const _SheetUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: ReaduoSpacing.screenHorizontal,
      vertical: 28,
    ),
    child: Center(child: Text(message, textAlign: TextAlign.center)),
  );
}

class _SavedSharedBook {
  const _SavedSharedBook(this.shelf, this.bookId);
  final Shelf shelf;
  final String? bookId;
}

class SharedBookSavedScreen extends StatelessWidget {
  const SharedBookSavedScreen({
    required this.title,
    required this.shelf,
    required this.bookId,
    required this.viewerId,
    required this.shelfRepository,
    required this.bookRepository,
    super.key,
  });
  final String title;
  final Shelf shelf;
  final String? bookId;
  final String viewerId;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Saved',
    children: [
      const SizedBox(height: 32),
      const Icon(
        Icons.bookmark_added_outlined,
        size: 48,
        color: ReaduoColors.accent,
      ),
      const Text(
        'On your reading list',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
      ),
      Text(
        '$title has been added to ${shelf.name} as Want to read.',
        textAlign: TextAlign.center,
      ),
      FilledButton.icon(
        onPressed: bookId == null
            ? null
            : () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => BookDetailsScreen(
                    ownerId: viewerId,
                    shelfId: shelf.id,
                    bookId: bookId!,
                    shelfRepository: shelfRepository,
                    bookRepository: bookRepository,
                  ),
                ),
              ),
        icon: const Icon(Icons.menu_book_outlined),
        label: const Text('View book'),
      ),
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep exploring'),
      ),
    ],
  );
}

class SaveFriendBookSheet extends StatefulWidget {
  const SaveFriendBookSheet({
    required this.viewerId,
    required this.friendId,
    required this.sourceShelfId,
    required this.book,
    required this.friendRepository,
    required this.shelfRepository,
    required this.bookRepository,
    this.onCreateShelf,
    this.canOpenExisting = false,
    this.publicAccess = false,
    super.key,
  });

  final String viewerId;
  final String friendId;
  final String sourceShelfId;
  final LibraryBook book;
  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final Future<Shelf?> Function()? onCreateShelf;
  final bool canOpenExisting;
  final bool publicAccess;

  @override
  State<SaveFriendBookSheet> createState() => _SaveFriendBookSheetState();
}

class _SaveFriendBookSheetState extends State<SaveFriendBookSheet> {
  String? _selectedShelfId;
  bool _owned = false;
  bool _saving = false;
  String? _error;

  Shelf? _shelfFor(List<Shelf> shelves, String shelfId) =>
      shelves.where((shelf) => shelf.id == shelfId).firstOrNull;

  Future<void> _createShelf() async {
    final create = widget.onCreateShelf;
    final created = create == null
        ? await _showQuickShelfCreator(context)
        : await create();
    if (created != null && mounted) {
      setState(() {
        _selectedShelfId = created.id;
        _error = null;
      });
    }
  }

  Future<void> _save(List<Shelf> shelves) async {
    final shelf = shelves
        .where((item) => item.id == _selectedShelfId)
        .firstOrNull;
    if (shelf == null) {
      setState(() => _error = 'Choose one shelf.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final input = CreateBookInput(
        title: widget.book.title,
        author: widget.book.author,
        isbnInput: widget.book.isbn ?? '',
        isOwned: _owned,
        readingStatus: ReadingStatus.wantToRead,
        coverUrl: widget.book.coverUrl,
        publisher: widget.book.publisher,
        publishedYear: widget.book.publishedYear,
        description: widget.book.description,
      );
      final repository = widget.bookRepository;
      String? createdId;
      if (repository is BookCreationReceiptSource) {
        createdId = await (repository as BookCreationReceiptSource)
            .createBookWithReceipt(
              ownerId: widget.viewerId,
              shelf: shelf,
              input: input,
            );
      } else {
        await repository.createBook(
          ownerId: widget.viewerId,
          shelf: shelf,
          input: input,
        );
        createdId = input.normalizedIsbn;
      }
      if (!mounted) return;
      Navigator.of(context).pop(_SavedSharedBook(shelf, createdId));
    } on DuplicateIsbnFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on BookFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FriendShelfAccessBoundary(
      friendRepository: widget.friendRepository,
      shelfRepository: widget.shelfRepository,
      viewerId: widget.viewerId,
      friendId: widget.friendId,
      shelfId: widget.sourceShelfId,
      requireFriendship: !widget.publicAccess,
      publicOnly: widget.publicAccess,
      dismissOnRevoked: true,
      builder: (context, _) => StreamBuilder<List<Shelf>>(
        stream: widget.shelfRepository.watchShelves(widget.viewerId),
        builder: (context, shelfSnapshot) {
          if (shelfSnapshot.hasError) {
            return const _SheetUnavailable(
              message: 'Your shelves are unavailable. Please retry.',
            );
          }
          if (!shelfSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final shelves = shelfSnapshot.data!
              .where((shelf) => shelf.mutationOperationId == null)
              .toList();
          if (_selectedShelfId == null && shelves.isNotEmpty) {
            _selectedShelfId = shelves.first.id;
          }
          return StreamBuilder<List<LibraryBook>>(
            stream: widget.bookRepository.watchLibraryBooks(widget.viewerId),
            builder: (context, bookSnapshot) {
              if (bookSnapshot.hasError) {
                return const _SheetUnavailable(
                  message: 'Your library is unavailable. Please retry.',
                );
              }
              if (!bookSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final isbn = widget.book.isbn;
              final existing = isbn == null
                  ? null
                  : bookSnapshot.data!
                        .where((book) => book.isbn == isbn)
                        .firstOrNull;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  ReaduoSpacing.screenHorizontal,
                  4,
                  ReaduoSpacing.screenHorizontal,
                  24 +
                      MediaQuery.viewInsetsOf(context).bottom +
                      MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existing == null
                          ? 'Save to your library'
                          : 'Already in your library',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: ReaduoColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.book.title),
                    const SizedBox(height: 12),
                    if (existing != null) ...[
                      Container(
                        key: const Key('copy-book-existing'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ReaduoColors.accentTint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'The same ISBN is already on ${_shelfFor(shelves, existing.shelfId)?.name ?? 'your library'} as ${existing.readingStatus.label}. Saving again keeps that entry unchanged.',
                        ),
                      ),
                      if (widget.canOpenExisting) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('copy-view-existing'),
                          onPressed: () => Navigator.of(context).pop(existing),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('View existing entry'),
                        ),
                      ],
                    ] else ...[
                      const Chip(label: Text('Want to read')),
                      const Text(
                        'Choose exactly one shelf for this ISBN-specific book entry.',
                      ),
                      RadioGroup<String>(
                        groupValue: _selectedShelfId,
                        onChanged: _saving
                            ? (_) {}
                            : (value) =>
                                  setState(() => _selectedShelfId = value),
                        child: Column(
                          children: shelves
                              .map(
                                (shelf) => RadioListTile<String>(
                                  value: shelf.id,
                                  title: Text(shelf.name),
                                  subtitle: Text(shelf.visibility.label),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      if (shelves.isEmpty)
                        const Text('Create a shelf before saving this book.'),
                      TextButton.icon(
                        key: const Key('copy-create-shelf'),
                        onPressed: _saving ? null : _createShelf,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create a new shelf'),
                      ),
                      SwitchListTile(
                        key: const Key('copy-owned-switch'),
                        contentPadding: EdgeInsets.zero,
                        value: _owned,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _owned = value),
                        title: const Text('I already own this book'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          key: const Key('copy-book-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton(
                        key: const Key('save-shared-book-button'),
                        onPressed: _saving || shelves.isEmpty
                            ? null
                            : () => _save(shelves),
                        child: _saving
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text('Save book'),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<Shelf?> _showQuickShelfCreator(BuildContext context) async {
    final controller = TextEditingController();
    final created = await showDialog<Shelf>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New shelf'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Shelf name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final shelf = await widget.shelfRepository.createShelf(
                  ownerId: widget.viewerId,
                  input: CreateShelfInput(
                    name: controller.text,
                    visibility: ShelfVisibility.friends,
                    autoShareActivity: true,
                  ),
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(shelf);
                }
              } on ShelfFailure catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                }
              }
            },
            child: const Text('Create shelf'),
          ),
        ],
      ),
    );
    controller.dispose();
    return created;
  }
}

class _FriendShelfAccessBoundary extends StatelessWidget {
  const _FriendShelfAccessBoundary({
    required this.friendRepository,
    required this.shelfRepository,
    required this.viewerId,
    required this.friendId,
    required this.shelfId,
    required this.builder,
    this.dismissOnRevoked = false,
    this.requireFriendship = true,
    this.publicOnly = false,
  });

  final FriendRepository friendRepository;
  final ShelfRepository shelfRepository;
  final String viewerId;
  final String friendId;
  final String shelfId;
  final Widget Function(BuildContext context, Shelf shelf) builder;
  final bool dismissOnRevoked;
  final bool requireFriendship;
  final bool publicOnly;

  @override
  Widget build(BuildContext context) {
    if (!requireFriendship) return _buildShelf(context);
    return StreamBuilder<List<ReaderProfile>>(
      stream: friendRepository.watchFriends(viewerId),
      builder: (context, friendSnapshot) {
        if (friendSnapshot.hasError ||
            (friendSnapshot.hasData &&
                !friendSnapshot.data!.any(
                  (friend) => friend.uid == friendId,
                ))) {
          return _revoked(context);
        }
        if (!friendSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildShelf(context);
      },
    );
  }

  Widget _buildShelf(BuildContext context) => StreamBuilder<Shelf?>(
    stream: publicOnly
        ? shelfRepository.watchPublicShelf(
            viewerId: viewerId,
            ownerId: friendId,
            shelfId: shelfId,
          )
        : shelfRepository.watchSharedShelf(
            viewerId: viewerId,
            ownerId: friendId,
            shelfId: shelfId,
          ),
    builder: (context, shelfSnapshot) {
      if (shelfSnapshot.hasError ||
          (!shelfSnapshot.hasData &&
              shelfSnapshot.connectionState != ConnectionState.waiting)) {
        return _revoked(context);
      }
      final liveShelf = shelfSnapshot.data;
      if (liveShelf == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return builder(context, liveShelf);
    },
  );

  Widget _revoked(BuildContext context) {
    if (dismissOnRevoked) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Shelf unavailable')),
      body: Center(
        child: _ErrorView(
          message:
              'This shelf is no longer available. Its privacy or your connection may have changed.',
          onRetry: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class _SharedShelfTile extends StatelessWidget {
  const _SharedShelfTile({required this.shelf, required this.onTap});

  final Shelf shelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.local_library_outlined),
        title: Text(shelf.name),
        subtitle: Text(
          '${shelf.bookCount} ${shelf.bookCount == 1 ? 'book' : 'books'} · ${shelf.visibility.label}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _SharedBookCover extends StatelessWidget {
  const _SharedBookCover({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: .68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: book.coverUrl == null
            ? GeneratedBookCover(title: book.title, author: book.author)
            : BookCoverImage(
                book.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: ReaduoColors.accentTint,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}

class BlockedReadersScreen extends StatelessWidget {
  const BlockedReadersScreen({
    required this.repository,
    required this.userId,
    super.key,
  });

  final FriendRepository repository;
  final String userId;

  Future<void> _unblock(BuildContext context, BlockedReader reader) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          ReaduoSpacing.screenHorizontal,
          8,
          ReaduoSpacing.screenHorizontal,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unblock ${reader.displayName}?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Unblocking does not restore a friendship. Either reader can send a new request afterward.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Unblock reader'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await repository.unblockReader(userId: userId, blockedUserId: reader.uid);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message(error, 'unblock reader'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked readers')),
      body: SafeArea(
        child: StreamBuilder<List<BlockedReader>>(
          stream: repository.watchBlockedReaders(userId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorView(
                message: _message(snapshot.error, 'load blocked readers'),
                onRetry: () =>
                    Navigator.of(context).pushReplacement<void, void>(
                      MaterialPageRoute<void>(
                        builder: (_) => BlockedReadersScreen(
                          repository: repository,
                          userId: userId,
                        ),
                      ),
                    ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Center(
                child: Text('You have not blocked any readers.'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: ReaduoSpacing.screenHorizontal,
                vertical: 20,
              ),
              itemCount: snapshot.data!.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reader = snapshot.data![index];
                return ListTile(
                  leading: _BlockedAvatar(reader: reader),
                  title: Text(reader.displayName),
                  trailing: TextButton(
                    onPressed: () => _unblock(context, reader),
                    child: const Text('Unblock'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RequestCountCard extends StatelessWidget {
  const _RequestCountCard({
    required this.label,
    required this.count,
    required this.onTap,
    super.key,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text('$label · $count', textAlign: TextAlign.center),
    );
  }
}

class _ReaderTile extends StatelessWidget {
  const _ReaderTile({
    required this.profile,
    required this.subtitle,
    required this.onTap,
    this.preview = false,
    this.book,
  });

  final ReaderProfile profile;
  final String subtitle;
  final VoidCallback onTap;
  final bool preview;
  final LibraryBook? book;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ReaduoColors.line)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        horizontalTitleGap: 12,
        leading: _ReaderAvatar(profile: profile, radius: preview ? 22 : 19),
        title: Text(
          profile.displayName,
          style: const TextStyle(
            color: ReaduoColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: ReaduoColors.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preview) ...[
              SizedBox(
                width: 38,
                height: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: book == null
                      ? const ColoredBox(
                          color: ReaduoColors.accentTint,
                          child: Icon(
                            Icons.menu_book_outlined,
                            size: 22,
                            color: ReaduoColors.muted,
                          ),
                        )
                      : book!.coverUrl == null
                      ? GeneratedBookCover(
                          title: book!.title,
                          author: book!.author,
                        )
                      : BookCoverImage(
                          book!.coverUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => GeneratedBookCover(
                            title: book!.title,
                            author: book!.author,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _FriendReadingTile extends StatefulWidget {
  const _FriendReadingTile({
    required this.friend,
    required this.viewerId,
    required this.shelfRepository,
    required this.bookRepository,
    required this.onTap,
    super.key,
  });
  final ReaderProfile friend;
  final String viewerId;
  final ShelfRepository shelfRepository;
  final BookRepository bookRepository;
  final VoidCallback onTap;
  @override
  State<_FriendReadingTile> createState() => _FriendReadingTileState();
}

class _FriendReadingTileState extends State<_FriendReadingTile> {
  late Stream<List<Shelf>> _shelves;
  void _load() => _shelves = widget.shelfRepository.watchSharedShelves(
    viewerId: widget.viewerId,
    ownerId: widget.friend.uid,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FriendReadingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerId != widget.viewerId ||
        oldWidget.friend.uid != widget.friend.uid ||
        oldWidget.shelfRepository != widget.shelfRepository)
      _load();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Shelf>>(
    stream: _shelves,
    builder: (context, snapshot) {
      final shared =
          snapshot.hasError ||
              snapshot.connectionState == ConnectionState.waiting
          ? <Shelf>[]
          : (snapshot.data ?? const <Shelf>[])
                .where(
                  (shelf) =>
                      shelf.ownerId == widget.friend.uid &&
                      shelf.visibility != ShelfVisibility.private &&
                      shelf.autoShareActivity &&
                      shelf.mutationOperationId == null,
                )
                .toList();
      if (shared.isEmpty)
        return _ReaderTile(
          profile: widget.friend,
          subtitle: 'View shared shelves',
          preview: true,
          onTap: widget.onTap,
        );
      shared.sort((left, right) => right.bookCount.compareTo(left.bookCount));
      return _FriendBookTile(
        key: ValueKey(
          '${widget.viewerId}/${widget.friend.uid}/${shared.first.id}',
        ),
        friend: widget.friend,
        viewerId: widget.viewerId,
        shelfId: shared.first.id,
        repository: widget.bookRepository,
        onTap: widget.onTap,
      );
    },
  );
}

class _FriendBookTile extends StatefulWidget {
  const _FriendBookTile({
    required this.friend,
    required this.viewerId,
    required this.shelfId,
    required this.repository,
    required this.onTap,
    super.key,
  });
  final ReaderProfile friend;
  final String viewerId;
  final String shelfId;
  final BookRepository repository;
  final VoidCallback onTap;
  @override
  State<_FriendBookTile> createState() => _FriendBookTileState();
}

class _FriendBookTileState extends State<_FriendBookTile> {
  late Stream<List<LibraryBook>> _books;
  void _load() => _books = widget.repository.watchSharedBooks(
    viewerId: widget.viewerId,
    ownerId: widget.friend.uid,
    shelfId: widget.shelfId,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FriendBookTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _load();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<LibraryBook>>(
    stream: _books,
    builder: (context, snapshot) {
      final books =
          snapshot.hasError ||
              snapshot.connectionState == ConnectionState.waiting
          ? <LibraryBook>[]
          : (snapshot.data ?? const <LibraryBook>[])
                .where(
                  (book) =>
                      book.ownerId == widget.friend.uid &&
                      book.shelfId == widget.shelfId &&
                      book.isOwned,
                )
                .toList();
      books.sort((left, right) {
        final priority = (left.readingStatus == ReadingStatus.reading ? 0 : 1)
            .compareTo(right.readingStatus == ReadingStatus.reading ? 0 : 1);
        return priority != 0
            ? priority
            : (right.createdAt ?? DateTime(1970)).compareTo(
                left.createdAt ?? DateTime(1970),
              );
      });
      final book = books.firstOrNull;
      final subtitle = book == null
          ? 'View shared shelves'
          : '${switch (book.readingStatus) {
              ReadingStatus.reading => 'Reading',
              ReadingStatus.finished => 'Finished',
              ReadingStatus.wantToRead => 'Wants to read',
            }} ${book.title}';
      return _ReaderTile(
        profile: widget.friend,
        subtitle: subtitle,
        preview: true,
        book: book,
        onTap: widget.onTap,
      );
    },
  );
}

class _ReaderAvatar extends StatelessWidget {
  const _ReaderAvatar({required this.profile, this.radius = 24});

  final ReaderProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: ReaduoColors.accentTint,
      foregroundImage: profile.photoUrl == null
          ? null
          : ReaduoImageCache.image(profile.photoUrl!),
      child: profile.photoUrl == null
          ? Text(
              profile.displayName.isEmpty
                  ? 'R'
                  : profile.displayName.characters.first.toUpperCase(),
              style: TextStyle(
                color: ReaduoColors.accent,
                fontSize: radius * .75,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _BlockedAvatar extends StatelessWidget {
  const _BlockedAvatar({required this.reader});

  final BlockedReader reader;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: ReaduoColors.accentTint,
      foregroundImage: reader.photoUrl == null
          ? null
          : ReaduoImageCache.image(reader.photoUrl!),
      child: reader.photoUrl == null
          ? Text(
              reader.displayName.isEmpty
                  ? 'R'
                  : reader.displayName.characters.first.toUpperCase(),
            )
          : null,
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ReaduoColors.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ReaduoColors.line),
      ),
      child: child,
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReaduoColors.accentTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ReaduoColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ReaduoSpacing.screenHorizontal,
          vertical: 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _message(Object? error, String action) => error is FriendFailure
    ? error.message
    : 'Readuo could not $action. Please retry.';
