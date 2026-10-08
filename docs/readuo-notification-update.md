# Readuo notification update — build30

## Scope

This improves the existing P1-16/17 notification implementation, not a new
notification system. Android only. Events remain friend requests, acceptance,
likes and comments. Routine book and reading-status updates do not send pushes.
No iOS, billing, new rules, production QA records or test pushes to users.
The previously approved circular book-plus shelf action is included.

## Reliability and privacy

- Audited the seven existing deployed notification functions read-only.
- Delivery uses a fenced three-minute lease, per-token hashed outcomes,
  six-attempt maximum, one-hour lifetime and bounded exponential backoff.
  Completed token outcomes are not resent on ordinary partial retries.
- Each batch rechecks current preferences, source generation, friendship,
  blocks, account deletion and content availability. Invalid and 30-day-stale
  tokens are removed; token rotation is protected from stale deletion.
- Generic lock-screen text, stable notification tag, Android social channel
  and a white notification icon. No private actor/content text in pushes.
- FCM is not exactly-once: a crash after send but before recording the result
  can still duplicate delivery. The stable Android tag and foreground event
  deduplication reduce visible duplicates. A terminal `sent` state means at
  least one token succeeded, not that every device received the notification;
  individual permanent failures remain in `pushResults`.
- Silent, dismissible foreground banner revalidates the current recipient,
  source, preferences and destination. It suppresses the currently visible
  conversation, including different comments on that conversation, but not a
  hidden tab or a conversation covered by a root modal. Pausing, signing out,
  offline transitions and tab changes invalidate or dismiss transient UI.
- A once-per-account explanation appears after a successful friend connection
  when navigation is safe. Not now does not request OS permission. Profile
  provides Enable notifications; denial routes to settings without reprompting.
  The local opportunity flag is erased with account deletion.

## Verification

- Final full Flutter suite: 294 passed, one existing skipped test.
- Backend unit suite: 53 passed, one emulator-only test skipped outside emulator.
- Real Firestore emulator partial-send/checkpoint/retry test: passed.
- Firestore/Storage rules suite: all 77 passed using `demo-readuo-shelves`.
- Focused UI tests exercise the actual root overlay above the Readuo shell,
  banner opening and dismissal, and underlying Profile navigation hit testing.
- Final analyzer: clean. Actual Android runs pass seven states each at
  390x844/font1.0 and 360x640/font1.3, including scrolled settings controls.
  Rendered permission/settings states were compared with canonical states
  114/97; approved notification copy/Enable behavior is the scoped override.
  Normal and small renders received independent bounded visual review.
  This is not a new full 117-state audit.
- Native `dumpsys notification` confirms the `readuo_social` channel exists.
- Only `deliverNotificationPush(us-central1)` was deployed successfully.
  No other function, rules, sharing configuration or production QA data changed.
- Logs: `app/test/build30-analyze.log`, `build30-tests.log`,
  `notification-backend-tests.log`, `notification-final-emulators.log`,
  `notification-experience-native.log`, `notification-experience-native-small.log`,
  `notification-delivery-deploy.log` and `notification-channel-verification.log`.
  Native evidence: `app/test/artifacts/notification-experience/` and
  `app/test/artifacts/notification-experience-small/`.

The UI/permission checks use deterministic fixtures. Physical two-account,
two-phone delivery, lock-screen icon, OS denial/settings and background/cold
tap behavior still need a real-device acceptance check. No such check is
claimed from emulator fixtures or read-only deployment inspection.

## Reference behavior

FCM foreground handling is application controlled:
https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
Android notification tags/channels:
https://firebase.google.com/docs/reference/admin/node/firebase-admin.messaging.androidnotification
Token lifecycle and response classification:
https://firebase.google.com/docs/cloud-messaging/manage-tokens
https://firebase.google.com/docs/cloud-messaging/error-codes
