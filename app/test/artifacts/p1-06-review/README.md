# P1-06 Android review evidence

Generated on 2026-09-20 before coordinator acceptance and without creating a
release artifact. The temporary debug-only launcher used local empty
repositories, no authentication provider, and no production data; its source
was removed after capture.

## Actual Android

`android/` contains direct screenshots from the installed x86_64 debug preview
on the API 36 Android emulator. Android was set to 160 dpi at exact 390×844 and
360×640 framebuffer sizes. UI Automator reported the real three-button system
navigation bar at `[0,796][390,844]` and `[0,592][360,640]`, exactly 48px in
both profiles.

- `first-book-390x844.png` verifies the full canonical first-book state with
  every action visible above the real Android inset.
- `first-book-360x640.png` verifies the compact portrait state without clipped,
  hidden, or overlapping actions.

## Canonical comparison

The unchanged authoritative `design/readuo-first-release.html` was served
locally and its exact `first-book` state was visually inspected in the Codex
in-app browser at 390×844 and 360×640. The Android renders preserve the
canonical title, subtitle, library mark, centered guidance, primary scan action,
outlined catalogue action, manual action, skip action, spacing hierarchy,
colors, and typography. Browser session screenshots were not exported to local
files; the two Android screenshots are the durable evidence.

This review preview is not a versioned APK and is not eligible for upload.
Firestore Rules were tested locally but were not deployed. No index, API
configuration, release version, production data, or production authentication
state changed.
