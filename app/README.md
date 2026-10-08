# Readuo Android prototype

Readuo currently implements Firebase Google authentication, personal shelf
creation, manual book entry, ISBN barcode and catalogue lookup, and private
friend connections. Firebase UID is the account and library owner identity.

Current Android build metadata is version `1.13.2` (`versionCode` 21) with
application ID `com.zipdosa.readuo`, allowing it to update the prior build.
Build 21 is the corrected P1-04 catalogue-search delivery; builds 19 and 20
remain preserved as superseded audit artifacts.

Authentication state owns the root app navigator. Logout, external session
loss, and UID switches dispose every authenticated route, dialog, sheet, and
user-scoped widget state before showing login; failed sign-out remains retryable.
The default portrait login fits without scrolling at 360×640, 360×800,
390×844, and 412×915 above Android system insets. Genuine short-height,
landscape, and large-text overflow remains scrollable.

## First-book onboarding review candidate

- New Google users persist owner-scoped first-book onboarding before their
  display name is committed. Pending setup resumes after restart; skip and first
  successful save persist terminal states for that Firebase UID.
- Existing accounts without an onboarding document bypass the new-user flow.
  Account changes rebuild the gate and never reuse another UID's onboarding
  state.
- The canonical first-book screen reuses scanner, catalogue, direct manual add,
  and create-shelf flows. Saving remains blocked until an own shelf exists.
- Profile, skip, completion, and book-save failures remain retryable. Typed
  profile and manual-book drafts stay intact, and a saved book can finish an
  interrupted onboarding completion without a duplicate write.
- The owner-only Firestore schema permits only `pending`, `skipped`, or
  `completed` for `users/{uid}/onboarding/firstBook`. Emulator tests reject
  cross-user access, owner spoofing, invalid status, alternate document IDs,
  deletes, and immutable-field changes.
- Review evidence is in `test/artifacts/p1-06-review`. No release APK or version
  bump was produced; the tested Rules were deployed alone.

## My Library increment

- Bottom navigation contains Circle, Library, Friends, and Profile only.
  Library's FAB expands to Create Bookshelf and Add Books; Add Books remains
  disabled until an available own shelf exists. It opens Scan barcode, Search
  catalogue, and Add manually. The Library header keeps Search only, and its
  empty state shows centered guidance below My Library / Explore. A shelf's
  round + FAB expands to Scan ISBN, Enter ISBN, Search Catalogue, and Add
  Manually, keeping that shelf selected. My books also exposes Add books from
  its header.

- Signed-in users see only shelves whose `ownerId` matches their Firebase UID.
- View all opens the live owner-scoped saved-entry collection with All, Want to
  read, Reading, and Finished filters; Recently added, Title A-Z, and Author A-Z
  sorting; deterministic ties; and retained filter, sort, search, and scroll
  state across book details and root-tab switches.
- Library search matches normalized title, author, ISBN-10, and ISBN-13 across
  owned and not-owned saved entries, reports accurate live result and containing-
  shelf counts, and preserves direct shelf search on the root Library screen.
  ISBN matching accepts only whole ISBN-shaped queries rather than extracting
  digits from mixed title/author text. Search itself is full-screen and bottom-
  inset safe; book and shelf destinations restore the single persistent shell
  bar while nested scanner/settings/catalogue routes hide and restore it.
- The Library screen follows the canonical release-one design with the
  My Library/Explore switch, library search, cover-stack shelf cards, live book
  previews, and the four-destination bottom navigation shell. The authenticated
  shell keeps one bottom bar and independent Library, Friends, and Profile tab
  histories; switching tabs preserves their search, scroll, and route state
  without pushing duplicate routes. Explore and
  Circle remain visibly unavailable until their backends are implemented.
- Selecting a book preview or shelf-grid entry opens that exact owner-scoped
  book. Its live details expose only saved metadata and independently editable
  ownership and Want to read/Reading/Finished status; moved, removed, and
  operation-locked entries fail safely without stale-path writes.
- The canonical Manage Book sheet moves or removes exactly one saved entry.
  Move to a Shelf targets another unlocked shelf owned by the same Firebase UID;
  the picker excludes the source and locked shelves, shows destination
  count/visibility, retains a failed selection for retry, and keeps a
  create-shelf branch. Remove from your library requires a second confirmation,
  names shared-view consequences, retains failures for retry, and returns to the
  still-existing source shelf after success.
- Owner-filtered all-library book reads use a Firestore collection-group rule
  proven by authenticated-owner, cross-user-denial, and unauthenticated-denial
  emulator tests. Read access denial is reported separately from authentication,
  offline, and missing-index failures.
- Empty, loading, error, retry, and live list states are implemented.
- Shelf creation requires a trimmed name of 1–60 characters and accepts an
  optional description of up to 500 characters.
- Visibility is stored as `friends` (default), `private`, or `public`.
- The Create Shelf control displays Private, Friends, Public while retaining
  Friends as the default.
- `autoShareActivity` defaults on for Friends and Public, but Private shelves
  force it off in both the UI and Firestore Security Rules.
- Shelf ownership, visibility, sharing preference, book count, and server
  timestamps are stored in Cloud Firestore. Legacy shelf documents remain
  owner-readable.
- Account details and sign-out remain available from the app bar.
- Bottom sheets use Android navigation and keyboard insets and remain scrollable
  on small screens.

Automatic Circle activity remains a preference only in this release. Friends
and Public discovery/shelf browsing are implemented below; Circle posts are not
implemented.

## Friends increment

- Every signed-in reader receives a random six-character invite code backed by
  an atomic, unique Firestore reservation. Profiles copy only display name and
  photo URL; email addresses and authentication credentials are never stored.
- Readers can copy or share the code text through explicit user actions. This
  release intentionally does not invent or advertise an unverified deep link.
- Entering a valid code creates a pending request, never an automatic
  friendship. Received requests can be accepted or declined, and sent requests
  can be canceled.
- Accepted friends, received requests, and sent requests remain distinct live
  lists with counts. Friends can be searched by their actual display name.
- Deterministic pair documents and Firestore transactions make repeated and
  opposite-direction requests idempotent under races. Self, unknown, invalid,
  already-friend, already-pending, and blocked states are handled explicitly.
- Either friend can remove the connection and later send a new request. Blocking
  atomically removes an existing request or friendship and prevents either
  direction from reconnecting; unblocking never restores prior state.
- Reader profiles show verified connection identity and accepted friends'
  shared shelves. Circle activity and messaging remain unavailable.
- Firestore rules deny profile/code enumeration and unrelated request,
  friendship, or block access. All connection transitions are participant- and
  state-constrained on the server.

## Shared shelves increment

- An accepted, unblocked friend profile lists that reader's Friends and Public
  shelves only. Private shelves are never returned, and all remote content is
  read-only.
- Shared shelf detail shows its current visibility, accurate live count, actual
  saved books, ownership marker, reading status, catalog cover, and metadata.
- Removing a friend or changing a Friends shelf to Private revokes its shelf and
  book reads. Blocking also denies Public shelf access through friend views.
- Friend shelf streams do not emit Firestore cache snapshots, so remote shelf
  content is not offered as offline browsing. The user's own library retains its
  existing cache behavior.
- Saving a friend's book requires exactly one owned destination shelf and uses
  Want to read plus not owned by default. Ownership can be enabled explicitly.
  The existing normalized ISBN transaction reports and preserves an existing
  library entry; no-ISBN saves receive a new user-local identity.
- The source shelf/book is never mutated. Collaboration and Circle activity
  remain out of scope.

## Friends Explore increment

- Library Explore now combines friends and public libraries in one searchable
  list, without Friends/Public scope controls. Search matches book titles,
  authors, exact ISBNs, reader names, and shelf names. Empty and no-match states
  use centered text. Exact-ISBN copies are grouped, with expandable library
  choices; friends have an avatar ring and a text label. Public pagination and
  partial-load retry remain available when needed.
- Library Explore composes accepted friends with their currently accessible
  Friends/Public shelves, then queries only nested books whose `isOwned` field
  is true. Private shelves and saved-but-not-owned entries never contribute to
  cards, search results, counts, shelf detail, or book detail.
- Removing a friendship, changing shelf privacy, or clearing ownership removes
  the affected content live. Query failures expose a retry state rather than
  retaining stale social content.
- Search keeps exact friend, shelf, and book identities. Friend shelf detail is
  owned-only and read-only; the discovery sheet links back to that exact shelf.
- Saving defaults to Want to read and not owned, requires exactly one unlocked
  own shelf, and reselects a shelf created from the picker. A matching normalized
  ISBN shows the existing shelf/status and performs no mutation.
- The owned nested-shelf query uses Firestore's automatic single-field index and
  requires no composite index.

## Public Explore increment

- Signed-in Public Explore reads a minimal public-shelf directory, then resolves
  each exact shelf through server-authorized Public-shelf reads. It never grants
  friend-only access or Circle privileges, and either-direction blocks deny
  profile, shelf, and nested-book content.
- Only owned books on currently Public shelves appear. Privacy, block, deletion,
  and ownership changes remove list content and revoke retained shelf, book, and
  save views live.
- Search matches normalized title/author text and only an exact canonical ISBN
  identity. Multi-owner discovery preserves exact reader, shelf, and book
  identity without an invalid global shelf query.
- Public profiles show current public shelves and owned-book counts. Sending a
  friend request requires confirmation and creates only a pending request for
  recipient approval; public access itself never creates friendship.
- Directory failure is retryable. Per-source failures are removed immediately
  and explicitly label remaining results as incomplete. Bounded loading offers
  larger-limit pagination using raw directory-page continuation metadata, so
  viewer-owned, blocked, or stale entries cannot hide later eligible results.
- The directory is a discovery index rather than an authorization boundary.
  Stale IDs never authorize shelf or book content. Authoritative owner shelf
  snapshots serialize per-entry reconciliation with current-state rechecks and
  bounded retries; cached snapshots never trigger migration writes.
- Saving reuses the duplicate-safe own-shelf picker, defaults to Want to read
  and not owned, and never mutates an existing normalized-ISBN entry.
- Review evidence is in `test/artifacts/p1-08-review`. Analyze is clean; 149
  Flutter tests and 49 Firestore Rules tests pass. The production index
  inventory needs no new composite index. Tested Rules were deployed alone; no
  release APK, version bump, API configuration, or production-data write was
  made.

## Shelf settings increment

- Shelf owners can edit the shelf name, optional description, visibility, and
  per-shelf automatic Circle-sharing preference. Settings list Friends,
  Private, Public; shelf creation retains Private, Friends, Public with Friends
  selected by default.
- Choosing Private requires the canonical privacy confirmation, forces
  automatic sharing off, and immediately revokes friend access to open shelf,
  book-detail, and save-picker views.
- Settings updates use an online Firestore transaction and fail safely while
  offline instead of entering the local write queue. Draft edits remain in the
  form after a failure so saving can be retried.
- Settings change only shelf metadata and preserve `bookCount`, creation time,
  nested books, and the immutable per-user ISBN index. Duplicate messages
  resolve the shelf's current name even when an older index stores its prior
  name.
- Automatic Circle sharing remains a stored preference only. Book editing
  remains out of scope for this increment.

## Shelf deletion increment

- Owners can remove a shelf and its entries after the canonical stronger
  confirmation, or move every entry to one selected owned shelf before the
  source shelf is deleted.
- Each destructive choice is online-only, guards double submission, keeps
  retry controls usable, and preserves book identity, metadata, ownership,
  reading status, timestamps, and the per-user ISBN uniqueness index on moves.
- Large shelves use a persisted, resumable operation instead of one oversized
  transaction or an arbitrary book cap. Each transaction names one exact book
  and atomically proves its source deletion, destination copy or removal, ISBN
  index transition, shelf counts, and operation progress.
- Source and destination shelves are locked and made Private while a confirmed
  operation is incomplete. This immediately revokes shared reads and prevents
  settings changes or book additions from racing the operation. A completed move
  restores the destination's original visibility and automatic-activity setting.
- My Library queries the authenticated user's running operation subcollection.
  A paused card survives app restart/sign-out, names the saved destination and
  remaining count, and resumes the already-confirmed action without asking the
  user to reconstruct it. Locked shelf detail explains the pending work and
  disables mutation controls.
- Emulator tests cover a 160-ISBN move, interruption during chunks and after the
  last removal before finalization, empty/pending startup queries, cross-user
  denial, lock concurrency, and forged/retained/missing/unchanged/mismatched
  source and index attempts. Tests never mutate production data.

## Single-book move increment

- A move is one online Firestore transaction over the exact source and
  destination shelves, source and destination book paths, immutable owner-only
  move record, both counts, and the ISBN index when present.
- The transaction rejects a same-shelf destination, a missing, moved, deleted,
  cross-owner, or operation-locked source, a missing/cross-owner/locked
  destination, a destination duplicate, stale counts/indexes, and retries after
  the entry has already moved. It never recreates or duplicates the entry.
- The destination book differs only by `shelfId`, preserving its immutable ID,
  metadata, ownership, reading status, cover, and `createdAt`. A no-ISBN entry
  keeps its existing document ID; an ISBN entry moves its existing per-user
  uniqueness index with strict before/after proof.
- Source and destination visibility and automatic-activity settings remain
  unchanged. The immutable `users/{uid}/bookMoves/{moveId}` record and shelf
  proof pointers preserve the future privacy-propagation contract without
  creating Circle data in this increment.
- The detail route rebinds to the exact destination path after success.

## Single-book removal increment

- Removal is one owner-only online Firestore transaction over the exact shelf,
  saved-book path, immutable removal record, shelf count, and ISBN index when
  present. The shelf itself and every unrelated entry remain intact.
- The transaction rejects a missing, moved, deleted, re-created, cross-owner, or
  operation-locked entry; stale counts and mismatched indexes also fail closed.
  The original `createdAt` is the entry generation proof, so a delayed
  confirmation cannot delete a later entry that reused the same document ID or
  ISBN. Repeating a completed removal cannot decrement the shelf twice.
- ISBN-backed entries release the per-user uniqueness index only when it still
  identifies that exact shelf, entry ID, title, and generation. No-ISBN entries
  are removed only by their immutable entry ID and generation.
- The immutable `users/{uid}/bookRemovals/{removalId}` record preserves source
  privacy/activity context for future Circle and review cleanup without creating
  Circle content in this increment.
- Keep book is non-mutating. Success closes only the confirmation and book-detail
  route, returning to the retained shelf with its live one-lower count. Friend
  shelf panels remain read-only and do not expose Manage Book.

## Manual book add increment

- Opening an owned shelf shows its live book list, empty state, loading state,
  and retryable error state.
- Owned shelf detail includes the canonical visibility/activity summary,
  two-column scan/settings actions, status filters, and a two-column book grid.
- Manual add targets exactly the opened shelf. Title and author are required;
  ISBN is optional.
- Ownership defaults to on and is editable independently of reading status.
- Reading status is limited to Want to read, Reading, and Finished, defaulting
  to Want to read.
- Valid ISBN-10 input is converted to its equivalent ISBN-13. ISBN-10 and
  ISBN-13 checksums are validated before saving.
- A canonical ISBN-13 can appear only once in a user's entire library. The book,
  per-user ISBN index, server timestamps, and shelf count are committed in one
  Firestore transaction. A repeat reports the existing title and shelf without
  overwriting either document.
- Books without ISBN use unique document IDs. Matching titles are shown for
  review but remain separate copies and are never merged automatically.
- Book documents and ISBN indexes are owner-only. Book metadata editing, general
  catalog discovery, and Circle integration remain out of scope; friend browsing
  and copy behavior are described in the increment above.

## ISBN scanning increment

- Scanning opens the camera directly after an owned shelf is selected, with
  Android requesting permission when needed. Add & Scan Next saves and resumes
  the camera immediately; Add & Finish saves and returns to the bookshelf.
  ISBN entry and manual book entry offer Add & Enter Another, clearing the
  previous book's fields while retaining the selected shelf.
- `mobile_scanner` `7.4.2` uses Android CameraX/ML Kit for EAN-13 detection. Its
  supported app lifecycle handling pauses and resumes camera use, and each
  scanner widget owns and disposes its controller.
- Repeated detections are gated so only one lookup or save can run at a time.
  Canceling a lookup invalidates late responses before the scanner reopens.
- Manual ISBN entry remains available when permission is denied, the device has
  no usable camera, or a barcode will not scan. Denied permission guidance
  directs users to Android Settings without blocking manual lookup.
- ISBN metadata first uses Open Library's key-free, exact ISBN Books API:
  `https://openlibrary.org/api/books?bibkeys=ISBN:{isbn}&jscmd=data&format=json`.
  Requests are user-driven and serialized, staying within the documented
  unidentified-client limit of one request per second.
- Only a successful Open Library no-match falls back to Google Books using an
  `isbn:` query, followed by a quoted-ISBN query if no exact edition matches.
  Network, timeout, malformed, and service failures remain
  retryable and never trigger fallback. Google results must contain an ISBN-10
  or ISBN-13 that canonicalizes to the requested edition before they are shown.
- Google Books configuration is supplied at build time with
  `--dart-define-from-file=config/google-books.local.json`. That ignored local
  file contains a `GOOGLE_BOOKS_API_KEY` entry and is never committed.
  For a phone APK, run from `app`:
  `flutter build apk --release --dart-define-from-file=config/google-books.local.json`.
  A plain `flutter build apk` omits this configuration; hot reload on an emulator
  does not update an APK already installed on a physical phone.
- Lookup has explicit timeout, offline, service, malformed response, and no-match
  states. No record is created until the user verifies the selected edition;
  manual and no-ISBN paths retain editable title and author fields.
- Provider format, publisher, year, and remote cover are shown when available.
  Stored HTTPS cover URLs are limited to `covers.openlibrary.org` or Google
  Books' exact `books.google.com/books/content` path; this is not a Firebase
  Storage upload.
- ISBN-10/13 normalization and the existing transactional per-user ISBN index
  continue to enforce edition duplicates across all shelves.

## Catalogue search increment

- Library empty/search-empty, owned shelf, and shelf scanner entry points open
  one bounded title, author, ISBN-10, or ISBN-13 catalogue flow. Mixed text and
  digits remain text search rather than being misclassified as an ISBN.
- Text search uses Open Library Search first. A successful no-match alone falls
  back to Google Books; network, timeout, throttling, malformed, and service
  failures stay distinct and retryable without provider fallback. Once a
  successful initial no-match selects Google Books, every continuation remains
  on Google Books; later Open Library exhaustion never changes provider.
- Open Library work matches open the separately paginated editions endpoint so
  readers select a specific ISBN edition. Google and exact-ISBN results are
  already edition-specific. Cross-page ISBN aliases are canonicalized and
  deduplicated while different ISBN editions remain separate choices. Work and
  edition pagination keep separate offsets, loading/error flags, and retries;
  Back from editions restores the prior query, results, and work scroll state.
- Catalogue responses are limited to supported title, author, ISBN, format,
  year, publisher, description, and safe provider cover fields. The current
  save path persists title, author, normalized ISBN, ownership, reading status,
  and a safe cover URL; it does not persist format, year, publisher, or
  description. A record without an ISBN follows an explicit manual-entry
  confirmation and never receives an invented ISBN or silently merges by title
  and author.
- Confirmation supports an existing unlocked own shelf or shelf creation before
  save. Shelf creation returns the exact created shelf ID or null on cancel, so
  unrelated concurrent shelf arrivals are never guessed or selected. A newly
  created shelf is selected automatically, and cancellation, duplicate, and
  save errors retain the current book draft.
- Clearing a query or starting a new search invalidates pending work and edition
  responses so late results cannot replace the current prompt or result set.
- Opening a work also releases any cancelled work-continuation loading state;
  Back restores the prior offset for a safe retry while the late page remains
  unable to alter the selected work, editions, or restored results.
- Saving reuses the existing transactional `createBook` path, including shelf
  count updates and the canonical per-user ISBN duplicate guard. No backend,
  Firestore Rules, or index change is required for catalogue search.

Physical-device acceptance still required after installation:

1. Grant Camera and scan real ISBN/EAN-13 barcodes in portrait and landscape.
2. Deny Camera, retry after permanent denial, and complete manual ISBN lookup.
3. Background/resume the app during scanning and confirm the camera restarts.
4. Toggle the flashlight on a supported phone and confirm it is hidden when not
   available.
5. Save, Save and scan another, cancel/back, wrong-book, and cross-shelf
   duplicate flows against the production account.
6. With two production accounts, exchange each manual friend code, verify only
   a pending request appears, accept it from the recipient, then verify counts
   and identities on both devices.
7. Exercise decline, cancel, remove/re-invite, block, blocked-code lookup,
   unblock, and re-invite. Confirm unblock does not restore the friendship.
8. Open a friend's Friends/Public shelf, change its privacy or remove/block the
   connection on the other device, and confirm the open remote view clears.
9. Save ISBN and no-ISBN friend books into one own shelf. Verify Want to read /
   not owned defaults, explicit ownership, and unchanged duplicate ISBN entries.
10. Interrupt a large move/removal by closing the app, reopen Library, and use
    Continue shelf change. Verify counts, destination settings, and ISBN entries.
11. Verify the login does not move at the four documented portrait sizes and
    still scrolls in landscape, large text, and genuinely short heights.

### Cover photos

Catalog cover images currently load remotely from Open Library or Google Books.
The user reports Firebase Storage is now enabled, but the bucket, rules, and app
access have not yet been independently verified. Optional cover photo capture or
selection for manually added books, followed by a Firebase Storage upload, is
the final Phase 1 implementation step. That later increment must preserve manual
entry drafts across permission and upload errors, provide explicit retry and
cancel paths, use owner-scoped Storage paths and rules, and verify upload/read/
delete behavior before release. This settings increment does not provision,
upload to, or test Storage, and no other media-upload path is implied.

## Firebase configuration

- Uses the existing default Firestore database in `nam5` on the free tier.
- `firestore.rules` preserves unrelated active project rules and adds isolated
  reader-profile, invite-code, friend-request, friendship, and directional-block
  paths alongside strict shelf/book/index, owner-scoped shelf-operation, and
  immutable single-book move/removal-record rules.
- `firestore.indexes.json` preserves the production index inventory and adds
  the `books.ownerId` ascending collection-group field index required by the
  signed-in Library startup query.
- Production rules reject unauthenticated and cross-user shelf access, owner
  spoofing, unknown fields, invalid visibility/status/ISBN shape, invalid names,
  client timestamps, duplicate ISBN identities, and automatic sharing on private
  shelves.
- The authenticated `users/{uid}/shelfOperations` query filters on the single
  `status` field, so it uses Firestore's automatic single-field index and does
  not require a new composite index.
- Google authentication configuration and registered debug SHA fingerprints are
  preserved. Apple and further iOS setup remain deferred.

## Verify

```powershell
cd C:\dev\ai\readuo\app
flutter pub get
flutter analyze
flutter test
```

Firestore rules tests use a `demo-*` project and never contact production data:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
npm --prefix rules-tests install
firebase emulators:exec --only firestore --project demo-readuo-shelves "npm --prefix rules-tests test"
```

Deploy the tested Firestore rules with:

```powershell
firebase deploy --only firestore:rules --project readuo-b2f24
```

The web build remains a local UI preview only. `firebase_core_web` is pinned to
`3.10.0` for compatibility with this workspace's Flutter `3.41.6` toolchain.
