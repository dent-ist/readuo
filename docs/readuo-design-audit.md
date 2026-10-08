# Readuo first-release design audit

## Result

The design handoff is ready to start application development. It is not a claim of production, legal, moderation-operations, Firebase, device-signing, or store-submission readiness. UI/domain scaffolding is unblocked, including the confirmed normalized-ISBN identity boundary.

The corrected fragment contains 117 screens/states in nine groups. The source baseline contained 113; four states were added because they were required but absent: `catalogue-no-results`, `manual-possible-duplicate`, `delete-account-error`, and `content-filtered`.

## Material defects corrected

- Changed the initial screen from Friends to `login` while retaining the complete screen catalog.
- Preserved the avatar fix and added fixed row-avatar geometry plus flexible text constraints; avatars now remain circular across friend, request, notification, profile, comment, and feed contexts.
- Replaced global/hardcoded book state with selected book IDs and consistent library entries. Normalized ISBN is the per-user uniqueness key; ISBN-10 and equivalent ISBN-13 converge, different ISBNs stay separate, and every entry remains on exactly one shelf.
- Propagated selected reader, remote shelf, and selected book through Friends/Public Explore, profiles, menus, and save flows.
- Removed the contradictory scenario where Sarah and Amara were simultaneously accepted friends and pending requests. Incoming, outgoing, accepted, Public-only, and invite-code readers are now distinct.
- Made friend/request/profile/library counts update from state after accept, decline, cancel, remove, block, unblock, save, move, and deletion mutations.
- Made search results correspond to entered text and added explicit no-result routing for personal library, discovery, and catalogue search.
- Made sort and status filters operate on the same sample entries and counts.
- Preserved post, review, and manual-book drafts across rating, attachment, photo, and fallback transitions.
- Made publish/edit/delete and comment edit/delete mutate the visible simulated source instead of showing a toast over contradictory unchanged content.
- Fixed create-shelf return behavior for scan confirmation, manual confirmation, discovery save, and move-all deletion flows.
- Made scan-from-shelf retain its shelf, first-book save require a shelf, batch confirmation keep the shelf, and duplicate scans route to the existing entry.
- Added an explicit no-ISBN possible-duplicate review. Manual entries retain immutable unique IDs and are never silently merged by title/author or assigned an invented ISBN.
- Added explicit sample-state language so the prototype does not claim real camera, barcode, authentication, permission, share-sheet, support, push, or catalogue operations.
- Added linked-provider-only reauthentication and an account-deletion failure state.
- Added privacy propagation wording for shelf moves, ownership changes, friendship removal, blocks, shelf deletion, library-entry removal, reviews, comments, likes, and offline limits.
- Raised interactive target geometry and corrected dark-host contrast for the catalog chrome while keeping the modern phone theme fixed.

## Verification evidence

### Structural/runtime checks

Command: `node C:\dev\ai\readuo\qa\check-readuo.cjs`

- 117 unique screen IDs across nine groups.
- Every screen rendered non-empty content with no `undefined` output.
- Every `data-go` route resolves to a screen and every `data-act` resolves to an action.
- No duplicate element IDs within a rendered screen.
- Login providers, name validation, like/comment state, privacy confirmation, ISBN validation/normalization, same-ISBN prevention, different-ISBN separation, no-ISBN review, deletion acknowledgement, friend filtering/identity, removal count, and avatar CSS invariants passed.
- No `fetch`, XHR, WebSocket, or other network API appears in the fragment.
- Fragment size remains under the 1 MB contract limit.

Generated inventory: `C:\dev\ai\readuo\qa\readuo-screen-inventory.json`.

### Live rendered browser audit

The standalone sandboxed wrapper was loaded in the Codex in-app browser from a read-only localhost server. Direct `file://` loading was rejected by browser security policy; no bypass was attempted.

All 117 states were rendered at each of these dimensions:

| Browser viewport | Measured phone surface | Purpose |
|---:|---:|---|
| 367 × 1000 | 320 px | Minimum supported phone width |
| 437 × 1000 | 390 px | Target modern phone width |
| 784 × 1000 | 390 px phone within 736 px catalog | Full catalog width |

Across 351 rendered state/viewport combinations, automated live-DOM measurement found zero:

- document or phone horizontal overflows;
- visible descendants outside the phone frame;
- clipped headings, labels, buttons, or supporting text;
- actionable controls below 40 px in either dimension, excluding native radio/switch inputs whose wrapping labels are the touch target;
- duplicate IDs; or
- avatars whose width and height differed by more than 1 px.

Manual screenshot inspection covered `login` at 320 px and `friends`, `scanner`, `manual-possible-duplicate`, `private-confirm`, `delete-account`, and `content-filtered` at 390 px. It confirmed readable catalog chrome in a dark host, non-stretched avatars, usable form/action hierarchy, clear simulated-scanner disclosure, legible duplicate/destructive/privacy copy, and retained-draft error treatment. The final browser console error count was zero.

Live interactions additionally verified:

- `login` starts first and Apple routes to `setup` without claiming a real provider call;
- empty display name remains on `setup` with an inline error;
- Friends search for “Tom” returns only Tom Bergen, and the profile/menu destination keeps Tom's identity;
- tapping Sea of Tranquility in Sarah's shelf opens the matching title and owner;
- saving that discovered title creates one Want-to-read entry on one shelf;
- opening the same normalized ISBN again shows “View your library entry” and preserves the existing shelf/status;
- selecting another ISBN for the same title permits a separate entry; and
- a no-ISBN title/author match opens review before a separate uniquely identified manual entry is created.

The live audit summary is recorded in `C:\dev\ai\readuo\qa\render-audit.json`. The browser-control surface did not export its screenshots to workspace files; visual findings were inspected in-session and are documented here.

## Verification limits

- Real camera, photo library, push permission, share sheet, Google/Apple auth, Firebase Security Rules, network failure/retry behavior, catalogue responses, account deletion jobs, moderation operations, and store integrations do not exist in this design artifact and were not claimed as tested.
- The destructive confirmation screens were inspected and their action handlers were structurally tested. No real account, cloud content, permissions, or production data were changed.
- Screen-reader announcements, VoiceOver/TalkBack traversal, dynamic type, localization expansion, physical-device safe areas, reduced motion, and platform-native permission sheets require Flutter implementation and device QA.
- Terms/privacy/community-guideline copy is conceptual, not legal-final.

## Remaining blockers to release

- Final legal/privacy/retention text, published support contact, and Google Play external deletion resource.
- Moderation filtering and staffed timely-response process, escalation/appeal rules, repeat-offender policy, and operator authorization.
- Sign in with Apple token revocation, provider configuration, and deletion-job failure recovery.
- Firebase schema, indexes, Security Rules, emulator tests, observability, backup/restore, and environment separation.
- Catalogue/cover provider selection and rights/rate-limit policy.
- Apple Developer/signing ownership, cloud macOS build path, TestFlight, and company-managed iPhone eligibility.

These are implementation or launch dependencies. None require redesigning the confirmed first-release navigation and screen catalog, but they must be closed before claiming store readiness.
