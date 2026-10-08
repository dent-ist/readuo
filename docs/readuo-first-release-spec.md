# Readuo first-release development specification

## Handoff status

September 20, 2026 execution update: the user resumed all remaining Android
Phase 1 features and final integration review. Verify each increment against
the canonical design, then build and upload one final APK after completion;
per-item release builds are no longer requested. Earlier September 14 hold
notes describe the previous pause and are superseded. iOS and Phase 2/3 remain
deferred, and manual-book cover photos/Storage remain the final Phase 1 feature.

The canonical 117-state modern design remains the binding handoff. The Android Flutter application at `C:\dev\ai\readuo\app` now includes Firebase Google authentication, profile setup, owner-scoped shelves, complete owner-scoped My Library all-books/status-filter/sort/search and empty states, shelf settings and resumable deletion/bulk-move flows, manual, ISBN-scanned, and bounded title/author catalogue book entry with specific-edition confirmation, live saved-book details with independent ownership and reading-status updates, exact single-book moves and generation-guarded removals, a persistent authenticated Circle/Library/Friends/Profile navigation shell, Open Library with exact Google Books fallback, private friend requests/connections/blocking, accepted-friend read-only Friends/Public shelf browsing, signed-in Public Explore/search/profiles with save-to-own-shelf, friends-only automatic Circle activity, and friends-only general text posts with durable drafts, one optional own-library book attachment, and author edit/delete. ISBN recognition accepts only whole ISBN-shaped input while mixed title/author text remains text-only. Catalogue discovery uses Open Library works plus separately paginated editions and falls back to Google Books only after a successful no-match; no-ISBN records require explicit manual entry. Full-screen searches are bottom-inset safe and preserve the single shell navigation contract. The login adapts to supported portrait heights without unnecessary scrolling while preserving scrolling for real overflow. Reviews, comments/likes, photo posts, moderation, notifications, account deletion, iOS, and store release remain incomplete. It is not yet App Store or Google Play ready; readiness still depends on the remaining product increments, final legal copy, published support/deletion resources, moderation operations, provider configuration, and device/build enrollment.

P1-04 catalogue title/author search and specific-edition selection is delivered
in Android build `1.13.2` (`versionCode` 21). Its accepted behavior includes
separate work/edition continuation state, generation-guarded stale-response
discard, exact offset retry after cancelled work continuation, exact created-
shelf selection, and canonical catalogue/confirmation/empty-state controls.
Builds 19 and 20 remain preserved as superseded audit artifacts. This delivery
does not change backend services, Firestore Rules, indexes, API configuration,
or production data.

P1-05 central scanner destination selection and batch entry is delivered in
Android build `1.14.0` (`versionCode` 22). Central Scan
is available from Library, Friends, and Profile; shelf-origin scans preselect
only the exact unlocked own shelf. Independent error state, live destination
revalidation, covered-route camera disposal, queued-detection rejection,
save-time snapshots/disabled conflicts, batch reset, late-lookup discard,
retryable save/move failures, and exact-ISBN duplicate branches are covered by
the 133-test Flutter suite. Shelf-origin completion revalidates and displays the
exact returned destination while cancellation preserves the origin shelf. View
existing opens canonical book detail with the single shell bar and returns to
the scanner; cancellation restores the origin tab, while Done returns the typed
selected shelf to Library. Actual API 36
Android captures at 390×844 and 360×640 verify the 48px three-button inset and
canonical permission, destination, loading, confirmation, duplicate, manual,
not-found, and saved layouts. Physical camera/torch acceptance remains
unconfirmed. P1-09 now integrates scanner saves with one stable activity batch
ID per scan screen. The signed APK is preserved at
`C:\dev\ai\readuo\app\release\Readuo-1.14.0-build22.apk` and in the existing
restricted Readuo Drive folder. Package, version, signer, SHA-256, byte size,
fresh installation, and launch were verified. No backend service, Firestore
Rules, index, API configuration, or production data changed. P1-06 and all later
items remain on hold pending explicit user resumption.

### Supplied Firebase configuration reference

- The user-supplied Android Firebase client configuration is preserved at `C:\dev\ai\readuo\config-reference\firebase\android\google-services.json`; the verified runtime copy is configured in the Android Flutter project.
- Verified Firebase project identifiers: project ID `readuo-b2f24`, project number `881895077363`, storage bucket `readuo-b2f24.firebasestorage.app`, and Android mobile SDK app ID `1:881895077363:android:29d58bb2b3504cf990ce86`.
- The configuration contains one Android client for application/package ID `com.zipdosa.readuo`, plus Android and web OAuth client records. API-key and OAuth-client values remain in the reference file and are intentionally not repeated in this handoff.
- This file is Android-only. A separate Firebase Apple configuration (`GoogleService-Info.plist`) and confirmed iOS bundle ID are still required before iOS integration. Receipt of this file does not confirm enabled Firebase services, production/development environment separation, Security Rules, or remote project access.

## Confirmed product decisions

### Binding design source

- `C:\dev\ai\readuo\design\readuo-first-release.html` is the final audited 117-state modern design and the binding source for application screen structure and styling.
- Implementation must reproduce its navigation, layouts, components, spacing, typography, colors, cards, controls, and flows for every implemented state. Incremental feature scope may disable unavailable destinations but does not authorize replacing or simplifying the agreed visual shell.
- Do not alter the prototype to excuse implementation differences. Earlier uploaded PNGs and exploratory playful/icon concepts are reference history, not the selected final design.
- Material design changes require a new explicit user request. Later explicit adjustments override the handoff only where they conflict: Create Shelf displays Private, Friends, Public while Friends remains the default; Android bottom actions account for system and keyboard safe insets; Google-only Android authentication ships before iOS; reading status remains exactly three values with no page progress.
- Every UI delivery requires an actual rendered comparison against the corresponding canonical state.

- Sign-in is required before all personal, friends, or Public browsing. Use Firebase Authentication with Google and Apple on both platforms; do not offer independent email/password registration.
- New users set a display name, optionally add a photo, then add or skip their first book. Friend connection is optional. Returning users land on Circle.
- Primary navigation is Circle, Library, central Scan, Friends, and Profile. Library contains separate My Library and Explore surfaces. Explore defaults to Friends and offers a Public filter.
- The authenticated app owns one persistent bottom navigation bar. Library,
  Friends, and Profile switch in place with independent retained histories;
  tab switches do not push routes, text inputs are unfocused before switching,
  deep fullscreen scanner/settings flows hide the shell, and authentication UID
  changes dispose all retained tab state.
- Modern is the only visible first-release theme. Keep behavior, data, and navigation independent of visual tokens so materially different skins can be introduced later without changing domain logic.
- A shelf has exactly one owner. Only the owner may add, move, edit, or delete its books. There are no collaborative or family shelves.
- A user's book identity is its normalized ISBN. The same normalized ISBN has at most one library entry for that user; ISBN-10 and its equivalent ISBN-13 are the same identity. Different ISBNs are separate books even when title, author, or optional canonical-work metadata matches. Every entry belongs to exactly one shelf, and moving transfers the entry without duplicating it.
- Reading status is exactly `wantToRead`, `reading`, or `finished`. Ownership is an independent Boolean.
- Public means any signed-in Readuo user, not an anonymous web visitor. Circle is always accepted-friends only.
- Release-one offline access is a partial, read-only cache of the signed-in user's own previously loaded library. No social data, edits, queued scans, or synchronization are available offline.

## Screen catalog

- **01 시작과 로그인**: `login`, `login-error`, `setup`, `profile-photo`, `first-book`, `terms`, `privacy`
- **02 Circle**: `circle`, `circle-empty`, `compose`, `compose-photo`, `attach-book`, `review`, `post`, `post-menu`, `own-post-menu`, `edit-post`, `delete-post`, `comment-menu`, `own-comment-menu`, `owner-comment-menu`, `edit-comment`, `delete-comment`, `report`, `report-sent`, `notifications`, `notifications-empty`
- **03 내 서재**: `library`, `library-books`, `sort-books`, `library-empty`, `search-results`, `search-empty`, `filter-empty`, `shelf`, `shelf-empty`, `create-shelf`, `shelf-settings`, `private-confirm`, `delete-shelf`, `move-all`, `delete-shelf-confirm`, `book`, `saved-book`, `book-menu`, `reading-status`, `move-book`, `remove-book`
- **04 Explore**: `explore`, `explore-public`, `explore-results`, `explore-empty`, `explore-no-results`, `friend-shelf`, `public-shelf`, `friend-book`, `public-book`, `save-shelf`, `book-saved`, `unavailable`, `public-profile`
- **05 책 추가와 스캔**: `camera-permission`, `scanner`, `camera-denied`, `scan-loading`, `scan-found`, `scan-duplicate`, `manual-isbn`, `isbn-not-found`, `catalogue-search`, `catalogue-results`, `catalogue-no-results`, `manual-book`, `book-photo`, `manual-confirm`, `manual-possible-duplicate`, `scan-saved`, `photo-denied`
- **06 친구**: `friends`, `friends-empty`, `invite`, `enter-code`, `invalid-code`, `request-preview`, `request-sent`, `requests`, `request-detail`, `sent-requests`, `friend-profile`, `profile-menu`, `remove-friend`, `block-friend`, `blocked-users`, `unblock`
- **07 프로필과 계정**: `profile`, `edit-profile`, `notification-settings`, `account`, `delete-account`, `reauth`, `deleting`, `delete-account-error`, `account-deleted`, `signout`, `support`, `support-message`
- **08 빈 화면과 오류**: `offline-library`, `offline-book`, `offline-action`, `network-error`, `feed-loading`, `save-error`, `content-filtered`, `notification-permission`
- **09 운영자 전용**: `moderation`, `report-detail`, `moderation-action`

## Flow acceptance criteria

### Authentication and first run

- `login` is the initial design state. Either provider continues to `setup`; a failed or cancelled provider flow reaches `login-error` without exposing library data.
- Store the immutable Firebase UID as account identity. Display name and photo are mutable profile fields; never expose email addresses on public profiles.
- `setup` requires a non-empty display name. Photo selection is optional and its permission failure returns without losing the form.
- `first-book` offers scan, catalogue search, manual entry, and skip. During first-book add, saving is blocked until the user creates or selects a first shelf.
- First-book progress is stored per immutable Firebase UID. A newly created account persists `pending` before profile completion; `pending` resumes after restart, `skipped` does not prompt again, and the first successful saved book records `completed`.
- Existing accounts with no first-book state continue to the authenticated shell rather than being reclassified as new users. UID switches must load only the target account's state.
- Failed profile, skip, completion, shelf, or book writes remain retryable without discarding the entered display name or first-book draft. If the book was saved but final onboarding state failed, observing that saved book safely retries completion without creating a duplicate.

### Circle and user-generated content

- `circle` is newest-first and refreshable. It contains general text/photo posts, optional book attachments, reviews with optional 1–5 stars, grouped shelf activity, likes, and comments.
- Publishing requires text or a photo. Attachment is optional. Draft text, selected photo, book attachment, and review text survive non-destructive navigation and failed saves.
- Authors may edit or delete their own posts, reviews, and comments. Post owners may remove another user's comment but may never edit another user's words.
- Destructive actions require explicit confirmation and update the source card/thread after success; failures retain the visible draft or original content.
- Report actions exist for posts, comments, and profiles. Blocking is offered only when the report has a reader target.

Implementation checkpoint (September 21, 2026): the Circle foundation is the
default returning-user tab after onboarding and remains accepted-friends only,
including activity sourced from Public shelves. It composes live friend, shared
shelf, shared-book, and nested immutable activity streams; supports pull refresh,
retry/partial-error handling, canonical empty state, exact friend-book detail,
and one grouped card for additions sharing a scanner-session batch ID. Eligible
owned additions atomically create Added events; Reading and Finished transitions
create events for both owned and non-owned books when the current Friends/Public
shelf has automatic activity enabled. Want to read, Private, disabled, and
ownership-only changes publish nothing. Rules bind the event ID to the book
mutation, reject suppression, forgery, duplicate or replayed status publication,
and all event edits. Current friendship, block, shelf privacy/automatic-sharing,
book ownership for Added events, and per-placement activity generation remain the
read boundary. Private or disabled sharing hides events while inaccessible and
may reveal the same current-placement events when reshared. Moves and re-adds
rotate generation, so activity from an earlier placement never resurfaces. The
feed loads at most the newest 20 current-generation events per book.

General text posts are now merged newest-first with activity. New-post drafts
persist under the authenticated UID, restore after navigation/restart, require
explicit discard, and survive failed publication. Each draft keeps one immutable
generated post ID; publication creates that exact document and consumes the
draft in one transaction, making ambiguous retries idempotent. Serialized,
immutable autosave snapshots are flushed before publish/discard, cleanup
failures remain retryable, and pending completion is scoped to the originating
UID. Publication verifies the current server draft before consuming it, and the
missing-document transaction read never grants access to an existing foreign or
blocked post. One optional attachment must
resolve to an exact current book in the author's own library; its identity and
display snapshot are Rules-verified at create/edit time. Authors see their own
posts and alone may edit or delete them, with confirmation before deletion and
retry-safe failure handling. Friends may read only while current friendship
exists and neither reader blocks the other. Reviews, likes, comments, and photo
attachments remain later queue items. The P1-09/P1-10 Rules and post index are
staged locally for coordinated final release; production intentionally remains
on the exact build-22-compatible P1-08 ruleset until that APK is replaced.

### Library and shelves

- My Library search covers all owned and saved entries. Status filters and sort order reflect the same underlying entries and counts.
- Shelf visibility is `private`, `friends`, or `public`. Friends is the new-shelf default. Automatic activity is per shelf, defaults on for Friends/Public, and is always off and disabled for Private.
- Shelf owners can edit name, optional description, visibility, and automatic activity. Making a shelf Private requires explicit confirmation, turns automatic activity off, and immediately revokes active friend shelf/book/save views. Metadata updates preserve the shelf count, creation timestamp, nested books, and per-user ISBN indexes; failed online-only updates retain the draft for retry.
- Shelf deletion has two paths: move every entry to one destination shelf, or remove the shelf and its library entries after a stronger confirmation.
- A confirmed deletion persists as an owner-scoped resumable operation. It locks involved shelves Private, applies one strictly cross-proven book/index/count transaction at a time, exposes remaining progress after restart, restores the move destination's original visibility/activity settings only at completion, and never imposes an arbitrary book-count cap.
- A book owner can change status, toggle ownership, move the entry, review it, or remove it. There are no page-count or percentage controls.
- Implemented saved-book details stream the exact owner/shelf/book identity.
  Ownership updates change only ownership plus `updatedAt`. Status updates
  change status plus `updatedAt`, and eligible Reading/Finished transitions
  also rotate the Rules-bound `lastActivityId` while atomically creating one
  immutable friends-only event regardless of ownership. Both preserve
  metadata/index/count and
  `createdAt` values and reject stale, moved, deleted, cross-owner, or
  operation-locked source paths.
- Implemented single-book moves use the canonical `book-menu` and `move-book`
  sheets, list only other unlocked shelves owned by the same UID with current
  counts and visibility, retain failed destination drafts, and include the
  create-shelf branch. One online transaction preserves the entry ID, metadata,
  status, ownership, cover, and `createdAt`; changes its `shelfId` and rotates
  its activity generation; adjusts both counts; and moves the existing ISBN
  index when present. Immutable move
  proof records reject same-shelf, stale/deleted/moved, duplicate-destination,
  locked, cross-user, replay, partial, index-forging, and visibility-changing
  writes. No-ISBN entries retain their IDs. The proof contract records source
  and destination privacy for future propagation, but creates no Circle data.

### Explore and saving

- Friends Explore shows owned books on shelves currently accessible through accepted friendship. Public Explore shows owned books on Public shelves to signed-in users.
- Shared shelves and books are read-only. Every book/person/shelf tap must propagate the selected identity to the destination.
- Saving a discovered book defaults to Want to read, ownership off, and requires one shelf. A create-shelf branch returns to the picker with the new shelf selected.
- If the same normalized ISBN already has a library entry, show the existing status and shelf and do not duplicate, move, reset status, or change ownership. A different ISBN may be saved as a separate entry even when it represents another edition of the same title or canonical work.

Implementation checkpoint (September 21, 2026): Friends Explore is accepted and
Public Explore is a review candidate. Both use owned-only nested shelf queries,
exact identity navigation, live privacy/block/ownership revocation, and
duplicate-safe saving. Public discovery resolves a minimal signed-in directory
through exact Rules-authorized shelf/profile/book reads, labels per-source
partial failure, retries directory failure, paginates by bounded limits, and
uses exact canonical ISBN identity matching.

The public-shelf directory is a discovery index, not an authorization proof.
Rules constrain directory writes against current shelf state, but shelf writes
do not require a mirrored directory mutation. A stale directory ID therefore
never authorizes profile, shelf, or book content. Legacy public shelves are
indexed after the owner's next authoritative server shelf snapshot; cached
snapshots do not trigger writes. Pagination continuation comes from raw
directory-page metadata rather than the number of displayable results.

### Scanning and manual entry

- A scan batch selects a shelf once. Each detected book is confirmed independently with ownership default on and status default Want to read. Scanning from a shelf preselects that shelf.
- Barcode, typed ISBN, catalogue title/author search, and manual metadata are equivalent entry paths. Camera/photo denial always leaves typed data intact and offers another path.
- Normalize every valid ISBN-10 to its equivalent ISBN-13 before lookup or uniqueness enforcement. Catalogue results must keep editions with different ISBNs selectable as separate books.
- A manually entered book with no ISBN receives an immutable unique entry ID. Title/author similarity may open an explicit possible-duplicate review, but it must never invent an ISBN, silently merge entries, or silently discard the new entry. If an ISBN is added later and creates a conflict, require an explicit resolution flow.
- The design preview uses an explicit sample-barcode state and never claims camera, catalogue, auth, or permission operations actually occurred.
- Batch additions create one grouped Circle activity item, only when the destination shelf's automatic activity is enabled.

### Friends

- Invite codes and links create a pending request, never an immediate friendship. The recipient must accept or decline.
- Accepted, incoming, and sent lists contain disjoint people in the same scenario. Counts update after send, cancel, accept, decline, remove, block, and unblock.
- Removing a friend revokes Friends shelf and Circle access. Blocking also prevents new requests and interactions. Unblocking never restores friendship.

### Notifications and account

- Push/in-app notification types are friend request, request accepted, like on my post/review, and comment on my post/review. Users can configure each type independently.
- Book added, started, and finished events remain in Circle and never produce an individual push in release one.
- Ask for platform notification permission only after an in-app explanation. Denial leaves per-type preferences intact and points to platform settings.
- Account deletion requires acknowledgement, linked-provider reauthentication, processing, failure, cancellation-before-processing, and completion states. Sign in again with only the provider linked to the account.

## Data model and invariants

- `User`: Firebase UID, display profile, created/updated timestamps, moderation/account state. Email remains private authentication data.
- `Shelf`: ID, owner UID, name, optional description, visibility, automatic-activity flag, count, optional active mutation-operation ID, optional last single-book-move proof ID, optional last single-book-removal proof ID, timestamps. Enforce owner-only writes in service logic and Firebase Security Rules.
- `ShelfMutationOperation`: owner UID, source shelf, optional fixed destination shelf, move/remove mode, running/completed status, original destination privacy/activity settings, total/processed counts, current book proof, and timestamps. Keep completed records for idempotent retries; running records are discoverable from My Library after restart.
- `BookMove`: immutable owner-scoped move ID, exact source/destination shelf IDs,
  book ID and optional ISBN, title, before-counts, source/destination
  visibility/activity snapshots, and server timestamps. Both updated shelves
  point to the same record for atomic cross-proof and replay rejection.
- `BookRemoval`: immutable owner-scoped removal ID, exact source shelf and book
  IDs, optional ISBN, title, source `createdAt` generation, count before removal,
  source visibility/activity snapshots, and server timestamps. The updated shelf
  points to the record for atomic deletion/index/count proof and replay rejection;
  retain it for future Circle activity and review-thread privacy cleanup.
- `Book` or `Edition`: store the normalized ISBN-13 as the ISBN-backed identity. Optional canonical `Work` metadata may group related editions for display or discovery, but it must never collapse entries with different ISBNs.
- `LibraryEntry`: store an immutable entry ID, user UID, optional normalized ISBN-13, one shelf ID, status, ownership, and timestamps. Enforce at most one active entry per `(user UID, normalized ISBN-13)` when ISBN is present, plus exactly one shelf per entry. No-ISBN entries remain distinct by entry ID until an explicit user resolution.
- `FriendRequest`: sender, recipient, status, timestamps. `Friendship`: normalized pair and accepted timestamp. `Block`: blocker, blocked UID, timestamp; block checks override requests, friendship, Public discovery, and social interaction.
- `Post`: author, type (`general`, `review`, `activity`), text/photo/book references, source shelf where relevant, audience metadata, moderation state, timestamps. `Comment`, `Reaction`, `Report`, `ModerationAction`, and `Notification` reference immutable IDs.

### Matching policy

- Strip spaces and hyphens, validate the checksum, and normalize every ISBN-10 to its equivalent ISBN-13. The normalized ISBN is the sole automatic uniqueness key for an ISBN-backed book within one user's library.
- The same normalized ISBN preserves the existing entry unchanged. Different valid ISBNs create separate entries even when title, author, or optional canonical `Work` metadata matches.
- Manual/no-ISBN similarity may use normalized title + primary author, with year/publisher as confidence inputs, only to flag a possible duplicate. A probable match must display an explicit review choice; the new book retains a unique entry ID and is never silently merged by metadata.

## Privacy propagation

- Authorize every read server-side from current shelf visibility, accepted-friend state, ownership, blocks, and moderation state. Never rely on a copied client audience list as the only access control.
- Moving to a stricter shelf or making a shelf Private immediately removes online discovery and Circle access to shelf-derived activity and linked reviews. Comments and likes inherit the parent content's visibility.
- Moving to the same or broader visibility does not retroactively repost hidden activity. New eligible events may post after the change.
- Turning ownership off removes the book from friends/Public ownership discovery but preserves the user's private library entry and reading status.
- Removing a friend revokes Friends-only shelves, Circle posts, reviews, comments, and derived data for that relationship. Public content may remain discoverable unless either user blocks the other.
- Blocking supersedes Public discovery and all interaction paths between the two accounts. Unblocking only removes the block.
- Deleting a shelf with entries or removing a library entry removes associated shelf-derived activity and review threads from shared views. The confirmation copy must name this consequence.
- Online revocation must be immediate after the server mutation. Release-one offline cache contains only the user's own library, so the product must not promise remote social cache erasure while disconnected.

## Event and notification rules

| Event | Circle | Push/in-app notification |
|---|---|---|
| Owned book added to eligible shelf | One item; batch additions grouped | None |
| Status changes to Reading | One item when shelf auto-activity is on | None |
| Status changes to Finished | One item when shelf auto-activity is on | None |
| Friend request received | No | Recipient, if enabled |
| Friend request accepted | No | Original sender, if enabled |
| Like on my post/review | No new Circle item | Author, if enabled |
| Comment on my post/review | Appears in thread | Author, if enabled |

Events must be idempotent. One logical mutation produces at most one activity/notification record; retries must reuse an event ID.

## Release-one versus later

Release one includes modern visuals, authentication, owned/saved library entries, shelves and visibility, Circle UGC, basic reporting/operator action, Friends requests/connections/blocks, discovery, scan/catalogue/manual add paths, notifications, account deletion, and read-only own-library offline cache.

The final Phase 1 implementation step adds an optional cover photo to the manual-book path. A reader may capture or select an image and upload it to Firebase Storage. The user reports Storage is enabled, but the bucket, deployed rules, and client access must be independently verified before implementation. The flow must preserve the manual-entry draft through permission denial, cancellation, offline/service failures, and retry; use owner-scoped Storage paths and access rules; and test upload, read, replacement, and deletion behavior. This milestone does not imply that any other media upload exists.

Next release defers nearby/location discovery, offline editing/synchronization, page or percentage progress, export, richer moderation tooling, and user-selectable themes. Theme architecture remains required from day one, but no picker or purchases appear in release one.

Phase-three exploration—customizable 3D/isometric libraries, purchasable shelf skins, interaction inside a customizable 3D room, visits/notes, or points—is not a release-one requirement. Ordinary release-one scanning from a shelf still preselects that shelf.

## Launch prerequisites and unresolved decisions

- Replace conceptual Terms, privacy, community-guideline, retention, and support copy with approved documents and a published support contact.
- Define moderation staffing, response targets, objectionable-content filtering, escalation, appeals, repeat-offender handling, and operator authorization. Apple requires filtering, reporting with timely handling, blocking, and published contact information; a report queue alone is insufficient: [App Review Guidelines 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
- Publish a functional external account-deletion request resource in addition to the in-app path before Google Play submission: [Google Play account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en).
- Implement provider reauthentication and revoke Sign in with Apple tokens where applicable: [Apple account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app).
- Decide report/moderation/security-record retention and disclose any lawful retained records before finalizing deletion copy.
- Confirm the catalogue provider, cover-image rights/cache policy, rate limits, and manual metadata stewardship.
- Verify the reported Firebase Storage enablement, bucket configuration, owner-scoped Storage Rules, and authenticated client access before implementing the final Phase 1 manual-book cover-photo step.
- Confirm company-managed iPhone eligibility, Apple Developer enrollment, signing ownership, cloud macOS build provider, TestFlight process, Firebase environment ownership/separation, the iOS bundle ID and `GoogleService-Info.plist`, and configuration/secrets handling. The supplied Android configuration does not block Flutter UI/domain development, but these items still block device/store delivery.
