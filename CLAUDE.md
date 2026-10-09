# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` holds binding design-fidelity rules (the canonical UI handoff is `design/readuo-first-release.html`, plus a list of explicit user overrides for navigation, Library, Explore, and bookshelf addition). Read it before any UI work and compare rendered app state against the matching canonical state; don't edit the prototype to justify a deviation.

## Repository layout

- `app/` – the product: a Flutter Android app (`com.zipdosa.readuo`, Firebase project `readuo-b2f24`) with its Firebase backend.
  - `lib/` – Dart client; `test/` – widget/unit tests; `integration_test/`, `test_driver/` – device tests.
  - `functions/` – Cloud Functions (Node 22, CommonJS, `firebase-functions` v2 plus a few v1 auth triggers).
  - `rules-tests/` – Firestore/Storage rules tests (Node, run against the emulator).
  - `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json` – backend config. The other `firebase.*.json` files are one-off variants; `firebase.json` is the default.
  - `hosting/` – static site (invite links, privacy, support, delete-account, `.well-known/assetlinks.json`).
- `design/` – canonical design handoff HTML (117 states). `qa/` – Node scripts that validate the prototype against `docs/` and generate brand assets (`node qa/check-readuo.cjs`).
- `docs/` – dated delivery/spec notes. `docs/readuo-implementation-queue.md` is the running status log (newest first); `docs/readuo-first-release-spec.md` and `readuo-design-audit.md` are the product spec.
- `app/README.md` is a long, detailed feature/behavior log; consult it for the contract of a specific feature before changing it.

## Commands

Run Flutter commands from `app/`:

```
flutter pub get
flutter analyze
flutter test                          # whole suite
flutter test test/isbn_test.dart      # single file
flutter test --plain-name "substring" # single test by name
```

Release APK (the Google Books key is injected at build time from an ignored local file; a plain `flutter build apk` omits it, and hot reload does not update an installed APK):

```
flutter build apk --release --dart-define-from-file=config/google-books.local.json
```

Cloud Functions tests (from `app/functions/`): `npm test` (`node --test test/*.test.js`). The `*_emulator.test.js` files need the Firestore emulator.

Rules tests (needs Java for the emulator; uses a `demo-*` project and never touches production):

```
npm --prefix rules-tests install
firebase emulators:exec --only firestore --project demo-readuo-shelves "npm --prefix rules-tests test"
```

Deploy rules only after tests pass: `firebase deploy --only firestore:rules --project readuo-b2f24`. The web build is a local UI preview only; `firebase_core_web` is pinned to `3.10.0` for the workspace's Flutter 3.41.6 toolchain.

## Architecture

**Identity and routing.** Firebase UID is both the account and the library owner. Auth state owns the root navigator (`auth/auth_gate.dart`): logout, session loss, or UID switch must dispose every authenticated route, dialog, sheet, and user-scoped state (`features/account_session_boundary.dart`). New Google users pass an owner-scoped first-book onboarding gate (`onboarding/`, `users/{uid}/onboarding/firstBook` with status `pending|skipped|completed`) before reaching the shell. Never let one UID's state leak into another.

**Dependency injection by constructor.** `ReaduoApp` in `lib/main.dart` takes optional repositories/services (auth, shelf, book, lookup, catalogue, circle, review, engagement, photo, friend, onboarding). Production defaults are Firebase-backed; tests inject fakes/in-memory doubles, which is why most tests need no emulator. Follow the same pattern: an abstract repository interface plus a Firebase implementation, with the screen receiving the interface.

**Feature modules under `lib/`:** `library` (shelves, books, ISBN, lookup, catalogue), `circle` (feed posts, reviews, engagement, photos), `friends` (private connections, invite links), `notifications`, `moderation`, `profile`, `account_deletion`, `offline` (read-only cached library fallback), plus `screens/` (full-screen UIs, `authenticated_shell.dart` hosts the four-tab shell), `widgets/`, and `theme/readuo_theme.dart`. `moderation/`, `notifications/`, and `profile/` each contain an `INTEGRATION.md` describing the wiring contract for that isolated module; read it before changing how it connects.

**Book lookup pipeline.** ISBN-10/13 are canonicalized (`library/isbn.dart`); Open Library is queried first, and Google Books is used only after a *successful* Open Library no-match (network/timeout/service failures stay retryable and don't fall back). Google results must contain an ISBN that canonicalizes to the requested edition. No record is created until the user verifies the edition. Stored cover URLs are restricted to `covers.openlibrary.org` or Google Books' exact content path; covers can also be cached server-side by the `loadBookCover` function.

**Writes require server confirmation.** Online-only writes go through `features/online_writes.dart` and callables; the app shows a "Reconnecting" notice after a 5-second grace and falls back to read-only offline mode after 30 seconds of sustained failure. Don't treat optimistic local writes as saved.

**Backend split.** Security-sensitive or cross-document work lives in Cloud Functions (`functions/index.js` wires exports; logic is in `accounts.js`, `book_additions*.js`, `covers.js`, `notification_*.js`, `profile_media.js`, `deletion/`, `moderation/`; each of `deletion/` and `moderation/` splits `policy.js` / `service.js` / store). Policy modules are pure and unit-tested; `index.js` only wires them to triggers. Firestore data is guarded by `firestore.rules` and exercised by `rules-tests/`; changing a collection shape usually means updating rules, rules tests, indexes, and the client repository together.

**Product constraints to preserve** (details in `AGENTS.md`/`app/README.md`): reading status is exactly Want to read / Reading / Finished with no page progress; bottom nav is Circle, Library, Friends, Profile; Android uses Google sign-in only (iOS deferred); bottom actions respect system and keyboard insets.

## Working with role agents

For non-trivial work, act as orchestrator rather than doing everything alone. Agents are defined in `.claude/agents/`:

- `project-manager` first: scope, task split, owners, acceptance criteria, decisions needed from the user.
- `android-ux` for any UI change (and verify the rendered state against the canonical design, per `AGENTS.md`); `ios-ux` for iOS planning only, since iOS is deferred.
- `market-researcher` for competitor/audience questions.
- `end-user-persona`, run in parallel once per age group (20s, 30s, 40s, 50s, 60s), to review user-facing screens, flows, and copy before delivery.

Launch independent agents in one message so they run concurrently, and summarize their findings for the user. Persona feedback is simulated: present it as hypotheses, not evidence from real users. Agent suggestions never override `AGENTS.md`; a new design direction still needs an explicit user request.
