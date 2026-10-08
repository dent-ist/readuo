# P1-04 final review correction evidence

Generated on 2026-09-14 and finalized with corrected P1-04 delivery
`Readuo-1.13.2-build21.apk`.

## App renders

`app/` contains Android emulator captures using the production `ReaduoTheme`
and readable platform fonts at 390×844 and 360×640. The 360×640 captures use
the emulator's actual 48px three-button navigation bar.

- Prompt, work results, ISBN-specific editions, deterministic no-results,
  normal-cover confirmation, and generated-cover confirmation are included at
  both sizes. The empty fixture visibly uses the complete query `Unknown title`
  and was inspected before replacing the mislabeled prior image.
- Normal confirmation uses Open Library edition `OL28300471M`, verified as
  *Piranesi* by Susanna Clarke, hardcover ISBN `9781635575637`; its displayed
  cover matches that title and author. This is fixture correction only and does
  not change provider or backend identity rules.
- `catalogue-confirmation-safe-inset-360x640.png` shows the 48px `Add book`
  action above the actual three-button inset after normal scrolling.
- `catalogue-confirmation-keyboard-simulated-360x640.png` explicitly labels a
  simulated standard full-width 240px keyboard inset and shows the real
  confirmation widget's 48px `Add book` action reachable above it. The widget
  regression test uses the same 240px view inset and verifies scrollability and
  action height. It replaces, rather than reusing, the rejected floating-keyboard
  evidence.

## Canonical references

`canonical/` was rendered directly from the unchanged authoritative
`design/readuo-first-release.html`. The catalogue search/results/no-results and
manual-confirm states are included at 390×844 and 360×640.

## Comparison notes

- Search uses a 46px white field, 12px radius, pale border, and inline action.
- Work and edition selection use full-width divider rows, 43×64 covers, 14px
  medium titles, and 12px muted metadata without cards or pills.
- Missing covers generate title-and-author artwork instead of an icon box.
- Prompt and no-results use the canonical 72×72 pale-blue, radius-23 accent
  mark; no-results uses the white outlined secondary `Add manually` action.
- Confirmation uses a 76×112 cover at 390px and 68×100 at 360px, a separately
  labeled 48px shelf selector, three custom status pills, and the exact blue
  switch track with white thumb.
- Canonical catalogue results represent the ISBN-specific edition state. The
  app's preceding technical work-selection state intentionally reuses the same
  divider-row treatment before presenting those editions.

No Ahem-font render is included or counted as evidence.
