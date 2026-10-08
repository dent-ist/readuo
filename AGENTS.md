# Readuo project instructions

## Design fidelity

- Treat `design/readuo-first-release.html` as the authoritative, audited 117-state modern UI handoff for screen structure, navigation, layout, components, spacing, typography, colors, cards, controls, and flows.
- Do not replace or simplify the agreed design merely because implementation is incremental. Unimplemented backends may leave destinations unavailable, but the implemented visual shell must remain faithful.
- Do not edit the canonical prototype to justify an implementation deviation. Earlier uploaded PNG references, playful concepts, and icon explorations are not substitutes for the final modern handoff.
- Any materially new design direction requires an explicit user request before implementation. Later explicit user decisions override older mock details only where they conflict.
- Current explicit overrides: Create Shelf displays visibility choices in the order Private, Friends, Public while Friends remains selected by default; bottom actions respect Android system and keyboard safe insets; Android uses Google sign-in now and iOS is deferred; reading status remains exactly Want to read, Reading, and Finished with no page-progress control.
- Navigation override: Bottom navigation contains four equally weighted destinations: Circle, Library, Friends, and Profile. Scanning belongs in Library's Add books action, alongside Search catalogue and Add manually. Own shelves expose the same choices with the current shelf selected.
- Empty Library override: The title bar has Search only, and My Library / Explore remain. Show centered text guidance without a card, illustration, or inline actions. A Library FAB expands to Create Bookshelf and Add Books; Add Books is disabled until an available own bookshelf exists.
- Bookshelf addition override: A round + FAB expands to Scan ISBN, Enter ISBN, Search Catalogue, and Add Manually. Scanning opens the camera directly. Confirmation offers Add & Scan Next (or Add & Enter Another for typed entry) and Add & Finish. Repeated entry retains the selected shelf and starts a fresh book without an intermediate success screen.
- Before delivering UI work, compare the actual rendered app state against the matching canonical state. Do not claim fidelity from code inspection or theme similarity alone.
- Explore override: Keep My Library / Explore and one search across friends’ and public libraries. Remove scope buttons and separate empty sections. Use centered text for empty and no-match states. Group exact-ISBN copies into one result with expandable library choices; mark friends with an avatar ring and a text label.

