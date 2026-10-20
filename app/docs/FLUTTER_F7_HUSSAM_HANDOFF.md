# F7 Flutter → Hussam: source-verified contract closure handoff

2026-10-20. Backend source last changed at
`8ad2ceafced5b1f06ade5a082d4939503d31c687`; no newer Backend guarantee found.
Flutter code checkpoint `2314ae2da97806b3d21cefab791d9b2d3df12ef3`.
All paths below have prefix `/api/v1`. This is a written handoff, not a Backend
implementation/deployment request executed by Flutter. No automatic message sent.

## Already available — preserve, do not recreate

- POST `/doctor/patients/{patient}/notes` and `/reviews`: optional
  `Idempotency-Key` (Flutter sends it), payload-bound per doctor/patient/operation;
  reviews require `expected_sequence`. Versioned original snapshots retained30days.
- GET `/doctor/patients/{patient}/attempts/{note|review|claim}/{key}`:
  schema1, original actor/patient/access/resource, recorded_at/expires_at,
  committed/expired + historical result; unknown has result:null/retry_safe:false.
  Original grant mismatch409. Authorization/current policy still applies.
- GET `/doctor/consent-attempts/{issue|revoke|revoke_all}/{key}` and existing
  grant issuance/claim/withdrawal. Receipt does not restore bearer validity.
- Product/configuration/adherence/message/plan/comparison operation receipts,
  current authorized reads, plan immutable history, routine history/calendar CAS,
  notifications device registration and existing session/current-action workflows.

Flutter F6-Q consumes these contracts. F7 additionally keeps an old contextual
page/editor bound to its original grant even after a connection refresh yields
another grant. Explicitly opening a NEW page can bind new current authority.
This client safeguard does NOT close the atomic first-write server gap below.

## B1 — P1 clinical first-write original-grant precondition: OPEN

**Actual source:** `api/v1/doctor.py:add_clinical_note/add_review`,
`services/doctor_loop.py:authorize`, `schemas/__init__.py:ClinicalNoteCreate`,
`schemas/doctor_loop.py:ReviewActionCreate`, `services/clinical_attempts.py`.

Current transaction locks patient then active grants, selects latest VIEW grant.
Notes/reviews requests forbid extra JSON fields and accept no original-access
precondition. Old keyed replay checks grant and payload; FIRST write has no row
whose original grant can be checked. Current authenticated safety policy and role
are checked by API dependencies; do not remove them.

Current accepted request example (synthetic; NOT an atomic grant binding):

```http
POST /api/v1/doctor/patients/patient-1/reviews
Authorization: Bearer <current doctor token>
Idempotency-Key: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Content-Type: application/json

{"state":"reviewed","expected_sequence":0,"recommendation":"doctor_review","rationale":"Synthetic explicit clinician assessment.","patient_visible":true}
```

A201 original result has schema_version `clinical-review-1.0`, patient_id,
doctor_id, access_id, sequence and versioned clinical fields. Response headers:
`Operation-Attempt-Id`, `Operation-Replay`, `Result-Snapshot: original_committed`,
`Cache-Control: no-store`. A note result uses `clinical-note-1.0` and does not
supply access_id itself; the attempt envelope binds original access separately.
401 auth,403 policy/authorization,409 key/payload/grant conflict or review sequence,
410 unavailable/expired keyed replay,422 malformed payload/key,503 unconfirmed
persistence are meaningful existing boundaries. GET expired envelope is200 with
status:expired, not an invented guarantee of safe resubmission.

**Required backward-compatible acceptance contract (PROPOSAL ONLY):** select and
document an explicit original-access precondition input/capability for hardened
clients; under the SAME patient/grant transaction lock require that exact original
grant belongs to actor+patient, is active/unexpired with current VIEW+consent/policy,
and is the grant used for first mutation AND receipt binding. Keep current CAS and
payload hashing. Define missing-precondition behavior for hardened clients and the
legacy-client transition. Suggested statuses:428 missing required precondition,
412 mismatch,403 revoked/expired; final shape/statuses are Hussam's documented
contract decision. Flutter sends NONE of these proposed fields/headers today.

**PostgreSQL acceptance:** A verified by client, then revoked/replaced with B before
POST acquires lock → no note/review/receipt under B for A's request. Test both lock
orders with independent connections and observed waits; duplicate same key/same
payload one original; changed payload conflict; concurrent review sequence one
winner; lost response lookup immutable original; wrong actor/patient; deletion,
policy loss, expiry; new grant never revives old keyed receipt. Do not erase prior
clinical decisions. Pending clinical safety decision: legacy/hardened rollout policy.

## B2 — P0 before replacement: authoritative unknown/in-flight/rejected semantics

Actual product/configuration/clinical and related domain attempts have their own
committed/unknown/expired schemas, not a universal registry. An absent committed
row does not fence a transaction still in flight. unknown is never safe replay.

Required only if safe replacement/unlock is expected: durable actor/domain-bound
reservation or fencing/terminal rejection with defined transaction/retention and
race semantics. Expose only states actually durably supported. Do not label a
missing row rejected or promise exactly-once. PostgreSQL: hold original transaction,
query unknown, attempt replacement, then release original; prove no double commit.
Also race duplicate keys, rollback, expiry, owner change and deletion. Flutter
retains original uncertainty and does not generate replacement keys automatically.

## B3 — Agent dependencies: OPEN

Actual routes: GET `/agent/sessions/{id}`, GET
`/agent/sessions/{id}/action-attempts/{key}`, POST
`/agent/sessions/{id}/actions/{action}/confirm`, POST
`/agent/requests/{action}/submit`, GET `/agent/requests`, POST
`/agent/requests/{action}/decision`, existing per-session/request DELETEs.

- **P1 discovery:** no account session list/current discovery/revoke-all. Known-ID
  read requires original login/TTL/scopes. Define authenticated minimum metadata
  discovery + explicit expiration/revocation/cross-login semantics if required.
  No private transcript restoration from guessed identifiers.
- **P1 request completeness:** doctor GET selects up to100 newest rows, filters
  authorized ones, returns `{items,limit:100,medical_execution_enabled:false,
  notification_delivery:"unavailable"}`; no next cursor or explicit authorized
  patient target in action_out. Add stable authorized pagination and original-
  grant-bound patient reference; absence must not authorize navigation.
- **P1 independent original proof:** action-attempt GET returns
  `{attempt_id,status:"committed"|"unknown",result:action_out(row)|null}`.
  action_out is MUTABLE CURRENT state/revision/payload/result. It is not immutable
  original preview, confirmation, submit or clinician-decision evidence. Current
  CAS/repeat behavior remains usable. If independent recovery is required,
  document operation-specific immutable original receipts and current authority
  separately; do not retrofit current rows as historical proof.

PostgreSQL tests: >100 requests, interleaved inserts/cursors, original login expiry,
wrong owner, revoke during discovery/decision, replacement grant, deletion cleanup,
late confirmation and current action advancing after original receipt. No LLM or
clinician decision fabrication; model remains unavailable.

## B4 — notifications: OPEN contracts, provider separate

Actual GET `/notifications` returns authorized current items with
`id,kind,source_id,source_revision,created_at,due_at,read_at,unread,
push_delivery:"unconfirmed"`; wrapper has `next_before,unread_in_page,
provider:"disabled",delivery_confirmed:false`. Source authorization is rechecked.
For message kinds, source_id is a message ID, not a trusted thread destination.

- **P1 target:** add authenticated current-authorized thread reference or resolver
  checking original thread grant and separate consent, participant and source.
  Test wrong account/closed thread/revocation/deletion; do not leak private bodies.
  Flutter currently opens the authorized conversation list, never guesses thread.
- **P1 if global ordering required:** PUT `/notifications/{id}/read` and `/unread`
  lock a row and update current read_at; no expected revision/CAS/original attempt.
  Define monotonic version/current state and accepted precondition plus original
  attempt semantics if independent recovery is required. Reversed device requests
  must not silently override newer intent under the new contract. Test two DB
  sessions, lost response, stale CAS, expired login and deleted account. Existing
  prefs/reminders already use CAS; do not recreate their APIs.
- **External:** POST `/notifications/devices` already exists. DisabledPushProvider
  is not device delivery. Actual provider/token transport/quiet-hours/revocation
  qualification requires separate reviewed work. Logout/session/device revocation
  tests must distinguish these different authorities; do not claim Push delivered.

## Comparison cancellation — P2 if original proof required

DELETE `/clinical-plans/{id}/evaluation?expected_revision=N` has current/history
readback and original plan authority, no keyed cancellation attempt route.
Existing POST evaluation/evaluation-review receipts already exist. Specify a
backward-compatible immutable cancellation receipt if independent recovery is
needed. PostgreSQL: cancel racing new job/review/revision/grant loss/deletion;
original cancellation must not be interpreted as consent for a later job.
Flutter does not invent a cancellation key/lookup or image inference.
Calendar policy likewise uses revision CAS rather than a keyed original receipt.

## Flutter acceptance after Backend changes

Publish exact OpenAPI/schema/header/error examples and migration IDs with isolated
PostgreSQL concurrency evidence. Amr can then add contract-faithful mocks, send the
actual documented precondition, extend supported reader selection and UI behavior.
No native/production journal activation follows automatically. Existing fake HTTP,
SQLCipher host and bounded simulator evidence do not replace Backend/PostgreSQL E2E.

Other external dependencies: real constrained Agent model, validated comparison
model/private image transport/clinical validation, genuine Push provider/device
proof. Device security and production rollout remain separate approval gates.
