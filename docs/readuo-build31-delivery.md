# Readuo 1.20.0+31 delivery

## Included and explicitly disabled

Includes the accepted compact Circle layout and doubled feed cover sizes.
Grouped owned-book alerts are **not active**: their source is staged, and the
normal release defaults to `READUO_BOOK_ADDITION_NOTIFICATIONS=false`.
The local release configuration does not contain an override. Four existing
notification settings, legacy token fields and the old inbox remain compatible
with the deployed backend. No new rules/functions/runtime configuration were
deployed; no production test content, pushes or billing changes were made.
See `readuo-book-addition-notifications.md` for separate activation requirements.

## Artifact

- File: `app/release/Readuo-1.20.0-build31.apk`
- Package: `com.zipdosa.readuo`, version1.20.0/code31, minSDK24/targetSDK36.
- Size: 78,032,319 bytes.
- SHA-256: `3088D78FD3F7901F55D9E569603E70EFC977252C6539FC1E0AE1F22A039157F6`.
- Existing Android Debug signer (not store signing):
  `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
- Built with normal `lib/main.dart` and existing local Google Books config;
  no fixture entry point or feature-enable flag.
- Build30 preserved byte-for-byte, SHA-256
  `5A6443C24FE625A2A4B81B3001D40638B8CC7264CCC8BA036F59EEA17FD9CFE6`.

## Verification

- Final analyzer clean. Full Flutter suite299 pass, one existing skip; final
  notification-focused rerun29 pass after the last copy adjustment.
- Backend unit55 pass, two emulator-only skips. Fresh Firestore delivery and
  aggregation emulator12 pass, including out-of-order eligibility timestamps.
- Previously staged rules suite79 pass; rules unchanged in this release pass.
  Port8080 belonged to unrelated Docker, so fresh backend emulator tests used
  isolated demo projects on8086. The temporary emulator config was removed.
- Actual Android notification render/interaction runs pass five states at
  390x844/font1.0 and360x640/font1.3. Four-setting release render compared with
  canonical state97 and accepted gutter override. Enabled staged screens are
  fixtures only, not evidence of a live production feature.
- Existing Circle density11-state normal/small render acceptance retained;
  this is not a fresh full117-state audit.
- Installed build30, upgraded with `adb install -r` to31; first-install time
  remained2026-10-03 15:17:52. Cold launch reports Status:ok and displays normal
  Google sign-in. No AndroidRuntime/Flutter error captured.
- Emulator restored to390x844/density160/font1.0; temporary storage threshold
  removed and reverse forwarding cleared.

Evidence: `app/test/build31-*.log`, `app/test/build31-artifact.json`,
`app/test/artifacts/book-additions/`, `app/test/artifacts/book-additions-small/`,
`app/test/artifacts/readuo-build31-login.png`.

Physical two-phone FCM receipt/background taps remain unverified. iOS deferred.

## Google Drive

Upload verified100% complete in the existing Readuo folder. General access is
Restricted with the existing two collaborators unchanged. No files were deleted
or sharing changed. A fresh folder reload shows build30 alongside31; older27–29
appeared in the initial cached listing but were absent after it refreshed before
upload. Their absence was not caused by this task and no restoration was attempted.

Download: https://drive.google.com/file/d/1nEdSZ6chsgjc3fCYZGqVue1O1SJUE5gS/view

The download page title matches `Readuo-1.20.0-build31.apk`. Evidence:
`app/test/artifacts/readuo-build31-drive-upload.png` and
`app/test/artifacts/readuo-build31-drive-access.png`.
Wait for user feedback; no further feature activation or unrelated work.
