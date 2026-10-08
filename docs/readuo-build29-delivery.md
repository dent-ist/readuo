# Readuo 1.18.2+29 combined delivery

The user explicitly authorized building and uploading after the unified
main-tab header work. This supersedes the earlier source-only restriction.

## Included changes

- Own-shelf Add book speed dial: Scan ISBN / Enter manually in place, with
  accessible collapse/back/focus behavior and exact shelf destinations.
- Edge-to-edge Circle cards with distinct top borders across all six kinds.
- Resume recovery: fresh Android network snapshot, invalidated stale checks,
  brief loss grace, active retries and neutral timeout/backend classification.
- Unified Circle / Library / Friends / Profile headers: shared typography,
  alignment, sizing, white background and action style; no title subtitles.

Existing logo assets, shelf filters, navigation and privacy protections remain.
No Firebase functions/rules or production data were changed.

## Verification

- Analyzer clean; 286 Flutter tests passed, one existing skip.
- Headers: real Android renders of all four tabs at 390x844/font1.0 and
  360x640/font1.3. Matching bounds/baselines/styles and account action checked.
  Both sets independently reviewed by the coordinator before packaging.
- Long localized header at 2x wraps and retains a 48dp action. Existing full-shell
  bottom-nav overflow at 2x is documented, not silently presented as passing.
- Earlier source checks: speed dial 13 states per normal/small run; Circle/resume
  12 states per normal/small run with actual Android HOME/resume and controlled
  probes. These are bounded fixture-based checks, not production incident
  reproduction, physical-device acceptance or a new 117-state design audit.
- Normal `lib/main.dart` release build using the existing local API config.
- Existing delivered 28 reinstalled, then upgraded successfully to 29 without
  clearing app data. Normal release launch shows login and the supplied logo;
  no fatal/unhandled application exception in the captured launch log.
- Emulator size 390x844, font 1.0 and original storage threshold restored.

## Artifact

- File: `app/release/Readuo-1.18.2-build29.apk`
- Package: `com.zipdosa.readuo`; versionName 1.18.2; versionCode 29.
- Size: 77,998,651 bytes. Minimum SDK 24 / target SDK 36.
- SHA-256: `13AEA0EDDBF0192AF71A798481B4661AA09994EA9463FCF4120EAB18655A39C1`.
- Existing Android Debug signer retained (not a store-signed release).
  Certificate SHA-256:
  `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
- Download: https://drive.google.com/file/d/1AxSajHB6x8VwG_Zz_-obI2zqVBuQG9Bm/view
- Drive reports one upload complete / 100%; folder reload retains builds 27,
  28 and 29. The uploaded file retains Restricted access and existing folder
  collaborators. No permissions, older files or sharing settings were changed.
- Upload proof: `app/test/artifacts/readuo-build29-drive-upload.png`.
  Access proof: `app/test/artifacts/readuo-build29-drive-access.png`.
  The direct file URL resolves to the new APK title.

Logs: `app/test/build29-analyze.log`, `build29-tests.log`,
`build29-release.log`, `build29-apk-verification.log`, `build29-upgrade.log`,
`build29-release-launch.log`. Rendered evidence:
`app/test/artifacts/tab-headers/`, `tab-headers-small/`, and
`app/test/artifacts/readuo-build29-login.png`.
