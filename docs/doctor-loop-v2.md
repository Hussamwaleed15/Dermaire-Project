# Doctor Loop v2

Scope: backend clinician workflow only, based on clean main `2a9f946e1813755b0043cd93e7d94b32dee82ff4`. No deployment, commit, push, Flutter change, Personal Skin Model v2, Blob work, live Vision, notifications, or broad UI/chat redesign.

## Architecture and roles

Reuse the existing patient-issued temporary QR consent/access table and immutable clinical-note table. Extend their metadata; add `doctor_review_actions` as append-only clinician state/decision history. Services project existing backend evidence without invoking an AI provider or altering source records. Current review is the highest per-patient sequence, shared across assigned clinicians. Optimistic concurrency requires `expected_sequence`; stale writes return 409. PostgreSQL patient row locks serialize writes/revoke/deletion; the database unique `(patient_id, sequence)` constraint is a second safeguard.

Trusted provisioning is unchanged. Authentication checks database role, credential stamp, session revocation and account existence. Only the `doctor` role can claim access, read clinician endpoints or write notes/reviews. Admin/support roles cannot impersonate a clinician through these endpoints; this deliberately narrows the old doctor/admin role allowance. A token claiming a different role cannot elevate the database role. Patient-only routes issue consent, inspect/revoke their own grants and read their own review status. No patient-ID query parameter exists on the patient status route. Assigned doctors share a patient clinical record, including internal clinician notes; there is no per-note doctor privacy boundary.

## Access lifecycle

1. Patient issues a signed QR token (15–1440 minutes; default 60), persisting `pending` with `granted_by=patient_id`, creation and expiry. A random JWT `jti` prevents same-second token collisions. Access tokens are widened to 512 characters for this payload.
2. A trusted doctor claims the token, binding that grant to one doctor, recording `claimed_at`, and setting `active`. A different doctor cannot claim it. Reclaim by the same doctor is idempotent in state and preserves the original claim timestamp; an audit event is still recorded.
3. Every doctor read/write checks specific patient, current doctor, active status, unexpired grant and existing patient account. The list only queries that doctor's active patient IDs. No arbitrary patient search is provided.
4. Patient can revoke one grant or all pending/active grants. Revocation records actor/time and an atomic audit event. All subsequent requests lose access immediately; another independent active grant still authorizes its bound doctor. Existing data already delivered to a client cannot be recalled. In-flight transactions serialize with revocation in PostgreSQL.
5. Expired grants are reported as expired at read time even if the stored status remains pending/active. Expiry/revocation never erase notes or review history. Regrant requires a new patient token. Legacy grant actors and transition timestamps stay unknown; the migration does not invent historical consent provenance.

Database grants/revocations and their audit events commit together. Write failures roll back and return 503. Validation/foreign linkage failures return 422 before persistence; unauthorized routes return 401/403, foreign grant revocation 404, invalid/expired QR claims 400.

## API contract

All routes are under `/api/v1/doctor`, authenticated with Bearer access tokens. The new projections carry `doctor-loop-2.0` or `doctor-timeline-2.0` schema versions. Existing paths and principal response fields remain compatible; additive note/list fields support v2. OpenAPI exposes request validation, and this document specifies the projection shapes.

| Method/path | Role | Contract |
|---|---|---|
| POST `/generate-qr?minutes_valid=60` | patient | Existing QR response: access_token, qr_payload, expires_at, instructions. |
| POST `/claim` | doctor | `{access_token}`; success/message. |
| GET `/access` | patient | Own grants with IDs, doctor_id, granted_by, effective status, created_at, expires_at, claimed_at, revoked_at/by. Never returns stored QR tokens. |
| DELETE `/access/{access_id}` | patient | Revoke own individual grant; returns its metadata; repeat revocation is safe. |
| DELETE `/revoke/{patient_id}` | owning patient | Revoke all pending/active grants; existing success/message response. |
| GET `/patients?priority=urgent` | doctor | Assigned, active patients only. Existing summary/notes plus safety, review_state and own access metadata. Priority never drops below current deterministic safety. Legacy current_day is no longer presented as authoritative experiment progress. |
| GET `/patients/{patient_id}` | assigned doctor | patient_id, full_name, active access metadata, review projection. |
| GET `/patients/{patient_id}/timeline?offset=0&limit=100` | assigned doctor | Aggregated timeline; ascending UTC chronology; limit 1–200, offset >= 0, total and next_offset. |
| GET `/patients/{patient_id}/notes` | assigned doctor | Immutable notes in ascending creation/ID order, including internal notes. |
| POST `/patients/{patient_id}/notes` | assigned doctor | 201; body below; returns the persisted note. |
| GET `/patients/{patient_id}/reviews` | assigned doctor | Current state, clinician decisions, complete action history, notes and unchanged current safety. |
| POST `/patients/{patient_id}/reviews` | assigned doctor | 201; body below; returns the appended clinician action with divergence flags and safety snapshot. |
| GET `/review-status` | patient | Own state/change metadata, current safety, patient-visible notes/actions, own access lifecycle. |

Note request: `content` (10–1500 trimmed characters), `priority` (`routine`, `review`, `urgent`, default routine), optional `follow_up` (<=100), `category` (1–50), `timeline_item_id` (<=255), `review_action_id` (<=36), and `patient_visible` (strict boolean, default false). Extra fields such as doctor_id/patient_id/created_at are rejected. Clinician identity and timestamps are server assigned. Returned notes include id, patient_id, doctor_id, created_at, updated_at, content, priority, follow_up, category, link IDs, patient_visible and `provenance=clinician_authored`.

Review request example:

```json
{
  "state": "follow_up_needed",
  "expected_sequence": 2,
  "recommendation": "doctor_review",
  "rationale": "Please arrange a clinician follow-up for these changes.",
  "patient_visible": true
}
```

States: `pending`, `in_review`, `reviewed`, `follow_up_needed`. These are workflow labels, not triage results. Authenticated assigned doctors may reopen or move between any explicit state; every change is a new action. `expected_sequence` is mandatory (0 for the first action). Recommendation is optional and uses the four safety vocabulary values solely as clinician recommendation labels. A recommendation requires a nonblank rationale (10–1500). No recommendation means the new current action has no decision; older decisions remain history and are not silently carried forward. Response includes id, sequence, doctor_id, patient_id, access_id, created_at, state, recommendation/rationale, patient_visible, provenance, safety_at_review, diverges_from_current_safety, lower_than_current_safety, urgent_safety_preserved. Persisted safety snapshots are complete reason/evidence documents.

Review projection: schema_version, patient_id, state, latest_sequence, changed_at/by, safety, current_decision, history, notes, access (own grant list on patient views, otherwise null). Before any action, a live pending/active grant yields pending; no such grant yields not_requested. Review state persists after grant revocation; access metadata distinguishes whether a clinician currently has access.

## Timeline schema and provenance

Each item has stable `id=source:source_id:field` (with an ingredient/evidence discriminator where needed), source, source_id, field, category, recorded_at (UTC or null), provenance and data. Sort is timestamp ascending, then stable ID; null timestamps sort first. Response includes built_at, items, total/offset/limit/next_offset, unknowns, derived_source_availability, safety and limitations. Pagination rebuilds the projection each request; concurrent changes can shift offset pages. It is not a frozen export.

| Category | Meaning/examples |
|---|---|
| patient_reported | Structured profile disclosures, validated check-in report/notes, manually reported tracking scores, daily context, routine setup/adherence, v2 experiment definition, explicitly user-reported Product Intelligence facts. |
| system_observed | Capture receipt/storage metadata, validated image proxy measurements, recorded manufacturer/curated/provider evidence with its verification/confidence status preserved. Unknown evidence stays explicitly unknown. |
| deterministic_derived | Capture quality assessment, baseline, normalized Product Intelligence facts/cautions, experiment evaluations, current PSM v1 findings, safety state/reasons. These are non-diagnostic derivations. |
| ai_inferred | Quarantined historical AI output availability/provenance, never clinician authorship. Historical free prose and simulated diagnostic claims are omitted. |
| clinician_authored | Notes and review/decision actions with authenticated doctor IDs and immutable server timestamps. |

Raw historical sources include the full owner-scoped profile snapshot, check-ins and tracking scores, daily context, routine/adherence, v2 experiments/evaluations, captures/quality, measurements, and all saved products' Product Intelligence facts. Verified image proxies require accepted owned captures, matching algorithm/capture/unit provenance, finite bounded values and accepted quality references. Invalid/unavailable values stay null. Legacy experiment defaults are excluded. AI/model prose is not medical evidence. Image blobs, URLs, credentials, QR tokens and unrelated account rows are not part of these clinical projections.

Existing `build_context` provides current baseline/PSM v1/safety and routine Product Intelligence derived projections; the timeline adds full raw source history and all product facts rather than using the small AI context as the entire timeline. Derived projections retain the existing 14-record / 240-fact context budgets and availability/truncation metadata. Baseline may have no single timestamp; its source check-in IDs remain in provenance. PSM findings preserve rule/evidence references and strength. Missing disclosures, incomplete screens, unavailable measurements and unknown provenance are not filled with defaults or negative evidence.

Mutable profile/context/routine/experiment/product rows are current snapshots with available source timestamps, not reconstructed edit histories. No new persistent safety-history store is introduced: safety is computed authoritatively on read and snapshotted at each clinician action. Original patient red-flag evidence remains in the historical check-ins regardless of clinician recommendations.

## Notes, safety, AI and patient visibility

Notes are immutable through the API: there are no update/delete endpoints. A correction is another note; it can link to the previous note's timeline item. On API creation updated_at equals created_at. Links are validated against this patient's available timeline/actions; a link is navigation metadata, not an immutable copy of the underlying source. Clinician actions and notes are append-only during normal operation, with atomic audit events containing metadata rather than clinical prose. This is not a tamper-proof database or protection against a privileged SQL administrator.

Clinician recommendation is a separate decision layer. It never mutates check-ins, safety reasons, provenance, PSM or AI outputs. Current safety and the recorded safety snapshot remain available. A clinician `track` recommendation with current `urgent` yields explicit divergence/lower flags, urgent_safety_preserved=true, and the unchanged urgent result/guidance. The patient list retains urgent priority too. Divergence flags compare against current safety; safety_at_review is the historical snapshot, so later freshness changes do not rewrite it.

Only authenticated doctor notes/assessments may carry clinician assessment language; system projections remain tracking/triage information, not diagnoses. Contextual AI does not consume the new notes/decisions in this milestone; its existing safety subordination stays intact. There is no chat redesign, prompt expansion or live AI activation.

Patient status exposes workflow state/time/actor even when a decision is internal. Content of internal notes, recommendations, rationales and review snapshots is filtered out. Visible historical actions remain explicitly historical; an internal latest action yields current_decision=null rather than promoting an older visible recommendation to current. Internal notes are never included in patient status or AI context. A patient-visible note/action is immutable in visibility too; toggling after publication is not supported. Revoking clinician access does not hide already patient-visible records from the patient.

## Persistence, migration and deletion boundaries

Apply `docs/doctor-loop-v2-migration.sql` before releasing the backend. `create_all` cannot add columns to existing tables. Changes:

- doctor_patient_access: access_token varchar(512), nullable granted_by, claimed_at, revoked_at, revoked_by.
- clinical_notes: nullable category, timeline_item_id, review_action_id FK; non-null patient_visible and updated_at. Existing notes backfill as internal, updated_at=created_at. Migration aborts for null legacy creation timestamps rather than fabricating history.
- doctor_review_actions: new immutable event table with patient/doctor/access FKs, sequence, validated state/recommendation, optional rationale, non-null visibility, safety_snapshot JSON and created_at. Unique patient/sequence and indexes on patient_id, doctor_id, access_id. UUIDs/timestamps/default values are application-side, matching ORM. Timestamp columns follow existing UTC timestamp-without-time-zone convention.

Revocation/expiry retain records. Account deletion follows the existing application hard-deletion policy: remove associated access, notes and review actions when the patient or authoring doctor is deleted. Notes linked to a removed review action are also deleted, including notes written by another clinician, to avoid dangling references and retention of deleted clinical episode data. Unrelated clinician grants/records remain. Audit details referencing affected IDs are scrubbed by the existing deletion service. There are no orphan FKs; cleanup runs in dependency order and is transactional after external-image deletion succeeds. Deleted accounts and revoked sessions cannot reuse doctor endpoints.

This intentionally preserves the repository's existing conservative deletion approach, rather than introducing retention of a deleted doctor's clinical records. It means doctor-account deletion can remove history from a surviving patient's record, including linked clinical notes; clients must not interpret missing historical rows as medical clearance. No statutory retention period, legal compliance, medical record export or clinical archival guarantee is claimed. A dedicated retention/archive policy requires a separate product decision before clinical operation. Infrastructure backups/external copies follow existing boundaries; this milestone does not introduce deletion guarantees for backups.

## Validation and limitations

Executed on Windows with Python 3.12: full backend suite **495 passed**, including **54 Doctor Loop tests**; 90 upstream Starlette HTTP-422 deprecation warnings. `git diff --check` passed, and whitespace was also checked for new untracked files. PostgreSQL table/index DDL was compared with ORM compilation; all new columns were checked. No live PostgreSQL migration or production request was performed. Doctor Loop tests cover trusted provisioning/role separation, forged role claims, scoped access, multiple grants, expiry/revoke/regrant, immediate denial after revoke, immutable/internal/visible notes, cross-patient links, state history, stale sequences, all four decision labels against urgent safety, unchanged reason evidence, AI subordination, all five provenance categories, chronological history/pagination, missing sources, validated vs invalid measurement provenance, preserved safety snapshots, foreign/deleted accounts, logged-out sessions, strict payloads and transactional rollback. Foreign keys are enforced in the isolated Doctor Loop SQLite fixture. Existing full backend suite is also required; Flutter is untouched.

PostgreSQL migration DDL was compiled from the new ORM table/index metadata; live PostgreSQL application, concurrent revoke/review/deletion and multi-worker tests are staging rollout requirements. SQLite does not exercise PostgreSQL row locks. The timeline currently materializes owner history before response pagination; very large records need query-level pagination/load validation. Notes/actions and the legacy patient list are not separately paginated. There is no notification, appointment, multi-episode case management, doctor-specific note privacy, export, immutable source edit history, clinician identity display enhancement, or Flutter v2 screen in this milestone. Current access is temporary, scoped patient QR consent rather than a long-lived administrative assignment system.

## Production rollout (not executed)

1. Review the schema and deletion/retention behavior; back up the database using the existing process and verify the pre-migration schema and legacy note timestamps.
2. Apply the SQL once to an isolated PostgreSQL staging copy. Verify columns, indexes, FKs, unique/check constraints and legacy notes remaining internal. Test rollback-on-error.
3. Release the backend to staging; exercise real trusted doctor provisioning, two-patient/two-doctor isolation, grant expiry/revoke, notes/history, conflicting urgent recommendation, account deletion and patient visibility. Run concurrent duplicate reviews/revoke/deletion with independent DB sessions and multi-worker requests. Load-test representative long histories.
4. Only after explicit production deployment authorization, apply the migration before the application rollout, deploy the tested backend and run disposable-account HTTPS smoke tests. Keep live AI/Vision disabled as currently configured. Verify internal-content non-disclosure and cleanup.
5. Monitor clinician endpoint failures and audit completeness using existing monitoring. If application rollback is needed, keep the additive schema/data and roll back code; do not drop clinician history as a routine rollback. Database restore requires a reviewed operational plan.
