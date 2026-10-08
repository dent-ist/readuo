# Circle cards and resume recovery — source-only

Delivery update: the later user-authorized combined build29 includes this work.
See `docs/readuo-build29-delivery.md`; the source-only status below is historical.

Status: source complete; no release build, version bump, backend deployment,
or Drive upload. The delivered APK remains 1.18.1+28 and does not contain
these changes or the preceding source-only shelf speed dial.

## Changes

- Circle general, attachment, photo, review, single activity and batch cards
  have zero horizontal outer margin, 3dp top borders and 1dp bottom borders.
  Existing internal padding, 14dp inter-card gap, header, actions, navigation
  and FAB remain unchanged. The canonical prototype is untouched; this is
  the requested scoped override, not a new full-design audit.
- Resume refreshes Android's current validated-network snapshot and starts a
  fresh server check. Pausing cancels timers and logically invalidates pending
  results; underlying Firestore futures cannot be physically cancelled.
- A brief network-loss hint has a two-second grace period. Periodic/retry
  probes continue to recover even when a network-restored event is missed.
- Timeout/backend errors produce a neutral delayed-check state rather than
  asserting Offline. Auth/permission errors block access. After grace, only
  the current user's saved library is available read-only; no social cache,
  queued writes or offline mutations were added.
- UID switches, logout and deletion retain session invalidation. Late checks
  cannot authorize actions or clear another session's cache.

## Diagnosed code paths

The previous false network flag prevented all subsequent server checks,
including resume and periodic checks. A missed true callback could therefore
latch Offline until restart. Resume also reused pre-pause checks, transient
errors were classified as Offline, and a synchronously failing probe could
leave a completed future latched. Network snapshots were computed before
dispatch to the UI thread. These deterministic paths are covered by tests;
the user's exact production incident was not independently reproduced.

## Verification

- Flutter analyzer: clean. Full tests: 282 passed, one existing skip.
- Six new controller regressions cover stale checks, background timers,
  fresh resume, timeout/backend classification, synchronous failure,
  brief/settled loss, missed recovery events, auth/permission and UID/logout.
- Native Android emulator: 12 captured states at 390x844 and another 12 at
  360x640. Each run passes actual HOME-to-activity resume twice, invokes the
  native network snapshot method, and verifies recovery without restart.
- Native tests use controlled server probes, an in-memory own-user cache
  and a lifecycle observer equivalent to the production boundary wiring.
  They do not exercise a production Firebase account, real radio failure or
  a physical device. The photo fixture is a one-pixel test image.
- Rendered Circle examples were compared with the canonical Circle capture
  and the scoped edge-to-edge override. All six card kinds have automated
  edge/border assertions; normal/small captures show retained header,
  padding and navigation. This is not an all-117-state fidelity certification.
- Evidence: app/test/artifacts/circle-resume/ and circle-resume-small/;
  app/test/circle-resume-analyze.log and circle-resume-all-tests.log;
  app/test/circle-resume-native.log and circle-resume-native-small.log.
- Emulator restored to 390x844, original storage threshold restored, test
  reverse port removed, and the existing delivered build28 reinstalled.

Unchanged release SHA-256:
`659D53FEE321A14BBAFD876D5A640993F93EAF2B010EBC70CA663956C61A2E69`.

Wait for user authorization before a release or further unrelated work.
