# Readuo 1.21.2+34 delivery

Delivered October 4, 2026. Includes the icon-only circular green Circle FAB
and bounded feed-photo reuse described in `readuo-circle-photo-cache.md`.

- APK: `app/release/Readuo-1.21.2-build34.apk`, 78,147,039 bytes.
- SHA-256: `5D0F34A6FFA2D3666D8F55E902F7FD9085C850A548391253D49664204B637EC7`.
- Package `com.zipdosa.readuo`, version1.21.2/code34, minSDK24/targetSDK36.
- Signature verified: existing Android Debug signer SHA-256
  `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`.
- Normal release entry point with existing local Google Books configuration.
  No backend deployment, IAM change, or notification feature activation.
- Preceding source verification: 318 tests passed, one existing skip, clean
  analyzer, native Circle/composer rendering checks. This packaging pass
  verified install with `adb install -r`, code34, cold launch Status: ok,
  normal Google sign-in screen and empty crash buffer. No production sign-in
  or physical camera flow was exercised. Temporary storage threshold removed.
- Drive upload visibly reached 100%, retaining previous APKs. Sharing remains
  Restricted with the existing owner and one editor; permissions unchanged.

Download: https://drive.google.com/file/d/1WZmVKQ3wOlW-9nvade5x5UIRIgRbPlpl/view

Evidence: `app/test/build34-release.log`,
`app/test/artifacts/build34-release-launch.png`,
`app/test/artifacts/readuo-build34-drive-upload.jpg`.
