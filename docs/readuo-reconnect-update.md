# Brief connection interruptions

Oct4 update, now included in the delivered 1.21.0+32 APK. See
`readuo-build32-delivery.md` for the artifact and Google Drive link.

After an already verified online session loses connectivity, keep its widget
tree mounted instead of immediately replacing it with the offline library.
For the first five seconds, show no connection notice. If server verification
still fails, show a small noninteractive `Reconnecting…` notice. Clear it only
after a successful server probe, not merely when Android reports a network.
Retries continue automatically. Repeated failures/network flapping do not
restart the grace window.

After30 seconds without successful verification, retain the existing read-only
own-library fallback rather than showing stale social content indefinitely.
Initial startup without a verified session does not expose online content.
Permission-denied and unauthenticated responses still block immediately and
clear private cached data. Session changes and disposal cancel notice timers.

This is presentation grace, not optimistic write success. `requireOnline`
still checks the actual server result, and transactional save/publish failures
are not suppressed or silently queued. The same mounted editor and its text
survive a short handoff. The separate Circle whitespace-conflict fix is also
included in build32; neither change is present in the older build31.

Tests cover silent recovery before five seconds, delayed notice, editor element
identity/text preservation, failed writes during grace, network return without
server recovery, automatic recovery, bounded offline fallback, authorization
failure, stale probes and account changes. Full Flutter suite305 pass with one
existing skip; analyzer clean. No production network/data/rules were changed.

Android fixture runs exercise the production connection boundary at390x844
and360x640/font1.3 with simulated probe failures. Captures in
`app/test/artifacts/reconnect/` and `reconnect-small/` show silent recovery,
the delayed notice, and restored content. The notice reserves vertical space
so it cannot cover the current screen's title or controls. This is bounded
component verification for the explicitly approved new notice, not a full
canonical-screen audit or a physical Wi-Fi-to-cellular carrier test.
The first native attempt failed to connect its test driver; the retry passed.
