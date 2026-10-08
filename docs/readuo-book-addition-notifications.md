# Grouped owned-book notifications — staged, not activated

## Release boundary

Build31 packages the current source, including accepted Circle density changes.
Grouped book alerts are **disabled in the normal APK**. No new rules, functions,
runtime configuration, billing changes or production test records were deployed.
The existing four notification types remain available.

`READUO_BOOK_ADDITION_NOTIFICATIONS` defaults to false. In that mode the app
writes only the deployed token fields (`token`, `platform`, `updatedAt`), does
not subscribe to the new inbox, hides the new setting, rejects new preference
writes and does not advertise grouped alerts in permission copy. This avoids
permission-denied failures against the currently deployed rules. Future enabled
builds must explicitly opt in after the backend dependencies are ready.

## Staged behavior

- Owned-book additions from manual entry, search and scan share one grouping
  path. Moves, edits, status updates, private/no-auto-share shelves and unowned
  books do not qualify.
- Actor/recipient groups close after two quiet minutes; the minute scheduler
  makes practical delivery roughly two to three minutes plus delivery latency.
- Immutable creation identity deduplicates replay. Out-of-order additions retain
  the earliest eligibility timestamp. A later addition extends the quiet window.
- Friendship, blocks, active accounts, deletion fences, preference epochs,
  shelf visibility and current book/source generation are rechecked at flush
  and retries. Tokens must advertise capability before the first addition.
- New notices use `bookAdditionNotifications`, not the legacy inbox, so build30
  never decodes the new type. New clients skip unknown/malformed notice data.
- Actor/count copy is used only in push text. The activity screen reloads
  authorized books in pages of20 and clears details when access fails.

## Bounds and operational limits

The source ceiling is1000 per actor/recipient window. A1001st source cancels the
entire summary with a sanitized operator diagnostic: no misleading partial
count, no split-push spam. This extreme window intentionally produces no push.
Fanout checkpoints at100 friends per invocation; the scheduler handles10 due
groups per invocation. Validation reads sources in chunks of100. This is not
an unlimited/free service: scheduler, functions and Firestore usage apply.

FCM validation and send are not atomic. A push already in flight or delivered
cannot be recalled after a privacy change. Delivery remains at-least-once in
ambiguous provider failure cases; checkpoints avoid known successful resends.
Physical two-phone receipt and lock-screen behavior remain unverified.

## Future activation requires separate authorization

1. Deploy the staged Firestore rules and verify required query indexes.
2. Deploy `collectBookAddition`, `flushBookAdditions`, `deliverBookAdditionPush`
   plus updated `processAccountDeletion` and `resumeAccountDeletions` so all new
   records participate in permanent account deletion.
3. Distribute a compatible APK built with the feature flag enabled; verify
   token registration and notification preferences against the deployed rules.
4. Only then enable `notificationConfiguration/bookAdditions` with a fresh
   server timestamp `enabledSince`. Missing configuration remains disabled.
   Do not backfill historical additions or backdate capability/preference epochs.

Local emulator tests cover grouping, duplicate events, partial retries,
privacy/deletion, source pagination, capacity overflow and mixed old/new tokens.
UI fixtures explicitly enable the staged screen for testing; this does not
enable it in the release app or production backend.
