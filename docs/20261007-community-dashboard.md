# Community dashboard implementation plan

Date: 2026-10-07  
Status: Proposed implementation plan; no application or backend changes made.

## Purpose

Give readers motivation and a sense of community through shared reading achievements, book discoveries, and friendly reader highlights. Show both the wider Readuo community and the user's circle. Keep the experience encouraging rather than competitive.

This is a new screen requested by the user. Reuse the typography, colors, spacing, cards, and controls from `design/readuo-first-release.html` and the current app. Do not edit the canonical handoff to justify deviations. Keep the four bottom destinations: Circle, Library, Friends, Profile.

## First-release scope

- A Community entry in the Circle header, alongside the existing notifications action. Use a chart icon with the accessible label "Community"; no fifth bottom tab.
- A compact Community page with two tabs: Everyone and My Circle. Default to My Circle for a personal first impression; allow Everyone even when there are no friends.
- Three metrics for the previous completed calendar month: books finished, books added, and readers who finished at least one book.
- Community library totals: books shared, catalogued editions, and books marked Finished.
- One book highlight: the most-finished eligible edition last month. Fall back to the most-added edition if there are no dated completions.
- Up to three readers who added the most eligible books in the last 30 days.
- Pull to refresh, clear loading/empty/error states, and a small explanation of counting and visibility.

Defer charts, streaks, badges, prizes, a full leaderboard, historical month browsing, reread tracking, and completion-date editing. Do not add page-progress controls or change Want to read / Reading / Finished.

## Suggested screen layout

Illustrative content only; never ship these numbers as fallback data.

```text
+--------------------------------------+
| <  Community                    (i)  |
|                                      |
|       Everyone  |  My Circle         |
|                                      |
| Last month                           |
| September 2026                       |
|                                      |
| +----------------------------------+ |
| | 42                               | |
| | Books finished                   | |
| | A little reading adds up.        | |
| +----------------------------------+ |
|                                      |
| +----------------+-----------------+ |
| | 86             | 18              | |
| | Books added    | Readers finished| |
| |                | a book          | |
| +----------------+-----------------+ |
|                                      |
| Community library                    |
| Current totals                       |
| 1,240 books shared                   |
| 720 catalogued editions              |
| 310 books marked Finished            |
|                                      |
| Last month's reading highlight       |
| +----------------------------------+ |
| | [cover]  Cosmos                  | |
| |          By Carl Sagan           | |
| |          Finished by 6 readers   | |
| |          View book >             | |
| +----------------------------------+ |
|                                      |
| Reader spotlight                     |
| Most books added - last 30 days      |
| [avatar] Kenny Kim           12 books|
| [avatar] Alex                 9 books|
| [avatar] Morgan               7 books|
|                                      |
| Updated just now                     |
| Based on activity shared with you.   |
+--------------------------------------+
| Circle    Library   Friends  Profile |
+--------------------------------------+
```

### Visual treatment and interaction

- Use the existing compact detail-page app bar; no oversized decorative heading or title icon.
- Match the current Circle/Library horizontal padding, normally 16 logical pixels. Use roughly 24 between sections and 12 within sections, adjusted to shared theme tokens.
- Give books finished the strongest emphasis: a restrained accent tint, a 28-32 logical-pixel number, and a plain label. Supporting figures use smaller numerals. Avoid a dense grid of six equal cards.
- Keep totals as compact text rows instead of another set of large tiles.
- Reuse the existing book attachment styling, cover loader/cache, and "By" author prefix. Reader rows use approximately 40-pixel avatars, names, and trailing counts; no medals or numbered podium.
- Numbers may use compact display notation at large values, with the exact count exposed to accessibility and the information sheet. Labels wrap rather than truncate.
- At narrow widths or large text scales, stack the two supporting metrics. Maintain 48-pixel touch targets, adequate contrast, and Android safe insets.
- Information opens a short sheet explaining scope, calendar boundaries, missing historical dates, and update timing. Stats themselves are not tappable in the first release.
- Book and reader taps open only destinations the viewer can currently access. Revalidate access on navigation; hide or disable a destination when no appropriate public reader profile/library is available.
- Use Circle's nested navigator. Existing tab-switch behavior returns to the landing page when the user leaves Circle and comes back.

## Counting contract

Agree and encode these definitions before implementation; UI labels must match them.

| Metric | Definition |
| --- | --- |
| Books shared | Current eligible owned library entries. Multiple copies may count separately. Want-to-read entries not marked owned do not increase this total. |
| Catalogued editions | Distinct normalized ISBNs among those entries. ISBN identifies an edition, not a work across editions. Exclude missing ISBNs and explain this; do not claim a precise unique-title total. |
| Books marked Finished | Current eligible entries whose status is Finished, including older records with no reliable finish date. This is a current status total, not a lifetime reading-event count. |
| Books finished last month | First recorded completion per reader and canonical book identity in the previous completed calendar month, after reliable tracking begins. Reading a borrowed book may count even when it is not owned. |
| Books added last month | First eligible owned addition per reader and canonical identity in the previous completed calendar month. Moving shelves, duplicate imports, and remove/re-add operations must not inflate the count. |
| Readers finished a book | Distinct eligible readers contributing at least one completion last month. |
| Reader spotlight | Top three eligible readers by additions in the trailing 30 x 24 hours, excluding zero counts. Resolve equal counts deterministically; use friendly presentation without rank badges. |
| Reading highlight | Edition with the most distinct eligible readers finishing it last month; otherwise the edition with the most distinct readers adding it. State which measure is shown. |

Use UTC server timestamps and half-open intervals [start, end). The main metrics and book highlight use the previous completed calendar month: start is the first day of the previous month at 00:00 UTC; end is the first day of the current month at 00:00 UTC. For example, on October 7, 2026, show September 1 through September 30, 2026. Derive this window from the server response time, including year rollover. Display both "Last month" and the explicit month/year so the period is unambiguous. For the first release, use UTC calendar-month boundaries for consistent community totals and disclose "Calendar months use UTC" in the information sheet. Current library totals remain current, labeled "Community library - current totals"; they are not a last-month snapshot. The reader spotlight remains a separate rolling period labeled "Last 30 days". Last 30 days ends at the response's `asOf` time. Return explicit period boundaries from the backend.

Use normalized ISBN as canonical identity where available. For books without ISBN, use a persistent library-entry identity that survives shelf moves; exclude these from edition popularity. Do not merge unrelated manual books solely by title. Preserve event identity if metadata/ISBN changes, with a reconciliation rule for merges.

A new book entered already Finished contributes to current Finished totals, but does not imply it was read last month. Existing Finished entries must never receive today's date during migration. A transition to Finished after tracking launches records a completion; toggling away and back does not add another completion. Explain that monthly reading statistics begin at launch. A future reread feature would require explicit reading-session data.

## Visibility and privacy

- Everyone means eligible public sharing, not an administrative view of every registered user or private book. Explain "From public libraries and shared reading activity."
- My Circle includes the viewer and current accepted friends, using only public/friends-visible shelves and shareable activity. Private shelves are excluded even from the viewer's contribution so the numbers consistently describe shared activity.
- Library inventory uses current shelf visibility. Dated activity, highlights, and reader spotlight also respect `autoShareActivity`; do not infer permission to publish behavior from inventory visibility alone.
- Exclude deleted/deleting accounts, moderated content where applicable, and blocked relationships in either direction. Reader names and counts must not reveal blocked users.
- Revalidate friendship, shelf visibility, ownership, sharing settings, blocks, and active account status on every response. Revoke contributions when their source becomes ineligible, including old events; historical totals may decrease, which the information sheet should explain.
- No client writes to aggregate collections. Do not expose raw global events, private library records, or service-account credentials.
- Avoid stale private payloads: keep My Circle responses in session memory only and invalidate them on access changes and sign-out. If access cannot be validated, show an unavailable state instead of serving a cached private response.

## Existing implementation findings

- `app/lib/library/book.dart` contains `readingStatus`, `createdAt`, ISBN, ownership, and activity generation, but no reliable first-completion timestamp.
- `app/lib/library/book_repository.dart` creates nested shelf/book activities for eligible shared additions and status changes. It also handles moves; identity must survive that path.
- `app/functions/book_additions.js` is a notification delivery pipeline with event lifetime, recipient preferences, sharing gates, and delivery receipts. Its records are not a complete analytics history and must not become the dashboard source of truth.
- `app/lib/screens/authenticated_shell.dart` owns nested navigation and account-service startup; dashboard loading should remain separate from that startup retry flow.
- Existing friendship, block, active-account, deletion, and moderation checks should be reused in a dedicated backend eligibility policy rather than reimplemented inconsistently.

## Backend and data design

Proposed names below are implementation targets, not existing APIs.

1. Introduce a stable entry identity carried through shelf moves and a server-owned contribution ledger, `communityContributions/{identity}`. Store owner, source references, canonical identity, first-added time, first-recorded completion time, eligibility projection, and schema version. Keep processing receipts separate from user-visible activity.
2. Observe committed book/shelf changes through dedicated functions. Use trusted Firestore commit/update times, not client-supplied dates, for new events. Process duplicate and out-of-order deliveries idempotently by source version; reconcile against the latest source rather than blindly incrementing on every trigger.
3. Maintain per-reader inventory summaries and UTC daily activity buckets with per-book contributions. These support previous-calendar-month totals, rolling windows, distinct-reader counts, edition highlights, and reversible removals. Do not store only scalar increments: correction and revocation require contribution identities.
4. Add an authenticated callable `getCommunityDashboard(scope)` returning totals, monthly metrics, highlight, spotlight, `asOf`, period boundaries, tracking start, and completeness. Enforce authentication, App Check consistent with the project, input validation, and request limits.
5. Everyone: use backend aggregates for eligible public contributions. Because block exclusions differ by viewer, a single public total cannot simply be returned unchanged. Apply exact per-viewer exclusions using contribution summaries before totals/top lists are finalized; overfetch/recompute candidates when exclusions affect the top three. Never expose excluded candidates to the client.
6. My Circle: resolve current friendship membership server-side and combine eligible summaries in bounded batches. Include the viewer once. Do not download all books or all events to the phone. If the permitted workload exceeds the request budget, return an explicit incomplete/unavailable result, not a silently truncated total.
7. Gate cached aggregates with eligibility versions. On privacy/deletion changes, mark affected projections invalid before serving them; fall back to validated computation or unavailable while rebuilding. A scheduled reconciliation repairs drift but is not the sole privacy mechanism.
8. Keep global computation asynchronous and use shards if write contention requires them. Specify required indexes in `firestore.indexes.json`, including owner/time and canonical-identity access paths after query design is finalized. Estimate reads/writes using representative small and large circles before deployment.
9. Account deletion removes attributable ledger records, summaries, spotlight data, and caches, then adjusts totals through idempotent cleanup. Integrate with the existing deletion workflow and retry checkpoints.

Target freshness: within five minutes for normal aggregation, explicitly labeled by `asOf`; access revocation must take effect on the next request regardless of this freshness target. Loading this page must not block app startup or navigation.

## Flutter implementation

Proposed files:

- `app/lib/community/community_dashboard.dart`: immutable response models, scope, completeness, and period metadata.
- `app/lib/community/community_repository.dart`: repository interface, callable implementation, and test fake.
- `app/lib/screens/community_screen.dart`: scope control, metric sections, highlight, spotlight, and information sheet.
- `app/lib/features/feature_services.dart`: repository injection.
- `app/lib/screens/circle_screen.dart` and `authenticated_shell.dart`: header entry and nested route wiring.
- `app/functions/community/`: counting, eligibility, projection, callable, and reconciliation modules; export handlers through the existing function entry point.
- `app/firestore.rules`, `app/firestore.indexes.json`, and account-deletion integration as required.

Use a request generation token so a slow Everyone response cannot overwrite My Circle after a tab change. Cancel/ignore responses after disposal, sign-out, or access changes. Keep loading and errors local to the dashboard. Reuse existing image caching for public covers/avatars and the existing authenticated path for restricted images.

## Required states

- Initial loading: stable skeletons with no fake zero counts.
- Loaded: all metrics and up to three spotlight rows; hide a highlight section when no qualifying title exists.
- Genuine zero activity: "No shared reading activity last month." Show valid inventory totals if available.
- No friends: retain the viewer's eligible contribution; add "Connect with readers to see your circle grow" with a Find readers link and the Everyone tab available.
- New tracking period: disclose "Reading totals tracked since [date]"; missing history is not a zero. If tracking began after last month ended, show "Last-month reading stats are not available yet" for affected metrics. If tracking began partway through last month, label those metrics "Partial data since [date]" and return partial completeness. Do not silently substitute this month or present partial data as a full month. Inventory totals and an eligible last-30-days spotlight can still appear independently.
- Failure: a concise inline error and Retry. Preserve only still-authorized data; show its age. Never convert failures or incomplete projections to zero.
- Refreshing: keep authorized content steady with a small refresh indicator.
- Access revoked/deletion: remove affected content; any open profile/book destination must also enforce its existing authorization boundary.

## Implementation sequence

1. Confirm counting contract, proposed layout, and scope labels against this document. Capture the proposed new-screen reference without altering the canonical prototype.
2. Implement pure counting/eligibility functions and tests, including time-window and privacy cases.
3. Add stable identity migration, contribution projection, backfill, reconciliation, and deletion cleanup behind a disabled feature flag. Backfill current inventory conservatively; skip unverifiable historical event dates and report migration completeness.
4. Implement callable response, authorization, indexes, and bounded aggregation. Validate against fixtures and manually computed counts in the Firebase emulator.
5. Build the Flutter screen with repository fakes first, then wire the real repository and Circle route.
6. Render every required state on an Android emulator; compare shared components with canonical styles and the new layout reference. Check narrow displays, large text, safe insets, tab switching, and revoked destinations.
7. Run backend/rules/Flutter tests, deploy backward-compatible backend changes, run backfill and reconciliation, and enable for internal accounts. Compare counts against source data before broad enablement.
8. Build the release APK after validation. Roll back by disabling the entry/endpoint feature flag; preserve source data and avoid destructive rollback migrations.

## Acceptance and verification

- Monthly and rolling-window fixtures match exact expected totals across UTC midnight, month-end, January-to-December year rollover, leap day, and 30-day boundaries. Verify the previous month remains selected throughout the current month and advances at the next UTC month boundary; refresh or invalidate cached responses at that boundary. Test launch dates before, during, and after the displayed month so missing history is never reported as zero.
- Duplicate delivery, retry, status toggling, move, metadata change, duplicate ISBN, delete/re-add, and out-of-order updates do not inflate counts.
- Imported Finished books affect current-status totals without fabricating dated completions.
- Changing public to private, disabling sharing, removing friendship, blocking either direction, moderation, and account deletion remove all affected contributions and drill-down access.
- Unauthenticated requests and client aggregate writes fail; malicious scope inputs fail validation.
- Distinct readers and ISBN editions are calculated correctly; missing ISBN and missing history are labeled honestly.
- Everyone/My Circle race handling, refresh, offline/error, no-friend, zero activity, partial readiness, and disposal have meaningful Flutter tests.
- Page data comes from bounded backend responses; the client never scans the full user population. Measure response time and read/write cost before release; target a normal cached response under two seconds.
- No new permission prompts, startup blocking work, bottom tabs, or unsolicited notifications.

## Decisions to retain for implementation

The main reporting period is the previous completed UTC calendar month, chosen to provide a full period of activity rather than sparse month-to-date results. A complete calendar period does not guarantee complete historical tracking or freeze totals against privacy corrections. The other proposed defaults are My Circle including the viewer, public-only Everyone, opt-in shared activity for behavioral highlights, first completion only, and no fabricated historical reading dates. If these product choices change, revise the counting contract and tests before shipping. Accurate lifetime books-read totals remain deferred until reliable dated history exists; the first release explicitly shows current books marked Finished instead.
