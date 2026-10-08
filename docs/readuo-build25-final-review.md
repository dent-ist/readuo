# Build 25 bounded final integration review

Date: September 27, 2026. Scope: evidence inventory and targeted source review of the delivered build-25 code. No new device run, backend mutation, canonical change, or APK rebuild occurred for this review.

## Readiness conclusion

Both requested APK deliveries exist. That is **not** full 117-state visual/accessibility or production readiness. The earlier blanket completion wording was too broad: the gaps below remain. This review maps all 117 canonical IDs, but does not claim all 117 were rendered in Flutter or tested on build 25.

Automated baseline remains **260 Flutter passed + 34 backend passed + 73 Firestore/Storage Rules passed = 367 passed**. One opt-in moderation visual test was skipped in the default Flutter suite. Existing widget-golden images are not Android screenshots. Tests were not rerun for this documentation-only review.

## Status legend

- **C**: September 27 Android render exists and was inspected in the milestone session; except login, these use local fixture repositories, not a signed-in production end-to-end flow.
- **H**: earlier Android render exists with historical milestone comparison evidence; not re-rendered on build 25. Older image widgets can have changed since that capture.
- **W**: Flutter widget-golden render with loaded fonts, not an Android capture; default final visual test skipped.
- **U**: no exact trustworthy Android capture mapped. Implementation-family and tests are leads, **not proof of this specific state's implementation, route, fidelity, or accessibility**.
- **G**: source-confirmed integration/design gap, not explained by physical-device testing.

Counts: C=11, U=57, G=2, H=43, W=4; total 117. Invalid build-19/Ahem captures and canonical-only screenshots are excluded. Screens sharing a widget are still listed separately; nearby screenshots are not substituted as exact-state evidence. Native camera permission screenshots do not establish the custom photo-denied state.

All matrix image paths are relative to `C:/dev/ai/readuo/app/test/artifacts/`. Source and test-family paths below are relative to `app/lib/` and `app/test/`. Canonical inventory: `qa/readuo-screen-inventory.json`, cross-checked against unchanged `design/readuo-first-release.html`.

## Implementation/test families

| Group | Source surfaces to inspect | Test family (not a per-state pass claim) |
|---|---|---|
| 01 | screens/login_screen.dart; screens/profile_setup_screen.dart; screens/first_book_onboarding_screen.dart; profile/information_screen.dart | widget_test.dart |
| 02 | screens/circle_screen.dart; screens/circle_post_composer_screen.dart; screens/circle_review_composer_screen.dart; moderation/moderation_screens.dart; notifications/notification_screens.dart | circle_test.dart; circle_engagement_test.dart; review_test.dart; moderation_test.dart; notifications_test.dart |
| 03 | screens/my_library_screen.dart; screens/library_books_screen.dart; screens/shelf_details_screen.dart; screens/book_details_screen.dart | widget_test.dart; library_books_test.dart; book_details_test.dart; manual_book_test.dart |
| 04 | screens/friends_explore_screen.dart | friends_test.dart; book_repository_test.dart |
| 05 | screens/isbn_scanner_screen.dart; screens/catalogue_search_screen.dart; screens/manual_book_flow.dart | isbn_scanner_test.dart; catalogue_search_screen_test.dart; manual_book_test.dart; book_cover_photo_test.dart |
| 06 | screens/friends_screen.dart; friends/invite_link_screen.dart; friends/invite_links.dart | friends_test.dart; p1_19_21_test.dart |
| 07 | screens/account_screen.dart; profile/edit_profile_screen.dart; profile/support_screens.dart; account_deletion/account_deletion_screen.dart | profile_test.dart; profile_repository_test.dart; p1_19_21_test.dart |
| 08 | offline/offline_library_screens.dart; moderation/moderation_screens.dart; notifications/notification_screens.dart; shared feature error branches | p1_19_21_test.dart; moderation_test.dart; notifications_test.dart |
| 09 | moderation/moderation_screens.dart | moderation_test.dart; moderation_visual_test.dart (opt-in) |

## Canonical state matrix

| # | Group | Canonical ID | Status | Render evidence or explicit limit |
|---:|---|---|---|---|
| 1 | 01 | `login` | C | p1-final-build25-login.png |
| 2 | 01 | `login-error` | U | Unverified exact-state Android render; see group source/test family. |
| 3 | 01 | `setup` | G | No exact render mapped; onboarding is a name/provider-avatar form, not the canonical setup shell. |
| 4 | 01 | `profile-photo` | G | No onboarding photo-picker route; existing-account Edit Profile has a separate picker. |
| 5 | 01 | `first-book` | H | p1-06-review/android/first-book-390x844.png |
| 6 | 01 | `terms` | U | Unverified exact-state Android render; see group source/test family. |
| 7 | 01 | `privacy` | U | Unverified exact-state Android render; see group source/test family. |
| 8 | 02 | `circle` | H | p1-09-review/circle-390x844.png |
| 9 | 02 | `circle-empty` | H | p1-09-review/circle-empty-390x844.png |
| 10 | 02 | `compose` | H | p1-10-review/compose-corrected-390x844.png |
| 11 | 02 | `compose-photo` | H | p1-12-14-review/photo-source-sheet-safe-390x844.png |
| 12 | 02 | `attach-book` | H | p1-10-review/attach-book-corrected-360x640.png |
| 13 | 02 | `review` | H | p1-11-review/write-review-390x844.png |
| 14 | 02 | `post` | H | p1-10-review/post-390x844.png |
| 15 | 02 | `post-menu` | U | Unverified exact-state Android render; see group source/test family. |
| 16 | 02 | `own-post-menu` | H | p1-10-review/own-post-menu-390x844.png |
| 17 | 02 | `edit-post` | H | p1-10-review/edit-post-corrected-390x844.png |
| 18 | 02 | `delete-post` | H | p1-10-review/delete-post-390x844.png |
| 19 | 02 | `comment-menu` | U | Unverified exact-state Android render; see group source/test family. |
| 20 | 02 | `own-comment-menu` | H | p1-12-14-review/own-comment-menu-390x844.png |
| 21 | 02 | `owner-comment-menu` | H | p1-12-14-review/owner-comment-menu-safe-390x844.png |
| 22 | 02 | `edit-comment` | U | Unverified exact-state Android render; see group source/test family. |
| 23 | 02 | `delete-comment` | U | Unverified exact-state Android render; see group source/test family. |
| 24 | 02 | `report` | H | p1-15-report-android.png |
| 25 | 02 | `report-sent` | W | p1-15-review/report-sent.png |
| 26 | 02 | `notifications` | H | p1-18-notifications-android.png |
| 27 | 02 | `notifications-empty` | U | Unverified exact-state Android render; see group source/test family. |
| 28 | 03 | `library` | H | p1-07-review/library-390x844.png |
| 29 | 03 | `library-books` | U | Unverified exact-state Android render; see group source/test family. |
| 30 | 03 | `sort-books` | U | Unverified exact-state Android render; see group source/test family. |
| 31 | 03 | `library-empty` | U | Unverified exact-state Android render; see group source/test family. |
| 32 | 03 | `search-results` | U | Unverified exact-state Android render; see group source/test family. |
| 33 | 03 | `search-empty` | U | Unverified exact-state Android render; see group source/test family. |
| 34 | 03 | `filter-empty` | U | Unverified exact-state Android render; see group source/test family. |
| 35 | 03 | `shelf` | U | Unverified exact-state Android render; see group source/test family. |
| 36 | 03 | `shelf-empty` | U | Unverified exact-state Android render; see group source/test family. |
| 37 | 03 | `create-shelf` | U | Unverified exact-state Android render; see group source/test family. |
| 38 | 03 | `shelf-settings` | U | Unverified exact-state Android render; see group source/test family. |
| 39 | 03 | `private-confirm` | U | Unverified exact-state Android render; see group source/test family. |
| 40 | 03 | `delete-shelf` | U | Unverified exact-state Android render; see group source/test family. |
| 41 | 03 | `move-all` | U | Unverified exact-state Android render; see group source/test family. |
| 42 | 03 | `delete-shelf-confirm` | U | Unverified exact-state Android render; see group source/test family. |
| 43 | 03 | `book` | U | Unverified exact-state Android render; see group source/test family. |
| 44 | 03 | `saved-book` | U | Unverified exact-state Android render; see group source/test family. |
| 45 | 03 | `book-menu` | U | Unverified exact-state Android render; see group source/test family. |
| 46 | 03 | `reading-status` | U | Unverified exact-state Android render; see group source/test family. |
| 47 | 03 | `move-book` | U | Unverified exact-state Android render; see group source/test family. |
| 48 | 03 | `remove-book` | U | Unverified exact-state Android render; see group source/test family. |
| 49 | 04 | `explore` | H | p1-07-review/explore-390x844.png |
| 50 | 04 | `explore-public` | H | p1-08-review/explore-public-390x844.png |
| 51 | 04 | `explore-results` | H | p1-07-review/search-390x844.png |
| 52 | 04 | `explore-empty` | U | Unverified exact-state Android render; see group source/test family. |
| 53 | 04 | `explore-no-results` | U | Unverified exact-state Android render; see group source/test family. |
| 54 | 04 | `friend-shelf` | H | p1-07-review/friend-shelf-390x844.png |
| 55 | 04 | `public-shelf` | H | p1-08-review/public-shelf-390x844.png |
| 56 | 04 | `friend-book` | H | p1-07-review/book-sheet-390x844.png |
| 57 | 04 | `public-book` | H | p1-08-review/public-book-390x844.png |
| 58 | 04 | `save-shelf` | H | p1-07-review/save-sheet-390x844.png |
| 59 | 04 | `book-saved` | U | Unverified exact-state Android render; see group source/test family. |
| 60 | 04 | `unavailable` | U | Unverified exact-state Android render; see group source/test family. |
| 61 | 04 | `public-profile` | H | p1-08-review/public-profile-390x844.png |
| 62 | 05 | `camera-permission` | H | p1-05-review/android/permission-rationale-390x844.png |
| 63 | 05 | `scanner` | H | p1-05-review/android/destination-390x844.png |
| 64 | 05 | `camera-denied` | H | p1-05-review/android/camera-denied-390x844.png |
| 65 | 05 | `scan-loading` | H | p1-05-review/android/lookup-loading-390x844.png |
| 66 | 05 | `scan-found` | H | p1-05-review/android/confirmation-top-390x844.png |
| 67 | 05 | `scan-duplicate` | H | p1-05-review/android/duplicate-390x844.png |
| 68 | 05 | `manual-isbn` | H | p1-05-review/android/manual-isbn-390x844.png |
| 69 | 05 | `isbn-not-found` | H | p1-05-review/android/isbn-not-found-390x844.png |
| 70 | 05 | `catalogue-search` | H | p1-04-review2/app/catalogue-prompt-390x844.png |
| 71 | 05 | `catalogue-results` | H | p1-04-review2/app/catalogue-editions-390x844.png |
| 72 | 05 | `catalogue-no-results` | H | p1-04-review2/app/catalogue-no-results-390x844.png |
| 73 | 05 | `manual-book` | C | p1-22-manual-form.png |
| 74 | 05 | `book-photo` | C | p1-22-cover-final-sheet.png |
| 75 | 05 | `manual-confirm` | C | p1-22-photo-confirm-recovered.png |
| 76 | 05 | `manual-possible-duplicate` | U | Unverified exact-state Android render; see group source/test family. |
| 77 | 05 | `scan-saved` | H | p1-05-review/android/saved-390x844.png |
| 78 | 05 | `photo-denied` | H | p1-12-14-review/photo-denied-390x844.png |
| 79 | 06 | `friends` | U | Unverified exact-state Android render; see group source/test family. |
| 80 | 06 | `friends-empty` | U | Unverified exact-state Android render; see group source/test family. |
| 81 | 06 | `invite` | C | p1-21-invite-corrected.png |
| 82 | 06 | `enter-code` | U | Unverified exact-state Android render; see group source/test family. |
| 83 | 06 | `invalid-code` | U | Unverified exact-state Android render; see group source/test family. |
| 84 | 06 | `request-preview` | H | p1-08-review/request-preview-390x844.png |
| 85 | 06 | `request-sent` | U | Unverified exact-state Android render; see group source/test family. |
| 86 | 06 | `requests` | U | Unverified exact-state Android render; see group source/test family. |
| 87 | 06 | `request-detail` | U | Unverified exact-state Android render; see group source/test family. |
| 88 | 06 | `sent-requests` | U | Unverified exact-state Android render; see group source/test family. |
| 89 | 06 | `friend-profile` | U | Unverified exact-state Android render; see group source/test family. |
| 90 | 06 | `profile-menu` | U | Unverified exact-state Android render; see group source/test family. |
| 91 | 06 | `remove-friend` | U | Unverified exact-state Android render; see group source/test family. |
| 92 | 06 | `block-friend` | U | Unverified exact-state Android render; see group source/test family. |
| 93 | 06 | `blocked-users` | U | Unverified exact-state Android render; see group source/test family. |
| 94 | 06 | `unblock` | U | Unverified exact-state Android render; see group source/test family. |
| 95 | 07 | `profile` | H | p1-18-profile-android.png |
| 96 | 07 | `edit-profile` | H | p1-18-edit-android.png |
| 97 | 07 | `notification-settings` | H | p1-18-notification-settings-android.png |
| 98 | 07 | `account` | U | Unverified exact-state Android render; see group source/test family. |
| 99 | 07 | `delete-account` | C | p1-19-acknowledgement.png |
| 100 | 07 | `reauth` | C | p1-19-21-verification.png |
| 101 | 07 | `deleting` | C | p1-19-21-processing.png |
| 102 | 07 | `delete-account-error` | C | p1-19-21-paused.png |
| 103 | 07 | `account-deleted` | C | p1-19-21-completed.png |
| 104 | 07 | `signout` | U | Unverified exact-state Android render; see group source/test family. |
| 105 | 07 | `support` | U | Unverified exact-state Android render; see group source/test family. |
| 106 | 07 | `support-message` | U | Unverified exact-state Android render; see group source/test family. |
| 107 | 08 | `offline-library` | C | p1-19-21-offline.png |
| 108 | 08 | `offline-book` | U | Unverified exact-state Android render; see group source/test family. |
| 109 | 08 | `offline-action` | U | Unverified exact-state Android render; see group source/test family. |
| 110 | 08 | `network-error` | U | Unverified exact-state Android render; see group source/test family. |
| 111 | 08 | `feed-loading` | U | Unverified exact-state Android render; see group source/test family. |
| 112 | 08 | `save-error` | U | Unverified exact-state Android render; see group source/test family. |
| 113 | 08 | `content-filtered` | W | p1-15-review/content-filtered.png |
| 114 | 08 | `notification-permission` | U | Unverified exact-state Android render; see group source/test family. |
| 115 | 09 | `moderation` | H | p1-15-moderation-android.png |
| 116 | 09 | `report-detail` | W | p1-15-review/report-detail.png |
| 117 | 09 | `moderation-action` | W | p1-15-review/moderation-action.png |

## Actual Phase 1 gaps found

1. **Onboarding setup/photo integration:** `app/lib/screens/profile_setup_screen.dart:88` shows the provider avatar, a differently structured “Finish your profile” name form, and no Add photo control/route. The canonical `setup` and `profile-photo` path is therefore not implemented as handed off. Existing-account photo editing in `profile/edit_profile_screen.dart` does not close this onboarding gap. A rendered repair/comparison is needed; source inspection alone is not a fidelity judgment.
2. **Profile-photo orphan reconciliation:** `app/lib/profile/INTEGRATION.md` explicitly calls for a backend sweep comparing both Auth photoURL and readerProfiles after process death/ambiguous saves/failed replacement cleanup. The deployed index exports an orphan sweep only for **book covers**. `firebase_profile_repository.dart` deletes previous photos on ordinary success and attempts cleanup after definite failures, but this is not crash reconciliation. Account deletion removes the entire profile-photo prefix; this gap concerns still-active accounts. Classify as media-lifecycle hardening/integration work, not a phone-only limitation.
3. **Profile camera recovery:** `DeviceProfilePhotoPicker` calls `ImagePicker.pickImage`; no `retrieveLostData` path or durable edit-profile draft is present in that flow. The camera process-recreation fix proven for manual book covers does not cover profile editing. Reproduce with the profile flow before declaring device-loss acceptance; do not generalize the book-cover proof.
4. **Unverified state fidelity/accessibility:** U rows are genuine review gaps. They are not automatically missing features, but cannot be counted as completed canonical acceptance. No build-25 TalkBack order/announcements, enlarged-text sweep, contrast/target-size measurement across all 117 states, or complete small-screen/keyboard sweep has been performed.

## Targeted deletion/offline/cover risk review

| Area | Evidence reviewed / protection | Residual boundary or follow-up |
|---|---|---|
| Deletion authorization | `functions/deletion/policy.js` enforces exact consent payload, Google provider and fresh auth_time; begin transaction removes activeAccounts with the job marker. Rules tests include stale-token recreation denial. | Real linked-provider reauth/cancellation and deletion on a disposable phone account remain unrun; no production user was deleted. |
| Deletion retries and scope | `deletion/service.js:37` leases work, checkpoints cursor/pendingPath, recursively removes owned/related roots, then all three media prefixes, then Auth and job records. Retry fixture tests passed. | Collection-group sweeps scan global datasets. Large-volume duration/cost and concurrent privileged-writer/in-flight-upload races are not stress-proven. A finite sweep is not proof against a privileged write arriving after that group was scanned. |
| No retention | Bucket soft-delete duration 0, no old soft-deleted objects found, no object retention/versioning, Firestore PITR off; reports/security groups included. | This is app-managed deletion policy, not a guarantee about Google infrastructure logs, other users' independent copies, or offline devices that never reconnect. |
| Local deletion clearing | `features/account_session_boundary.dart:181` clears image cache, manual draft and offline cache on completion; sign-out clears session data; Android backup/transfer disabled. | Completion uses unawaited cleanup. Disk/plugin failure handling has not been fault-injected; `_restore` awaits draft clearing before its guarded backend block. Do not claim guaranteed local erasure under storage failure. |
| Offline isolation | Explicit owner-only metadata serialization strips image URLs, uses server-confirmed captures, clears on UID switch/sign-out/blocked probe, and replaces the social navigator. Duplicate network events no longer reset it. | Tested controller/widget behavior, not prolonged physical airplane-mode/reconnect acceptance. An already-offline device cannot learn of remote deletion until reconnect. |
| Book cover authorization | `functions/covers.js:11` checks both active accounts, blocks, current shelf visibility/ownership and friendship before bytes; no public download token. Rules enforce owner-scoped immutable uploads. | Already-rendered pixels cannot be retroactively unseen. `BookCoverImage` reloads on URL change, not a timer; parent access-revocation navigation/listener behavior still needs live multi-device review. |
| Book cover lifecycle | Create uploads then uses a transaction; ambiguous save cleanup checks server book reference before deletion. Copy gets a new owner path, moves retain references; deleted-book trigger checks references; orphan sweep has 24-hour grace. | Crash orphan objects may last until the next daily sweep after grace, not exactly 24 hours. Concurrent very-long uploads/saves versus cleanup not stress-tested. No production image was uploaded as a test. |
| Manual camera draft | Per-UID persisted photo/text; serialized writes; completion/account change clears; emulator force-stop/reopen restored bytes and title/author. | This proof is specific to manual books; profile and post picker process-death paths require separate evidence. |

## Device/store limitations (not missing feature coding by themselves)

- Physical camera barcode/torch, OEM gallery/permission behavior, real push delivery/deep-link return, and external invite-to-login-to-request acceptance.
- Android domain was verified. The separate shell VIEW-intent smoke command was blocked; parser/queue tests are not an end-to-end browser acceptance test.
- APKs preserve the existing Android Debug certificate. Production keystore/store release, legal review, operational moderation/support staffing, and iOS remain outside delivered private-APK readiness.
- First-milestone and final APK hashes/links remain unchanged in the queue. No canonical file, app code, deployed backend, permissions, or APK was changed for this review.

## Closure criteria

Resolve/verify onboarding photo integration and active-account profile-media lifecycle, disposition the U rows with actual rendered evidence or explicit user-approved deviations, and perform physical/accessibility acceptance. Until then report **“requested APK milestones delivered; final acceptance has open gaps,”** not “all 117 states fully verified.” Do not silently reinterpret the canonical handoff or mark unverified rows as passing.

