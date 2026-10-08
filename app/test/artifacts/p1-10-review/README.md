# P1-10 Circle post review evidence

Captured September 21, 2026 from the actual Flutter Android app on the API 36
emulator using deterministic authenticated-reader, post, draft, and own-library
book fixtures. The QA-only entrypoint was removed after capture, build 22 was
restored on the emulator, and no per-item release APK or version bump was made.

## Viewports and states

- `post-390x844` and `post-360x640`: own general text post with exact book
  attachment inside the persistent Circle shell and Android safe inset.
- `compose-390x844` and `compose-360x640`: restored durable draft, privacy
  banner, text editor, attached-book card, deferred photo control, and publish.
- `compose-corrected-390x844` and `compose-corrected-360x640`: corrected
  canonical labeled field and generated title cover after coordinator review.
- `compose-action-scrolled-360x640`: full-width publish action remains reachable
  above the compact Android system inset after scrolling.
- `compose-keyboard-open-390x844`: actual Android Gboard state with the publish
  action still reachable while the editor is focused.
- `attach-book-390x844`: searchable own-library attachment picker.
- `attach-book-corrected-360x640`: corrected canonical search shell, divider
  rows, and generated title covers.
- `edit-post-390x844`: canonical author edit state with retained attachment.
- `edit-post-corrected-390x844`: corrected shared edit composer components.
- `own-post-menu-390x844`: author-only edit/delete actions.
- `delete-post-390x844`: destructive confirmation preserving the library book.
- PNG evidence is paired with UI XML except where the menu PNG and XML were
  captured in successive openings of the same deterministic state.

## Canonical comparison

The rendered app was compared with the unchanged `circle`, `compose`,
`attach-book`, `own-post-menu`, `edit-post`, and `delete-post` states in
`design/readuo-first-release.html`. It preserves the modern typography, spacing,
privacy copy, outlined cards, full-width primary actions, destructive sheet,
single shell navigation, central scanner, scrolling on compact height, and real
48-pixel Android three-button inset. Photo upload remains explicitly deferred to
P1-14 and reviews to P1-11 rather than being represented by fake completion.

## Verification

- `flutter analyze`: clean.
- `flutter test`: 170 tests passed.
- Staged Firestore emulator: 59 tests passed.
- Restored P1-08/build-22 compatibility emulator: 1 test passed for add, status,
  and exact move payloads without generation/activity fields.
- Posts stream for the author and accepted friends, disappear on unfriend or
  either-way block, and reject outsider reads.
- UID-scoped drafts restore, explicitly discard, survive failed publish, and
  reject cross-user reads or alternate draft IDs.
- Each draft retains an immutable generated post ID; publication creates that
  exact post and consumes the draft in one transaction, so an ambiguous retry
  cannot duplicate a committed post.
- The missing-post transaction read exception applies only while that document
  is absent. A self-writable draft can never expose an existing outsider or
  blocked reader's post, and it cannot widen collection queries.
- Autosaves use immutable snapshots and a serialized queue. Publish/discard
  flush or invalidate queued work, cleanup failures stay visible and retryable,
  pending submission locks edits/back navigation, and owner changes cannot
  update the next account.
- Publication reads the current server draft before any write and refuses to
  consume a concurrently replaced or edited draft.
- Optional book attachment must match one exact current author-owned library
  path and copied title/author/cover; forged metadata and undeclared photo fields
  are rejected.
- Only the author may edit or delete; identity and creation time are immutable,
  delete is confirmed, and failed operations retain retryable UI state.
- Local staged Rules normalized SHA-256 is
  `791575E30564475639972BFC27A3973DA4B3CEE9F9F0D6584C09E807F1700CEB`.
  P1-10 Rules and its `circlePosts` index are not deployed pending the final APK.
- Production remains exact P1-08 ruleset
  `35fadc9e-1231-480d-aba3-9f3ac6188152`, SHA-256
  `541CA433D0AE44386A6A372411E030F9482A5BFE5DA9FE9F6EC76115E3704C9E`;
  the previously deployed P1-09 activity index is `READY`.
- No production user data was written.
