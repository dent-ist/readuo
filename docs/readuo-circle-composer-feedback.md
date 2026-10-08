# Circle composition feedback — October 4, 2026

## Scope

The user explicitly requested a Circle Post FAB instead of the header action, removal of the redundant feed subtitle, repair of camera-photo uploads, and a bottom-anchored Post to Circle action. These override only the corresponding approved Circle/main-composer details. `design/readuo-first-release.html` is unchanged.

- Circle keeps its notification action and replaces the header Post control with a blue, labeled Post FAB above the main navigation. The feed still uses friends-only access and newest-first ordering, without repeating those defaults in a subtitle. Existing end-of-feed padding keeps the final actions clear of the FAB.
- The composer opens as a focused root route, without the tab bar. The editor and attachments scroll independently of the full-width bottom action. The action stays 16 logical pixels above the system/keyboard safe edge, including when editing an existing post. Uploading disables publication rather than presenting a clickable no-op.
- Errors are visible above the bottom action and announced as a live region. Text drafts survive a denied upload and successful retry. Storage permission errors no longer incorrectly assert that the user lost access; expired authentication has a separate sign-in message.

## Upload diagnosis and approved production repair

Read-only inspection confirmed that the deployed Storage rules exactly match the local source. They require `firestore.exists` checks of the active account and moderation lock before accepting a photo. However, the existing Storage service agent had only `roles/firebasestorage.serviceAgent`, not the cross-service Firestore role. This is a concrete production configuration defect; emulator rules tests cannot detect missing production IAM.

After the user explicitly answered yes, granted only `roles/firebaserules.firestoreServiceAgent` to `service-881895077363@gcp-sa-firebasestorage.iam.gserviceaccount.com` in `readuo-b2f24`. The role was verified to contain only `datastore.entities.get`. The update preserved existing IAM bindings and used the policy etag to prevent overwriting concurrent changes. A subsequent read-only check confirms the role is present.

The active Storage ruleset remains `401722d6-1443-42f6-b1b6-b15e9e811c41`, with SHA-256 `10be37016f4b199c036bf1270962217e8f9bd62a26b4ba0051bf5f947cf55b19`. No public-access change, client security-rule relaxation, Firebase function/rule deployment, production test upload, or grouped-notification activation occurred.

Firebase documents this dependency in [Manage permissions for cross-service Cloud Storage Security Rules](https://firebase.google.com/docs/rules/manage-deploy#manage_permissions_for_cross-service). The backend repair applies to the already delivered build32; the visual changes require a replacement APK. Actual camera-to-production upload on the user's phone still needs user confirmation.

## Regression checks

- Full Flutter suite: 313 passed, one pre-existing skip. Analyzer clean.
- Focused Circle/composer/photo/navigation suite: 35 passed.
- Four isolated Firestore/Storage emulator tests pass: valid camera-format JPEG metadata/path before publication, private draft/friend access after publication, block revocation, unauthenticated/other-owner denial, inactive-account/moderation denial, and invalid/oversized upload denial.
- Android layout checks exercise the FAB and focused compose route, keyboard-visible action, denied upload/draft preservation, successful camera-picker fixture retry, attached photo, and editing. Camera bytes are deterministic fixtures, not evidence of a physical camera capture or production upload.

Native Android checks passed at 390x844/density160/font1.0 and 360x640/density160/font1.3. Each captures seven app states plus an actual keyboard-visible device screenshot in `app/test/artifacts/circle-composer-feedback/` and `circle-composer-feedback-small/`. The app render was compared with canonical `compose`/`compose-photo` and the approved Circle reference, applying the user's FAB/subtitle/footer overrides and retaining the previously accepted gutters. The editor, privacy notice, attachment controls, photo preview/removal, and large-text scrolling remain; this is not a new all-117-state fidelity audit. The small device's keyboard screenshot also contains an Android keyboard onboarding tooltip, not a Readuo control.

An initial screenshot callback captured the keyboard too late, after test completion. The evidence was replaced using a synchronized, loopback-only test bridge during the keyboard-visible state, and both native runs passed again. The driver cleans its bridge in the response callback because `integrationDriver` exits the process before a normal `finally` would run.

Evidence logs: `app/test/circle-feedback-*.log`, `app/test/circle-photo-rules.log`, `app/test/circle-photo-iam-repair.log`, and `app/test/circle-photo-iam-verified.log`.

The read-only deployment preflight is `node tool/storage-rules-preflight.cjs` from `app/`. It exits unsuccessfully if cross-service Storage rules require a missing service-agent role. `FIREBASE_CLI_LIB` can point to a different installed Firebase CLI library directory. Its `--enable-cross-service` mode is for explicitly approved IAM repairs only, never routine testing.

Run the dedicated rules regression from `app/rules-tests/` with:

```powershell
firebase emulators:exec --config ../firebase.circle-photo-qa.json --project demo-readuo-circle-photos --only firestore,storage "node --test --test-concurrency=1 circle-photos.rules.test.mjs"
```

It uses isolated demo-project emulators on Firestore8086/Storage9199, without touching unrelated services on8080.

## Delivery boundary

The user subsequently requested packaging and upload. The UI changes are now delivered as 1.21.1+33; see `readuo-build33-delivery.md` for artifact verification and the Google Drive link. The older build32 is retained unchanged.

The existing build32 was reinstalled and cold-launched successfully after fixture QA; its SHA-256 remains `DD5744035FDE35CCB9C49A3F422F5F635D1A7B36247052B50D39279E08EE03E1`. Emulator settings are restored to 390x844/density160/font1.0, temporary storage/stylus overrides are absent, and ADB reverse forwarding is empty. No user data was deleted to free space.
