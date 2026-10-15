# Amr — expanded backend integration handoff

Backend owner Hussam; Flutter owner Amr. Source-only HTTP contracts, no mobile
implementation, device/provider certification or managed rollout. Application UI
remains English-only per app/AGENTS.md. This handoff is independent of the Arabic
execution report. All paths below use `/api/v1`, current bearer auth and current
stored role. Never infer clinician license verification from `role=doctor`.

## M1–M6 integration map

| Flutter milestone | Backend integration now available | Preserve unsupported states |
|---|---|---|
| M1 entry/profile/Home | H3 policy version/onboarding readbacks, H4 observation versus measurement/day provenance, patient PostgreSQL `/clinical-snapshot` | Report completion does not create measurement baseline/clinical clearance; no local fake policy acceptance |
| M2 captures/comparison | Existing private captures/image authorization plus explicit `/clinical-plans` source/baseline/ack/follow-up/review lifecycle | Stored accepted private captures only; image inference/AI date proposal unavailable, no automatic routine-end comparison |
| M3 agent | `/agent/capabilities`, scoped sessions/turns/context, typed preview and user-confirmed request records | Model unavailable, no autonomous agent, no medical resource changes or clinician notification |
| M4 products/routine/experiments | Existing CAS plus product CREATE/PATCH/DELETE receipts; routine create/update/stop and experiment create/edit/activate/finish/cancel/evaluate receipts | Unknown is uncertain, original result is historical, not current; no durable rejection/in-flight registry/full configuration history |
| M5 notifications | Opt-in preferences/CAS, JWT-bound encrypted device registration, due inbox/read/unread flags, local outbox and reminders for messages/acknowledged plans | Actual push unavailable; recurring routine enqueue generation and complete cancelled-event history remain unsupported |
| M6 doctor | H1 explicit VIEW/EXPORT and grant read/revoke, immutable messaging, actual typed follow-up plans, doctor PostgreSQL bundle | VIEW is not EXPORT; no new license claim, emergency messaging SLA or fake delivery/clinical clearance |

## Migration/configuration order

Source expects reviewed migrations through `20261015_09`:03 existing product
creation receipts →04 messaging →05 notifications →06 clinical plans →07 agent
sessions →08 product mutations →09 routine/experiment attempts. Managed readiness
rejects older revisions. No live DB was migrated. Populated downgrades refuse data
loss. App and migration PG connections explicitly use UTC; historical UTC rows are
not transformed. Deployment/backup/restore/DR remains separately unvalidated.

Existing SAFETY_POLICY_ENFORCE flag retains its configured default and authority.
No Flutter feature flag was changed. New notification preferences default to empty
kinds/push false; safety acceptance and OS permission are not push consent. Push
and new image/agent adapters are disabled in source with honest unavailable
responses; no environment switch silently enables a genuine integrated provider.
Existing contextual-AI configuration does not enable the new agent model.

## Authority and error rules

401 invalid/expired/logged-out/credential-invalid session.403 current role,
consent or original grant denied. Foreign message/plan/device/resource404, while
existing doctor patient authorization uses generic403.422 invalid typed input,
duplicate/missing required key or invalid cursor.409 changed payload on a key,
plan/config conflict or stale explicit body revision.412 stale If-Match;428 missing
precondition on a protected Product/Routine/Experiment.410 expired/erased replay.
503 unconfirmed operation or unavailable actual PG snapshot: reconcile the
original identity/key; never fabricate success, issue a replacement operation or
force overwrite. Current safety acceptance gates new mutations; withdrawal/logout/
account erasure remain available through the documented recovery routes.

All new private successful reads are no-store. Clear private cached content on
logout/account switch/grant revoke/consent withdrawal; reauthorize deep links.
Original result receipts never bypass current account/grant authority.

## M6 messaging

1. Patient `POST /messaging/threads`:
   `{"access_id":"owned-active-grant","messaging_consent":true}`.201 returns
   id, patient_id, doctor_id, access_id, latest_sequence, read watermarks,
   emergency_service false and retention policy. VIEW alone never creates a thread.
2. Participant `POST /messaging/threads/{id}/messages`, one Idempotency-Key:
   `{"body":"Please review my progress"}`.201 immutable participant-authored
   message id/thread_id/actor_id/sequence/body/created_at, clinical_clearance false.
3. `GET /messaging/threads/{id}/attempts/{key}` is original sending actor-bound;
   committed/unknown/expired with original result for30 days. Same key/different
   body409. Persist original key and normalized body across uncertain responses.
4. `GET /messaging/threads?limit=50&after=owned-thread-id` returns items/next_after.
   `GET /threads/{id}/messages?after=0&limit=50` returns as_of_sequence and
   next_after; pass that same as_of on subsequent pages to freeze the send window.
5. `PUT /threads/{id}/read {"through_sequence":3}` is monotone explicit app read,
   not push delivery. `DELETE /threads/{id}/consent` withdraws patient consent.

Original grant expiry/revoke or messaging withdrawal denies content/readback on
both sides. New grant never revives old conversation; new enrollment required.
No edit, per-message delete or export endpoint. This is not an emergency service.
Deleting either participant erases the shared conversation and related notices.
See MESSAGING_CONTRACT.md for complete retention/error details.

## M2/M6 typed clinical plans

Doctor `POST /clinical-plans` with one Idempotency-Key, example synthetic request:

```json
{"access_id":"active-grant-id","kind":"comparison","purpose":"Clinician selected follow-up comparison","local_due":"2026-11-10T10:00:00","timezone":"UTC","source_type":"routine","source_id":"owned-routine-id","baseline_capture_id":"owned-persisted-baseline-id"}
```

Response has schema_version clinical-plan-1, id, revision1, state proposed,
patient_visible true, source identity/revision snapshot, schedule_provenance,
due_at_utc and baseline reference. Image inference is unavailable with null model
version/result. Explicit IANA wall-time gap rejection/overlap fold0/1 required;
travel does not alter saved UTC. Schedule is distinct from free-text follow_up.

| Endpoint | Required action/body |
|---|---|
| GET /clinical-plans and /{id} | patient owner or doctor with original grant; list limit/after |
| POST /{id}/acknowledge | patient expected_revision1, consent true →scheduled/revision2 |
| POST /{id}/reschedule | doctor expected_revision + local_due/timezone/fold; returns proposed, resets ack/cancels old reminder |
| POST /{id}/cancel | patient withdrawal or current authorized doctor; expected_revision/reason |
| POST /{id}/capture | patient expected_revision/capture_id, scheduled comparison; new accepted persisted private capture after acknowledgment |
| POST /{id}/review | doctor expected_revision/assessment; scheduled follow-up or captured comparison only |
| GET /{id}/history | immutable revision events, after_revision/limit; numeric_comparison_metrics null |
| GET /{id}/attempts/{operation}/{key} | actor-scoped original committed/unknown/expired result |
| GET /creation-attempts/{patient_id}/{key} | original doctor lost-create-response reconciliation |

Each mutating POST requires one key. History supports lifecycle chronology, not
AI accuracy/numerical treatment charts. Early capture is explicitly labeled early;
it does not prove sufficient exposure or clinical validity. Patient retains own
plan history after grant revoke; doctor loses read/replay. Patient may withdraw;
activation still requires the original current grant. No routine-end auto-schedule.
See CLINICAL_PLAN_CONTRACT.md.

## M5 notification boundaries

`GET /notifications/preferences` returns revision0/empty kinds/push false until
explicitly configured. Example `PUT /notifications/preferences`:

```json
{"expected_revision":0,"enabled_kinds":["message","follow_up","comparison"],"push_enabled":true,"timezone":"Africa/Cairo","quiet_start":1320,"quiet_end":420}
```

Quiet hours are half-open local minutes, including both DST repeated hours; equal
ends disable the window. They affect delivery timing, not saved UTC due instants.
`DELETE /notifications/preferences?expected_revision=1` disables/cancels outstanding
effects even after policy change. Do not expose a recurring routine scheduling UI
as functional merely because routine exists in enabled_kinds.

`POST /notifications/devices` input: installation_id (16..128 ASCII identifier),
token, platform ios/android/web, push_consent true. Requires push enabled; response
contains device id/platform/registered/disabled provider only, never token. Token
is JWT/session/credential/expiry-bound and encrypted. Reuse in another active
session409 until old registration revoked; logout/expiry/credential change prevents
dispatch and permits safe replacement. DELETE /notifications/devices/{id} is
owner-only and clears token/cancels jobs. No cross-account deep-link authority.

`GET /notifications?limit=50&before=owned-notice-id` returns due, uncancelled,
currently authorized source items with id/kind/source id/revision/created_at/
due_at/read_at/unread, unread_in_page and next_before. This page count is not a
global unread total or complete cancellation history. `PUT /notifications/{id}/read`
returns app_read_acknowledged/read_at, delivery_confirmed false. No mark-unread
mutation or full provider history/detail contract is claimed in this version.

Message and patient-acknowledged plan commits create opted-in inbox/outbox jobs;
new device registration also attaches to still-authorized future plan reminders.
No historical/overdue backfill promise. Local fake tests prove enqueue/lease/retry/
quiet-hour/revoke flow; provider unavailable is persisted and never labeled sent
or delivered. Generic lock-screen payload has no PHI. No hosted worker was deployed.
See NOTIFICATION_CONTRACT.md.

## M3 durable local request broker

Read `/agent/capabilities` first. Model agent-model-boundary-1 is unavailable,
invoked false, null provider/version/response. POST `/agent/sessions` with one key:
`{"longitudinal_read_consent":true,"proposal_actions_consent":true}`. Context is
redacted/owner-scoped with freshness/provenance; DB-only multi-read consistency is
explicit, not the clinical snapshot guarantee. GET session retrieves it; POST
`/{id}/context {"expected_revision":1}` refreshes with CAS. One-hour/JWT minimum
expiry, original logout/credential binding, five active sessions, eight retrieval+
preview calls and40 turns apply.

POST `/{id}/turns {"message":"My tracking question"}` with key saves raw untrusted
text and returns unavailable model/zero actions. No generated assistant turn is
invented. GET turns is bounded. Typed action example:

```json
{"expected_session_revision":1,"kind":"request_checkin","rationale":"I want to record a check-in"}
```

POST `/agent/sessions/{id}/actions/preview` with key returns preview id/revision1/
preview_valid_until, no medical change. Explicit POST `.../actions/{action_id}/confirm`
`{"expected_revision":1,"confirm":true}` records a duplicate-safe request only.
Other allowed kinds propose_followup/propose_routine_adjustment; routine proposal
requires owned active routine_id/routine_revision. Changed/stale evidence or preview
older than5 minutes409; urgent escalation blocks treatment/follow-up proposals.

Result explicitly says medical_resources_modified false, notification_enqueued
false and clinician_notified false. This does not perform a check-in or change a
routine/clinical plan. GET action-attempts/{key} and actions provide reconciliation.
DELETE session revokes scopes and erases raw memory, including after policy change.
No cross-session learning or autonomous medical decisions. See AGENT_PLATFORM_CONTRACT.md.

## M4 operation receipts and CAS

Product create uses existing `/products/attempts/{key}`. PATCH/DELETE product now
support optional key plus the original If-Match; GET
`/products/{id}/operation-attempts/{patch|delete}/{key}` reads original result.
PATCH result survives later edits as historical original output; product erase
scrubs its content. DELETE replay204 has a minimal committed tombstone and does not
rewrite the independent deletion journal. Journal intent alone does not prove SQL
commit; unknown may coexist with a durable privacy-erasure requirement.

Routine create/update/stop and experiment create/edit/activate/finish/cancel/
evaluate/legacy pause accept optional keys. CREATE lookup uses no resource id:
`/routine/configuration-attempts/create/{key}` or
`/experiments/operation-attempts/create/{key}`. Other operation lookups use the
same prefix/op/key plus `?resource_id=original-id`. Activation also binds original
Routine-If-Match. Evaluation replay returns its original evaluation id and original
Experiment-ETag; a fresh key requires current CAS. Deleting an experiment is a
preserved lifecycle transition, not physical erase.

Persist key, effective typed body and original preconditions across uncertainty.
Do not "fix" an uncertain retry by replacing If-Match with the latest revision:
that is a different operation409. Responses include Operation-Attempt-Id,
Result-Snapshot original_committed and Operation-Replay true/false. Read current
resource separately before treating a receipt as current state.30-day access;
expired/erased replay410, no rejected/in-flight promise. Product/account/restore
erasure covers embedded configuration/product names. No numeric units or existing
observational evaluation rules changed. See PRODUCT_MUTATION_ATTEMPTS.md and
CONFIGURATION_ATTEMPTS.md.

## Doctor snapshot and integration verification

Patient GET `/clinical-snapshot` remains patient-only. Doctor GET
`/clinical-snapshot/patients/{id}` requires current original VIEW grant and actual
PG REPEATABLE READ; SQLite503. Schema2 identifies reader_id/access_id and
projection_visibility doctor_review_with_patient_home_and_psm. Doctor review
contains authorized private current notes/decision; home and PSM retain patient
visibility and never substitute an older public decision for a private latest one.
One Safety/clock across bundle; no external/images/standalone endpoint atomicity,
no clinical_clearance, no replay token or EXPORT. Current session/role/original
grant rechecked before response. See DOCTOR_CLINICAL_SNAPSHOT.md.

Amr verification remains separate: account switch/logout/cache cleanup; revoked
original grant and private-current UI; exact key/CAS persistence after uncertainty;
frozen page cursors; unavailable provider/model states; real stored-capture IDs;
no client-generated clinical authority, delivery/accuracy claims or medical
resource changes. Backend isolated gates do not certify mobile/device behavior.
