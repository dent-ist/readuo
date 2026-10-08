# P1-15 integration contract

All implementations here are isolated additions. Main owns existing routes,
repositories, Firestore/Storage Rules, deployment configuration, Auth claim
provisioning, and production deployment. No pubspec changes are required.

## Client wiring

Construct `FirebaseModerationTransport(auth, baseUri, client)` with named
arguments, an existing FirebaseAuth instance, an owned http.Client, and the
regional functions base URL ending in `/`. Construct
`CallableModerationRepository(call: transport.call,
checkModerator: transport.isModerator)`. Dispose the HTTP client with its owner.
The transport uses the Firebase callable JSON protocol, authenticates using the
current Firebase ID token, bounds request duration, and rejects results following
an account switch. A future cloud_functions adapter can supply the same `call`.

Use `ReportScreen(repository, target, onDone, onBlockReader)` named arguments:

- `ReportTarget(kind: 'post', id: postId)` resolves circlePosts.
- `ReportTarget(kind: 'review', id: reviewId)` resolves circleReviews.
- `ReportTarget(kind: 'comment', id: commentId, parentKind: 'post'|'review', parentId: parentId)` resolves the parent's comments subcollection.
- `ReportTarget(kind: 'profile', id: uid)` resolves readerProfiles.
- `const ReportTarget.support()` has no content or reader target.

Only use the server-returned readerId for the optional block callback. Hide that
callback for self-reporting. Mount `ModerationScreen(repository: repository)` only
under the authenticated shell. Remove operator routes when auth changes. The
screen refreshes the ID token claim before fetching the queue, while every server
operator callable independently requires `request.auth.token.moderator === true`.
No client writes custom claims. Main has verified/provisioned the authorized
operator separately; there is no hardcoded email/UID authorization in this module.
The user-approved support contact is `plogramer.dev@gmail.com`; main owns support
contact presentation and links. These screens do not send email.

Supply `ModerationScreen(repository: repository, photoRepository: photoRepository)`
to display reported post/profile photos; the optional default repository produces
an explicit unavailable warning. Storage Rules must allow moderator-claim reads
of circlePosts photos and profilePhotos. Profiles snapshot photoStoragePath and
HTTPS photoUrl; external provider photos use the latter only when no Storage path
exists. Images are references, not retained binary copies: deleted/changed images
may no longer be available. Review text and image references are also captured in
the action audit before deletion/redaction.

## Callable endpoints and records

- `submitReport({requestId,target,reason,note}) -> {reportId,readerId}`.
- `listReports({afterId?}) -> {reports,nextCursor}`: operator-only, at most 50 pending/processing records per page. Cursor is a report ID.
- `moderationAction({reportId,decision,note}) -> {reportId,status}`: operator-only. Decisions are remove/dismiss, or resolve for support. A nonblank review note is required.
- `checkContent({text}) -> {allowed,policyVersion,violations}`: authenticated, advisory. It never publishes content.

Reports resolve content from Admin Firestore with transactionally checked current
ownership, friendship, both block directions, review source shelf visibility and
exact book generation/metadata, and comment parent access. Client-supplied paths,
author IDs, snapshots, status, and operator identities are rejected. Report reason
is an enum, note max 2,000 characters, deterministic per-user request IDs provide
idempotency, and reportLimits/{uid} bounds new reports to 20 per hour. Reports are
not filtered because evidence may itself include prohibited text.

Server-only collections: reports, moderationActions, reportLimits,
moderationLocks, moderatedProfiles. Deny all client writes and report reads;
operator reads flow through callables. Reports/actions/locks carry reporterId and
targetAuthorId for account cleanup; actions also carry actorId. Content snapshots
are private operator evidence, never returned to the reported reader.

## Removal and Rules changes

For post/review/comment removal one Firestore transaction creates an audit,
creates a permanent write lock, and **deletes the target document immediately**.
The report becomes processing. This revokes normal parent/descendant reads using
existing parent existence checks without per-document read lock lookups. Admin
recursiveDelete then removes orphan descendants; post photos under
`circlePosts/{authorId}/{postId}/` are deleted. Completion sets report resolved.
If cleanup fails the original operator can retry the same decision/note; no second
audit is created. The queue exposes processing items with a Retry action. Maintain
write locks until account deletion or explicit trusted operational recovery.

Write lock IDs:

- moderationLocks/post--{postId}
- moderationLocks/review--{reviewId}
- moderationLocks/{parentKind}--{parentId}--comment--{commentId}

Reject recreation/updates of locked content, including parent locks for comment
creation/update and photo uploads. Validate parent existence on descendant reads.
Storage post photos must also require current post existence on reads, except
owner draft workflows explicitly validated by main. Deny access through legacy
overlapping allow rules. The client must never choose arbitrary moderation paths.

Profile action uses moderatedProfiles/{uid}, redacts displayName to Reader,
photoUrl/photoStoragePath to null, updates Firebase Auth displayName/photoURL,
and deletes `profilePhotos/{uid}/` from Storage. It does not suspend the account
or add moderationState to readerProfiles. Rules must deny profile create/update
and avatar upload while its server-only lock exists, and ensureProfile must not
restore the provider name/photo. Main coordinates any explicit operator unlock.

## Exact deterministic filter: basic-threats-v1

Lowercase the original text. Do not trim, normalize Unicode, strip zero-width
characters, or substitute punctuation. Reject when this regex has a match:

```text
(?:^|[^a-z0-9_])(?:i[ \t\r\n]+will[ \t\r\n]+kill[ \t\r\n]+you|kill[ \t\r\n]+yourself)(?:$|[^a-z0-9_])
```

JS: `new RegExp(prohibitedPattern).test(text.toLowerCase())`.
Dart: `RegExp(BasicContentFilter.pattern).hasMatch(text.toLowerCase())`.
Rules: `value.lower().matches('[\\s\\S]*' + pattern + '[\\s\\S]*')`,
where the Rules string literal for pattern must escape each backslash once:

```text
'(?:^|[^a-z0-9_])(?:i[ \\t\\r\\n]+will[ \\t\\r\\n]+kill[ \\t\\r\\n]+you|kill[ \\t\\r\\n]+yourself)(?:$|[^a-z0-9_])'
```

Main adds identical server Rules checks to post/review/comment create AND update
and readerProfiles displayName create/update, preserving existing shape/ownership
validation. Apply the Dart check before sharing AND editing text/display names;
never apply it to private retained drafts or report evidence. No client-set
`filterPassed` flag or standalone preflight can authorize a write. Future Admin
publishing callables must invoke `enforceContent` on the exact text they persist.

`ContentFilteredScreen(draftController:,onEdit:,onGuidelines:)` keeps the caller's
controller alive and editable. The caller owns/disposes/persists the draft; never
clear a draft on rejection. Handle direct Rules denial without discarding text.
Explain the rule using BasicContentFilter.explanation. Guidelines destination is
supplied by main; no legal policy, response promise, appeals process or retention
period is invented. This narrow phrase filter has known false positives (quotes)
and bypasses (obfuscation, other languages, images); it is not comprehensive UGC
safety or store-compliance certification. Rule changes must update all three
implementations and their parity test vectors together.

## Account deletion

User decision: permanently delete all records, including reports and security
records; no retention exception. Later account deletion must delete reports by
reporterId OR targetAuthorId, actions by reporterId OR targetAuthorId OR actorId,
locks by reporterId OR targetAuthorId, moderatedProfiles by ownerId/reporting
participants, and reportLimits/{uid}. Delete related audit snapshots and pending
processing state; coordinate deletion markers against new submissions/actions to
prevent races. Do not retain evidence under a supposed legal retention policy.
Submission checks accountDeletions for the reporter and target author inside its
transaction; decisions check operator, reporter and target author. Main must keep
deletion markers present throughout cleanup and revoke/delete Auth before removing
them. Concurrent marker writes conflict with these transactions, preventing new
evidence after cleanup starts.

## Verification and rollout

`flutter test test/moderation_test.dart`: submission/receipts/retries, operator
gate, confirmation, retained drafts, safe insets, and Dart filter vectors.
`npm test` in app/functions: moderation transaction/access/idempotency/rate-limit
tests, notification policy tests, and isolated real sourceAvailable access tests.
Fakes enforce read-before-write and no network; these are not emulator/deployment
verification. Main must run Rules emulator bypass tests and production smoke tests
with explicit disposable data before treating rollout as complete.

Optional Windows widget render capture:
`flutter test --dart-define=MODERATION_VISUALS=true --update-goldens test/moderation_visual_test.dart`.
This uses local Segoe UI only for visual artifacts. It is separate from normal CI.
Canonical content/styles were inspected, but this task's browser URL policy
blocked opening the canonical local HTML. Main must compare rendered app states
against matching rendered canonical states; no fidelity claim is made here.

App Check is deliberately not enforced because it is not configured. Firebase
Auth, strict claims, target authorization, validation and report rate limits are
enforced now. Main can enable App Check after client enrollment. index.js exports
the four callables plus public notification exports, excluding test helpers.
Runtime is Node 22; dependencies are firebase-admin and firebase-functions.
