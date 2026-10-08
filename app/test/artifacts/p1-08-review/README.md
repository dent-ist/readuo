# P1-08 Public Explore review evidence

Captured September 21, 2026 from the actual Flutter Android app on the API 36
emulator using deterministic public-reader, shelf, and book fixtures. The
QA-only entrypoint was removed after capture and no release APK or version bump
was produced.

## Viewports

- `explore-public-390x844.png` and XML: canonical Public Explore at 390×844.
- `explore-public-360x640.png` and XML: compact Public Explore at 360×640.
- XML confirms the real Android three-button navigation bar occupies
  `[0,796][390,844]` and `[0,592][360,640]`, exactly 48 physical pixels.

## Canonical states

- `search-public-390x844.png`: exact-ISBN `explore-results` in Public scope.
- `public-profile-390x844.png`: signed-in public profile and public-shelf count.
- `request-preview-390x844.png`: recipient-approval confirmation with explicit
  bottom safe-area padding.
- `public-shelf-390x844.png`: owned-only, read-only three-column public shelf.
- `public-book-390x844.png`: public discovery summary and exact shelf link.
- `save-public-book-390x844.png`: Want to read, not-owned, one-shelf save picker.

The rendered app was compared against the unchanged `explore-public`,
`explore-results`, `public-profile`, `request-preview`, `public-shelf`,
`public-book`, and `save-shelf` states in
`design/readuo-first-release.html`. The comparison corrected repeated reader
headers and the request sheet's Android bottom inset before final capture.

## Verification

- `flutter analyze`: clean.
- `flutter test`: 149 tests passed.
- Firestore emulator: 49 tests passed.
- Pagination continuation is based on raw directory-page metadata; regression
  coverage includes a viewer-owned first-page entry and a later eligible shelf.
- Directory reconciliation ignores cached shelf snapshots, serializes exact
  shelf rechecks, and uses bounded per-entry transactions with retries.
- Directory entries are discovery hints only. Rules-authorized shelf and book
  reads remain the access boundary even when a stale directory ID exists.
- Production index inventory: no new composite index required.
- Tested Firestore Rules deployed alone to `readuo-b2f24`; local SHA-256
  `541CA433D0AE44386A6A372411E030F9482A5BFE5DA9FE9F6EC76115E3704C9E`.
- No production user data was written.
