# Own-shelf Add book speed dial

## Scope and release boundary

The user's explicit follow-up replaces the Add book bottom sheet with an in-place speed dial. Two smaller actions, Scan ISBN and Enter manually, appear immediately above the existing blue FAB. The main action becomes a close control. Main-toggle, outside tap, Escape, and Android Back collapse it; Back does not leave the shelf. Actions collapse before opening the existing scanner/manual flow with the exact current shelf.

The expanded menu has a route-scoped outside-dismiss layer. When closed there is no barrier or pointer interception. Tab changes and app backgrounding discard expansion; existing shelf/search/status state, tab swipes, navigation, gutters, logo and destinations remain unchanged. The canonical prototype is not modified because this is a later explicit user override.

This is source-only work. Do not build, increment, or upload a new release APK without the user's next request. Latest delivered APK remains `1.18.1+28`; its existing bytes and Drive link must remain unchanged. Debug test builds are permitted only for Android UI verification.

## Verification

Source implementation and verification are complete. Analyzer: no issues. Full Flutter suite: 275 passed, one existing skip. Focused tests cover in-place action geometry and no bottom sheet, toggle/outside/Back/Escape collapse, tab-away collapse, lifecycle collapse and expanded semantics, focus restoration, and exact scanner/manual/catalogue destinations. Closed-state status filtering and final-book clearance still pass.

Actual API36 Android debug runs each pass 13 states: 390x844 at standard text and 360x640 at 1.3 font scale. Native Android Back collapses the dial without leaving the route; both actions still open their real workflows with the exact shelf. The large-text catalogue save button required scrolling the test's lazy list before lookup; no product workaround was introduced.

Evidence directories:
- `app/test/artifacts/shelf-controls-speed-dial/`
- `app/test/artifacts/shelf-controls-speed-dial-small/`

Each contains `manifest.json`, `shelf-add-choices.png` (expanded dial), `shelf-speed-dial-collapsed.png`, and `shelf-last-book-clear.png`, plus the existing flow captures. These are actual Android Flutter captures, compared with the explicitly requested in-place override and unchanged surrounding layout; not a new all-117-state audit. Native screenshots additionally record system bars/keyboard and can contain surface-conversion repaint artifacts.

After QA, the existing delivered APK was reinstalled without rebuilding it. Emulator state is restored to 390x844, font scale1.0, absent stylus-handwriting override and absent storage threshold override; test reverse-port8788 was removed. No production backend data writes, release build, version change, or Drive action occurred.

Existing `app/release/Readuo-1.18.1-build28.apk` SHA-256 remains `659D53FEE321A14BBAFD876D5A640993F93EAF2B010EBC70CA663956C61A2E69`. That delivered APK still contains the earlier bottom-sheet behavior; this source-only follow-up awaits the user's explicit next release request.
# Delivery update

The later user-authorized combined build29 includes this source-only work.
See `docs/readuo-build29-delivery.md`; earlier no-release notes are historical.

