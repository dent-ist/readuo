# Build-26 phone feedback follow-up

## Scope and explicit design overrides

The user's eight phone findings supersede only these canonical details: narrower
12dp outer horizontal gutters; a Circle compose floating action button instead of
the top composer; subtly clearer white Circle cards on a cool background; a
Friends invite floating action button instead of the top invite button; horizontal
swipes between Circle, Library, Friends and Profile. The central scanner remains
an action, not a fifth page. Internal card spacing and Android safe insets remain.
`design/readuo-first-release.html` is unchanged.

## Root causes and repairs

- Circle: each shared book observes its exact optional review. Missing review
  reads previously required an owned draft, so an ordinary book without a review
  raised permission-denied. Read-only production diagnosis found three absent
  reviews and no failed author/activity index queries. No Circle reset or deletion
  is needed. The additive rule permits missing-document gets for the active owner
  or unblocked accepted friend only; existing review privacy and list rules remain.
- Library: Explore disposed the library stream builders and returning re-listened
  to cached single-subscription streams. Keep the library subtree mounted and
  lazily retain visited Explore subtrees. Reset visited state on account/repository
  replacement.
- Navigation: retained per-tab navigators now live in a four-page PageView. Child
  horizontal controls retain gesture priority; edge starts are excluded from tab
  swipes, and fullscreen flows disable tab paging. Nested navigator notifications
  cannot turn off framework Back handling while the shell owns Back dispatch.
- Circle/Friends: primary actions are accessible FABs; feed/list bottom clearance
  prevents the last content row from sitting beneath the action.
- Outer gutters: shared 12dp token applies to page lists, forms, empty/error states,
  modal sheets, auth screens and headers; card-internal padding is retained.

## Validation so far

- Red/green repeated Explore-return regression reproduced and fixed
  `Bad state: Stream has already been listened to`.
- Red/green real Firestore emulator regression reproduced missing-review denial.
- 77 Firestore/Storage rules tests pass, including blocked/inactive/anonymous and
  malformed-id denial, existing private review protection, and a live listener
  changing from a missing review to a private review (permission revoked).
- Firestore-rules-only production deployment succeeded; no function redeployment,
  production test writes, data cleanup, sharing change or billing change.
- 271 Flutter tests pass, one existing skip; analyzer reports no issues.
- New widget navigation regression covers bidirectional four-tab swipes, both FABs,
  repeated Explore return, retained shelf route and scanner Back from every tab
  and a shelf. Platform-channel assertions require framework Back handling and no
  system-exit calls during those flows.

Native Android normal-viewport verification now passes: 33 captured states at
390×844, with a local test-only HTTP/ADB bridge delivering actual Android Back
events during the running test. Coverage includes every central scanner origin,
shelf scanner, manual ISBN entry, unsaved compose veto, canceling its discard
dialog, then discarding successfully. Long Circle/Friends lists prove their last
action/row can scroll above the FAB; the shelf's horizontal status strip does not
change the active main tab. Screenshots are in `app/test/artifacts/phone-feedback/`.
The bridge and synthetic repositories are integration-test-only, not release code.

Actual Circle/Friends renders were compared to their canonical states with the
explicit overrides above; final actions use the existing accent blue. No unrelated
design overhaul or canonical modification. The 360×640 Android run with system
font scale 1.5 also passes (36 states), including a real 299px keyboard inset,
native Back/dialog veto, four-tab swipes, scanner origins, long-list FAB clearance,
and inner horizontal shelf-strip priority. Small captures are in
`app/test/artifacts/phone-feedback-small/`. Emulator size/font were restored and
the local test bridge's ADB reverse was removed after verification.
Flutter screenshots omit native IME pixels; the recorded positive platform inset
and interaction assertions, not the screenshot alone, establish keyboard coverage.
The final run also captures native IME pixels after refreshing the Flutter surface:
`keyboard-compose-action-native.png` shows the Post action above the visible
keyboard without dismissing it, and `keyboard-friends-native.png` shows the invite
FAB above the keyboard. Both have matching 299px-inset assertions. Ten actual
Android Back events cover the navigation/dialog cases in that run.

The shared-gutter sweep also passes: 82 normal-viewport production-widget fixture
states, zero rendering errors, in `app/test/artifacts/phone-gutters/manifest.json`.
The focused `REVIEW_GUTTERS_ONLY` run excludes the original harness's two standalone
onboarding keyboard captures; it is not an all-117-state pixel audit.

The intermittent zero-inset keyboard result was traced to Android's floating stylus
handwriting UI by an actual device screenshot. Docked-keyboard QA temporarily sets
the emulator's `stylus_handwriting_enabled` setting to 0; the original absent setting
is restored afterward. This does not change production app behavior or user data.

Release `1.18.0+27` is built from the normal main entry point with the existing local
Google Books configuration. Package `com.zipdosa.readuo`, minimum SDK 24, target 36,
same Android Debug signer SHA-256
`4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
APK size: 77,436,700 bytes. SHA-256:
`B3D2D905C4DACF944600BED19EB5A5866AB96CD2F48628CF97A46331D751ADB9`.
Build-26 to build-27 upgrade installation succeeds; normal main launches to the
Google sign-in screen with no Flutter/AndroidRuntime error in the captured log.
Proof: `app/test/artifacts/readuo-build27-login.png`; verification logs:
`app/test/phone-feedback-apk-verification.log` and
`app/test/phone-feedback-release-launch.log`.

Drive upload reached 100% and the new file remains listed after reloading:
https://drive.google.com/file/d/1FvT4Xtm14jFKQ0DRJOQ3JA2QlYcAvaA1/view
in the existing Readuo folder. Proof:
`app/test/artifacts/readuo-build27-drive-upload.png`.
Local builds 24–26 retain their recorded SHA-256 hashes. No Drive deletion, move,
replacement or sharing change was issued. The refreshed folder listing currently
shows build 27 only; this delivery does not assert the current location of the
older remote files. All eight requested fixes are delivered; await user feedback.
