# P1-07 Friends Explore review evidence

Captured September 21, 2026 from the actual Flutter Android app on the API 36
emulator using deterministic friend/shelf/book fixtures. The QA-only entrypoint
was removed after capture and no release artifact was produced.

## Viewports

- `explore-390x844.png` and XML: canonical Friends Explore at 390×844.
- `explore-360x640.png` and XML: compact Friends Explore at 360×640.
- XML confirms the real Android three-button navigation bar occupies
  `[0,796][390,844]` and `[0,592][360,640]`, exactly 48 physical pixels.

## Canonical states

- `search-390x844.png`: `explore-results` with exact friend/shelf/book identity.
- `friend-shelf-390x844.png`: `friend-shelf`, owned-only three-column grid.
- `book-sheet-390x844.png`: `friend-book`, compact discovery summary and shelf link.
- `save-sheet-390x844.png`: `save-shelf`, Want to read, not owned, one shelf.

The rendered app was compared against the unchanged matching states in
`design/readuo-first-release.html`. The comparison corrected the Explore active
segment, friend-shelf identity row, three-column grid, one-line shelf metadata,
and compact horizontal discovery summary before final capture.
