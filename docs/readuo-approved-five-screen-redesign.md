# Approved five-screen redesign

## October 6: approved compact cards, search, and book details

This later scoped approval supersedes conflicting descriptions below, not the canonical prototype. Reference images in the same generated-images directory are Circle `exec-6dfaaad7-9e7e-4d48-8e81-30dda0f4d7c2.png`, Library `exec-4af8fc4d-0569-4682-86fd-188a22711480.png`, and book details `exec-4de8fdd9-035e-4154-9ab2-8b57aeab0918.png`. The user explicitly removed the duplicate upper Write a review action.

- Circle cards have larger covers, authorized live edition information, and tighter engagement spacing while retaining accessible touch targets and the round green icon-only FAB. Own post/review menus offer Delete; other readers' menus offer Report before entering the existing report flow. Automatic reading activity uses the existing author-profile report target; no activity-report backend was introduced.
- Library search expands from the header magnifier and supports clear/cancel. Nonempty searches show richer results without shelf previews or status filters restricting the query; cancel restores the previous filter. Shelf cards, section spacing, and book previews are more compact.
- Book details retain the left-cover/right-title arrangement, add full-width description and ISBN copying, and keep only the lower My review action. Friend details show reader provenance and See more leading to shared shelves, with the existing access checks and safe bottom Add to my library action preserved. Existing navigation and modal shells remain intact.
- Catalogue, scanner, and shared-book copying preserve available description, publisher, and publication year. Missing metadata is stated honestly; no invented genre/page count, retrospective backfill, or expanded offline cache is included.

Validation: 321 Flutter tests passed with one pre-existing skip (`app/test/compact-redesign-tests-complete.log`); analyzer reports no issues (`app/test/compact-redesign-analyze-complete.log`). Native Android checks passed at 390x844/font1.0 and 360x640/font1.3, with rendered screenshots reviewed against the scoped approved references. Evidence is in `app/test/artifacts/approved-redesign-compact/` and `app/test/artifacts/approved-redesign-compact-small/`, with logs `app/test/compact-redesign-native-final.log` and `app/test/compact-redesign-native-small.log`. This uses deterministic fixtures, not a production-data or physical-camera test, and is not a fresh audit of all 117 states.

The initial implementation pass did not build a release APK or deploy a backend. After that QA pass, the emulator was restored to delivered version1.21.2/code34 and 390x844/font1.0. The temporary storage-threshold override was removed; no user data was deleted.

### Requested APK delivery

On October 6, the user requested packaging and upload. Delivered `app/release/Readuo-1.22.0-build35.apk` (78,228,947 bytes), SHA-256 `4426F785C0CDDCDE011483119B5419C089F825F22E0C20EBFF207F8523D3595D`. Package `com.zipdosa.readuo`, version1.22.0/code35, minSDK24/targetSDK36. Signature verification confirms the existing Android Debug signer `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`; signing configuration is unchanged. Built from the normal release entry point with existing local Google Books configuration. Upgrade installation succeeded, cold launch returned Status: ok, the normal Google sign-in screen rendered, and the crash buffer was empty. No production sign-in or backend deployment occurred. The emulator now runs build35; the temporary storage-threshold override was removed.

Google Drive visibly confirmed one completed upload, preserving prior APKs and existing restricted sharing permissions. Download: https://drive.google.com/file/d/1alXeo3yBdS4I1fXVDQ9yAI_9MFsHxOPD/view . Evidence: `app/test/build35-release.log`, `app/test/artifacts/build35-release-launch.png`, and `app/test/artifacts/readuo-build35-drive-upload.png`.

The user approved implementation of the five proposed screen images on October 4, 2026. This is an explicit, scoped override of the corresponding main screens in `design/readuo-first-release.html`. The canonical 117-state handoff remains unchanged and continues to govern other flows.

## Approved references

The approved images are in `C:/Users/realp/.codex/generated_images/01a09e3f-db7f-7162-9299-3dbcb4b87788/`:

- Circle: `exec-c834d091-24a7-4d91-a568-083517fc4621.png`
- Library: `exec-36b5af42-96eb-4952-be20-46a05c874ef3.png`
- Friends, refined: `exec-bb12d2a4-ab21-4b92-90ea-b1292bf068d1.png`
- Profile: `exec-29f3e48b-94b3-4fdd-a8f7-c812776b11d1.png`
- Scanner, refined: `exec-5344955c-06c1-4700-95da-b76a4c6e98ab.png`

## Implementation

- Shared main-screen typography, 16-point gutters, blue primary header actions, and selected navigation icon backgrounds. The central Scan action now has a visible label; it is not an additional persistent tab. Android safe insets and enlarged text remain supported.
- Circle moves Post into the header, retains notifications and compact full-width cards, and places review text and rating beside the cover. Existing engagement, reporting, editing, and large horizontally scrolling added-book covers remain intact.
- Library adds a working add-book header action, underlined My Library/Explore tabs, real library totals, horizontally scrolling shelf previews, and a three-column book grid. Reading-status filters survive tab switches. View all, search, pending shelf operations, privacy badges, and empty/error states remain available.
- Friends moves Invite into the header and separates friends from requests without dropping received or sent request management. Book previews use existing authorized shared-shelf/book streams, only for owned books on non-private, unlocked shelves with automatic activity sharing enabled. Private shelves, revoked access, stream errors, and disabled sharing clear the preview. Other readers receive an honest shared-shelf navigation prompt and placeholder, not invented reading activity.
- Profile displays real Books/Shelves/Friends totals, an invitation strip, and grouped preferences/account/support rows with leading icons and trailing chevrons. Moderator actions, editing, sign-out, and account deletion routes remain available.
- Scanner uses a focused confirmation sheet, a read-only inherited shelf-visibility badge, Add to shelf, Scan again, and manual/catalogue alternatives. Ownership and the three existing reading statuses remain under Book details; batch saving remains available. A successful lookup never automatically saves a book.

## Deliberate implementation constraints

The generated pictures contain illustrative identities, counts, portraits, and cover art. None is hardcoded into production data. Fixtures use deterministic sample books and the app's real missing-cover rendering. Camera capture stops during confirmation; the confirmation header therefore shows a truthful paused-camera context rather than a fabricated live image or a nonfunctional flashlight. Smaller screens scroll rather than shrinking touch targets or removing actions. No page-progress control, extra reading status, or new backend feature was introduced.

The existing Circle draft-whitespace correction and delayed network-reconnection notice are included with this redesign in the subsequently delivered 1.21.0+32 APK. Grouped book-addition notifications remain disabled, and no Firebase functions/rules were deployed. See `readuo-build32-delivery.md` for the artifact, upgrade check, and Google Drive link.

## Validation

Automated coverage includes two viewport/text-scale variants, all Circle card types, shelf-carousel access, retained filters, real profile totals, both request paths, scanner cancellation/explicit save, and live preview privacy revocation.

- Full Flutter suite: 308 passed, one pre-existing skip (`app/redesign-all-tests-final.log`).
- Analyzer: no issues (`app/redesign-analyze-final.log`).
- Final scanner/safe-inset and preview regression run: 19 passed (`app/redesign-safe-insets-final.log`).
- Native Android runs passed at 390x844/density160/font1.0 and 360x640/density160/font1.3. Each records 19 states in `app/test/artifacts/approved-redesign/` and `app/test/artifacts/approved-redesign-small/`; logs are `app/redesign-native-final.log` and `app/redesign-native-small.log`.

The rendered main screens were visually compared against the approved images, including review/cover alignment, shelf previews and filtered grid, friend reading previews, profile settings groups, scanner confirmation, and enlarged-text layouts. Review placement and profile icon placement were corrected after the first render comparison. Scanner fixtures preserve actual Android view padding; the primary action and scrolled book-detail actions stay above the system inset. This is a scoped review of the five approved screens, not a new audit of all 117 canonical states or a physical-device camera/network test.

After native QA, the emulator was restored to the delivered `Readuo-1.20.0-build31.apk` (version1.20.0, code31) and the 390x844/density160/font1.0 baseline. The first restore encountered the emulator's low-storage threshold; retrying with the existing temporary threshold workaround succeeded. The workaround and ADB reverses were then cleared. No user data was deleted to free space.
