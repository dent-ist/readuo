# Corrective integration — build 26 delivered

September 27, 2026. Build 26 delivers these corrections; builds 24 and 25 remain available in the original restricted Drive folder. The build-25 review remains a historical baseline, not final acceptance.

## Deployment gate

The user confirmed the owner grant after the initial blocker. The single bounded retry successfully deployed all eight functions. Live inspection verified 24/24 functions ACTIVE: four new profile functions and four updated deletion functions, preserving the others. The Storage finalizer is in `us-east1`, matches the exact existing bucket, retries generation-matched cleanup, and has a 60-second timeout/maxInstances 3. Profile callables remain in `us-central1`, 60 seconds/maxInstances 3; reconcilers have 540-second timeouts/maxInstances 1. Firebase CLI configured one-day Artifact Registry image cleanup in the new region; this is deployment-image cleanup, not user-data retention or a billing upgrade. The earlier failure below is retained as history, not a request for another grant.

The initial bounded eight-function deployment stopped in preflight because Firebase CLI could not grant the Storage service agent the Pub/Sub publishing role required for Eventarc. All 20 existing functions remained ACTIVE during that blocker.

The owner resolved the blocker with this minimum grant, without changing billing or assigning broader roles:

```powershell
gcloud projects add-iam-policy-binding readuo-b2f24 --member=serviceAccount:service-881895077363@gs-project-accounts.iam.gserviceaccount.com --role=roles/pubsub.publisher
```

The initial CLI error was “We failed to modify the IAM policy for the project.” Denied access was not bypassed or repeatedly retried; deployment resumed only after the user's grant confirmation. The finalizer uses generation-matched, idempotent cleanup with retries; the deployment's `--force` acknowledged that retry policy, not account/data deletion.

## Safety and recovery

- Profile setup now uses the canonical shell and shared camera/gallery picker, with UID-isolated persisted name/photo drafts and Android lost-result recovery.
- Draft loading disables editing until restoration finishes; storage failure offers explicit retry without overwriting the unread draft. Onboarding photo-save failure retains the selected photo and completes name setup only after a successful retry.
- Completed server deletion is not presented as completed local cleanup. All cleanup operations are attempted; failures retain a completed server checkpoint and retry local cleanup without restarting server deletion.
- Profile media reservations coordinate Auth and readerProfiles changes. Lease ownership and expiry are checked transactionally before committing or claiming removal. The 660-second lease exceeds the longest configured profile invocation (540 seconds).
- A reservation enters `committing` before the external Auth write. Ambiguous writes remain protected even if the holder expires; a successful fenced retry marks them committed. This deliberately favors preserving possibly referenced images over deleting an uncertain orphan.
- Daily cleanup checks both Auth and readerProfiles references. It only sweeps tagged managed-v2 objects. Historical untagged active-account orphans and unresolved committing uploads are **not guaranteed to be swept**. Account deletion still removes all owned media and operation records, without a retention period.
- Reservation cleanup now paginates beyond retained objects. A late-upload finalizer removes exact object generations belonging to inactive/deleting accounts.

## Evidence so far

- Backend: 43 tests passed, including expiry takeover during Auth save, stale reconciler takeover, and pagination past 100 retained objects.
- Local Firestore/Storage emulators: 75 tests passed after those server changes. No production QA data was written or deleted.
- Flutter: full run 269 passed, one opt-in golden skipped, including onboarding-photo failure/retry and shared-icon changes. Final Book/Circle guidance/spacing changes additionally passed all 32 relevant tests.
- Android captures use production widgets with deterministic local repositories, not production end-to-end data. Source: `app/integration_test/final_review_test.dart`; host image writer: `app/test_driver/final_review_driver.dart`.
- Raw captures: `app/test/artifacts/final-review/`. Normal files are 390×844; `-small-large-text` files are 360×640 with 1.5× text scaling. `-FAILED` captures are diagnostic only and must never count as accepted evidence.
- Exact current versus retained historical state evidence is recorded in `docs/readuo-corrective-evidence-matrix.md`: 79 canonical IDs have current fixture renders, 38 retain earlier evidence, and five supplemental captures cover keyboard/photo access/profile-bottom. These counts are not all-117 fresh acceptance.
- Normal and small/large-text runs both passed 84 captures with no recorded render failures, covering every historical U/W/G ID plus profile-bottom. Missed taps are now fatal; fixture scrolls settle before interaction. The two small-screen dialog overflows were corrected with scroll-controlled, scrollable sheets. Final Book/Circle guidance/spacing refinements additionally passed four focused captures at both sizes, with separate `manifest-refinements*.json` files. The repeated full run interrupted by an emulator disconnect is not counted as a pass. Normal focused retry recovered the driver connection and passed.
- Canonical reference captures now load pinned Lucide through the QA wrapper, without changing the authoritative handoff. All 117 full-page reference PNGs were recaptured after verifying icon replacement. Earlier blank cropped or missing-icon reference captures were invalid and have been replaced.
- Shared navigation now uses the canonical Lucide icon family. The source has corrected Friends request controls, sent-request confirmation, moderation rows, root Circle header and book-detail controls; fresh device render comparisons remain the acceptance gate.

## Delivery and acceptance limits

- IAM and deployment gates are resolved. Logs: `app/test/p1-correction-deploy-after-grant.log` and `app/test/p1-correction-functions-deployed.json`.
- Coordinator read-only comparison accepted the bounded structural corrections to Friends, request confirmation, reporting/moderation, book controls, Circle root navigation, and profile-bottom controls, including the final Book/Circle guidance and spacing after the focused rerenders. This is not all-117-state pixel acceptance.
- Build `1.17.1+26` is uploaded: https://drive.google.com/file/d/1cMqrH1nqTsXsMbfgqgns3h92H85wqpEG/view . Drive showed 100% completion and all three APK rows. Prior files and sharing permissions were not changed.
- Local APK: `C:\dev\ai\readuo\app\release\Readuo-1.17.1-build26.apk`, 77,305,628 bytes, SHA-256 `74E13CAC07F31CE79566242AE65369EF449A2835D6EEB15DA3D0060013A7CDD2`.
- Verified package `com.zipdosa.readuo`, versionCode 26, minSDK 24, targetSDK 36, and unchanged signer SHA-256 `4df0fced63b42f630c45df3f60000e8f7e6d7e89e75e64d74b491574b5e7b1f7`. This remains the Android Debug certificate, not store signing.
- Release upgrade from build 25 and normal `main.dart` launch succeeded with no captured Flutter/AndroidRuntime error. Evidence: `app/test/artifacts/p1-final-build26-login.png` and `app/test/artifacts/p1-final-build26-drive-upload.png`. No integration-test entrypoint is packaged.

Independent local validation is complete: clean analysis, 269 Flutter tests (one opt-in golden skipped), 32 final relevant Book/Circle tests, 43 backend tests, 75 local Firestore/Storage emulator tests, 84-state normal/small runs and the final four-state normal/small refinements. Native keyboard insets were 299 pixels in both sizes; header wrapping and reachable bottom actions were visually checked. No production QA data was written/deleted. Build 25 was reinstalled and launched on the QA emulator after test cleanup; its viewport is restored to 390×844.

No claim of all-117-state fresh pixel acceptance, store readiness, or physical-device acceptance is made here. Physical-phone Google reauthentication/deletion, FCM delivery, camera/gallery and external invite acceptance remain separate checks. No production QA writes/deletions were used to prove those flows. New APK delivery is verified as described above.
