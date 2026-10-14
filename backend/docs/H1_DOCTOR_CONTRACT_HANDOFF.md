# H1 doctor consent contract — Hussam / Amr

Source-only backend change, 2026-10-14. No Flutter, native, provider configuration, production/cloud resource or live database changed. Flutter linking stays blocked until Amr separately integrates and verifies the contract and the deployed backend is separately released. This code does not implement a clinical export API or prevent a clinician saving bytes already legitimately displayed.

## Root cause / corrected authority

Before H1, QR creation explicitly wrote `export_consent=True`, the ORM default was also true, and claim accepted both pending and active codes. There was no distinct export selection/readback; the same doctor could replay a claim. Existing patient grant reading/revocation, clinician notes, review expected_sequence CAS and current clinical image viewing were already real and are preserved.

After H1, legacy no-body POST generation grants VIEW intent only. New explicit export requires a true separate boolean and an existing selected doctor. VIEW includes existing patient list/detail/timeline, clinical notes/reviews and authenticated image viewing. EXPORT is distinct additional consent, never implied by VIEW; no export route is added. Future export consumers must call `doctor_loop.authorize(db, doctor, patient_id, scope="EXPORT")`, not inspect the stored boolean. This helper denies unknown scopes, legacy export booleans, pending/revoked/expired grants and another doctor's grants. It can find an eligible explicit export grant even if a newer view-only grant exists.

## Existing routes and additive payload

`POST /api/v1/doctor/generate-qr?minutes_valid=60` remains patient-only; expiry limits 15–1440 minutes remain. No body means VIEW only, never export; it is a temporary bearer invitation that the first authorized doctor can claim once. New clients should bind the selected clinician even for VIEW:

```json
{"view_consent":true,"export_consent":false,"doctor_id":"selected-doctor-id"}
```

Separate patient export selection uses `export_consent:true` with a selected doctor. Missing view intent in a supplied body, false/nonboolean view, nonboolean export, extra authority fields, or export without doctor: 422. Missing/non-doctor selected ID: generic 404. No clinician directory or license badge is invented: existing live account role is provisioning authority, not license verification.

Generate still returns access_token/qr_payload/expires_at/instructions; additive `access` is the authoritative pending consent receipt. JWT is signed, not encrypted; do not log/cache/share it outside the intended QR handoff. No tokens are returned by patient grant readback or clinician receipts. Token expiry and stored expiry agree to the JWT second.

`POST /api/v1/doctor/claim` retains `{"access_token":"..."}`. Successful 200 returns existing success/message plus `access`. Code is single-use: same doctor replay 409, another doctor 403, invalid/expired/revoked code 400, unavailable patient or stale consent 403. SQL conditional pending→active transition prevents concurrent overwrite/replay. Role/session/credential enforcement remains in current authentication dependencies. Pending codes issued by a logged-out patient session or old credential fail; existing active grants continue until expiry/revocation/deletion. Old pre-H1 pending codes fail closed and must be regenerated; old active grants retain existing clinical VIEW only and cannot imply EXPORT.

`GET /api/v1/doctor/access`, DELETE `/access/{id}`, doctor list/detail, claim and generation expose additive receipt fields:

| Field | Meaning |
|---|---|
| id/patient_id/doctor_id/granted_by | Server grant, subject, assigned/intended doctor and patient actor |
| doctor_name | Current stored full name when DB context is available; nullable, no license claim |
| consent_version / consent_source | 2 + explicit_patient_intent for verified new receipt; legacy_view_only otherwise |
| view_consent / export_consent / scopes | Recorded supported intent; legacy boolean alone never enables export |
| effective_scopes | Granted scopes only while active and unexpired, otherwise empty; pending is not usable access |
| status/created_at/expires_at/claimed_at/revoked_at/revoked_by | Existing lifecycle receipts; expired pending/active projected as expired |

Patient review-status also gets additive scope readback through existing access projection. Its doctor_name may be null. Do not turn an empty/missing effective_scopes or null identity into a positive UI claim. Re-read owned `/access` after generation/claim/revoke as appropriate. Receipt is not an operation attempt lookup: a lost response remains uncertain; no automatic claim retry. Existing authorized list/detail routes are readback for active access.

## Persistence / migration and rollback

No DDL, Alembic revision, live migration or destructive legacy update. ORM default changes to false (client-side SQLAlchemy default, not a server schema default). Existing private VARCHAR(512) JWT stores only consent version and grant binding; full intent lives in the atomic `DOCTOR_QR_GENERATED` audit event, with patient actor, access_id, scopes, intended doctor, expiry, source session JTI and credential HMAC stamp. Grant + consent audit commit together via existing save/rollback behavior. Audit details are internal, never returned in public receipts or logged; existing account deletion scrubs actor/related details and removes grants. Session/credential markers do not contain passwords or raw session tokens.

Consent resolution requires the signed QR binding and matching owned audit receipt; simply changing a boolean cannot broaden permission. Legacy true rows remain physically unchanged but effective export is false. Preserve these audit events for each live grant; missing evidence denies export. Existing account erasure/recovery/journal requirements remain. A rollback to pre-H1 code would restore unsafe generation defaults: do not deploy such rollback with QR generation open. Production release/preflight remains separately authorized.

Isolated fresh SQLite Alembic upgrade to `20261008_01` and Alembic check found no new upgrade operations. This is not PostgreSQL migration/release validation. Docker daemon unavailable; no local PostgreSQL installation found. Parallel SQLite sessions validate conditional claim behavior; PostgreSQL lock/deadlock/clinical-write vs revocation races still require an isolated PostgreSQL environment before rollout. Historical deployed race reports are not present-wave verification.

## Verification

H1-A full suite: `python -m pytest tests -q --basetemp=../.pytest-h1-final --tb=short`: **722 passed, 99 dependency deprecation warnings, 199.82 seconds**. Doctor/API focused suite passed 84 before final additional cases; parallel two-session claim regression independently passed 1. First iteration failed 55/84 because full consent metadata made QR exceed DTO/storage bound; corrected before any security push by using the atomic private audit receipt. Real UUID patient/grant token length is 392, within 512. Initial Windows temp fixture failure solved by workspace basetemp. An intermediate full run was interrupted; only the completed final run is counted. Compilation/whitespace checks passed; no configured repo linter/static checker found. H1-B additional revocation tests follow separately; PostgreSQL runtime verification remains blocked locally.
