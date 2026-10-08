# Logo and own-shelf controls update

## Explicit design overrides

The supplied `readuo.svg` replaces the login and launcher brand asset only. The existing blue app theme, navigation glyphs, layout and canonical prototype remain unchanged. Source provenance and deterministic generation are documented in `app/assets/brand/README.md`; iOS assets are generated, not an iOS build or runtime acceptance.

The user's later own-shelf request replaces the three top actions with an Add book FAB (Scan ISBN / Enter manually), a title-area catalogue search and existing ellipsis settings. Catalogue submission opens the existing catalogue flow with the exact current shelf, not a local filter. Closing or backing out of search restores the title and clears its draft.

There is no All status chip. Want to read, Reading and Finished independently toggle, selected statuses combine with OR, and none selected shows all. Small bookmark, open-book and check-circle icons accompany the chips. Global Library filters are unchanged. The shelf maintains 12dp gutters, bottom navigation and scroll padding below books for the FAB. Long destination names ellipsize within the existing manual/catalogue pickers instead of overflowing.

## Verification scope

- Final Flutter suite: 274 passed, one existing skip; analyzer reports no issues.
- Focused shelf tests: all eight filter combinations, no-result and clear-filter recovery; add-sheet cancellation; scanner's exact destination; manual and catalogue writes to that destination with an unrelated shelf first in the repository; search cancellation and draft clearing.
- Asset regeneration: 45 PNGs, all 15 unique iOS catalog files, matching source/font hashes, no text nodes in outlined derivatives, opaque RGB iOS outputs; repeated manifest hash identical.
- No Firebase deployment or production QA data writes for this update. Native flow uses in-memory repositories.

## Native Android verification

API 36 emulator: 11 states at 390x844 and 12 at 360x640 pass, using the actual authenticated shell with in-memory repositories. Native Android Back cancels the add sheet, returns from scanner/catalogue, dismisses the real 299px keyboard, then closes header search without leaving the shelf. Manual and catalogue saves retain the exact destination even with an unrelated first shelf. Status toggling recovers from no results. The small-screen final-book geometry is above the FAB after scrolling to the bottom; the 100px list padding makes its metadata reachable.

Evidence: `app/test/artifacts/shelf-controls/manifest.json` and `app/test/artifacts/shelf-controls-small/manifest.json`. Complete Flutter captures from the Android run are the primary visual evidence; native screencaps additionally prove the keyboard/system bars but can have partial repaint artifacts after surface conversion. Review `shelf-filter-cleared.png`, `shelf-add-choices.png`, `shelf-header-search-native.png`, and the small `shelf-last-book-clear.png`. Horizontal-strip clipping after selecting Finished is the retained scroll offset, not damaged icons; the last-book proof resets the strip to its left edge.

The emulator's 519MB free space was insufficient under Android's default 500MB reserve. Its storage-reserve threshold was temporarily lowered to 64MB for test installation, without deleting other apps or user data. The original absent setting was restored and verified after the final APK installation. Screen size (390x844) and stylus setting (absent) are also restored to their prior values.

## Release verification

- Normal `main.dart` release APK: `app/release/Readuo-1.18.1-build28.apk`, 77,900,343 bytes.
- SHA-256: `659D53FEE321A14BBAFD876D5A640993F93EAF2B010EBC70CA663956C61A2E69`.
- Package `com.zipdosa.readuo`; version code 28; min SDK 24 / target SDK 36.
- Existing Android Debug signer retained: SHA-256 `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`. This is a test-distribution APK, not Play Store signing.
- Previous normal build27 installed, then build28 upgraded with `adb install -r`: success. Normal launch and tapping the actual launcher icon both work; no Flutter/AndroidRuntime error logs.
- Native release evidence: `app/test/artifacts/readuo-build28-login.png` and `app/test/artifacts/readuo-build28-launcher.png`. Login retains build27 layout with only the supplied asset replacement. Pixel launcher circle keeps the wordmark, sun and book recognizable without wordmark clipping.
- Local build27 hash remains unchanged. No backend changes or sharing-permission changes.

Drive upload completed at 100%; both build27 and build28 remain listed after reload. Download: https://drive.google.com/file/d/1xZtd4veai0vHowGGKKfd6tIX-YEK3hNE/view . Existing folder sharing was not changed. Proof: `app/test/artifacts/readuo-build28-drive-upload.png` and `app/test/artifacts/readuo-build28-drive-retained.png`.

This is a bounded review of changed states against the canonical shelf/login plus explicit overrides, not a fresh all-117-state design audit or physical-device/iOS test. Delivery is complete; wait for user feedback before unrelated work.
