# M2-F1 — Guided Camera & Capture Experience

## Source / scope

Started from clean main `c84fc27ff229ebe7eed0ee03a4f3f950ebb33528`, matching
origin/main and fresh GitHub main. Read app/AGENTS.md, architecture audit/M2
roadmap, current capture/observation/entry/state/API/tester code and actual
backend capture/quality/measurement/image-access implementations and tests.
English-only/direct Flutter. No prototype/gallery, backend/infrastructure/provider
changes, live API/OAuth, production build/deploy or later M2 increment.
Implemented supported M2-F1 scope; delivery is recorded by the final normal
main push in the completion report. Physical Android/iOS/emulator acceptance
belongs to the external testing team and was not performed by Codex.

## Camera architecture and package decisions

No camera dependency existed; file_picker remains the supported photo/document
fallback. Added pinned camera 0.12.1 (real native CameraController/CameraPreview,
front lens preferred, high preset, portrait capture lock, flash off where
supported, audio disabled). Official support is Android SDK24+/iOS13+ and lifecycle
is app-managed: [camera documentation](https://pub.dev/packages/camera).
The existing Flutter SDK default minSdk24 and iOS13 project already fit these
requirements; no signing, production URL or OAuth/provider settings changed.

Added permission_handler 13.0.2 to distinguish denied/permanently denied/restricted
on Android as well as iOS and open app settings after an explicit tap; the camera
plugin alone distinguishes permanent denial only on iOS. See
[permission_handler documentation](https://pub.dev/packages/permission_handler).
The existing iOS project uses Swift Package Manager; the camera Info.plist usage
key enables its camera permission strategy. Android camera hardware features are
optional; the app manifest removes the newly introduced plugin microphone
permission. Still-photo initialization is tested with enableAudio=false. No audio
or video capture is used; no broad new photo-library permission is requested.
Generated Windows permission-plugin registration is included; live camera is
explicitly Android/iOS only, with honest supported picker fallback elsewhere.
No Windows/web/desktop live-camera support is claimed.

Added image 4.9.2 for bounded file decode/orientation and crypto 3.0.7 for the
existing server upload fingerprint: [image documentation](https://pub.dev/packages/image).
They perform compatibility/metadata preparation, never a local image-quality,
medical-risk or skin-classification model. Other pinned dependencies remain.

CameraSession owns view lifecycle behind injectable CameraPort; NativeCameraPort
implements actual plugin and OS permission/file APIs. GuidedCaptureController
is one account-owned in-memory attempt on existing DermaireState, independent
of native camera lifetime. Immutable typed receipt/quality/proxy models and new
narrow authenticated ApiService methods isolate the official journey.

Legacy CapturePanel, CaptureController, photoUploadDisclosure, submitCapture,
getCaptureHistory, main_tester.dart and all app/lib/tester files remain unchanged.
The official observation photo entry now opens GuidedCameraScreen. Shared Flutter
dependencies/native declarations change for the official camera; the separate
Tester harness logic/UI/API paths were not changed or run against production.

## Actual inspected API contract

backend/app/api/v1/captures.py, services/capture_quality.py, measurement.py,
image_access.py and api/v1/measurements.py; capture and measurement backend tests.
Signed authenticated get_current_user determines owner; patient UI additionally
requires server-confirmed consent and patient session. No owner selector is sent.

POST /api/v1/captures multipart: photo JPEG/PNG, source camera/upload, view front,
optional Idempotency-Key <=128 chars. Limit 8 MiB, 16,000,000 pixels, one frame,
opaque image, declared MIME matching actual format, valid EXIF orientation.
Quality v1 expects >=640 each dimension and upright portrait/front-facing photo.
201 follows database commit. The response contains actual id, state accepted/
rejected, received_at UTC server receipt (not camera time), source/view, quality,
storage azure_blob/not_persisted, nullable image_reference and provenance:
timestamp server_received_not_camera_time, source/view client_reported, quality
server_computed and server_version. There is no response user_id. Ownership is
anchored in authenticated requests/session plus server owner filters; any present
stored reference is checked against the authenticated owner's prefix and discarded
from the DTO, not turned into a public URL.

Quality capture-quality-1.0: decision, checks{status pass/fail/unknown, metrics,
confidence measured/heuristic/unavailable, nullable reason}, reasons, thresholds,
limitations and request_fingerprint. Required checks: resolution/orientation/
face/framing/scale/roll/coarse_front_view/sharpness/exposure. Yaw/pitch/occlusion/
uneven_lighting remain unknown. Acceptance is a heuristic quality screen, not
identity recognition, diagnosis or proof of comparability. New DTOs retain
labels/reasons/limitations, not raw evidence/threshold/fingerprint logs.

Accepted uploads return inline measurement. measurement-1.0 has id/capture_id,
status measured/insufficient_quality/failed/unavailable, measured_at, two metrics,
capture_quality, comparison and provenance. Metrics are red_chromaticity_proxy
(median R/(R+G+B)) and texture_contrast_proxy (normalized grayscale residual),
unit fraction_0_to_1, nullable value, status/reliability/method_version/
source_capture_id/region/measured_at/limitations/reason. They are nonclinical
image appearance proxies, not legacy 0..100 hydration/redness/texture scores.
DTOs validate algorithm, capture ID, exact quality fingerprint, units, status,
finite range, reliability, region and timestamp consistency. Missing/unsupported/
malformed optional estimates stay unavailable while a valid capture receipt remains
confirmed. No client zero, probability, diagnosis, treatment or improvement delta.

GET /captures/{id} exists and returns owned metadata without inline measurement.
GET /measurements/{capture_id} exists, returns owned stored measurement, or 404
if not generated /409 for rejected capture. New flow uses these GETs only; no
historical generation POST, list/timeline/comparison functionality added.
GET /captures/{id}/image exists: authenticated own image (or authorized doctor
via live grant), no-store/nosniff bytes; 404 unavailable/unowned, 503 storage
failure. This increment uses a selected local preview only, not image URLs,
SAS or shared authenticated image caching. Remote image browsing is later scope.

Rejected quality retains metadata, not image bytes. Accepted-not-persisted is
supported in development/readback; production/staging refuses an accepted write
when live storage is unavailable and can return 503. Flutter reports only actual
receipt storage, never infers environment/provider settings. Quality is local
server OpenCV/Pillow and estimates deterministic; no Vision provider enablement.

## Capture / review / upload / result

Explicit Open camera or Choose JPEG/PNG -> real native preview with subtle oval
framing guide -> Take photo -> prepared local preview -> Confirm photo & upload
-> one request -> confirmed receipt (accepted or quality-rejected), definitive
request rejection, unknown write or ended session. Selection never uploads.
Retake/discard/back before submission drops the local preview without POST.
Native instructions are guidance only: consistent soft light, steady camera,
whole face/both eyes, portrait, similar distance. No verified alignment/light claim.

Result shows ID, actual server receipt time, confirmed storage and actual quality
reasons/limitations with expandable individual checks. Estimates use exact raw
values/units/algorithm/time and limited-proxy labels. Missing estimates can be
read from the existing GET route; no invented analysis stages or generation.
Return Home/back/another-photo actions use existing navigation; bottom tabs/Home
are unchanged. ClinicalHomePanel remains above capture/results; urgent guidance
is not delayed by motion. New result/unknown states expose the top guidance.

## Upload outcomes, idempotency and readback

One reviewed attempt has a private 128-bit random key and exact prepared bytes,
source/view/MIME fingerprint. Duplicate taps and route reopening cannot create
simultaneous POSTs. Upload/await-response is one honest indeterminate state,
not a guessed sequence or percentage. 60s timeout/offline/5xx/malformed or
contradictory acknowledgement is unknown; no automatic POST retries. Current 401
uses existing session invalidation; 400/403/409/413/415/422 are request rejection.
A quality-rejected 201 is a confirmed metadata receipt with no retained image,
different from request rejection or an unknown write.

Unlike report-only /checkins, Capture already supports owner-scoped idempotency:
UUID5 identity from owner+key (or content fingerprint), owner lock, conflicting
key/payload409, replay of stored/rejected rows, and possible not-persisted->stored
promotion when storage later becomes available. The client does not silently
replay or derive/guess server IDs. It preserves honest unknown outcome in memory.

Exact inspected capture-v1 fingerprint encodes Python JSON array with spaces:
[source, front, declared MIME, SHA256(upload bytes)], then SHA256 of that encoding.
A golden independent Python value tests client compatibility. Valid confirmation
requires the returned source/fingerprint to match this upload. Only an actual ID
received from the server can trigger GET reconciliation, which must match owner,
ID/source/fingerprint; content/time-only correlation or empty history is no proof.
No returned ID means no supported lookup for this attempt. Starting a separate
capture after uncertainty requires an explicit warning/acknowledgement.

Leaving during upload warns that it may continue/store; it does not claim network
cancellation. State retains attempt/receipt across view departure, rejects old
responses and releases local preview. Read timeouts20s preserve uncertainty or
receipt without resending. Optional estimate failures never revoke a confirmed
capture or manufacture a number. See Hussam handoff for formal attempt lookup.

## Preparation / privacy / lifecycle / isolation

Byte stream stops above8 MiB; decoder header rejects >16M pixels before raster
allocation. Single opaque JPEG/PNG required. JPEG EXIF orientation is validated
and applied by its decoder; PNG orientation is handled explicitly. Normal
orientation preserves pixel/scan data while stripping JPEG EXIF/XMP/IPTC/comments
and PNG EXIF/text/time chunks. Rotated JPEG alone needs quality95 re-encoding;
rotated PNG is lossless. No silent resize/downsample/crop or quality prediction.
Post-normalization byte size is checked again. Tests cover corrupt/unsupported/
alpha/animated/oversized/pixel-limit/EXIF cases. The pinned image library's
ExifData.read reports false on success; a bounded TIFF-orientation directory
reader avoids treating valid photos as corrupt or inventing orientation.

Camera-plugin-created temporary files are read with bounds and deleted immediately
in finally; original picker files are never deleted. Picker private-cache cleanup
uses its API, best effort where supported. No app disk image cache or health
persistence added. Preview decode width is capped800 and image cache entries are
evicted on replacement/discard/logout/disposal; raw preview references are dropped
immediately on confirmed/unknown outcome. No forensic RAM erasure guarantee.
Official welcome/upload disclosure reflects local review before explicit upload,
private Azure storage where available and account-deletion erasure only. Legacy
Tester disclosure stays aligned with its unchanged selection-and-upload behavior.
No individual stored-photo deletion or automatic post-analysis erasure claim.

Inactive/background/disposal releases native resources, invalidates stale camera
work and stops displaying a feed. Resume reopens only after an explicit previous
camera request. OS permission/discovery pending is handled separately from allocated
hardware, with a visibility check before native creation. Android's external
picker may emit hidden/paused; the explicitly authorized selection is retained,
not a camera stream. Logout/disposal/owner change always invalidates it. Camera
initialization/release waits are bounded20s, capture/preparation30s; slow cleanup
must not freeze gallery fallback. Native runtime errors are mapped without raw
exception details. Actual hardware cleanup/timing still needs device acceptance.

Session generation/owner/request revision protect native preparation, POST/GET,
results and navigation. Same-token old401 cannot end a newer account. API/role/
server-consent guards precede every upload/read; consent revocation closes camera
and clears health state through existing session notifications/account listener.
No plaintext photo/key/result persistence, raw medical/credential/image logs or
cross-account preview reuse. Captures remain separate from observations, safety,
clinician decisions and baseline; no automatic linkage, completion or score conversion.

## Design / automated evidence

Approved theme tokens/Fraunces/Karla/native cards/buttons retained; English-only.
Real camera surface, calm framing guide, explicit steps, focused button feedback,
existing route motion and bounded detail expansion; Reduced Motion uses immediate
routes/details and static upload feedback. Medical colors/meaning remain separate.
Safety/source/status text/icons and live feedback support screen readers; 320px/
200% text tested in light/dark and normal/reduced motion for review and results.

Final checks: flutter analyze clean; full flutter test **619 passed** = **510
retained +109 new** (100 guided/file/contract/service/widget cases +9 real adapter
cases via fake native channels). Prior tests retained; welcome disclosure assertion
updated/strengthened for explicit upload. All Google/password/consent/profile,
M1 safety/history/uncertain writes/Home/provenance/Tester regressions pass.
Test binding denies unmocked HTTP; fake transports assert flutter-tests.invalid.
No production/staging/provider/OAuth calls or real camera/emulator tests. Diff/XML
checks pass and protected-source byte comparisons pass.

## Modified files (22)

- app/pubspec.yaml; app/pubspec.lock
- app/android/app/src/main/AndroidManifest.xml
- app/ios/Runner/Info.plist
- app/windows/flutter/generated_plugin_registrant.cc
- app/windows/flutter/generated_plugins.cmake
- app/lib/capture/camera_session.dart
- app/lib/capture/native_camera_port.dart
- app/lib/capture/photo_preparation.dart
- app/lib/capture/guided_capture_models.dart
- app/lib/capture/guided_capture_controller.dart
- app/lib/capture/guided_camera_screen.dart
- app/lib/capture/guided_photo_disclosure.dart
- app/lib/services/api_service.dart
- app/lib/dermaire_state.dart
- app/lib/observations/observation_ui.dart
- app/lib/entry/entry_copy.dart
- app/test/guided_capture_test.dart
- app/test/native_camera_port_test.dart
- app/test/photo_disclosure_test.dart
- app/docs/M2_F1_GUIDED_CAMERA.md
- app/docs/M2_F1_HUSSAM_HANDOFF.md

## Remaining boundaries / external acceptance

Supported M2-F1 code and automated gates complete; physical Android/iOS/emulator
acceptance pending with the designated team. They should use approved synthetic/
nonproduction transports, validate first/permanent permission/settings, no hardware,
front/rear availability, portrait/EXIF, picker Activity/cancel, pause/resume/disposal,
8MiB/16MP/corrupt files, narrow/large text/reduced motion, confirmed/rejected/unknown/
401 cases and temporary-cache cleanup. No device/performance certification claimed.
No full image history/timeline/comparison, PSM/AI/doctor redesign, standalone image
delete, Capture/Observation linking, provider configuration or M2-F2 work included.
