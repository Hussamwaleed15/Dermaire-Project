# M2-F1 — Backend handoff for Hussam

Source inspected: `c84fc27ff229ebe7eed0ee03a4f3f950ebb33528`.
No backend/Azure/DB/AI/provider/production edits, live calls or deploy.
Supported Flutter guided capture is implemented; these are nonblocking needs.

## 1. Explicit Capture/Observation relationship

Actual /captures creates Capture + optional inline Measurement; report-only
/checkins creates a distinct CheckIn.observation. No capture_id relationship is
available in that report-only request/response. Capture proxies use fractional
appearance units, not the legacy 0..100 score baseline. Flutter does not attach
by time/content, convert values, mark check-in complete or increment baseline.

If product scope requires linking, define an explicit owner-validated reference
between an existing Capture and observation/check-in, with nullable relationship,
correction/deletion/account-erasure semantics and readable source IDs. Preserve
report-only unknowns and separate metric reference. Tests: cross-owner rejection,
missing/rejected capture, duplicate link/correction and deletion/readback.
This is a future authorized backend/product increment, not a client workaround.

## 2. Formal attempt lookup/fingerprint/idempotency contract

Existing capability: POST /captures accepts Idempotency-Key, derives owned
UUID5 identity, validates request_fingerprint, returns409 on changed payload,
serializes on owner lock, replays stored/rejected rows and can promote accepted
not_persisted storage later. This is NOT the missing report-only /checkins B2.
GET /captures/{id} and GET /measurements/{capture_id} already exist; by-ID readback
is NOT missing. Flutter uses actual returned ID + exact submitted fingerprint
for safe GET reconciliation; no POST retry or guessed UUID/correlation.

Real gap: a completely lost POST response gives no server ID. There is no owned
read endpoint by attempt key; a history content/time match is not proof of this
attempt. Formalize key/fingerprint encoding/version, durable retention/expiry,
replay/promotion/deletion/in-flight semantics and, if required, an owner-scoped
lookup by attempt key (including unresolved/not-found semantics). Avoid exposing
another owner's records or hashes. Tests: lost acknowledgement, concurrent same
key, changed source/MIME/bytes, storage recovery, restart/account deletion,
wrong owner and query while the original transaction is pending. Flutter's
unknown state remains honest until this is supported.

## 3. Proxy/schema/version continuity (existing v1 boundaries)

Current measurement-1.0 exposes only red_chromaticity_proxy and
texture_contrast_proxy, fraction_0_to_1, limited_image_proxy, exact capture ID,
quality reference/fingerprint, method/time/status/limitations. No calibrated skin
severity/hydration/clinical accuracy or treatment plan. Quality v1 leaves yaw,
pitch, occlusion and uneven lighting unknown; current comparisons cannot claim
validated longitudinal comparability. Flutter preserves these boundaries and
does not show improvement deltas or manufacture missing values.

For future richer measurements/comparison, publish versioned units/source/region/
quality/availability/time semantics and reference IDs. Do not silently change
v1 values into clinical scores. No Vision/provider enablement requested for M2-F1.

## 4. Individual image deletion — not implemented/requested as current capability

Only account erasure is confirmed. There is no individual-image DELETE route.
No fake Delete Photo action or automatic deletion-after-analysis promise in
Flutter. Any future image-only erasure is a separately approved product feature
with owner checks and durable journal/measurement/link/cache semantics.

Existing owned image GET with no-store and clinician-grant authorization is
acknowledged. Full image history/pagination/comparison belongs to later scope;
no missing existing image route invented. M1 B1/B2 handoffs remain unresolved
and separate. Do not treat this document as permission to alter production.
