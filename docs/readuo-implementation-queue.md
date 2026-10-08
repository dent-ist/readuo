# Readuo Android Phase 1 implementation queue

## Execution agreement

Oct4 Circle feedback delivery COMPLETE: 1.21.1+33 includes the restored Post
FAB, removed subtitle, pinned composer action and clearer photo errors. Normal
release build, same-signer build32-to33 upgrade and launch verified. Storage
preflight confirms the earlier approved IAM repair remains present. Upload100%
complete; older APKs and Restricted sharing unchanged. See
`docs/readuo-build33-delivery.md`. Wait for user feedback.

Oct4 Circle composer feedback: Post is a FAB again, the redundant feed subtitle
is removed, and the focused composer pins its action above system/keyboard
insets. The user approved the missing cross-service Storage IAM role repair;
it is now present, with rules and sharing unchanged. Full Flutter suite313 pass
(one existing skip), analyzer clean, dedicated photo rules4 pass. These UI
changes are now packaged in build33. See `docs/readuo-circle-composer-feedback.md`.

Oct4 approved five-screen redesign delivery COMPLETE: 1.21.0+32 includes the
redesign, reconnect grace, and draft-whitespace correction. Its release and
Drive evidence are in `docs/readuo-build32-delivery.md`. The older source-only
and build31-current statements below are historical and superseded.

Oct4 reconnect source update: five-second silent handoff grace, then a small
Reconnecting notice while retaining the mounted screen. Confirmed server
recovery removes it automatically;30-second sustained failure uses the existing
read-only offline fallback. Auth failures remain immediate and writes still
require actual server confirmation. Full suite305 pass(one skip), analyzer
clean. See `docs/readuo-reconnect-update.md`. Not yet packaged; current build31
on Drive contains neither this change nor the Circle draft-conflict fix below.

Oct4 Circle post conflict fix: reproduced build31's false "draft changed on
another device" warning with leading/trailing whitespace. Draft saves reused
published-post serialization, which trimmed text, while the publication
transaction compared the original editor text exactly. Draft storage now
preserves the editor text; published posts still trim outer whitespace and
genuine remote-draft differences still block publication. Regression tests
exercise the production repository save/load/publish/retry path with a local
Firestore test double. Source fix only; build31 on Drive is unchanged and does
not contain this fix. No backend/rules changes or production test writes.

Oct3 current-version APK request COMPLETE: delivered1.20.0+31 with the
accepted Circle density changes. Grouped-book notification source is staged
but deliberately disabled in the normal APK; no backend/rules activation or
deployment is included. Default-off compatibility preserves legacy token
fields, four settings and the old inbox. Full Flutter suite299 pass(one skip),
backend55 pass(two emulator-only skips), dedicated Firestore emulator12 pass.
Fresh normal/small five-state native checks pass; same-signer build30→31 upgrade
and normal launch verified. Upload100% complete, Restricted access unchanged,
build30 retained. No files deleted. Final analyzer clean/focused29 tests pass.
APK: https://drive.google.com/file/d/1nEdSZ6chsgjc3fCYZGqVue1O1SJUE5gS/view
See `docs/readuo-build31-delivery.md` for hash, size, scope and evidence.
See `docs/readuo-book-addition-notifications.md` for future activation boundaries.
This request supersedes the earlier source-only packaging hold below.
Wait for user feedback; do not activate grouped alerts or start unrelated work.

Current Circle density follow-up SOURCE COMPLETE: between-card gap14→7dp,
vertical card padding16→8dp, compact Like/Comment decoration with48dp targets,
feed thumbnail48x68→96x136 and added/batch82x126→164x252. Long titles/authors
wrap; batch strip scrolls. Detail/composer layouts and backend unchanged.
Analyzer clean;28 focused tests pass; actual Android normal/small11-state
runs pass. Existing build30 restored and its bytes unchanged; no version bump,
new release build or upload for this source-only follow-up.
See `docs/readuo-circle-density-update.md`. Wait for review/user authorization
before packaging these new source changes.

Notification follow-up delivery COMPLETE: `1.19.0+30` improves existing social
push retries, privacy-checked silent foreground banners, first-connection
permission explanation and Profile Enable; includes approved circular book-plus
shelf action. Analyzer clean;294 Flutter tests pass(one existing skip),53 backend
unit tests pass, real Firestore delivery emulator test passes,77 rules tests pass.
Actual Android normal/small seven-state runs pass with bounded visual review.
Only `deliverNotificationPush` deployed and verified ACTIVE; no rules changes or
production QA records/test pushes. Physical two-phone FCM acceptance remains
unverified. Same package/debug signer, build29-to30 upgrade and normal launch
verified. Emulator restored. Upload100% complete, prior27/28/29 retained,
Restricted sharing unchanged.
Download: https://drive.google.com/file/d/1_4mpFCmOONzEpiMv8OPVodQEc2SUTBku/view
APK:77,999,547 bytes; SHA-256
`5A6443C24FE625A2A4B81B3001D40638B8CC7264CCC8BA036F59EEA17FD9CFE6`.
See `docs/readuo-build30-delivery.md` and `docs/readuo-notification-update.md`.
Wait for user feedback; older delivery entries below are historical.

Combined delivery COMPLETE: `1.18.2+29` includes the shelf speed dial,
Circle edge-to-edge cards, resume recovery and unified main-tab headers.
The user's later release authorization supersedes historical source-only/no-upload
notes below. Analyzer clean; 286 Flutter tests pass (one existing skip).
All four headers pass actual Android normal and small/font1.3 checks, independently
reviewed. Normal release build, same package/signer, build28-to29 upgrade and
launch verified. Emulator restored; no backend changes. Drive upload is complete;
builds27/28 retained and Restricted sharing unchanged.
Download: https://drive.google.com/file/d/1AxSajHB6x8VwG_Zz_-obI2zqVBuQG9Bm/view
APK: 77,998,651 bytes; SHA-256
`13AEA0EDDBF0192AF71A798481B4661AA09994EA9463FCF4120EAB18655A39C1`.
See `docs/readuo-build29-delivery.md` and `docs/readuo-main-tab-headers.md`
for evidence and the pre-existing full-shell2x navigation limitation.
Wait for the user's next feedback; do not start unrelated work.

Current follow-up SOURCE COMPLETE: Circle cards are edge-to-edge with distinct
top borders; resume actively recovers stale connection checks without restart.
282 Flutter tests pass (one existing skip); analyzer clean. Native Android
normal/small runs pass 12 states each, including actual background/resume.
Existing build28 is reinstalled and unchanged; no release/upload authorized.
See `docs/readuo-circle-resume-update.md` for diagnosis, evidence and limits.

Previous follow-up SOURCE COMPLETE: own-shelf Add book now expands in place.
275 Flutter tests pass (one existing skip); analyzer clean. Native Android runs
pass 13 states each at390x844 and360x640 with1.3font. All test-device changes
are restored; the existing delivered build28 bytes remain unchanged.
No new release APK, version bump or Drive upload is authorized for this change.
Latest delivered APK remains `1.18.1+28` below. Debug UI tests are allowed.
See `docs/readuo-shelf-speed-dial.md` for the explicit design override and QA.

September 27 logo + own-shelf controls delivery COMPLETE: `1.18.1+28` uses the
supplied SVG for login and Android icons, with deterministic iOS icon assets
(iOS runtime remains deferred). Shelf detail now has Add book FAB choices,
title-area catalogue search, ellipsis settings, and three independent OR status
chips with no All chip. Existing blue theme/navigation and global filters remain.
274 Flutter tests pass (one existing skip); analyzer clean. Native Android
390x844 (11 states) and 360x640 (12 states) verify exact destinations, native
Back/IME, filtering and final-book FAB clearance. Release27-to28 upgrade,
normal login and actual launcher icon are verified. Emulator settings restored.
Download: https://drive.google.com/file/d/1xZtd4veai0vHowGGKKfd6tIX-YEK3hNE/view .
APK: 77,900,343 bytes; SHA-256
`659D53FEE321A14BBAFD876D5A640993F93EAF2B010EBC70CA663956C61A2E69`.
Drive shows both build27 and build28 after reload; no sharing changes.
See `docs/readuo-logo-shelf-update.md` for provenance, evidence and scope limits.
Wait for user feedback; do not start unrelated work.

September 27 phone-feedback delivery COMPLETE: all eight requested fixes are in
`1.18.0+27`: Circle missing-review reads, 12dp outer gutters, compose FAB, card
contrast, four-tab swipes, repeated Explore-to-library return, Friends invite FAB,
and native Android Back from scanners. No Circle reset or production QA writes.
77 rules tests pass and the additive rules are deployed; 271 Flutter tests pass
(one existing skip), with focused navigation regressions and native Android QA.
Normal navigation: 33 states; small/large-text navigation: 36 states including
visible-IME action/FAB proof; shared gutters: 82 states. Not a new 117-state audit.
Release upgrade/install/normal launch and 100% Drive upload are verified:
https://drive.google.com/file/d/1FvT4Xtm14jFKQ0DRJOQ3JA2QlYcAvaA1/view .
APK: 77,436,700 bytes; SHA-256
`B3D2D905C4DACF944600BED19EB5A5866AB96CD2F48628CF97A46331D751ADB9`.
Local builds 24–26 remain unchanged; no Drive delete/move/sharing action was taken.
See `docs/readuo-phone-feedback.md` for evidence and test-scope limits. Wait for
the user's next feedback rather than starting unrelated work.

September 27 corrective delivery: the user resolved the minimum IAM grant;
the bounded eight-function deployment succeeded and all 24 functions are ACTIVE.
Corrected APK `1.17.1+26` is uploaded to the same restricted Drive folder:
https://drive.google.com/file/d/1cMqrH1nqTsXsMbfgqgns3h92H85wqpEG/view .
Size 77,305,628 bytes; SHA-256
`74E13CAC07F31CE79566242AE65369EF449A2835D6EEB15DA3D0060013A7CDD2`.
Package/signer continuity, release install/launch and 100% Drive upload verified.
Builds 24/25 and sharing are preserved. See `docs/readuo-corrective-integration.md`
and the supplemental evidence matrix for bounded UI acceptance and remaining
physical-device/store-signing limits; this is not a new all-117-state pixel audit.

Historical starting point, superseded by the build-26 delivery above:
September 27 corrective integration: build 25 is delivered, but final acceptance
has open gaps. Continue the existing authorized coordination workflow to repair
the audited onboarding, photo-lifecycle, local-cleanup and rendered-evidence gaps.
Build 24 remains the first-milestone delivery. No competing writers or new feature
scope. Existing build-24 account compatibility was validated before stricter rules.

Latest user override (September 21, 2026): **complete P1-15 through P1-18 and
upload an APK to the existing Google Drive folder, then complete P1-19 through
P1-22 and upload a second APK.** Continue automatically between these two
deliveries. Manual-book cover photos remain the final feature. This supersedes
the previous stop after P1-14. Do not claim completion while a required service
or product decision remains unresolved.

Previous user override (September 21, 2026): **complete through P1-14, build and
upload the coordinated APK, then stop and wait before starting P1-15.** P1-15
through P1-22 and the final Phase 1 integration review are not authorized to
start until the user explicitly resumes development. This supersedes the
September 20 automatic continuation instruction and earlier notes below.

Previous user override (September 20, 2026): **resume all remaining Android
Phase 1 items P1-06 through P1-22 and final integration review. Verify each
item, but build and upload ONE final delivery APK after all remaining work is
complete.** This is superseded by the September 21 stop after P1-14.

Previous user override (September 14, 2026): **finish only the current P1-05
scanner/batch-scanning item, verify it, deliver its APK to the existing restricted
Readuo Google Drive folder, and then stop development.** Do not start P1-06 or
any later item until the user explicitly resumes development. The earlier
advance-through-all-items authorization below is superseded by this limit.

On September 14, 2026 the user authorized continuing automatically through the
remaining items: implement one item, verify it, build and upload a separate APK
to the existing Readuo Google Drive folder, then start the next item without
waiting for phone acceptance. Record phone acceptance separately from automated
verification. Never report a feature as complete merely because its UI exists.

This queue covers Android Phase 1. The existing iOS deferral and Phase 2/3
deferrals remain in effect. The canonical 117-state modern handoff and AGENTS.md
remain binding. Manual-book cover-photo capture/selection and Firebase Storage
upload must be the last Phase 1 feature implementation.

For each item:

1. Inspect the specification, canonical states, and current implementation.
2. Implement the bounded item without silently including later queue items.
3. Run meaningful Flutter and backend checks appropriate to the change and
   compare actual rendered screens with the canonical handoff. Preserve auth
   isolation, persistent tab navigation, safe insets, and data invariants.
4. Deploy necessary authorized Firebase changes only after verification;
   preserve unrelated resources and verify the exact query indexes are ready.
   Do not mutate production user data for testing.
5. After ALL remaining items and integration checks, build one uniquely
   versioned APK with increasing versionCode, the existing
   package/signing identity, and the existing local API configuration.
6. Verify package/version/signer and record SHA-256, size, and local path.
7. Upload it to the existing restricted Readuo Drive folder, preserve previous
   builds and sharing settings, and record the file link in the delivery log.
8. Record per-item implementation and verification without claiming APK delivery.
   Continue the next ready item. After final delivery, notify the user and stop.

If a concrete access, billing, device, publishing, or product decision prevents
completion, record the exact dependency and ask only for the missing input.
Continue independent ready items; do not claim a blocked item is complete or
invent user decisions. Do not make purchases or billing upgrades. Do not publish
to an app store under this implementation-and-APK-upload authorization.

## Coordination

- Workspace: `C:\dev\ai\readuo`; app: `app`.
- Existing implementation task: `01a09e3f-db7f-7162-9299-3dbcb4b87788` on `local`.
- Coordination task: `01a09ddd-794a-7273-a914-7674f2c96b4d` on `local`.
- Continue the existing implementation task; do not create duplicate tasks or
  start another writer while an item is active. Inspect its status first.
- Drive folder: https://drive.google.com/drive/folders/1aewUtdN0EfIX8-SlhiHuEfpLy0T1dcCh
- Latest delivered APK: 1.17.0, build 25 (second milestone, P1-19–P1-22).
- Delivery work: requested APK uploads complete. Final acceptance has open gaps
  recorded in `docs/readuo-build25-final-review.md`; this is not only phone QA.
  No duplicate workers or new tasks are needed.

## Ordered remaining items

P1-06 through P1-18 are implemented as of September 21, 2026. The latest
authorization resumes P1-19 through P1-22 after the first milestone upload.

The specification defines acceptance, not the short labels below. Reconcile
each item with existing code before starting; record any already-complete
portion with evidence instead of reimplementing it. A dependency may justify
reordering ready work; record that reason. Keep manual cover photos last.

| ID | Item | Status | APK / dependency |
|---|---|---|---|
| P1-01 | Move one saved book to another own shelf | Delivered | 1.10.0 / 15 |
| P1-02 | Remove one saved book with confirmation | Delivered | 1.11.0 / 16 |
| P1-03 | Complete My Library all-books, sorting, filtering, and search states | Delivered | Corrected 1.12.1 / 18; build 17 preserved |
| P1-04 | Catalogue title/author search and edition selection | Delivered | Corrected 1.13.2 / 21; builds 19 and 20 preserved as superseded |
| P1-05 | Central scanner destination selection and batch entry flow | Delivered | 1.14.0 / 22; analyze clean; 133 Flutter tests; corrected Android sheet/overlay and exact shelf return accepted. STOP after delivery. |
| P1-06 | Complete first-book onboarding and skip/resume flows | Implemented / verified | Durable owner state, deployed strict Rules, rendered QA; no release APK |
| P1-07 | Explore friends' owned books and shelves | Accepted | Owned-only live friend Explore, search/save/revoke coverage, rendered QA; no release APK |
| P1-08 | Public Explore, search, public profiles, and save flows | Accepted | Signed-in Rules-authorized discovery; live visibility/block/ownership checks; rendered QA; no release APK |
| P1-09 | Circle activity feed, automatic events, batch grouping, and home tab | Accepted | Source/emulator accepted; stricter Rules staged for final coordinated release; no per-item APK |
| P1-10 | General/book-attached text posts with drafts and edit/delete | Accepted; staged | Corrected idempotent publication/draft races and missing-document read exception reviewed; 170 Flutter/59 Rules tests; no release APK |
| P1-11 | Reviews and optional star ratings with edit/delete | Accepted / delivered | Included in coordinated 1.15.0 / 23 APK |
| P1-12 | Likes on posts/reviews | Accepted / delivered | Included in coordinated 1.15.0 / 23 APK |
| P1-13 | Comments and author/post-owner moderation controls | Accepted / delivered | Included in coordinated 1.15.0 / 23 APK |
| P1-14 | Circle photo attachment/upload and draft recovery | Accepted / delivered | Included in coordinated 1.15.0 / 23 APK; Storage Rules deployed |
| P1-15 | Basic reports, operator authorization/handling, and content filtering | Implemented | Trusted callables, moderator claim, audited removal, basic threat filter; 25 backend tests |
| P1-16 | In-app notifications and per-type preferences | Implemented | Four event types; server-only creation, live destination checks, independent preferences |
| P1-17 | Android push notifications and permission flow | Implemented | Seven deployed event handlers, rationale/settings, token lifecycle tests; physical-device receipt remains user acceptance |
| P1-18 | Complete Profile, editable profile/photo, and account/support screens | Implemented | Profile/photo editing, support queue and published user-approved contact |
| P1-19 | Provider reauthentication and account deletion/cleanup | Delivered in build 25 | Google reauthentication, resumable server cleanup, stale-token write protection. Permanent deletion including reports/security, no retention. External deletion page live. |
| P1-20 | Explicit read-only own-library offline states | Delivered in build 25 | Isolated own-metadata cache, no offline social data, server transactions prevent queued writes. |
| P1-21 | Real invite links with Android routing and request confirmation | Delivered in build 25 | Owned readuo-b2f24.web.app domain verified by Android, explicit request confirmation. Physical-device end-to-end acceptance pending. |
| P1-22 | Manual-book optional cover capture/selection and Storage upload | Implemented last; delivered in build 25 | Optional camera/gallery, generated fallback, recoverable draft, authenticated private Storage covers, orphan cleanup. |

Metadata/ISBN correction was previously listed as possible remaining work. The
canonical book menu currently contains move/remove only. Reconcile its exact
approved scope before adding any new editing UI; do not silently invent a new
design. Pre-save manual/catalogue metadata correction already exists.

P1-06 review candidate: a new Google-authenticated reader persists owner-scoped
`pending` first-book state before profile completion, then resumes the canonical
first-book screen after restart. Existing readers with no onboarding record
bypass it. Scan, catalogue, and direct manual entry reuse the existing add-book
flows; the first successful save completes onboarding only after a required own
shelf exists. Skip persists `skipped`, account switches reload only the target
UID's state, and saved-book observation safely completes an interrupted final
step. Profile, skip, completion, and book-save failures remain retryable without
discarding entered names or book drafts. Analyze is clean; all 137 Flutter tests
and 47 Firestore Rules emulator tests pass. Actual API 36 Android renders at
390×844 and 360×640 with a real 48px three-button inset are preserved in
`app/test/artifacts/p1-06-review` and were compared with canonical `first-book`
at both viewports. The tested owner-only onboarding Rules were deployed alone
to `readuo-b2f24`; active ruleset
`97320bc4-7c25-466b-bac2-d6d5a727f0d2` matches the local normalized SHA-256
`65c2d2e53cdf31c067147f6a8da7e75b142bb944b1558f5502161a53ee1d7f4d`.
No release APK, version bump, index, API configuration, or production-data write
was made.

P1-07 review candidate: Library Explore now composes accepted-friend, accessible
shelf, and nested `isOwned == true` book streams. Private shelves and not-owned
entries are excluded from queries, cards, search, counts, shelf detail, and book
detail. Friendship removal, privacy revocation, and ownership revocation remove
content live. Search preserves exact friend/shelf/book identity; saving defaults
to Want to read and not owned, requires one own shelf, returns a created shelf,
and reports an existing normalized ISBN without duplicating or resetting it.
Public remains explicitly unavailable for P1-08. Analyze is clean; all 143
Flutter tests and 47 Firestore Rules emulator tests pass. The production index
inventory was read-only verified; this nested single-field query needs no new
composite index. Actual API 36 Android renders at 390×844 and 360×640 with a
real 48px three-button inset are in `app/test/artifacts/p1-07-review` and were
compared with canonical `explore`, `explore-results`, `friend-shelf`,
`friend-book`, and `save-shelf`. No release APK, version bump, Rules/index/API
deployment, or production-data write was made for P1-07. Stop before P1-08.

P1-08 review candidate: signed-in Public Explore uses a minimal shelf directory
and resolves every referenced shelf, profile, and owned nested-book stream
through exact server-authorized reads. Public never grants friendship or Circle
access. Either-direction blocks, shelf privacy/deletion, and ownership changes
remove content live and revoke retained shelf/book/save routes. Exact canonical
ISBN search, multi-owner identity propagation, pending friend-request approval,
duplicate-safe saving, raw-directory pagination metadata, retry,
stale-source removal, and explicit partial-result labeling are covered. The
directory is only a discovery index: every resolved shelf/book read is
authorized independently, so a stale directory ID never grants content access.
Legacy public shelves are indexed from authoritative owner shelf snapshots;
cached snapshots never write, and serialized per-entry transactions revalidate
current shelf state with bounded retries. Analyze is clean; all 149 Flutter
tests and 49 Firestore Rules emulator tests pass. The production index inventory
requires no new composite index. Actual API 36 Android renders at 390×844 and
360×640 with a real 48px three-button inset are in
`app/test/artifacts/p1-08-review` and were compared with canonical
`explore-public`, `explore-results`, `public-profile`, `request-preview`,
`public-shelf`, `public-book`, and `save-shelf`. The tested Rules were deployed
alone to `readuo-b2f24`; local SHA-256 is
`541CA433D0AE44386A6A372411E030F9482A5BFE5DA9FE9F6EC76115E3704C9E`.
No release APK, version bump, index/API change, or production-data write was
made. Stop before P1-09.

P1-09 review candidate: returning authenticated readers now land on Circle after
the existing onboarding gate, while the central scanner remains available from
Circle. The newest-first, pull-to-refresh feed composes accepted friends,
currently shared shelves, all shared books, and immutable nested activity. It
shows canonical populated, empty, loading, partial-error, and retry states. One
scan screen generates one stable batch ID, so eligible owned additions from that
session group into one card. Added events remain ownership-gated, while Reading
and Finished transitions publish for owned and non-owned books when the current
Friends/Public shelf has automatic activity enabled. Want to read, Private, and
disabled changes publish nothing; ownership toggles never publish. Firestore
Rules require the exact activity and book mutation in one transaction, bind one
generated activity ID through `lastActivityId`, reject suppression, forgery,
duplicate/replayed status events, and all event edits, and keep Circle
friends-only even for Public shelves. Every placement has an immutable activity
generation that rotates on moves and re-adds, preventing orphaned nested events
from resurfacing after remove/re-add or move-away/move-back. Private or disabled
sharing hides current-generation activity while inaccessible and may reveal it
again if that same placement is reshared. Unfriend and either-direction block
revoke access. The client records the newest 20 current-generation events per
book and replaces retained listeners on generation or ownership changes. Cloud
Functions API was verified disabled but is not needed for this Rules-proven
transaction design. Analyze is clean; all 157 Flutter tests and 55 Firestore
Rules emulator tests pass. The required `activities` composite index on
`activityGeneration`, `type`, and descending `createdAt` is deployed and
`READY`. Actual API 36 Android renders at 390×844 and 360×640 with a real 48px
three-button inset are in
`app/test/artifacts/p1-09-review` and were compared with canonical `circle` and
`circle-empty`. The required P1-09 activity index is deployed and `READY`, but
the stricter P1-09 Rules are intentionally staged locally until the coordinated
final APK release. Production was restored to the exact build-22-compatible
P1-08 ruleset `35fadc9e-1231-480d-aba3-9f3ac6188152`, SHA-256
`541CA433D0AE44386A6A372411E030F9482A5BFE5DA9FE9F6EC76115E3704C9E`.
An emulator compatibility test proves build-22 add, status, and exact move
payloads remain accepted without `activityGeneration` or activity pointers.
No release APK, version bump, function/API change, billing upgrade, or production
user-data write was made. P1-09 was accepted in source/emulator scope.

P1-10 review candidate: Circle now merges friends-only general text posts with
the existing activity timeline and the author's own posts. New-post drafts are
durable under the authenticated UID, restore after navigation/restart, require
explicit discard, and remain available after failed publication. Each draft owns
an immutable generated post ID; publish creates that exact document and consumes
the draft transactionally, so ambiguous success retries remain idempotent.
Serialized immutable autosaves are flushed or invalidated before terminal
actions, cleanup failures remain visible/retryable, and async completion is
scoped to its originating UID. A post may
attach exactly one current book from the author's own library; Rules verify the
owner/shelf/book identity and copied title, author, and cover at write time.
Authors alone receive edit/delete controls, deletion is confirmed, and failures
retain the source post or draft for retry. Current friendship and either-way
block state gate every friend read; unfriend or block removes the stream live.
Photo posts and reviews were deferred to P1-14 and P1-11 at this review point.
Analyze was clean; all 170 Flutter tests, 59 staged Firestore Rules tests, and the separate
P1-08/build-22 compatibility test pass. Actual API 36 Android evidence at
390×844 and 360×640 is in `app/test/artifacts/p1-10-review` and was compared
with canonical `circle`, `compose`, `attach-book`, `own-post-menu`, `edit-post`,
and `delete-post`. Local staged Rules SHA-256 is
`791575E30564475639972BFC27A3973DA4B3CEE9F9F0D6584C09E807F1700CEB`;
the `circlePosts` composite index and these incompatible Rules remain undeployed
for the final coordinated release. Production still runs the verified P1-08
ruleset above, while the P1-09 activity index remains `READY`. No release APK,
version bump, production user-data write, or new API/billing change was made.
Stop before P1-11.

P1-11 through P1-14 accepted delivery: Circle supports book reviews with optional
star ratings and author edit/delete; deterministic per-user likes on posts and
reviews; live comments with author edit/delete and parent-author moderation; and
single-photo posts selected from camera or gallery. Photo-only publication is
supported. Upload validation limits files to JPEG, PNG, or WebP at 10 MB, stores
owner-scoped versioned paths, and keeps failed uploads and durable drafts
retryable. Draft photo restoration uses authenticated Storage reads rather than
public token URLs. Post deletion removes nested interactions and its photo.
Current friendship and either-direction block checks protect parent content,
likes, comments, and photo reads. Actual API 36 Android evidence at 390×844 is
in `app/test/artifacts/p1-11-review` and `app/test/artifacts/p1-12-14-review`,
including post/review details, comment moderation sheets, photo-source safe
insets, denied upload, restored photo draft, and the release login screen.
Analyze is clean; all 182 Flutter tests and 66 Firestore/Storage emulator tests
pass. Production Firestore Rules, Storage Rules, and the required Circle indexes
were deployed to `readuo-b2f24`; all indexes are `READY`. Local deployed-source
SHA-256 values are `A81A4D2DE82B798D60D4A9321EEF223946BAB6806ADAD0FFE967334D295E777A`
for Firestore Rules and
`3BB72A12CA091238A885324976AF43068DC7ACBC107B4AF26A50750234ECEA8A`
for Storage Rules. No production user data was written. Stop before P1-15.

## Delivery log

September 21 P1-15–P1-18 milestone: uploaded `1.16.0+24` to
https://drive.google.com/file/d/1HvOa81keRQfVhgk_nkti_CO-_TC495RL/view.
APK `app/release/Readuo-1.16.0-build24.apk`, 75,044,499 bytes,
SHA-256 `3a6718e84f3771ada9919b994effbb630281fffbd4013c57ab5aa12d06914e42`.
Existing package and signing certificate verified. Analyze clean, 243 Flutter
tests passed (one opt-in render test skipped), 71 Firestore/Storage Rules tests,
25 backend tests. Eleven gen2 functions ACTIVE; rules/indexes deployed. Actual
API36 profile/edit, notifications/preferences, report/operator detail and release
login reviewed against canonical structure; physical-device push receipt remains
acceptance, not claimed by emulator fixtures. User authorized
`plogramer.dev@gmail.com` moderator/support and permanent deletion with no
report/security retention. P1-19–P1-22 now in progress for second delivery.

September 20 coordinator review: P1-06 first-book onboarding implementation
accepted after source/rules and actual Android layout review. Analyze clean;
137 Flutter tests and 47 Firestore Rules tests passed in the implementation
task. On September 21 the onboarding-inclusive Rules were deployed alone and
their active ruleset identity/content hash was verified without production data
writes. P1-07 through P1-14 were subsequently accepted. P1-11 through P1-14
were delivered together in the coordinated build 23 APK; development is stopped
before P1-15.

| Item | Version / code | Verification | APK |
|---|---|---|---|
| Baseline: persistent navigation and book details/status/ownership | 1.9.0 / 14 | Analyze clean; 80 Flutter tests; 40 Firestore rules tests; rendered QA | https://drive.google.com/file/d/1j2hSqruZ3te8d2wfSF0L0KQGd5zuc7jC/view |
| P1-01: move one saved book | 1.10.0 / 15 | Analyze clean; 81 Flutter tests; 43 Firestore rules tests; canonical `book-menu`/`move-book` rendered at 390×844; production rules deployed; package/version/signer verified | https://drive.google.com/file/d/1lyC7DLT6lnlGvTgfowjf6PnC1kqX24aX/view?usp=sharing |
| P1-02: remove one saved book | 1.11.0 / 16 | Analyze clean; 82 Flutter tests; 46 Firestore rules tests; canonical `book-menu`/`remove-book` rendered at 390×844 with cancel and retained-shelf return; production rules deployed; index inventory and package/version/signer verified | https://drive.google.com/file/d/1Gf3JK__c__mL_NcBbTZABXFDNf211Rt2/view?usp=sharing |
| P1-03: My Library all-books, sorting, filtering, and search | 1.12.0 / 17 | Analyze clean; 89 Flutter tests; canonical `library`, `library-books`, `sort-books`, `library-empty`, `search-results`, `search-empty`, and `filter-empty` rendered at 390×844 and 360×640; production owner-book collection-group index verified; no rules deployment needed; package/version/signer verified | https://drive.google.com/file/d/1y2Jz-WWvFA5Tm7uruBzR0WClDmZ3g_PL/view?usp=sharing |
| P1-03 correction: ISBN query recognition and nested search navigation | 1.12.1 / 18 | Analyze clean; 91 Flutter tests; mixed text/digit ISBN false-positive regressions and valid ISBN-10/13/separator/partial coverage; search→book/shelf→scanner/settings and nested sign-out coverage; corrected search/book/shelf/scanner/settings rendered at 390×844 and 360×640 with a 24px three-button inset; no backend or rules change; package/version/signer verified | https://drive.google.com/file/d/1y-IgSLYj95DK06SfZENGCJrK-_z2inV0/view?usp=sharing |
| P1-04 initial delivery (superseded) | 1.13.0 / 19 | Preserved for audit; coordinator rejected shared pagination/provider state, inferred shelf selection, and unreadable non-production-theme PNG evidence | https://drive.google.com/file/d/12LD40MOWdtxJWxaaaMtq4W_QKvYzoT0c/view?usp=sharing |
| P1-04 correction candidate (superseded) | 1.13.1 / 20 | Preserved for audit; coordinator accepted its core state separation but required cancelled-continuation release and final canonical visual/evidence corrections | https://drive.google.com/file/d/1RwC5hFxliIy6UfQi8ll6ffKJWdIGxFUw/view?usp=sharing |
| P1-04 corrected delivery: catalogue title/author search and edition selection | 1.13.2 / 21 | Analyze clean; 119 Flutter tests; exact cancelled-continuation stale-discard/offset-retry regression; canonical catalogue-only fields, divider rows, generated covers, confirmation controls, prompt/no-results accent marks, and outlined empty-state action; deterministic inspected Android/canonical evidence at 390×844 and 360×640 with real 48px three-button and labeled simulated full-width keyboard insets; no backend, rules, index, API-config, or production-data change; package/version/signer verified | https://drive.google.com/file/d/1rWvAdE4UHolFM8S_SvOgID-ZlQIQfgu7/view?usp=sharing |
| P1-05: central scanner destination selection and batch entry flow | 1.14.0 / 22 | Analyze clean; 133 Flutter tests; coordinator accepted corrected scanner sheets, lifecycle/error/race handling, duplicate detail return, and exact selected-shelf completion; actual API 36 Android evidence at 390×844 and 360×640 with a real 48px three-button inset; release entrypoint and local API configuration used; no backend, rules, index, API-config, or production-data change; package/version/signer/hash/size and fresh install/launch verified | https://drive.google.com/file/d/1wAy5dXILMTRs6kMtY-GJPKxBOoVznOWj/view?usp=sharing |
| P1-06–P1-14 coordinated delivery: onboarding, Explore, Circle activity/posts/reviews/engagement/photo posts | 1.15.0 / 23 | Analyze clean; 182 Flutter tests; 66 Firestore/Storage emulator tests; canonical API 36 Android evidence retained; Firestore and Storage Rules deployed; all required indexes READY; fresh install/launch and package/version/signer/hash/size verified | https://drive.google.com/file/d/1vhP5ip0pop6HgajNEAdvbXSqG2BJSlzf/view?usp=sharing |

P1-05 corrected delivery: scanner shelf and lookup errors are isolated;
live shelf updates and stream failures cannot erase lookup recovery or select a
deleted/locked destination. Covered picker/manual/catalogue/detail routes dispose
the camera surface and reject queued detections. Save snapshots retain the exact
ISBN/result/destination and disable conflicting actions through duplicate and
generic failures. The bounded live picker remains usable with more than ten
shelves at 360×640 plus a 48px Android inset. Duplicate View existing now opens
canonical book detail above the scanner with the one shell navigation bar; Back
returns to the scanner, nested move/sign-out remains safe, cancellation restores
the origin tab, and Done scanning returns the typed selected shelf to Library.
Permission rationale, dedicated manual ISBN, compact loading, generated-cover
confirmation, exactly three status pills, duplicate, not-found, and saved-session
states match the canonical branches. Shelf-origin completion revalidates the
typed destination and switches from shelf A to exact shelf B, while cancellation
retains A. Analyze is clean and all 133 Flutter tests pass. Actual API 36 Android
evidence at 390×844 and 360×640 with an observed
48px three-button bar is in `app/test/artifacts/p1-05-review`; all nine canonical
scanner states were separately captured and visually inspected at both browser
viewports from the unchanged handoff. The signed production artifact is
`C:\dev\ai\readuo\app\release\Readuo-1.14.0-build22.apk`, SHA-256
`49E69F50E9EED85CDD061B39B568723D962636D29A5BCAE701FCBC2A838401DB`,
72,348,790 bytes, package `com.zipdosa.readuo`, version `1.14.0`
(`versionCode` 22), signer certificate SHA-256
`4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
It installed fresh and launched on the API 36 emulator. Drive preserves all
prior APKs and the new file inherits the restricted folder access for owner
Kenny Kim and editor Philip Choi. Physical camera/torch acceptance remains unconfirmed. No
backend, Rules, indexes, API configuration, or production data changed. P1-09
remains responsible for Circle activity and grouped batch events. P1-06 and all
later work remain on hold; development stops after this delivery.

Baseline local artifact: `C:\dev\ai\readuo\app\release\Readuo-1.9.0-build14.apk`.
SHA-256: `3E98E51102984F16B62838E8D54904FA0A5526FD90CF977E9A8013864413361F`.
Size: 71,381,178 bytes. Physical-phone acceptance of this build is unconfirmed.

P1-01 local artifact: `C:\dev\ai\readuo\app\release\Readuo-1.10.0-build15.apk`.
SHA-256: `195536B54B8A9AD04F73BD5BA4565D1AF78AA968BC193802053BEC19C67870E2`.
Size: 71,479,498 bytes. Package `com.zipdosa.readuo`, version `1.10.0`
(`versionCode` 15), and the existing signer certificate were verified. Drive
access remains restricted to owner Kenny Kim and editor Philip Choi. Physical-
phone acceptance of this build is unconfirmed.

Coordinator verification for P1-01: local APK byte count and SHA-256 match the
delivery report; implementation task completed; source/index/count transaction
and strict proof rules reviewed. P1-02 starts automatically after this delivery.

P1-02 local artifact: `C:\dev\ai\readuo\app\release\Readuo-1.11.0-build16.apk`.
SHA-256: `61809ABAF4C1613F69ABAB3292BC3A46674E40826EDB6BD697FB5A3401D3C024`.
Size: 71,692,490 bytes. Package `com.zipdosa.readuo`, version `1.11.0`
(`versionCode` 16), and signer certificate SHA-256
`4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`
were verified. Drive access remains restricted to owner Kenny Kim and editor
Philip Choi. Physical-phone acceptance of this build is unconfirmed. P1-03
was not included in this APK. Coordinator verified the artifact hash/size,
completed task status, and source/count/ISBN-index removal proof before
starting P1-03 automatically.

P1-03 local artifact: `C:\dev\ai\readuo\app\release\Readuo-1.12.0-build17.apk`.
SHA-256: `9D3C9775D74757AFDBD7DA631DE784297F9FBB5EE728109B7AA5C10AF855D56E`.
Size: 71,725,422 bytes. Package `com.zipdosa.readuo`, version `1.12.0`
(`versionCode` 17), and signer certificate SHA-256
`4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`
were verified. Drive access remains restricted to owner Kenny Kim and editor
Philip Choi. Physical-phone acceptance of this build is unconfirmed. P1-04 was
not included in this APK and remains pending coordinator review/start.

Coordinator review of build 17 found an ISBN fallback false-positive for mixed
text/digit queries and requested nested search navigation and Android safe-area
corrections. Those corrections were delivered in build 18; build 17 is preserved.

P1-03 corrected local artifact:
`C:\dev\ai\readuo\app\release\Readuo-1.12.1-build18.apk`.
SHA-256: `2D95979AE16AF7B306D63D1B64312F307D7A5076E2CCCDAB0822A0159CBCBFE0`.
Size: 71,725,422 bytes. Package `com.zipdosa.readuo`, version `1.12.1`
(`versionCode` 18), and signer certificate SHA-256
`4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`
were verified. The original build 17 remains in Drive. Corrected build 18
retains restricted access to owner Kenny Kim and editor Philip Choi. Physical-
phone acceptance is unconfirmed. P1-04 was not included. Coordinator verified
build 18's byte count and SHA-256, inspected the complete-query ISBN guard,
search destination navigation wrappers and regression coverage, and confirmed
the implementation task completed. P1-04 starts automatically after this review.

P1-04 local artifact:
`C:\dev\ai\readuo\app\release\Readuo-1.13.0-build19.apk`.
SHA-256: `DD1422D94E437E096259A5F442BE98E24F3BB45121E1C0BF968EC8DA9EF7667D`.
Size: 71,954,990 bytes. Package `com.zipdosa.readuo`, version `1.13.0`
(`versionCode` 19), and signer certificate SHA-256
`4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`
were verified. Drive access remains restricted to owner Kenny Kim and editor
Philip Choi. Physical-phone acceptance is unconfirmed. No backend, Firestore
Rules, index, or production data change was required. P1-05 is not started.

Build 19 is superseded by the corrected P1-04 delivery below. Its APK and
rejection evidence remain preserved for audit and must not be represented as
the accepted P1-04 build.

Coordinator review of build 19 confirmed artifact hash/size but found blockers
before accepting P1-04: work and edition pagination share offsets/flags and
Back does not restore them; clearing an in-flight query does not invalidate it;
provider selection is not retained for continuation; new-shelf auto-selection
infers an arbitrary new ID instead of using the creation result. Retained QA
PNGs render Ahem block glyphs with the default purple Material theme, so they
do not establish canonical design fidelity. The catalogue/confirmation controls
also need comparison and correction against the agreed handoff. A corrected
build and readable production-theme rendered evidence are required; P1-05 waits.

P1-04 corrected local artifact:
`C:\dev\ai\readuo\app\release\Readuo-1.13.1-build20.apk`.
SHA-256: `275E7A352CB4CEDD3BAC55CAE131FC28FE5F77A565AC1B02D096590473822877`.
Size: 71,954,986 bytes. Package `com.zipdosa.readuo`, version `1.13.1`
(`versionCode` 20), and signer certificate SHA-256
`4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`
were verified. Drive access remains Restricted to owner Kenny Kim and editor
Philip Choi. Corrected Android renders and their matching canonical references
are retained under `app/test/artifacts/p1-04-correction`; rejected Ahem/default-
theme build 19 PNGs are explicitly labeled under
`app/test/artifacts/p1-04-build19-invalid`. This APK predates the final review
source corrections below and remains unaccepted. No backend, Firestore Rules,
index, or production data change was made. Physical-phone acceptance remains
unconfirmed. P1-05 is not started.

Coordinator review of build 20: local hash/size verified; task completed;
exact created-shelf return, sticky provider, clear-query invalidation, and
separate pagination changes inspected. Readable Android and canonical captures
were opened side by side. Remaining deviations include outlined square search
and shelf fields, boxed edition cards instead of divided rows, icon-only cover
fallbacks instead of title covers, and default Material status/switch styling.
Also, entering an Open Library work while a work continuation is pending
invalidates that request but leaves its loading flag set, disabling continuation
after Back. Correct and send readable renders for coordinator review before
building the next corrected APK. This is P1-04 refinement, not P1-05.

Final P1-04 review correction: the cancelled work continuation now releases
its loading flag when a work opens and defensively on Back, without advancing
the offset or accepting the stale page. A regression proves the exact pending
request sequence and retries offset 8. Catalogue-only controls now match the
canonical field, divider-row, generated-cover, cover-size, shelf-selector,
status-pill, switch, prompt/no-results accent-mark, and outlined secondary-action
treatment. Analyze is clean and all 119 Flutter tests pass. Readable Android and
canonical evidence is under
`app/test/artifacts/p1-04-review2`, including real 48px three-button inset
coverage and explicitly labeled simulated full-width keyboard-inset evidence.
The deterministic no-results captures visibly show `Unknown title`, and the
normal-cover fixture uses verified Open Library Piranesi edition `OL28300471M`
with ISBN `9781635575637`. The release entrypoint contains no QA harness or auth
bypass. No backend, Firestore Rules, index, API configuration, or production
data change was made.

P1-04 final local artifact:
`C:\dev\ai\readuo\app\release\Readuo-1.13.2-build21.apk`.
SHA-256: `D03CEB2939CBE5B584A52577E5915561BCE5A96C53BDB769D9291B76BD10FA03`.
Size: 71,971,370 bytes. Package `com.zipdosa.readuo`, version `1.13.2`
(`versionCode` 21), and signer certificate SHA-256
`4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`
were verified. Drive preserves builds 19 and 20 beside build 21 and inherits the
existing restricted folder access for owner Kenny Kim and editor Philip Choi.
Physical-phone acceptance remains unconfirmed. Coordinator verified build 21
size/hash, completed task status, and the corrected readable prompt, no-results,
and matching-cover confirmation captures against the canonical references.
The P1-04 delivery is accepted; P1-05 starts automatically. Subsequent UI items
receive a rendered review before packaging to catch deviations before upload.

## Final readiness and deferred work

### September 27: final milestone implementation and deployment

- P1-19: consent plus fresh Google reauthentication, persisted deletion
  checkpoint, non-cancellable processing, retry/status recovery, and leased
  idempotent server cleanup. Deletes owned data, related reports/security
  records, uploaded files, and finally Auth; no retained deletion tombstone.
  Stale tokens cannot recreate data after the active-account registry is removed.
- P1-20: UID-isolated, explicitly read-only own-book/shelf metadata cache.
  No social content, bearer cover URLs, or uploaded private images in this cache.
  Account switch/sign-out/deletion clears private local state. Android backup
  and device transfer exclude app-private data. Writes require server transactions;
  repeated connectivity callbacks do not reset the online navigator.
- P1-21: strict owned-host invite URLs, cold/warm Android intent handling,
  login/onboarding deferral, explicit friend-request preview, and hosted browser
  fallback. Invite, support, privacy, external deletion page, and assetlinks are
  deployed at `https://readuo-b2f24.web.app`.
- P1-22 was implemented last: optional camera/gallery covers, two-step canonical
  manual-book flow, generated-cover fallback, validation, duplicate review,
  permission/cancellation handling, retained failed-save draft, and Android camera
  process-death recovery. Photos upload only on save to immutable owner-scoped
  Storage paths. Callable reads recheck shelf visibility, friendship, blocks and
  active accounts; no permanent public download links. Independent copies receive
  their own bytes/path. Moves preserve the existing cover; deleted/orphaned covers
  are cleaned up. Uncommitted crash uploads expire after 24 hours; account deletion
  does not wait for this orphan grace period.
- Firebase deployment succeeded: all 20 functions ACTIVE, Firestore/Storage rules
  and indexes deployed, coverStoragePath collection-group index confirmed READY.
  Five existing Auth accounts were registered before stricter rules, preserving
  build-24 sign-in/profile bootstrap compatibility. No production test books,
  accounts, photos, reports, or destructive deletion jobs were created.
- User policy applied: `plogramer.dev@gmail.com` is support/moderator; no retention.
  The exact project's Storage soft-delete duration is 0, with no previously
  soft-deleted objects found; no object versioning/retention policy and Firestore
  point-in-time recovery disabled. This describes application-managed records,
  not a claim to erase Google infrastructure/service logs outside app control.
- Backend tests: 34 passed. Firestore/Storage emulator Rules tests: 73 passed using
  `demo-readuo-shelves`, including stale-token deletion fences, legacy build-24
  schemas, immutable cover uploads, and cross-owner/MIME/pointer rejection.
- Actual Android QA renders were compared with matching canonical deletion,
  offline, invite, manual form, picker and confirmation states. Evidence:
  `app/test/artifacts/p1-19-acknowledgement.png`, `p1-19-21-*.png`,
  `p1-21-invite-corrected.png`, and `p1-22-*.png`. Emulator camera capture returned
  a selected photo; force-stop/relaunch restored the photo and title/author
  (`p1-22-photo-confirm-recovered.png`). The local QA fixture does not write to
  Firebase and was removed from `lib` before packaging the real `main.dart`.
- Physical-phone Google reauthentication/deletion, FCM delivery, and device-specific
  camera/gallery acceptance remain user acceptance checks, not claimed results.
  No destructive production deletion was used for verification.
- Final Flutter suite: 260 passed, one opt-in moderation visual test skipped;
  `flutter analyze` found no issues. Release build uses the normal `lib/main.dart`
  and existing local Google Books configuration. Android release install and cold
  launch succeeded with no Flutter/AndroidRuntime error in the captured log.
  Android reports `readuo-b2f24.web.app: verified`. A separate shell VIEW-intent
  smoke command was blocked by the environment, so end-to-end browser-to-app
  invitation acceptance is not claimed; parser/login-queue tests passed.
- Build 25: `1.17.0+25`, package `com.zipdosa.readuo`, minSDK 24, targetSDK 36.
  File: `C:\dev\ai\readuo\app\release\Readuo-1.17.0-build25.apk`.
  Size: 75,865,027 bytes. SHA-256:
  `3829F3D8FF61C637264D53F27D0DFA8BEFAA52C26EA66092397DEF7B91EC8004`.
  Signature verified; certificate SHA-256:
  `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
  This preserves the earlier APK identity but is the Android Debug certificate,
  not production store signing. Release login screenshot:
  `app/test/artifacts/p1-final-build25-login.png`.
- Google Drive upload verified at 100% / “1 upload complete”; prior build 24
  remains in the same folder. No sharing/permissions were changed.
  Final APK: https://drive.google.com/file/d/1fwUjHVZoLNlehg4RoGZ5gZ47Y5722fT2/view
  First milestone: https://drive.google.com/file/d/1HvOa81keRQfVhgk_nkti_CO-_TC495RL/view
  Proof: `app/test/artifacts/p1-final-drive-upload.png`.

P1-06 through P1-14 were accepted and delivered in Android build `1.15.0`
(`versionCode` 23). The exact signed APK is preserved locally and in the existing
restricted Drive folder; prior builds and sharing remain intact. Its SHA-256 is
`8DAE79CC37D41D60C02965F23EE34C2C872401A818CC3DA2A642966A2AD04462`
and size is 74,007,594 bytes. Package `com.zipdosa.readuo` and signer certificate
SHA-256 `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`
were verified after a fresh install and launch. Physical-phone camera/gallery
acceptance is not implied by emulation. This historical build-23 stopping point
was superseded by the user's two-milestone authorization. P1-15–18 are delivered
in build 24; P1-19–22 and the second APK are delivered in build 25. Support and moderator
account is plogramer.dev@gmail.com; permanent deletion has no retention period.

September 27 bounded final review is recorded in
`docs/readuo-build25-final-review.md`: all 117 canonical IDs are mapped, with
11 current Android captures, 43 historical Android captures, 4 widget-only
captures, 57 exact-state render gaps, and 2 onboarding integration/design gaps.
This inventory is not a fresh all-117 rendered audit. Onboarding photo selection,
active-account profile-photo orphan reconciliation, and profile-picker process
recovery need follow-up; these are not merely production signing/phone limits.
The review also records deletion race/scale and local-cleanup fault-injection
limits. Both APKs remain delivered with unchanged hashes; blanket final readiness
is not established. Accessibility/device acceptance, legal review, moderation
operations, and production signing remain separate release gates.

iOS setup, nearby discovery, offline editing/sync, page progress, export,
advanced moderation, selectable themes, and Phase 3 virtual-library purchases,
decorations, visits/notes, and points remain deferred.
