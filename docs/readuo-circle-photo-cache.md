# Circle round FAB and photo reuse — 2026-10-04

- Explicit user override: Circle compose is a circular, icon-only FAB. Its
  `#3D7A1A` background comes from the existing launcher SVG gradient; the edit
  icon is white and the accessible “Share a thought” tooltip remains.
- `CirclePhoto` now keeps its download Future across rebuilds and resets it
  when the path or repository changes. Missing objects show the unavailable
  image state instead of an indefinite spinner.
- Circle owns a nonpersistent photo cache, shared by recycled feed cards.
  Concurrent requests are coalesced; cache hits resolve synchronously so
  returning cards do not flash a loading spinner. LRU retention is bounded to
  24 MiB of encoded bytes and 32 photos. Older evicted photos may download again.
- Live post removal, replacement, friendship removal, and post stream errors
  prune paths. Refresh, viewer/repository changes, and disposal clear the cache.
  Invalidated in-flight requests cannot repopulate it. Failed/missing downloads
  are not retained. Firebase access rules and backend permissions are unchanged.
- Android fixture rendering at 390×844 was inspected against the canonical
  Circle reference with the subsequently approved feed redesign and explicit
  FAB/subtitle overrides. Round green icon-only FAB clears bottom navigation;
  composer and keyboard-safe actions still pass native checks.
- Native evidence: `app/test/artifacts/circle-composer-feedback-round-green/`.
  Regression coverage includes card disposal/recreation without another fetch
  or spinner, rebuilds, missing photos, request coalescing, invalidation races,
  bounded LRU eviction, retries, and FAB shape/color/label/size.
- This is a source update, not a new release APK or Drive upload. Build 33 is
  the previously delivered artifact; it does not contain these changes.
