# Measurement Engine v1

## Authority and scope

The backend records two deterministic **image appearance proxies**, not skin health,
medical measurements, diagnosis, disease, sensitive attributes, or population rankings.
This milestone does not establish a clinically validated longitudinal skin model.
Flutter remains unchanged and calculates no canonical metrics. Backend API clients
can read structured results; a Flutter measurement surface is intentionally deferred.

## Metrics and algorithm (`measurement-1.0`)

Use the existing Pillow decoder and OpenCV 4.12.0.88 frontal Haar detector. Analyze
RGB at longest side 800 pixels with the same Pillow resizing as Guided Capture.
Require one detected face. Relative to its bounding rectangle, take two cheek
rectangles: x 0.18–0.36 and 0.64–0.82, y 0.50–0.68; integer edges use Python round.
Each patch must be at least 16 pixels on both sides. These are **fixed image regions**,
not validated skin masks; cosmetics, hair, facial hair, shadows, occlusion and imperfect
localization can contaminate results. No skin-tone or sensitive-attribute classification
is used to select pixels. No cheek images, landmarks or embeddings are persisted.

Require at least 90% of each patch's grayscale pixels to be strictly between 20 and
235. Otherwise the entire set is `insufficient_quality`, with null metric values.
Exposure is an input-quality screen only, never a health metric.

| Key | Value / unit | Meaning and limitations |
| --- | --- | --- |
| `red_chromaticity_proxy` | median R/(R+G+B), `fraction_0_to_1` | Pool usable pixels from both cheeks; measures relative red-channel contribution in camera RGB. Not inflammation, redness severity, redness area or an erythema index calibrated to skin physiology. |
| `texture_contrast_proxy` | mean absolute grayscale residual / 255, `fraction_0_to_1` | Each entire patch is resized to 64×64 using OpenCV INTER_AREA; subtract a 5×5 Gaussian blur (sigma=0, default border), take mean absolute residual and average the two patches. Measures local image contrast, including noise; not physical surface roughness, pore size, scars or lesion burden. |

Values are bounded [0,1] and rounded to three decimal places to avoid excessive
numeric detail. This is storage/display quantization, **not** an accuracy claim.
The texture metric may include up to 10% clipped pixels after the patch screen;
its limitations and limited reliability remain explicit. Chromaticity is invariant
to ideal uniform channel multiplication without clipping, but is not invariant to
white balance, nonlinear camera processing, illumination color or cosmetics.
Gaussian residuals capture local contrast and noise; they cannot separate the two.
Synthetic tests establish arithmetic behavior, not clinical validity or fairness.
The public-domain NASA fixture verifies actual detection and end-to-end computation.
Representative skin-region and repeatability validation remains outstanding.

Implementation primitives follow [OpenCV Gaussian filtering](https://docs.opencv.org/4.12.0/d4/d13/tutorial_py_filtering.html)
and [RGB grayscale conversion](https://docs.opencv.org/4.12.0/de/d25/imgproc_color_conversions.html).
These references document image operations; they do not validate the resulting
proxies as medical or scientifically comparable skin measurements.

### Excluded metrics

* Hydration: ordinary RGB photographs do not provide a justified water-content
  measurement here; no hydration result is emitted.
* Spots, blemish or lesion counts/burden: no validated localization, segmentation,
  lesion detector or threshold calibration exists in the current libraries/code.
* Redness area: no validated skin mask or erythema threshold; use only relative
  cheek image chromaticity, with the limitations above.
* Physical roughness, elasticity, pores, wrinkles, melanin or barrier health: no
  calibrated acquisition/reference instruments or validated algorithms.
* Brightness/illumination as health, diagnosis, attractiveness score, population
  percentiles and causal interpretation: excluded from both values and deltas.

## Processing and honest storage

`POST /captures` first runs unchanged Guided Capture. Accepted captures generate
one canonical measurement set **synchronously from the uploaded decoded pixels**
before request bytes are discarded. Rejected captures never get measurement rows.
Capture plus measurement are flushed and committed together; database/storage
failure rolls back both. Unexpected numerical/detector failure records `failed`
with null values, preserving accepted capture linkage; insufficient region/exposure
records `insufficient_quality`. There is no fabricated success fallback.

Real Azure persistence remains unchanged. With `storage=not_persisted`, only capture
quality and measurement JSON persist. No durable image byte history is invented,
no image file is written by this engine, and no extra Azure infrastructure is added.
Images may exist in request memory and framework multipart temporary spooling.
The existing Blob upload behavior, compensation and deletion limitations still apply.

Old captures cannot be retroactively measured from metadata. Generation for an
old accepted capture with no current-version set records immutable `unavailable`
results with `historical_image_bytes_unavailable`. v1 deliberately does not fetch
historical Azure blobs either, even if a capture has a blob key; the reason denotes
unavailability to this generation operation. New captures use upload bytes in both
storage modes. It never accepts replacement images for old capture references.
An unavailable/failed set stays immutable for that capture/version. A version change
creates a distinct set; without retained/retrievable pixels it remains unavailable.

## Status, confidence and provenance

Sets and each metric report `measured`, `insufficient_quality`, `unavailable` or
`failed`. Measured values have reliability band `limited_image_proxy`; all other
states have reliability `unavailable` and null values. There is no invented confidence
probability. `measured` means the arithmetic was supported by screened image regions,
not proof those regions are skin or that the result reflects a skin-health change.

Each metric includes key, value, unit, proxy meaning, status, reliability, method
version, source capture ID, server UTC measured_at, region definition, reason and
limitations. The set includes algorithm version, accepted capture reference, server
measurement time, full immutable capture-quality snapshot and comparison result.
Capture receipt time is server receipt, not camera acquisition time. No uploaded
filename, EXIF/GPS, inferred sensitive attribute or raw pixel data is stored here.

## Conservative comparability

Same authenticated owner only; accepted captures, measured sets, same algorithm
and quality version. Search strictly earlier captures in receipt-time/ID order,
newest first, and use the most recent **comparable** candidate. If none is comparable,
retain the nearest earlier measured candidate ID and its blocking reason for context;
`previous_comparable_measurement_id` remains null. Never compare to a future capture.
History is ordered by capture receipt time/ID descending, with algorithm version as
an additional deterministic tie-breaker, not by the time an old set was generated.

All four yaw, pitch, occlusion and uneven-lighting checks must explicitly pass.
Unknown, missing or failed dimensions block deltas. Quality scale, roll, exposure,
framing and sharpness checks must pass with finite numeric values. Candidate mismatch
bounds: face-width fraction 0.05; roll 3 degrees; each clipping fraction 0.03; each
normalized framing offset 0.03; sharpness variance ratio at most 1.5. Metric status,
unit, method version, finiteness and bounds must also match.

**Current Guided Capture v1 always leaves the four dimensions unknown. Therefore
all genuine current production comparisons are `not_comparable`; no deltas or
trend claims are emitted.** Acceptance alone never grants comparability.

The conditional comparison branch is exercised only with hypothetical complete
server quality snapshots in tests. Before a future quality gate can enable it,
validated pose, occlusion and illumination checks and repeatability evidence are
required; these engineering tolerances alone are not scientific validation. Signed
deltas use the metric's fraction unit. Absolute changes <=0.010 chromaticity or
<=0.005 contrast are `no_meaningful_change`, **engineering tolerance only**, with no
clinical significance. Larger changes are `increase`/`decrease`, never better/worse,
causal or treatment-success claims. The current production gate cannot reach them.

## Authenticated API

Existing account/session auth applies to every endpoint. Ownership is checked for
both capture and measurement; sessions cannot read another user's records.

* `GET /api/v1/measurements?limit=50`: bounded recent sets (limit 1–100).
* `GET /api/v1/measurements/{capture_id}`: own current-version set; 404 if missing.
* `POST /api/v1/measurements/{capture_id}`: return existing canonical set idempotently,
  or record unavailable for an old accepted capture. No body or empty JSON object
  is allowed; client metrics/algorithm/quality fields are rejected with 422.
* `POST /api/v1/captures`: unchanged multipart contract, additive `measurement`
  response on accepted captures; rejected captures have no measurement field.

Foreign/missing capture references yield 404; rejected capture references 409;
authentication failures 401; invalid input/query 422. Existing decoder returns
413/415/422 for oversized/unsupported/corrupt images, with no partial capture or
measurement persistence. Persistence failures return 503 with rollback.

## Schema, deployment and privacy/deletion

One new table `measurements`: id, user_id FK, capture_id FK, algorithm_version,
status, measured_at, results JSON, quality_reference JSON and comparison JSON.
Unique `(capture_id, algorithm_version)` protects idempotency, status CHECK restricts
states, owner/capture indexes support reads. Ownership/accepted-state checks are
explicit application invariants; separate FKs alone do not enforce their combination.
No existing table columns change; no cascade deletion is assumed. Previous references
are IDs in comparison JSON belonging to the same owner; account deletion explicitly
deletes measurements before captures and users, after external image cleanup succeeds.
Inconsistent cross-account capture links block deletion rather than altering another
account. External cleanup failure retains metadata for retry, matching Guided Capture.

**Production migration is required before deployment.** Apply exactly one matching
additive transactional manual migration, once, after an operational backup:

* `docs/migrations/measurement-engine-v1-postgresql.sql`
* `docs/migrations/measurement-engine-v1-sqlite.sql`

SQLite migration is executed in tests with FK enforcement, uniqueness, invalid states
and deletion restrictions. PostgreSQL SQL is generated using the installed SQLAlchemy
PostgreSQL dialect; no live PostgreSQL or production migration is run in this milestone.
UTC follows existing naive-database/explicit-UTC-response convention. PostgreSQL user
row locking serializes writes with account deletion; SQLite relies on its transaction
and uniqueness constraints, without pretending `FOR UPDATE` works there.
No commit, push, migration, deployment or production smoke test is performed here.

## Future boundary

These canonical capture-linked observations could feed Personal Skin Model v2,
experiments or doctor summaries only after acquisition/skin-region/repeatability
validation and validated missing quality dimensions. They must keep limited proxy
semantics and never substitute for clinical interpretation or infer causality.
This milestone does not wire them into those downstream engines, disease detection,
Product Intelligence, Safety Engine, Contextual AI, Doctor Loop v2, notifications,
Azure infrastructure or animation work.
