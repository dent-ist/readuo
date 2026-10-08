# P1-09 Circle review evidence

Captured September 21, 2026 from the actual Flutter Android app on the API 36
emulator using deterministic friend, shelf, owned-book, and activity fixtures.
The QA-only entrypoint was removed after capture and no release APK or version
bump was produced.

## Viewports

- `circle-390x844.png` and XML: populated, newest-first Circle feed.
- `circle-360x640.png` and XML: compact populated feed without clipping or
  bottom-navigation overlap.
- `circle-empty-390x844.png` and XML: canonical empty state.
- `circle-empty-360x640.png` and XML: compact empty state.
- XML confirms the real Android three-button navigation bar occupies the final
  48 physical pixels at both sizes.

## Canonical comparison

The actual app was compared with the unchanged `circle` and `circle-empty`
states in `design/readuo-first-release.html`. The final implementation preserves
the Circle title/subtitle, notification affordance, composer shell, activity
cards, grouped scan covers, explicit refresh action, empty-state actions, active
Circle tab, central scanner, and Android safe inset. General posts and reviews
remain intentionally deferred to P1-10 and P1-11 rather than represented by
fake backend content.

## Verification

- `flutter analyze`: clean.
- `flutter test`: 157 tests passed.
- Firestore emulator: 55 tests passed.
- Owned additions publish only when the current Friends/Public shelf has
  automatic activity enabled. Reading and Finished transitions publish for
  owned and non-owned books; ownership toggles publish nothing.
- One scanner session supplies one stable batch ID; the feed groups matching
  additions into one card.
- Firestore Rules reject suppressed required events, private/disabled events,
  forged authors, duplicate/replayed status events, and all event edits.
- Public shelves remain friends-only in Circle. Unfriend and block revoke
  access; privacy or automatic-sharing changes hide activity while inaccessible
  and may reveal it if the same placement is reshared.
- Each placement has a generation rotated on moves and re-adds, so orphaned
  activity cannot return after remove/re-add or move-away/move-back. Retained
  listeners are replaced when generation or ownership changes.
- The feed records the newest 20 current-generation events per book. Its
  `activityGeneration` + `type` + descending `createdAt` composite index is
  deployed and `READY`.
- Cloud Functions API is disabled on the project. It is not required by this
  implementation because each book mutation and its immutable event share one
  Rules-proven Firestore transaction.
- The required activity index is deployed and `READY`. The stricter P1-09 Rules
  remain staged locally for the coordinated final APK release because build 22
  does not send generation/event fields. Production was restored to exact P1-08
  ruleset `35fadc9e-1231-480d-aba3-9f3ac6188152`, SHA-256
  `541CA433D0AE44386A6A372411E030F9482A5BFE5DA9FE9F6EC76115E3704C9E`.
- A separate emulator check proves build-22 add, status, and exact move payloads
  remain accepted by production Rules without weakening staged P1-09 guarantees.
- No production user data was written.
