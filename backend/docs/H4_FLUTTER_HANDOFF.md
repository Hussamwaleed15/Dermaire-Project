# H4 Backend → Amr: standalone Android/iOS HTTP contract

Source-only Backend handoff, not a mobile build, device test or deployed-environment claim. All paths use `/api/v1`; send `Authorization: Bearer <access_token>`. Decode additive fields and keep all state/queued attempts/cursors scoped to the authenticated account. Existing M1–M6, H1 QR VIEW/EXPORT consent, H2 attempts/revisions and H3 policy/onboarding/doctor contracts remain authoritative; H3_FLUTTER_CONTRACT_HANDOFF.md and H2_COMPLETION_AMR_API_HANDOFF.md contain their full pre-existing details.

## 1. Routine and adherence calendar

Existing routine create/read/edit/list responses add `day_basis:"UTC"` and `configuration_history:"current_with_adherence_snapshots"`. Existing adherence create/list/attempt results add `day_basis:"UTC"`. New stored configuration snapshots include the basis; older snapshots are untouched and can lack it. These fields describe the existing UTC calendar, not a new user timezone preference.

Send start_date/adherence date as YYYY-MM-DD in the server UTC calendar. Do not convert a date-only value through the phone's timezone. AM/PM are reported slots, not scheduled clock times. Cairo/device DST does not move the server's day boundary. New association created_at, page as_of and PSM freshness timestamps are UTC-aware; pre-existing routine/adherence server instants may be unsuffixed and must be interpreted as UTC, not device local time. Do not assume phone-local midnight is server midnight.

Configuration history is bounded: current routine revision plus stopped entries and adherence-time configuration snapshots. It is not a full historical version-event stream. Report dates cannot predate start/latest configuration UTC day. Stopped entry rules and active stop-experiment skipped reports are unchanged.

Keep current quoted ETag/If-Match contracts for protected Product/Routine/Experiment mutations. Matching PATCH opts protection in permanently; stale412 reload/conflict, missing428 revision-aware flow, malformed422. Never calculate the next revision. Experiment activation still uses Routine-If-Match for referenced protected routine; evaluate still returns Experiment-ETag. No H4 expected_version body field, general mutation receipt or protection reset exists.

## 2. Frozen experiment metric provenance

New v2 evaluation `result.metric_contract` is an object; old saved evaluation returns null when absent. Do not fill a null descriptor with today's algorithm.

| Field | Values / meaning |
|---|---|
| schema_version | 1 |
| metric | hydration / texture / redness |
| unit / delta_unit | score_0_to_100 / score_points, **not percent** |
| source | manual / image_proxy, never pooled |
| direction | higher_is_better for hydration/texture, lower_is_better for redness; existing tracking-score semantics only |
| aggregation | within_UTC_day_mean_then_equal_day_mean |
| evaluation_algorithm | experiment_v2_rules_1 |
| measurement_algorithm_versions | Recorded versions actually present in the frozen selected evidence; [] means absent |
| measurement_algorithm_provenance | recorded / missing / mixed |
| clinical_measurement | false |

New manual score input records manual-score-input-1.0; the existing local check-in image score calculation records local-image-property-proxy-1.0. Provider tags are not score authority. Historical missing versions remain unknown. Known/unknown or different image algorithm versions force insufficient_evidence; do not render a directional success from raw means in such a result. Legacy unknown-version evidence is not version certification. Capture measurement-1.0 fractions are separate from these 0–100 check-in scores and must not be converted or pooled.

Existing evaluation labels, engine_version2, evidence strengths and limitations remain. Results/evidence are frozen; source edits do not revise a saved evaluation. Repeated POST evaluate can create another evaluation and lacks a durable H2 attempt receipt. On lost response, reconcile owned results/current revision rather than blindly evaluating again. Labels describe observational association, never causation, diagnosis or clearance.

## 3. Explicit capture ↔ structured observation association

No automatic link from timestamp proximity, capture completion, routine ending or experiment ending. Only send selection after the patient explicitly chooses the two records. Linking does not infer that a photo establishes a reported symptom; it creates no measurement, score or comparison.

| Method/path | Request | Result |
|---|---|---|
| PUT `/captures/{capture_id}/observations/{checkin_id}` | `{ "associated": true }` exactly | 200 CaptureObservationOut |
| GET `/captures/{capture_id}/observations` | none | 200 list of association metadata |
| DELETE `/captures/{capture_id}/observations/{checkin_id}` | none | 204; repeated removal remains204 while pair is valid |

PUT/DELETE are patient-owner only; both resources must belong to that account. Capture must be accepted and CheckIn must contain a valid structured user report. A metric-only/legacy quarantined check-in is not a structured observation. No existing record is modified by selection. Extra fields, missing/false/string/numeric consent are rejected422.

Synthetic response:

```json
{"schema_version":1,"id":"synthetic-association","capture_id":"synthetic-capture","checkin_id":"synthetic-observation","created_at":"2026-10-15T14:00:00Z","source":"patient_selected","clinical_inference":false}
```

Same PUT while present returns the original ID/time and does not duplicate audit. After removal, reselecting is a new choice; it is not a permanent operation-attempt receipt. GET is owner or doctor with a current VIEW grant under existing H1 rules (including legacy VIEW-only behavior). Pending/revoked/expired grants fail403; no EXPORT authority is added. Responses contain no image bytes, transferable image URL, report content, private doctor note or patient selector. Existing authenticated image and doctor detail APIs retain their own checks. Do not cache doctor-visible association data after grant revocation or account switch.

401 absent/invalid/deleted identity;403 doctor mutation, current grant denial or enforced policy denial;404 foreign/missing owned pair;422 rejected capture/non-report/invalid explicit choice;409 conflicting DB write;503 uncertain write/read failure. A timeout/503 is uncertain: GET the selected capture's associations to reconcile the current pair; do not claim a durable attempt outcome or replay a removed historical selection automatically. No H2 in_flight/rejected state was added. Account erasure removes owned links and scrubs audit references.

## 4. Bounded adherence history pages

New GET `/routine/adherence/history` accepts optional `routine_entry_id`, `limit`1–500 default100, and opaque `cursor` max4096. Existing GET `/routine/adherence?limit&offset` remains unchanged for old clients.

```json
{"schema_version":1,"day_basis":"UTC","consistency":"append_only_keyset_cutoff_not_atomic_snapshot","order":"created_at_desc_id_desc","as_of":"2026-10-15T14:00:00Z","items":[],"next_cursor":null}
```

Items use existing AdherenceOut including configuration_snapshot and nullable receipt. New ordering is server created_at descending then ID descending, not report date. Start without cursor. For next page send the returned cursor and same routine_entry_id filter; page size may change. Stop at next_cursor:null. Cursors are signed, account/filter bound, and expire one hour after the initial read (not extended per page). Treat them as opaque, not bearer authentication or an ETag. Discard them on account switch, filter change or refresh.

422 tampered/mismatched/invalid cursor;410 expired => restart history;401 auth failure;404 foreign entry filter. No-store response. Later-created rows are excluded by the first as_of timestamp and equal-time rows use ID to avoid offset shifting. A transaction begun before cutoff but committed later may still appear; account erasure or administrative correction can remove rows. This is **not** a durable snapshot, full revision history, or cross-source clinical consistency guarantee. No client-supplied arbitrary as_of query exists.

## 5. PSM evidence freshness

PSM schema_version2/contract_version personal-skin-model-2.0 remain. Existing source freshness objects gain schema_version1, as_of, basis elapsed_UTC_duration, threshold_days14, age_days_basis UTC_calendar_difference. Existing latest_at, age_days and fresh/stale/missing remain; **unknown** now represents a future source timestamp and age_days is null. More than14 elapsed days is stale, exactly14 is fresh. age_days separately counts UTC calendar difference; it is not a clinical validity duration.

Findings add nullable typed `freshness` using the same fields and their latest referenced evidence. A newly generated PSM is not proof its evidence is new. Stale/unknown/missing input is not clinical clearance; do not suppress Safety or clinician authority based on a freshness badge. Safety current > clinician precedence rules > PSM/AI remain. Multiple source reads are explicitly non-atomic; no frozen cross-endpoint clinical snapshot is delivered.

## 6. Integration and future rollout order

In a separately authorized environment: rehearse backup/restore and migration first; upgrade through `20261015_02` before association code; deploy Backend; consume additive contracts; offer explicit patient selection and readback; handle all uncertainty/null/error cases. H4 did not perform any managed migration/deployment or change staged policy enforcement. When SAFETY_POLICY_ENFORCE is enabled in an authorized rollout, association mutations require current policy acceptance through the existing H3 flow. Existing erasure/grant-revocation exceptions remain unchanged.

Android and iOS should verify the same HTTP scenarios when Amr implements them: UTC vs local midnight/DST; legacy snapshot and metric_contract null; ETag conflicts; timeout/readback; explicit pair/repeated selection/removal; wrong account and revoked/expired doctor access; tied history times, new inserts, altered filters, expired cursor; stale/missing/future PSM evidence. These are handoff acceptance scenarios, **not mobile tests performed by Backend**.

Still OPEN: generalized durable H2 attempts/reservations/rejections/tombstones, atomic clinical snapshot, full routine revision event history, user-local timezone scheduling, stable cursor histories for every clinical/source endpoint, calibrated image comparison, autonomous agents, scheduled followups, messaging/notifications, managed rollout/DR. No H5 was started.
