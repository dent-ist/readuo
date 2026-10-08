# P1-16/17 notification client integration

## Dependencies and ownership

Main owns `pubspec.yaml`, Firebase initialization, Android configuration, auth,
shell/navigation, rules, Functions, and deployment. Client files are isolated in
this directory. Dependencies: `firebase_messaging` (resolved 16.5.0),
`app_settings` 6.1.1, `shared_preferences` (resolved 2.5.5), plus existing
`cloud_firestore`. No `cloud_functions` dependency is needed by this client.
Android only; do not instantiate the FCM adapter for web tests or deferred iOS.

## Construction and lifecycle

After Firebase/auth initialization, construct one installation store for the
application, and one client for the authenticated UID. Await the previous
client's disposal before creating another account's client. The shell and
navigator must be ready before `start()` because it handles cold-start taps.

```dart
final store = SharedPreferencesNotificationStore(SharedPreferencesAsync());
final messaging = FirebaseNotificationMessaging(
  messaging: FirebaseMessaging.instance,
  store: store,
);
final repository = FirestoreNotificationRepository(FirebaseFirestore.instance);
final client = NotificationClient(
  userId: user.uid,
  installationId: await store.installationId(),
  repository: repository,
  messaging: messaging,
  openDestination: openAuthorizedNotificationDestination,
  onError: showNotificationError,
);
await client.start();
```

Start notifications independently of profile creation and moderator-claim
lookups. A failed `start()` remains retryable: call it on resume/reconnect before
`synchronizePermission()`. Concurrent calls share startup, successful setup is
idempotent, listeners are installed once, and a consumed cold-start message ID
is retained if its server read throws. Main's routing callback must distinguish
transient failures (throw, so retry is possible) from permanent unavailability.

`start()` invalidates the previous FCM token before subscribing to refreshes or
registering a replacement. This prevents an old account's token from being
reused after an interrupted sign-out. Stale documents under another UID cannot
be deleted by the new user: backend must prune invalid/unregistered FCM tokens.
One document per installation is replaced on refresh, leaving other devices
intact. Keep installation IDs private; do not use Android hardware identifiers.

Call and await `client.synchronizePermission()` on app resume, including after
returning from phone settings. It registers granted tokens or removes denied
ones; it never asks for OS permission. Surface errors with retry, without
changing preferences. The in-app list comes from Firestore; foreground pushes
do not create notifications, navigate automatically, or write server records.

Every sign-out path, including account switching/deletion, must run:

```dart
await client.beforeSignOut();
await authService.signOut();
```

Do this while Firebase Auth still authorizes deletion of the old UID's token
document. Cleanup immediately sets `client.isActive` false, stops listeners,
invalidates the SDK token, then drains pending registrations and removes the
installation document. SDK token fetch/invalidation calls are serialized so
an in-flight fetch cannot recreate a token after cleanup. Remote unregister
failure or timeout is reported through `onError` but does not throw after SDK
invalidation: proceed to Firebase Auth sign-out. A registration-drain timeout
skips remote unregister and leaves the invalid token for server cleanup, rather
than scheduling a later delete against a future session. Waits are bounded by
`cleanupTimeout` (five seconds per operation by default). Error reporting is
sanitized and a throwing error callback cannot block cleanup. SDK invalidation
failure/timeout still throws a sanitized error; main owns the auth fallback
policy and must not claim successful token invalidation in that case. Timeouts
do not cancel an underlying SDK/Firestore operation. On forced auth loss, dispose the client and
invalidate the SDK token; backend invalid-token cleanup handles any orphan.
`dispose()` alone stops listeners; it deliberately does not claim sign-out
cleanup. Never share a disposed client with a later authenticated session.

## Screens and routing

Push these as full-screen routes, hiding shell bottom navigation with the
existing shell visibility callback until the route returns:

* `NotificationsScreen(client: client, onSettings: openNotificationSettings)`
* `NotificationSettingsScreen(userId: user.uid, repository: repository,
  openSettings: messaging.openSettings)`
* `NotificationPermissionScreen(client: client, onDone: closeRationale)`

Only the rationale's explicit **Enable notifications** action calls
`enableAfterRationale()`. Opening settings or the inbox does not prompt.
Android 13 can report denied before any prompt, so the local persisted
`readuo.notifications.permissionRequested` flag distinguishes a first request
from a prior refusal. It is recorded before requesting. Subsequent refusals
offer phone settings and retain every preference. This flag and installation
ID are installation-scoped, not reset on account switching.

Implement this exact callback:

```dart
Future<NotificationOpenResult> openAuthorizedNotificationDestination(
  String recipientId,
  NotificationDestination destination,
)
```

Invalidate the shell's routing session generation before invoking the sign-out
hook. Check that generation and `client.isActive` after awaits and immediately
before navigation; the client cannot cancel a callback already executing in
the shell. Remove authenticated pushed routes when auth is lost.

Return `opened` immediately after the exact route is installed, not when the
user eventually pops it. Recheck the active auth UID before and after every
await. Fetch current server state and enforce current friendship, blocks,
request ownership/status, moderation, shelf visibility, parent existence and
review/source-entry validity as appropriate. Route `request` by exact pair ID,
`reader` by exact reader UID, and `post` by exact document ID with `isReview`
preserved; focus the exact `commentId` when supplied. Missing/revoked/deleted
destinations return `unavailable` and must not fall back to a similarly named
reader/book/post. A deleted requested comment is unavailable, rather than a
silent redirect. Destination screens must continue enforcing live revocation.
Only a successful authorized open marks the notification read.

## Exact Firestore contract

`users/{uid}/preferences/notifications`

| Field | Type | Default |
| --- | --- | --- |
| friendRequest | boolean | true |
| requestAccepted | boolean | true |
| like | boolean | true |
| comment | boolean | true |

Missing document/fields mean true. Client merges one field, never replaces the
whole document. Backend applies each preference to both push and in-app event
creation. OS denial only suppresses delivery; it does not alter preferences.

`users/{uid}/notificationTokens/{installationId}`

| Field | Type |
| --- | --- |
| token | nonempty FCM string |
| platform | literal `android` |
| updatedAt | server timestamp |

`users/{recipientUid}/notifications/{eventId}`

| Field | Type / meaning |
| --- | --- |
| recipientId | exact recipient UID, same as path UID |
| actorId | immutable actor UID |
| actorName | display snapshot string |
| type | `friendRequest`, `requestAccepted`, `like`, or `comment` |
| targetId | request pair ID / accepting reader UID / exact post or review ID |
| createdAt | server timestamp |
| readAt | null initially; recipient can set server timestamp once |
| preview | optional display string, defaults to empty |
| isReview | optional boolean, defaults false; true for review destinations |
| commentId | immutable comment ID for comment events; otherwise omitted |

Use globally safe Firestore IDs without `/`. The inbox queries this collection
ordered by `createdAt desc`, newest 100; older-history pagination is not included.
Push payload data is exactly `{notificationId: eventId}`. The client does not
trust push-supplied routing/content: it fetches that ID from its owner's
collection using `Source.server`. Use generic notification title/body on the
lock screen. Backend should omit sensitive previews and redact/remove stale
content snapshots when access is revoked.

## Backend/rules handoff

Only trusted server triggers create notification content. Use deterministic
event IDs and idempotent creation; retry must not overwrite `readAt`. Honor
preferences, actor/recipient inequality, account state, blocks, and current
access. Generate no notification for book-added/started/finished activities.
Dispatch on server-created notification records with delivery deduplication;
recheck eligibility before delivery and prune invalid FCM tokens.

Rules must restrict reads to the path owner. Notifications deny client create
and delete; updates may change only `readAt`, from null to `request.time`, with
recipientId matching auth and the path. Preferences and token docs are
owner-only with exact field/type validation. Token creation/update must require
`platform == 'android'`, nonempty bounded token, and `updatedAt == request.time`.
Do not expose tokens through public profile reads. Rules/emulator tests and
trusted Functions deployment are main's responsibility.

`EmptyNotificationRepository` returns empty reads and throws on mutations; it
never reports a fake save or delivery. Widget tests use explicit in-memory
fakes. No test in this package writes production data.
