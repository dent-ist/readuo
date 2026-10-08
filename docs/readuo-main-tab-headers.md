# Unified main-tab headers

The user requested one simple, modern title-bar style for Circle, Library,
Friends and Profile, and subsequently authorized a combined APK delivery.

## Implementation

`app/lib/widgets/readuo_tab_header.dart` owns the shared 26sp semibold title,
1.2 line height, 64dp minimum toolbar, 12dp leading alignment, white background,
zero elevation/scroll tint and 48dp outlined icon action treatment. Header
height grows with scaled/wrapped titles rather than truncating them. Circle's
friends-only/newest-first information now sits in the feed, not the title bar.

Circle, Friends and Profile opt into the header through `ProfilePage.mainTab`;
Library uses it directly. Nested ProfilePage screens retain their prior
headers/back controls/subtitles. Existing notification/account callbacks,
tab navigation, swipes, FABs, searches and privacy behavior are unchanged.
The canonical prototype is untouched; this is a scoped user design override.

## Bounded verification

- Widget checks compare all four actual main-tab header bounds, title baselines,
  typography, alignment and colors at normal and 1.3 text scale; Library's
  account action still selects Profile.
- A 2x long localized title wraps inside the expanded header and its 48dp
  action remains usable. Nested headers retain their existing behavior.
- Full-shell 2x testing exposed an existing bottom-navigation label overflow,
  outside this header-only scope. No unrelated navigation redesign was made;
  isolated 2x header verification is not a full-app accessibility certification.
- Android captures use real rendered app screens with repository fixtures,
  not production account writes. Normal and small/large-text evidence lives
  under `app/test/artifacts/tab-headers/` and `tab-headers-small/`.

Combined release verification and delivery are recorded in
`docs/readuo-build29-delivery.md` once complete.
