# Readuo 1.21.1+33 delivery

Delivered October 4, 2026, after the user requested the updated APK and Google Drive upload.

## Included

- Circle Post FAB in place of the header Post action; redundant friends-only/newest-first subtitle removed without changing audience or ordering.
- Focused composer without the main tab bar, with a pinned Post to Circle / Save changes action above system and keyboard insets. Uploading disables publication; errors remain visible above the action.
- Clearer photo permission/authentication errors. The previously approved production Storage-to-Firestore service-agent role repair remains verified; it also applies to the older build32.
- Existing five-screen redesign, Circle draft-whitespace correction, and brief-network-interruption grace are retained.

See `readuo-circle-composer-feedback.md` for diagnosis, scoped visual acceptance, and tests. Grouped book-addition notifications remain disabled, with no release-config override. No functions/rules deployment, production test upload, notification activation, or further IAM change occurred during this packaging pass. iOS remains deferred.

## Artifact

- File: `app/release/Readuo-1.21.1-build33.apk`
- Package: `com.zipdosa.readuo`, version1.21.1/code33, minSDK24/targetSDK36.
- Size: 78,147,039 bytes.
- SHA-256: `A9F1603D1BB87C3F2412C4813C53E8A710CAE1449A7AEFA6E68BD4265571036E`.
- Verified APK v2 signature with the existing Android Debug signer, not Play/store signing: `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
- Built in release mode from normal `lib/main.dart` using the existing local Google Books configuration, not an integration-test entry point.
- The arm64 AOT library differs from build32; its SHA-256 is `6657EF017B0B1703177C19C8AF7A27051473DB545DD62B1523293F56BB6F2986`.
- Previous build32 is unchanged: SHA-256 `DD5744035FDE35CCB9C49A3F422F5F635D1A7B36247052B50D39279E08EE03E1`.

## Verification

The immediately preceding implementation pass records 313 passing Flutter tests, one pre-existing skip, a clean analyzer, 35 focused tests, four isolated photo-access rules tests, and successful Android rendering/keyboard checks at390x844/font1.0 and360x640/font1.3. These are scoped checks, not a fresh all-117-state audit or a physical-camera production-upload test.

This delivery pass verifies the normal release build, package/version, signer, artifact hash, and upgrade from the existing build32 with `adb install -r`. First-install time remains `2026-10-04 14:04:14`; app data was not cleared. Cold launch reports `Status: ok` and displays the normal Google sign-in screen. The app remains running, the crash buffer is empty, and captured error-priority startup logs contain only Android JDWP/ashmem diagnostics, not Flutter/AndroidRuntime failures. Authenticated production flows were not retested by signing in during this delivery.

Read-only Storage preflight confirms the required cross-service role remains present and the deployed ruleset unchanged. Emulator state remains390x844/density160/font1.0, the temporary storage threshold is removed, and ADB reverse forwarding is empty. No user data was deleted to free space.

Evidence: `app/test/build33-*.log`, `app/test/build33-artifact.json`, `app/test/artifacts/build33-release-launch.png`, and the earlier Circle composer normal/small render directories.

## Google Drive

Upload reached100% in the existing Readuo folder. Build33 is listed beside builds30,31,32. General access remains Restricted with the same owner and one editor. No old file or sharing permission was changed.

Download: https://drive.google.com/file/d/1DC075WEsFiymsm236Q4rfSgY4d7owEIQ/view

The direct download-page title matches `Readuo-1.21.1-build33.apk`. Evidence: `app/test/artifacts/readuo-build33-drive-upload.jpg` and `app/test/artifacts/readuo-build33-drive-access.jpg`.

Delivery complete. Wait for user feedback before further work.
