# Readuo 1.21.0+32 delivery

Delivered October 4, 2026, after the user requested the approved redesign APK.

## Included and explicitly disabled

- The five approved Circle, Library, Friends, Profile, and Scan redesigns, including Android system insets and enlarged-text layouts. See `readuo-approved-five-screen-redesign.md` for the scoped visual acceptance and references.
- Circle draft whitespace round-trips without a false cross-device modification conflict. Genuine remote changes still conflict; published text remains normalized.
- Brief connection interruptions keep the existing screen/editor mounted, with five seconds of silent recovery, a delayed reconnect notice, and the existing read-only fallback after 30 seconds. Actual write failures and authorization errors are not hidden. See `readuo-reconnect-update.md`.
- Grouped book-addition notifications remain disabled: `READUO_BOOK_ADDITION_NOTIFICATIONS=false` by default, with no local release-config override. No Firebase rules/functions/runtime configuration, production test content, or notification activation was deployed.
- The canonical 117-state handoff is unchanged. iOS remains deferred.

## Artifact

- File: `app/release/Readuo-1.21.0-build32.apk`
- Package: `com.zipdosa.readuo`, version 1.21.0/code 32, minSDK 24/targetSDK 36.
- Size: 78,147,039 bytes.
- SHA-256: `DD5744035FDE35CCB9C49A3F422F5F635D1A7B36247052B50D39279E08EE03E1`.
- Verified APK v2 signature with the existing Android Debug signer, not Play/store signing: `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
- Built with normal `lib/main.dart` and the existing local Google Books configuration, not a fixture entry point.
- Build31 remains unchanged: SHA-256 `3088D78FD3F7901F55D9E569603E70EFC977252C6539FC1E0AE1F22A039157F6`.

## Verification

The implementation pass immediately preceding this packaging pass records 308 passing Flutter tests, one pre-existing skip, and a clean analyzer. Final focused scanner/safe-inset and preview checks record 19 passes. Native Android redesign runs passed at 390x844/font1.0 and 360x640/font1.3, with 19 rendered states per size compared against the approved five-screen references. See `app/redesign-*.log` and `app/test/artifacts/approved-redesign/` / `approved-redesign-small/`. This is not a fresh all-117-state audit or a physical-device camera/carrier-handoff test.

This delivery pass built the normal release successfully and verified package metadata, signature, size, and hash. `adb install -r` upgraded the existing emulator from build31 to32 without clearing application data; first-install time remained `2026-10-04 13:30:02`. Cold launch reports `Status: ok`, shows normal Google sign-in, and remains running. The crash buffer is empty; captured error-priority startup logs contain only Android JDWP/ashmem diagnostics, not Flutter/AndroidRuntime failures. Authenticated production flows were not retested by signing in during this delivery pass.

The emulator retains 390x844/density160/font1.0. Its temporary low-storage install threshold was removed after installation, and ADB reverse forwarding is empty. No user data was deleted to free space.

Evidence: `app/test/build32-*.log`, `app/test/build32-artifact.json`, and `app/test/artifacts/build32-release-launch.png`.

## Google Drive

The existing Readuo folder shows build32 beside builds30 and31. Upload completion reached 100%. General access remains Restricted with the existing owner and one editor; no permissions or old files were changed.

Download: https://drive.google.com/file/d/15ulnBfQILZ5i4hwJMfoG23Ggu60p87Q2/view

The direct page title matches `Readuo-1.21.0-build32.apk`. Upload and access evidence: `app/test/artifacts/readuo-build32-drive-upload.jpg` and `app/test/artifacts/readuo-build32-drive-access.jpg`.

Delivery complete; wait for user feedback before further work.
