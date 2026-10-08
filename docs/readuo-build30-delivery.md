# Readuo 1.19.0+30 delivery

## Artifact and compatibility

- APK: `app/release/Readuo-1.19.0-build30.apk`
- Size: 77,999,547 bytes.
- SHA-256: `5A6443C24FE625A2A4B81B3001D40638B8CC7264CCC8BA036F59EEA17FD9CFE6`.
- Package `com.zipdosa.readuo`, version code30, name1.19.0, minSDK24/targetSDK36.
- Existing Android Debug signer (not a store signing key):
  `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
- Normal release entry `lib/main.dart`, using existing local Google Books
  configuration. No fixture entry point or test-account login in the APK.
- Existing build29 was installed, then build30 upgraded with `adb install -r`.
  Package first-install time stayed unchanged. Cold launch succeeded; normal
  Google sign-in screen observed, no AndroidRuntime/Flutter error captured.
- Build29 remains unchanged locally, SHA-256
  `13AEA0EDDBF0192AF71A798481B4661AA09994EA9463FCF4120EAB18655A39C1`.
- Emulator restored to390x844/font1.0, temporary storage threshold removed,
  and no adb reverse forwarding remains.

## Included changes

Existing social push reliability fixes, silent privacy-checked foreground
banners, first-connection permission explanation and Profile Enable action;
also the approved circular book-plus own-shelf action. See
`docs/readuo-notification-update.md` for exact behavior and limits.

## Verification

- Analyzer clean; 294 Flutter tests pass, one existing skip.
- Backend53 pass, one emulator-only skip; real emulator delivery test passes.
- Firestore/Storage rules77 pass. No rules changes deployed.
- Actual Android normal/small seven-state runs pass and receive bounded
  independent visual review; not a new full117-state audit.
- Only `deliverNotificationPush(us-central1)` deployed, verified ACTIVE with
  timeout120. All seven existing notification handlers remain ACTIVE.
- Packaged manifest references `readuo_social` and `ic_stat_readuo`; optimized
  vector resource `res/2a.xml` verifies24dp and white `0xffffffff` fill.
  Native channel existence confirmed without a production push.
- Evidence: `app/test/build30-{analyze,tests,release,apk-verification,upgrade,release-launch}.log`
  and `app/test/artifacts/readuo-build30-login.png`.

Physical two-account/two-phone receipt, actual lock-screen icon and
background/cold notification taps remain unverified. No test pushes or QA
content were written to production. iOS and billing remain deferred.

## Google Drive

Upload complete (100% and one-upload-complete UI), with build27/28/29 retained
after folder reload. Restricted access and existing collaborators unchanged.

Download: https://drive.google.com/file/d/1_4mpFCmOONzEpiMv8OPVodQEc2SUTBku/view

The download page was opened and its exact build30 filename verified.
Evidence: `app/test/artifacts/readuo-build30-drive-upload.png` and
`app/test/artifacts/readuo-build30-drive-access.png`.
Wait for user feedback; do not start unrelated work.
