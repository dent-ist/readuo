# Readuo UX review of the running app (2026-10-09)

Review of the current Flutter app's rendered screens by three Android UI/UX reviewers and five simulated end-user personas (20s, 30s, 40s, 50s, 60s). This is a findings document only; no app code was changed.

## Method and limits

- Renders came from the real app screens run under `flutter test` with Flutter 3.41.6, using the fake repositories from the existing widget tests. Phone size 390x844 at 2x. The design mockups under `design/` were not used.
- Rendered flows: login, profile setup, first-book, empty Library and its "+" menu, create shelf, Library with books, search, filters, book details, add-books sheet, shelf "+" menu, typed-ISBN and scan confirmations, manual entry, Explore (4 states), Circle (post, review, activity, batch, report menu), friend book sheet and friend profile, Friends, Profile, notification states, tab headers.
- Judged from code only, not rendered: camera scanner, Friends invite and enter-code screens, profile edit, moderation report, account deletion, Circle composer.
- Not tested: 360x640 and 412x915, large-text scales, keyboard-open layouts, TalkBack on a device, animation. Large-text and TalkBack notes are inferred from code and need on-device verification.
- Harness artifacts, ignored in the findings: header titles and generated-cover text render as solid blocks (test engine font fallback); a thick black ring on the Library "+" button is a keyboard-focus highlight.
- An early harness bug (missing in-memory preferences) made profile setup show a "could not restore your saved photo draft" error and hid the first-book screen. It was fixed; findings based on it were discarded.
- Persona feedback is simulated opinion. Treat it as hypotheses to validate with real users, not evidence.

## Conformance with `AGENTS.md` overrides

Verified as met in the renders: Empty Library (Search-only title bar, centered text, no card or illustration, FAB with Create Bookshelf and Add Books, Add Books disabled until a shelf exists); bookshelf addition (FAB with Scan ISBN, Enter ISBN, Search Catalogue, Add Manually; Add & Scan Next / Add & Enter Another and Add & Finish; no success screen between repeated entries); Explore (single search, no scope buttons, grouped exact-ISBN copies with expandable choices, friend avatar ring plus text label, centered empty and no-match text); Create Shelf order Private, Friends, Public with Friends selected; reading status exactly Want to read, Reading, Finished; four-tab bottom nav; Google-only sign-in.

Not verified: scanner opening the camera directly, shelf retention across repeated entries (not visible in the render), bottom actions above the keyboard.

## Findings, ranked

### 1. Plain wording and developer-facing text
- "Share activity to Circle - Your preference is saved; posting arrives later." is shown on a toggle that is on by default (`lib/screens/my_library_screen.dart:1787`). It reads as unfinished and was flagged by every age group. Reword, or hide the toggle if posting is not live.
- Jargon: "Search catalogue", "Turn off to hide this book from discovery" (`lib/screens/book_details_screen.dart:1216`), "ISBN-10 is normalized to ISBN-13. ..." (`lib/screens/manual_book_flow.dart:720`), "Circle", "Explore", "libraries" in Explore search.
- Add a hint wherever ISBN is requested, such as "the number under the barcode".

### 2. "Book found" confirmation has too many similar choices
- In the typed-ISBN flow the title still reads "Scan a book" and the scanner viewport is shown.
- "Enter Another ISBN", "Enter ISBN" and a disabled-looking "Search books" appear together. Keep one retry link and one "other ways" row, and explain the disabled action.
- "Book details · Want to read" is a collapsed grey line hiding the status choice; it is not obviously a control and is under 48dp.
- No clear "this isn't my book" exit.
- The "added to <shelf>" line on the next manual entry is plain text, not announced to screen readers.

### 3. Duplicate and overlapping add actions on the empty shelf
- Inline Scan, Search and Add manually buttons repeat the "+" menu actions (`lib/screens/shelf_details_screen.dart:1616-1637`); when the menu opens its pills overlap those buttons.
- Labels are inconsistent: "Scan barcode" (Library sheet), "Scan ISBN" (shelf menu), "Scan a book" (empty state), "Search catalogue" vs "Search Catalogue".
- The Library add sheet lacks Enter ISBN, which the shelf menu has.

### 4. Accessibility and tap targets
- Targets under 48dp: filter and status chips (about 32-38dp), Explore avatars (about 31dp, `unified_explore_body.dart:347`, `:431`), notification switch rows (34dp, `notification_screens.dart:301-307`), "Not now", "Add a photo", account-deletion back button (44dp), quiet-banner dismiss button, footer links.
- Login buttons wrap the real button in `ExcludeSemantics` under a Semantics node with no tap action (`login_screen.dart:340-375`); TalkBack activation needs a device test.
- Profile display-name field has no label; photo posts have no alt text (`widgets/circle_photo.dart`); Friends rows, per-book engagement rows and the friend-sheet owner card need merged labels; quiet banner needs a live region; deletion and invite screens lack heading semantics; progress indicators lack labels.
- Switch and status chips rely on colour alone in places; filter chips do not show a selected state beyond colour.

### 5. Privacy clarity
- Shelf visibility, the per-book "I own this book" toggle, and Profile > Shelf privacy overlap; users cannot tell which wins.
- "Public: Visible to signed-in Readuo readers" should say plainly that strangers can see it.
- Show visibility next to the shelf name wherever books are added or moved. The scan confirmation does this with a small chip that is easy to miss.
- Consider one "who can see what" summary on Profile.

### 6. Layout and state clarity
- The Library "+" covers the last row of the book grid (status text hidden); add bottom scroll padding. Scrolled tab labels are clipped half-way.
- On the shelf screen the "Finished" chip is clipped at the edge with no scroll affordance.
- Book cards: authors and status do not align when titles wrap to different line counts.
- "ISBN not available" is drawn in a bordered box that looks like an input or error (`widgets/book_information.dart:77`).
- Denied-notifications state shows a dead grey "Enable notifications" above the working settings button; the settings screen shows active toggles while OS permission is off.
- Add Books is disabled in the empty-Library menu with no explanation; add a one-line reason (keeps the override intact).
- Disabled "Search books" in scan confirmation has no reason.

### 7. Onboarding
- Profile-setup back arrow signs the user out and clears the draft with no confirmation (`profile_setup_screen.dart`, `_leave`).
- First-book subtitle "Connect with friends whenever you're ready." does not match the screen.
- First-book and account-deletion headers use fixed heights and will clip titles at large text; the tab header already measures its height (`widgets/readuo_tab_header.dart:43-65`).
- Edit-profile Save is inside the scroll area and may sit under the keyboard on 360x640.

### 8. Destructive actions and errors
- Moderation action sheet puts the destructive "Remove & resolve" first and filled; "Resolve concern" uses the danger colour; the screen shows `error.toString()` (`moderation/moderation_screens.dart:420`).
- Account deletion: "Try deletion again" is red; two indeterminate progress bars; copy says permanence twice.
- Remove-from-library and move flows were reviewed against the mockup earlier and discarded; re-review them once rendered from the app.

### 9. Smaller polish
- Circle dates older than a week show "1/1/2026" (`circle_screen.dart:2381`); use a localised format.
- Circle post button is an off-palette green (`0xFF3D7A1A`, `circle_screen.dart:968`).
- Batch-activity cards: unstyled centered titles and repeated like/comment rows per book; covers are large (164x252).
- Report sheet has no title and a different background colour; the activity-card menu tooltip says "Post options" but reports a profile.
- Activity cards show both a "Book details" button and a chevron.
- Friend-profile header "..." is circular while other header actions are rounded squares.
- Sheet titles differ in weight; back buttons differ in style (boxed vs plain).
- Quiet banner overlaps the Circle header and is vague ("New activity in your circle").

## Decisions needed from the product owner

- **Disabled Apple button on login** (`login_screen.dart:369`): three age groups read it as unfinished. Keep, make secondary, or remove.
- **Default shelf for the first book:** the 20s and 60s personas wanted books to land on an auto-created shelf. This conflicts with the Empty Library override (Add Books disabled until a shelf exists), so it is not recommended.
- **Friends as the default visibility:** the 30s and 50s personas wanted Private. The Create Shelf override keeps Friends, so it is unchanged.
- **New features requested by personas:** bulk or Goodreads/CSV import, a continuous-scan mode with a running count, share cards for Stories, genre and vibe search, friend-link invites and contact import, duplicate-copy handling, undo after remove, multi-select. These are new design directions and need an explicit request. The bulk-add gap was the strongest signal from the reader with a large collection.

## Suggested next steps

1. Wording fixes (finding 1) and the confirmation-screen cleanup (finding 2): small and self-contained.
2. A shared minimum tap-target pass (finding 4).
3. Render and review the screens not yet captured (scanner, invite, enter-code, profile edit, report, deletion, composer) and re-run at 360x640 and 2.0x text.
4. Validate the persona hypotheses with real users before committing to the larger feature requests.
