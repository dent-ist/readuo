# P1-05 Android review evidence

Generated on 2026-09-14 before versioned delivery packaging. After coordinator
acceptance, the production entrypoint was packaged as `1.14.0` (`versionCode`
22); these captures remain the accepted pre-package review evidence. The temporary
debug-only launcher used fake local repositories and no production data; its
source was removed after capture.

## Actual Android

`android/` contains screenshots from the installed x86_64 debug preview on the
API 36 Android emulator. Android was set to 160 dpi at exact 390×844 and 360×640
framebuffer sizes. UI Automator reported the real three-button system navigation
bar at `[0,796][390,844]` and `[0,592][360,640]`: exactly 48px in both profiles.
No debug banner, Ahem text, or relabeled Flutter-render image is included.

- `permission-rationale-*`, `android-camera-permission-390x844.png`, and
  `camera-denied-*` show rationale before the Android prompt and honest denied
  recovery with phone-settings, ISBN, and catalogue alternatives.
- `destination-*`, `lookup-loading-*`, `confirmation-top-*`, and
  `confirmation-actions-*` show explicit destination choice, compact lookup,
  generated title/author cover, separate shelf selector, owned switch, exactly
  three reading-status pills, and both save actions.
- `duplicate-*`, `isbn-not-found-*`, `manual-isbn-*`, and `saved-*` show the
  non-mutating duplicate branches, manual/catalogue recovery, dedicated ISBN
  entry, truthful batch confirmation, Scan next, and visible Done scanning.
- `manual-isbn-keyboard-simulation-*` is explicitly labeled QA evidence. It is
  a full-width standard Android numeric-keyboard simulation only; all other
  images are direct production-widget Android captures.

The emulator establishes permission-dialog/denial behavior and Android layout,
not physical-camera barcode or torch acceptance. The debug preview is not a
versioned delivery artifact and is not eligible for upload.

## Canonical comparison

The unchanged canonical source `design/readuo-first-release.html` was served
locally and reviewed in the normal Codex in-app browser. The exact states
`camera-permission`, `scanner`, `camera-denied`, `scan-loading`, `scan-found`,
`scan-duplicate`, `manual-isbn`, `isbn-not-found`, and `scan-saved` were each
captured and visually inspected at browser viewports 390×844 and 360×640 in the
implementation task's browser review. The coordinator separately compared the
current source and corrected Android confirmation, duplicate, and saved captures
against canonical `scan-found`. Browser security policy prevented exporting those
session screenshots to local PNGs; no raw protocol, headless-browser, data-URL,
or file-URL workaround was used.

The implementation matches the canonical hierarchy and recovery branches while
omitting the prototype-only sample-barcode control. P1-09 remains responsible
for automatic Circle activity and grouped batch events. P1-05 makes no grouping
claim and changes no backend, Rules, indexes, API configuration, or production
data.
