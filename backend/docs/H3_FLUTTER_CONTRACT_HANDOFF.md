# H3 Backend → Flutter contract handoff (Amr)

Source-tested API contract, not a mobile release or deployed-environment claim. All paths below have `/api/v1`; authenticated routes require `Authorization: Bearer <access_token>`. Responses can gain fields: decode additively. Never cache profile, consent, clinical, or attempt state across account IDs. For the complete pre-existing H1/H2 revision and attempt contracts see `H2_COMPLETION_AMR_API_HANDOFF.md`; H3 preserves them.

## Policy and profile

| Method/path | Actor | Request | Successful readback |
|---|---|---|---|
| POST `/auth/register` | public patient | Existing email/password/full_name/`accept_safety:true`, optional `policy_version` default `"1.0"` | 201 `TokenResponse` |
| POST `/auth/login` | public | email/password | 200 `TokenResponse`; then GET `/users/me` |
| GET `/users/me` | own patient/doctor | none | 200 `UserOut` including `safety_consent`, `onboarding` |
| POST `/auth/accept-safety` | own patient/doctor | `{ "accepted": true, "policy_version": "1.0" }`; old `{}` uses 1.0 | 200 `UserOut`; GET `/users/me` is authoritative reconciliation |
| PATCH `/users/skin-profile` | own actor, existing role rules | existing `skin_type`, `selected_goal`, `skin_concerns`, `profile_context` optional fields | 200 `UserOut`; does **not** complete review |
| POST `/users/profile-review` | own patient only | `{ "reviewed": true }` exactly | 200 `UserOut`; GET `/users/me` after uncertain response |
| POST `/auth/logout` | signed-in actor | none | 204; old bearer invalid |

`UserOut` preserves id/email/full_name/role/safety_accepted/safety_accepted_at/skin_type/profile_context/selected_goal/skin_concerns/tokens_balance/baseline_checkins_count/created_at. New `safety_consent` schema_version 1 has `state` missing/current/outdated/unknown, `required_version`, `accepted_version|null`, `accepted_at|null`, `acceptance_required`, `enforcement_enabled`. Equality to server required version defines current; `unknown` includes malformed legacy version, missing/future timestamp. An old `safety_accepted:true` alone is insufficient. Version is major.minor numeric up to 20 characters. Duplicate accept preserves the first receipt. A new required version makes old recorded acceptance outdated; registration/accept with old version returns 409. Editorial wording changes need no version increment unless policy owner decides reacceptance is required. Policy content itself is not served by this contract.

`onboarding` schema_version 1 has `review_state` never_reviewed/reviewed/not_applicable, `reviewed_at|null`, `optional_data_present`. Doctor => not_applicable. Legacy patient => never_reviewed even if optional fields were populated. `reviewed` with `optional_data_present:false` means explicit review with no optional values; no disclosure is required. Null/empty optional health fields mean no supplied information, not a known negative. Explicit `none_reported` and `prefer_not_to_say` retain their literal meanings. Review timestamp persists and duplicate POST preserves it. Later optional edits do not unset review; `optional_data_present` may change. Review requires current policy acceptance even while general policy enforcement is staged off.

Synthetic response fragment (other `UserOut` fields omitted here; the actual response includes all fields):

```json
{
  "id": "synthetic-patient", "role": "patient",
  "safety_consent": {"schema_version": 1, "state": "current", "required_version": "1.0", "accepted_version": "1.0", "accepted_at": "2026-10-15T09:00:00Z", "acceptance_required": false, "enforcement_enabled": false},
  "onboarding": {"schema_version": 1, "review_state": "reviewed", "reviewed_at": "2026-10-15T09:01:00Z", "optional_data_present": false}
}
```

At default `SAFETY_POLICY_ENFORCE=false` existing mutation clients continue; enablement is a separate rollout decision after Flutter sends actual `required_version`. Once enabled, patient and doctor POST/PATCH/PUT/DELETE need current policy, except acceptance, logout, erasure and doctor-grant revocations. Reads remain available. Old empty accept request succeeds only while required version remains 1.0. Do not treat a 403 as proof a clinical issue is resolved.

## Current Safety, Home, review and PSM

| Method/path | Actor | Request | Successful response |
|---|---|---|---|
| GET `/safety` | own patient | none | 200 `SafetyEvaluation` |
| GET `/home` | own patient | none | 200 existing Home projection plus nested current `safety` |
| GET `/doctor/review-status` | own patient | none | 200 `ReviewStatusOut` with patient visibility filtering |
| GET `/doctor/patients/{patient_id}/reviews` | doctor with current VIEW grant | none | 200 `ReviewStatusOut` |
| POST `/doctor/patients/{patient_id}/reviews` | doctor with current VIEW grant | `ReviewActionCreate` below | 201 `ReviewActionOut` |
| GET `/doctor/patients/{patient_id}` | doctor with current VIEW grant | none | 200 detail containing typed access/review |
| GET `/doctor/patients/{patient_id}/timeline` | doctor with current VIEW grant | `offset`, `limit` existing bounds | 200 `DoctorTimelineOut` |
| GET `/personal-skin-model` | own patient | none | Existing PSM v2 response with added source freshness/current-history metadata |

`SafetyEvaluation`: `status` track/low_risk_self_care/doctor_review/urgent, `engine_version:"safety-1.0"`, `evaluated_at`, `reasons[]` (code/state/summary/evidence), `evidence_status`, `guidance`, `limitations[]`, `provenance|null`. A fresh dynamic `provenance` schema_version 1 has `evaluation_id`, `source:"deterministic_safety_engine"`, `mode:"dynamic_current"`, `as_of`, opaque `source_revision`, `consistency:"multiple_reads_not_atomic_snapshot"`, `report_freshness` current/stale/missing, `latest_report_at|null`, `evidence_completeness` partial/screen_complete, `clinical_clearance:false`. `screen_complete` is only completeness of the current structured screen; it is never medical clearance. Old saved review snapshots can have provenance:null. A source failure is an HTTP failure, not a successful `track` result. Fingerprint is an input-change hint, not an ETag or cross-request transaction ID. Separate Safety/Home/doctor/PSM calls can observe different commits and evaluation IDs. Always keep current Safety and clinician decisions above PSM/AI assistance; a stale positive is not clearance.

`ReviewStatusOut` schema_version `doctor-loop-2.0`: patient_id, state not_requested/pending/in_review/reviewed/follow_up_needed, latest_sequence, changed_at|null, changed_by|null, as_of, consistency, current_decision_visibility available/absent/not_available_to_patient, safety, current_decision|null, history[], notes[], access[]|null. Doctor status access:null is existing projection behavior, not a grant denial. History sorts descending by sequence. The newest private review yields current_decision:null for the patient and **never promotes** an older visible review to current. `ReviewActionOut` schema_version `clinical-review-1.0`: id, sequence, patient_id, doctor_id, access_id, state, recommendation|null, rationale|null, patient_visible, created_at, provenance:"clinician_authored", safety_at_review, diverges_from_current_safety, lower_than_current_safety, urgent_safety_preserved, is_current, resource_revision=sequence, safety_at_review_kind:"historical_saved", current_safety_evaluation_id|null, clinical_clearance:false. Historical Safety is a saved review-time result, not live Safety. Synthetic fragment:

```json
{
  "schema_version": "doctor-loop-2.0", "patient_id": "synthetic-patient", "state": "reviewed", "latest_sequence": 2,
  "changed_at": "2026-10-15T10:00:00Z", "changed_by": "synthetic-doctor", "as_of": "2026-10-15T10:01:00Z",
  "consistency": "multiple_reads_not_atomic_snapshot", "current_decision_visibility": "not_available_to_patient",
  "current_decision": null, "history": [], "notes": [], "access": [],
  "safety": {"status": "doctor_review", "engine_version": "safety-1.0", "evaluated_at": "2026-10-15T10:01:00Z", "reasons": [], "evidence_status": {}, "guidance": "Synthetic guidance", "limitations": [], "provenance": null}
}
```

Review write body: `state` pending/in_review/reviewed/follow_up_needed, required integer `expected_sequence>=0`, optional `recommendation` track/low_risk_self_care/doctor_review/urgent, optional `rationale` 10–1500 characters (required when recommendation set), `patient_visible` default false. Send the current `latest_sequence`; stale sequence =>409, reload status, preserve draft, do not silently resubmit. Existing patient/grant row locks and unique `(patient_id, sequence)` remain. This is revision CAS, not an attempt receipt. `resource_revision` equals the saved sequence, not a generated next value.

## Clinical notes and grants

| Method/path | Actor | Request | Response |
|---|---|---|---|
| POST `/doctor/patients/{patient_id}/notes` | doctor/current VIEW grant | `content` 10–1500, optional `category` <=50, `priority` routine/review/urgent default routine, `follow_up` free text <=100, `patient_visible` default false, optional same-patient `timeline_item_id`/`review_action_id` | 201 `ClinicalNoteOut` |
| GET `/doctor/patients/{patient_id}/notes` | doctor/current VIEW grant | none | 200 `ClinicalNoteOut[]` |
| POST `/doctor/generate-qr` | own patient | explicit `view_consent:true`; `export_consent` default false; optional selected `doctor_id` | 200 QR token plus access receipt; token is sensitive |
| POST `/doctor/claim` | doctor actor | `access_token` | 200 claim/access receipt |
| GET `/doctor/access` | own patient | none | 200 `AccessGrantOut[]` |
| DELETE `/doctor/access/{access_id}` | own patient | none | 200 revoked `AccessGrantOut` |

`ClinicalNoteOut` schema_version `clinical-note-1.0`: id, patient_id, doctor_id, content, priority, category|null, follow_up|null, patient_visible, timeline_item_id|null, review_action_id|null, created_at, updated_at, provenance:"clinician_authored". Notes remain immutable; follow_up is literal free text and `follow_up_needed` is a state, neither represents a scheduled appointment. Patient visibility checks remain on clinical projections; private content must not be displayed to the patient.

`AccessGrantOut`: id, patient_id, doctor_id|null, granted_by|null, status pending/active/revoked/expired, created_at|null, expires_at, claimed_at|null, revoked_at|null, revoked_by|null, doctor_name|null, consent_version:2|null, consent_source explicit_patient_intent/legacy_view_only, view_consent, export_consent, scopes[], effective_scopes[]. Scope entries are VIEW/EXPORT. QR token itself is returned only by generation, not in access list. VIEW does not imply EXPORT; legacy grants are view-only. Claim replay, wrong doctor, expiry or revocation cannot expand consent. There is no new export endpoint. Lost claim/grant response has no generic attempt receipt; reconcile owned access, without assuming a retry succeeded.

## Error/readback and rollout

Success reads200, register/review/note writes201 where stated, profile/policy writes200, logout204. 400 remains for certain QR claim errors; 401 for missing/invalid/expired/revoked session; 403 for role/current grant/policy denial; 404 for missing owned resource; 409 for stale policy or review sequence/business conflict; 422 for invalid body or foreign evidence link; 500/503 for unavailable/failed backend. Existing envelope carries `success:false,statusCode,errorCode,message,details,timestamp,path` (HTTP exceptions `HTTP_ERROR`, validation `VALIDATION_ERROR`). A 5xx or timeout after mutation is uncertain. Re-read `/users/me` or appropriate owned resource; for check-in/adherence use their existing attempt lookup with same key/payload. No blanket exactly-once claim.

H2 revisions remain: products, routine and experiments use ETag/strong quoted `If-Match` when protected, stale412, required-but-absent428, malformed422; routine-protected experiment activation additionally uses `Routine-If-Match`. Check-in and adherence attempts have bounded committed/unknown/expired receipts; `unknown` does not mean not committed. Capture idempotency is separate. See H2 handoff for detailed fields and return codes. Home observation_status remains independent from measured baseline. Clinical current/history metadata are additive; timeline offset paging is not a stable snapshot cursor.

Activation order for a **separately authorized** environment: upgrade DB through `20261015_01` before H3 model code; deploy additive backend and verify `/users/me`; ship Flutter policy-version/readback and explicit profile-review UI, plus clinical nullable/visibility handling; only then consider `SAFETY_POLICY_ENFORCE=true` and any policy version rollover after policy content/legal review. The local work performed no managed migration, Flutter edit, deployment, or live validation.

Unsupported/OPEN: transactionally atomic cross-endpoint clinical snapshot, typed scheduled appointments, clinician messaging, notifications, verified-doctor badge, new export capability, AI actions/memory, general durable attempts for products/routine configuration/experiments/clinical/grants, persisted rejected/in-flight check-in/adherence receipts. Do not synthesize these in UI from free text or cached optimistic data.
