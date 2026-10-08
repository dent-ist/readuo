# P1-18 integration contract

AccountScreen preserves required `authService`/`user`. Optional injections:
`profileRepository`, `supportRepository`, `photoPicker`, `bookCount`, `friendCount`,
`onNotifications`, `onModeration`, `onSupportQueue`, `isModerator`, `onDestination`.
Defaults need no Firebase initialization and reject writes rather than simulate success.
The integrating AppServicesScope should supply these at the account entry point.
Use one FirebaseProfileRepository(auth:, firestore:, storage:) per signed-in scope.
Use FirestoreSupportRepository(auth:, firestore:) for both support interfaces.
Open SupportRequestsScreen(repository:) from onSupportQueue. No HTTP endpoint exists.
Notification routing is wholly delegated to onNotifications; no preference schema is owned here.

onDestination receives invite, blocked-users, privacy, terms, camera-denied,
isbn-not-found, and report (support context). Missing destinations show unavailable feedback.
Delete account remains an unavailable canonical row; P1-19 was not implemented.
SUPPORT_EMAIL defaults to the explicitly authorized plogramer.dev@gmail.com.
That email is informational configuration only, never an authorization condition.
The main agent verifies the exact Auth identity and grants the moderator custom claim.

## Exact security/schema needs

* `readerProfiles/{uid}` already exists through friend ensureProfile. Permit the owner
  to update displayName (trimmed 1–80), photoUrl (HTTPS or existing null),
  photoStoragePath (`profilePhotos/{uid}/{uniqueId}`), updatedAt == request.time;
  preserve all other fields, including invite code and createdAt. photoStoragePath
  is optional for preexisting Google photos. Never delete external/provider photos.
* `profilePhotos/{uid}/{uniqueId}`: authenticated owner create/delete; create only
  image/jpeg or image/png, bytes > 0 and <= 5 MiB; authenticated reads for reader
  avatars. Download URLs are bearer URLs consumed by Auth photoURL; revoke/delete
  on replacement. Do not assume possession of a URL proves current authentication.
* `supportRequests/{uid}--{32 lowercase hex requestId}`: create only by authenticated
  uid; exactly ownerId, subject, message, status, createdAt. ownerId == auth.uid,
  subject trimmed 1–120, message trimmed 1–5000, status == pending,
  createdAt == request.time. No extra keys. Owner must be allowed to get their
  deterministic nonexistent path for the transaction, and to read existing own
  requests for idempotency. Same ID/content retry succeeds without updating.
* Moderator claim permits query/read and pending -> resolved update with exactly
  status, resolvedAt == request.time, resolvedBy == auth.uid, resolutionNote <= 2000.
  The explicit Mark resolved action records `Handled by support` as its note;
  ownerId/subject/message/createdAt are immutable. Owners cannot resolve or edit.
  Direct client deletion denied; privileged account deletion later removes records.
* Composite index: supportRequests status ASC, createdAt ASC. Queue shows oldest
  100 pending requests; resolving reveals subsequent pending requests.
* Keep ownerId indexed for permanent account cleanup. Support has no target account;
  reporting schema owned elsewhere must index reporterId and targetId. Delete all
  matching support/report/security records when account deletion is implemented,
  with no retention period, per explicit user decision.

## Synchronization and cleanup

Auth name/photo update happens before a Firestore transaction; transient Firestore
failures retry three times. The transaction accepts either the original values or
the same desired Auth values already written by friend ensureProfile, while
preserving unrelated profile fields. Do not let stale Auth snapshots run ensureProfile
during an edit. Fresh userChanges should drive it. Existing profile creation must
finish before enabling editing; absence returns an actionable error.

Successful replacement deletes only the previous owner Storage path after Firestore
commits. Upload failure before Auth update attempts cleanup. An ambiguous Auth or
Firestore failure retains the photo and reports incomplete synchronization rather
than deleting a potentially live asset. A subsequent name-only save recovers an
owner photo path from the current Auth URL (same bucket only), repairs the profile,
and cleans the old path. Cleanup failure after success is surfaced.
Integrating backend needs orphan reconciliation for process death/ambiguous failures
and failed old-photo deletion: compare both Auth photoURL and readerProfiles before
deleting unreferenced owner objects. This is not account-deletion retention.

AuthService.signOut must implement the canonical device-data clearing promise.
The screen calls the existing method only; shared auth/cache code was not changed.
Full-screen routes must be removed on auth loss by the signed-in navigator/scope.

## Verification boundary

Main agent coordinates actual rendered Flutter versus canonical HTML QA for profile,
edit-profile, account, support, support-message, signout, notification-settings.
Local analyzer/widget checks are not a claim of visual fidelity. No APK build/deploy.

Focused evidence: `flutter test test/profile_test.dart test/profile_repository_test.dart`
passes 22 tests. `flutter analyze lib/profile lib/screens/account_screen.dart`
passes, including both focused test files. Three declaration-scoped
subtype_of_sealed_class ignores apply only to deliberate in-memory Firebase SDK
test doubles (CollectionReference, DocumentReference, DocumentSnapshot).
These tests do not replace emulator rule tests or live Auth/Storage verification.

Temporary capture entrypoint: `flutter run -t lib/qa_p1_18_profile.dart
--dart-define=QA_SCREEN=profile`. Supported values: profile (default), edit-profile,
account, support, support-message, support-requests, selector. System Back returns
to the selector. Profile includes the production bottom navigation; full-screen
destinations do not. Open Profile and tap Sign out to capture its confirmation.
Fixtures use the production theme, in-memory Auth/Profile/Support, and no Firebase
initialization/network writes. Photo picking deterministically cancels.
