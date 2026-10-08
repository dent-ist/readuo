# Circle density and larger covers

Oct3 delivery update: these accepted source changes are now included in
1.20.0+31. See `readuo-build31-delivery.md` for the verified APK and Drive link.
The source-only status and build30 restoration below describe the earlier QA.

## Explicit user override

Source-only follow-up to build30: halve spacing between Circle cards, reduce
decorative padding around Like/Comment, and double book images. Preserve
full-width cards, top borders, privacy, interactions and accessible targets.
No version bump, new release artifact, upload or backend change is authorized.
The canonical HTML is unchanged. Detail/composer layouts are out of scope.

## Measurements

| Feed element | Before | After |
| --- | --- | --- |
| Between cards | 14dp | 7dp |
| Card vertical padding | 16dp | 8dp |
| Card horizontal padding | 16dp | 16dp |
| Header/content/media gaps | 14dp | 8dp |
| Gap above Like/Comment | 6dp | 0dp |
| Feed action vertical padding | Theme default | 0dp, minimum48dp target |
| Attachment/review/started/finished cover | 48x68dp | 96x136dp |
| Added/batch cover | 82x126dp | 164x252dp |

General cards become shorter. Larger covers can make book-bearing cards taller
despite reduced padding; total card height is not claimed to halve. The batch
strip remains horizontally scrollable. Feed titles/authors wrap rather than
being truncated, and image containment preserves the complete cover. The
existing detail review cover remains64x92dp with its prior detail text behavior.

## Verification scope

Focused Circle/engagement tests cover7dp rendered separation,8dp outer padding,
exact doubled cover boxes,48dp action targets, existing interaction/privacy
regressions, long titles and batch scrolling. All28 focused tests pass;
analyzer clean. Actual Android runs pass11 states each at390x844/font1.0
and360x640/font1.3, including visible action rows and the scrolled batch strip.
The first small run lost its emulator connection before testing; the bounded
rerun passed. This was not an app assertion failure.

Rendered feed states were compared with canonical Circle state8 and the
explicit density/cover-size override. Existing approved full-width cards and
top borders are preserved. Normal and small-screen renders received independent
bounded visual acceptance.
This is not a new full117-state audit.

Evidence: `app/test/artifacts/circle-density/`,
`app/test/artifacts/circle-density-small/`, `app/test/circle-density-tests.log`,
`app/test/circle-density-analyze.log`, `app/test/circle-density-native.log`
and `app/test/circle-density-native-small.log`.
Fixture cover placeholders are used; no production records or images changed.
Latest delivered APK remains1.19.0+30, unchanged.
Its SHA-256 remains
`5A6443C24FE625A2A4B81B3001D40638B8CC7264CCC8BA036F59EEA17FD9CFE6`.
Restored that release after debug QA; package version30 and normal login screen
observed. The initial `am start -W` timed out, but the subsequent screenshot
confirms the normal release screen (`app/test/artifacts/readuo-density-restored.png`).
Device390x844/font1.0 and temporary storage thresholdnull are restored, with
no adb reverse forwarding. No new APK is delivered for this change.
