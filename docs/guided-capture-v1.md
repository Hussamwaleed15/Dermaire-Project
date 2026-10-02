# Guided Capture + Image Quality Gate v1

## Scope and authority

This is a non-medical, post-capture quality screen. It does not diagnose, recognize
identity, detect lesions, infer skin conditions, or produce skin measurements.
Quality results are stored in `captures`, separately from check-ins and future
Measurement Engine results. Existing journal observations continue to work.
Flutter's photo workflow now uses `/captures`; it never invokes the legacy image
measurement path when checking capture quality.

The backend computes all results using Pillow and OpenCV 4.12.0.88 (bundled Haar
frontal-face and eye cascades). There is no Azure AI call and no simulated or local
success fallback. Missing/broken detectors produce 503 and no capture row.
Reference: https://docs.opencv.org/4.12.0/db/d28/tutorial_cascade_classifier.html

## Flow and states

1. Flutter shows static capture guidance: upright front view, one centered face,
   both eyes visible, soft even light, steady camera, repeat distance and lighting.
2. The user takes a photo using their device's camera app and selects JPEG/PNG.
   Flutter sends `source=upload`; it does not claim direct camera capture.
3. `ready -> checking`: server decodes and validates the image, then assesses it.
   Pending processing is transient, not a persisted draft. No asynchronous job is
   implied and there are no mutable acceptance endpoints.
4. Valid decoded photographs yield immutable `accepted` or `rejected` records.
   Rejected photographs retain quality metadata only. Invalid requests yield 4xx
   and no record. Infrastructure/save failure yields 503, never acceptance.
5. Flutter displays server-confirmed acceptance or actionable rejection reasons.
   Retake clears the old result before selecting/submitting another photo.
   Failure clears acceptance. Late responses after retake/disposal/logout are
   ignored. Capture history can be refreshed after an uncertain network outcome.

No live camera preview/frame analysis, device camera control, face overlay tracking,
or automatic editing is implemented. Native camera EXIF rotation must be applied
when exporting an upright photo; v1 deliberately requests retake/export instead of
silently rotating, enhancing, sharpening or changing exposure.

## API

All endpoints use existing authenticated account/session dependencies and ownership
filters. No client-supplied owner, acceptance, quality values or foreign reference
is used. There is no previous-capture linkage in v1.

* `POST /api/v1/captures`: multipart `photo` required; `source` is `upload` or
  `camera` (client reported), `view` is `front` only. Returns 201 for either assessed
  decision. MIME and decoded format must match JPEG/PNG.
* `GET /api/v1/captures?state=accepted&limit=50`: optional accepted/rejected filter,
  latest first, limit 1–100. This is a bounded recent history, not pagination.
* `GET /api/v1/captures/{id}`: own capture metadata; foreign/missing IDs return 404.
* `GET /api/v1/captures/{id}/image`: own persisted image only, authenticated PNG
  response with `Cache-Control: no-store` and `nosniff`. No public URL or SAS is
  returned. Foreign/missing/unpersisted images return 404; storage outage 503.

413: over 8 MiB encoded or over 16,000,000 pixels. 415: unsupported/mismatching
format, animation, or transparency. 422: corrupt image or invalid form/query
values. A decodable undersized image is an assessed rejection (201), with an
actionable resolution reason. Auth failures follow existing 401 behavior.

The route bounds the file read to 8 MiB + 1 and rejects decompression bombs before
decoding pixel data. Multipart parsing can spool uploaded input before the route
runs; deployments should also enforce an ingress request size/rate limit. No
original filename is stored. EXIF/GPS are stripped from retained image bytes.

## Deterministic quality rules

`backend/app/services/capture_quality.py`: immutable `Thresholds` / `RULES` is the
single configuration source. The full threshold snapshot and gate version
`capture-quality-1.0` are saved with every result. Threshold changes require a new
gate version; historical rows are never silently reassessed.

| Check | Rule |
|---|---|
| Resolution | Both dimensions >= 640 pixels; max decoded area 16 MP |
| Orientation | EXIF orientation absent/1, height >= width |
| Face | Exactly one detected frontal face; detector scaleFactor 1.1, minNeighbors 5, minSize 80 × 80 on analysis image |
| Framing | Face center within 0.15 of each normalized frame-center coordinate; all bounding-box margins >= 0.03 |
| Scale/distance proxy | Detected face width 0.30–0.70 of image width, inclusive; no physical distance claim |
| Coarse front view | Exactly two eye detections in upper half of detected face; left/right centers in respective interior halves; eye spacing 0.20–0.70 of face width |
| Roll proxy | Absolute angle of detected eye-center line <= 10 degrees |
| Sharpness | Variance of grayscale Laplacian >= 20 after face ROI resized to 256 × 256 with area interpolation |
| Exposure clipping | ROI pixels <= 10 at most 35%; pixels >= 245 at most 20%, on 8-bit grayscale |

Analysis image is resized to a longest side of 800 pixels; no adjusted analysis
image is stored as the photograph. The face ROI is used for sharpness/exposure
when one face is detected, otherwise the full frame is assessed (and face check
still rejects). Stored accepted images preserve decoded original RGB pixels,
losslessly re-encoded to PNG without metadata. No quality-improvement filter is
applied. These rules are conservative engineering heuristics, not clinically or
population calibrated thresholds. The fixture establishes detector operation,
not medical validity or demographic fairness. Upscaling cannot restore detail;
v1 does not reliably detect previously upscaled or edited images.

Every required check must be `pass` for overall `accepted`. Required unknowns
(e.g. roll cannot be computed) reject. Reasons deduplicate actionable guidance:
center face, move closer/farther, face forward/level, improve light, hold still and
refocus, or use higher resolution. Rules do not use skin tone, sex, ethnicity, age,
or brightness-based skin classification. Exposure checks only detect extreme
clipping, and can still have false rejects; repeatability/fairness requires future
representative validation before scientific comparison claims.

Yaw, pitch, occlusion (including hair/hand/mask/glasses glare), and uneven lighting
are explicitly `unknown`, confidence `unavailable`, and non-blocking in v1. Eye
detection is only a coarse pose proxy; it cannot establish these missing checks.
Numeric roll is heuristic, not a calibrated head-pose estimate. Measured pixel
checks carry confidence `measured`; detections/proxies use `heuristic`. No invented
probability is returned. `accepted` therefore means the implemented screen passed,
not that all obstructions/pose/lighting problems are absent or that the capture is
scientifically comparable. No downstream measurement should treat it as such.

## Provenance

Rows include authenticated owner, immutable server receipt timestamp in UTC,
client-reported source and front-view label, quality version/threshold snapshot,
per-check status/metrics/confidence/reason, decision, server app version, and real
storage key when persisted. `received_at` is server receipt time, **not** camera
capture time. Capture time, device model and app version are omitted because the
current file picker does not reliably supply them. Source/view are explicitly
client reported. Quality is `server_computed`.

## Storage, privacy and deletion

The existing Blob adapter supports configured Azure and a local offline fallback.
The new capture path never uses that local fallback or its static public route.

* Without configured real Blob storage: actual server CV assessment and metadata
  persistence work. Both decisions return `storage=not_persisted` with null image
  reference. The UI explicitly says accepted images were **not stored**. No local
  image file is written by this feature. Metadata-only captures cannot later supply
  pixels for Measurement Engine analysis.
* With configured real Blob storage: only accepted images upload, after verifying
  the container is private. Upload uses a generated owner namespace and no
  overwrite, no SAS generation. Failures never downgrade to local success.
* Rejected images are not retained by application storage in either mode. Decoded
  images and request bytes exist during processing; framework multipart temporary
  spooling may use host disk. No claim that photos stay on the device is made.
* Image bytes, filenames, EXIF, secrets, signed URLs, device identifiers and detector
  embeddings are not logged/stored as metadata. Only quality metrics are retained.
* Account deletion deletes capture images before metadata/user rows. Existing Blob
  deletion refuses to claim permanent cleanup with retention/versioning/historical
  copies present; the account remains retryable on external deletion failure.
* Upload/DB failure rolls back metadata and attempts deletion of the generated key.
  DB and Blob storage are not a distributed transaction: failed compensation may
  leave an object under the owned namespace. Existing `delete_owned_images` covers
  those objects on account deletion. This is a documented operational limitation,
  not a claim of guaranteed immediate cleanup after simultaneous outages.

Live Azure access, production persistence, retention policy, cloud recovery and
production migration were **not** exercised by local verification. Cloud adapter
branches are tested with controlled test doubles. No Azure infrastructure or AI
integration rollout is included in this milestone.

## Schema and manual deployment

New table: `captures`, FK to users, owner index, checks for decisions, source/view,
and storage consistency. JSON quality is separate from measurement/check-in tables.
There are no changes to existing table columns or prior milestone semantics.

Apply **one** matching manual migration before deploying the API:

* PostgreSQL: `docs/migrations/guided-capture-v1-postgresql.sql`
* SQLite: `docs/migrations/guided-capture-v1-sqlite.sql`

Back up first using the established operational workflow. Migration is additive
and transactional, intended once (not `IF NOT EXISTS` drift masking). Verify table,
FK/index/check constraints and backend dependency installation after applying.
Do not replay on an already migrated database. SQLite migration is tested against
an enforced-FK in-memory database; PostgreSQL SQL is generated from the same model
using the PostgreSQL dialect and has not been applied to a production server.
Existing DateTime convention stores UTC without timezone and serializes UTC.

Deploy backend with `opencv-python-headless==4.12.0.88`; deploy Flutter after the new
API is available. No commit, push, migration, or production deployment is performed
by this implementation task. Rollback to old code can leave the additive table in
place; dropping it would destroy capture history and is not a routine rollback.

## Verification and future boundary

Backend tests cover a real NASA photograph with actual face/eye detection,
determinism, blur, clipping, geometry boundaries, unsupported/corrupt/oversized
images, immutable structured provenance, isolation, storage failures, metadata-only
mode, and account deletion. The public-domain fixture is attributed under
`backend/tests/fixtures/README.md`; geometry boundary tests use injected detections
and are not described as real-world pose validation.

Flutter tests cover ready/checking/accepted/rejected/failure, server-only acceptance,
actionable reasons, retake, stale-result suppression and honest non-persistence.
Full backend suite, Flutter suite, analyzer and `git diff --check` must pass before
external closure. Exact run totals are recorded in the milestone handoff report.

Measurement Engine v1 now consumes accepted upload bytes synchronously before
request discard; see `docs/measurement-engine-v1.md`. It cannot recover historical
pixels from metadata-only captures. Current unknown quality dimensions block all
production deltas; capture acceptance alone never establishes comparability.
