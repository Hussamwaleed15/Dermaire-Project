# Amr — post-expanded Flutter integration handoff

Backend owner Hussam; mobile owner Amr. All routes below are real backend routes,
with `/api/v1` prefix, bearer auth and stored current role. No Flutter/native/Tester
source changed, no device/emulator used, no live DB/provider deployed. Isolated
backend tests do not certify mobile behavior, delivery, clinical safety or accuracy.

## Integration priorities

1. Retain original operation key, normalized body and precondition across timeout;
   reconcile first. Original SQL receipt is historical evidence, not current state.
2. Add explicit independent routine-reminder and clinician-request consent. OS push
   permission, safety acceptance, VIEW and EXPORT remain different permissions.
3. Wire immutable routine history and UTC/local labels without relabeling old dates.
4. Wire agent clinician inbox/decisions and explicit nonclinical tool confirmation.
5. Wire comparison queued/unavailable/running/cancelled/pending-human-review and
   separate doctor signoff. Never invent a comparison score or generated model reply.
6. Clear private caches at logout/account switch/revoke/withdrawal, and reauthorize
   every private deep link. Preserve private-current doctor decision precedence.

## Migrations and operations

Reviewed source migration order is existing09 ->10 clinical/grant receipts ->11
configuration/calendar evidence ->13 recurring reminders. There is no12 migration;
H8/H7 use existing durable action/clinical-plan event tables. Readiness requires13.
No live migration was run. Old UTC columns/keys are preserved. Populated new
receipts/history/reminder downgrades refuse data loss. SQLite remains supported,
but PostgreSQL provides the actual locking/snapshot/concurrency guarantees.

Default notification kinds are empty and push false. Provider/model transport is
unavailable. Hosted workers, provider credentials, real device proof, secure model
artifact/image loading and clinical validation are still prerequisites for live use.
`DERMAIRE_AGENT_MODEL_PROVIDER` is a nonsecret adapter-name request; unsupported
names return unavailable and never activate transport. Existing contextual AI/PSM
is separate from the new agent contract.

## Auth, consent, headers and uncertain outcomes

| Status | UI handling |
|---|---|
|401|Invalid, expired, credential-invalid or logged-out session; clear private cache|
|403|Role, current policy or original grant/consent denied; no cached content bypass|
|404|Foreign/missing private resource; do not disclose ownership|
|409|Payload/key mismatch, changed body revision, stale preview, current clinician busy; reconcile original identity|
|410|Expired/erased receipt, unavailable bearer invitation or expired history cursor|
|412|Stale If-Match or calendar expected revision; refresh without overwriting uncertainty|
|422|Invalid input, duplicate/malformed key, invalid cursor/timezone/consent shape|
|428|Missing required protected resource precondition|
|503|Commit/readback unconfirmed or unsupported true PG snapshot; preserve original identity|

New receipt writes expose `Operation-Attempt-Id`, `Operation-Replay: true|false`,
`Result-Snapshot: original_committed` and `Cache-Control: no-store`. Use a distinct
16..128 character `Idempotency-Key` per intent; preserve exact full typed body and
original If-Match/Routine-If-Match/sequence. Unknown is not proof of rejection or a
safe reason to create another operation. No durable rejected/in-flight registry is
claimed. Missing keys retain legacy behavior; key migration is not silently forced.

## Doctor notes, reviews and access receipts

Existing POST `/doctor/patients/{patient_id}/notes` and `/reviews` now accept keys.
A note body example is `{"content":"Clinician authored note"}`; review example is
`{"state":"reviewed","expected_sequence":0}`. Private fields retain existing typed
contracts. GET `/doctor/patients/{patient_id}/attempts/{note|review|claim}/{key}`
returns committed/unknown/expired, original access_id and original result. Current
VIEW/original grant is rechecked. A replacement grant409 never revives old authority.
Review replay returns its original sequence before fresh CAS evaluation.

POST `/doctor/generate-qr` accepts a key and explicit consent payload. EXPORT needs
selected real doctor and separate export_consent; stored role is not license proof.
DELETE `/doctor/access/{access_id}` and `/doctor/revoke/{patient_id}` support keyed
single/bulk revoke. GET `/doctor/consent-attempts/{issue|revoke|revoke_all}/{key}`
reconciles. Issued QR token is returned only while the original invitation is still
pending/unclaimed/unrevoked/unexpired with valid issuing session/credential. A
claimed QR receipt may say committed with result_availability unavailable and null
result; never display it as reusable. Bulk revoke replay never revokes newer grants.

GET `/users/completion-receipts/{safety|profile-review}/{version}` reads actual atomic
audit evidence. Safety version equals the required policy; profile supports1 only.
Legacy state without audit is unknown, with current state separately shown. Existing
safety version equality and one-time profile timestamp remain unchanged.

## Routine evidence and calendar

GET `/routine/configuration-history?routine_entry_id=<optional>&limit=100&cursor=...`
returns schema_version, day_basis UTC, coverage, coverage_since, last_evidence_at,
as_of, immutable items and next_cursor. Future create/edit/stop/archive/experiment
writers record actual configuration and product evidence transactionally, with
known actor/writer provenance. No invented historical backfill. Signed one-hour
cursors bind owner/filter;422 invalid/foreign scope,410 expired. Cutoff is explicitly
not an atomic MVCC snapshot; an already-in-flight write may commit later.

GET `/routine/calendar-policy` starts revision0/UTC. PUT accepts:

```json
{"expected_revision":0,"timezone":"Africa/Cairo"}
```

Returns prospective effective_at/local_today; concurrent stale revision412. No
backdating. Travel changes display labels at recorded policy instant, never old
UTC adherence dates or `(entry,date,slot)` uniqueness. Continue labeling existing
adherence dates UTC. Per-routine reminder zones are independently approved; account
calendar changes do not silently reschedule reminders or clinician due instants.
See PROSPECTIVE_HISTORY_CALENDAR_HANDOFF.md for DST/midnight/freshness rules.

## Recurring reminders and inbox

PUT `/notifications/preferences` example:

```json
{"expected_revision":0,"enabled_kinds":["routine","agent_request"],"push_enabled":false,"timezone":"Africa/Cairo","quiet_start":1320,"quiet_end":420}
```

Allowed kinds also include message/follow_up/comparison. Explicitly set push true
only with user permission; actual provider is still disabled. Quiet hours use local
half-open minutes, both repeated hours, equal endpoints disabled. Device registration
keeps existing session/credential/encryption rules and never returns raw tokens.

GET/PUT `/notifications/routine-reminders/{entry_id}`. PUT example:

```json
{"expected_revision":0,"enabled":true,"timezone":"Africa/Cairo","am_minute":540,"pm_minute":1260,"fold":0,"gap_policy":"skip"}
```

AM/PM/BOTH follows routine schedule; nonexistent DST time skips, overlap selects
exact approved fold once. Normal times resolve fold0. Effective future generation
is bounded; no overdue backfill. Setting edits/travel create new revision and cancel
old occurrences. Routine changes/stop/archive fence jobs atomically. Preference
withdrawal disables schedules; restoring preferences never silently re-enables them.
Logout cancels jobs for that session and clears its encrypted device credential.
Routine push older than24h is cancelled; authorized historical inbox remains.

GET `/notifications` returns currently authorized due items/read/unread flags and
next_before. PUT `/{id}/read` acknowledges app read; PUT `/{id}/unread` reverses it
explicitly. Neither means push delivered. GET `/notifications/history?limit=50&before=...`
returns privacy-filtered durable state plus prospective per-lease attempts. Expired
leases become unknown; retries and provider acceptance remain separate, and every
attempt says delivery_confirmed false. No history before migration13 is backfilled.
Revoked clinical content is omitted and account deletion erases attempt evidence.
Generic push contains only Dermaire/You have an update; no PHI/deep-link authority.

Executable isolated worker: `python -m app.workers.notifications --database-url
sqlite:///dermaire_rehearsal_worker.db --once` from backend after migrations. No
ambient application DB selection. It also performs bounded expired agent memory
cleanup. Fake adapter tests prove infrastructure only. Live enablement steps and
retry/lease/provider distinctions: RECURRING_REMINDER_WORKER_HANDOFF.md.

## Agent request and nonclinical action lifecycle

Existing explicit scoped sessions, five-minute freshness, urgent Safety, budgets,
raw untrusted turns and preview/confirm rules remain. Typed turn content never
selects tools. No model response is fabricated. A confirmed clinical proposal is
only a request; it never changes treatment or performs a check-in.

POST `/agent/requests/{action_id}/submit`:

```json
{"expected_revision":2,"access_id":"original-active-grant","clinician_request_consent":true}
```

Records version1 explicit routing consent, revision3 and original session TTL.
GET `/agent/requests` is current doctor's bounded inbox. POST
`/agent/requests/{id}/decision` accepts `{"expected_revision":3,"decision":"accepted"}`;
pending ->accepted/rejected, accepted ->reviewed. Repeat original decision/revision
to reconcile. DELETE same request withdraws/erases content even after policy/session
expiry. Session revoke/expiry also erases memory. Bilateral account deletion purges
directed content. TTL is enforced before bounded cleanup, at original one-hour max.
Clinician busy/deleting can409 without mutation; retain original submission.

Separate agent_request preference permits transactional doctor/patient notices only
after actual submission/decision commit. notification_enqueued reflects real local
insertion; clinician_notified stays false without delivery proof. Accept/review does
not authorize a treatment change. Doctor inbox pagination beyond100 remains OPEN.

The actual nonclinical `mark_notification_read` tool uses existing action preview:

```json
{"expected_session_revision":1,"kind":"mark_notification_read","notification_id":"owned-current-unread-id","rationale":"Mark this update read"}
```

Explicit confirm locks/current-authorizes the notice and compares unread state;
stale state409. Read transition and action receipt commit together. Broader tools
require a separately implemented explicit allowlist; no arbitrary tool/model action.

## Private comparison evaluation and human review

Captured, acknowledged comparison plan + owned accepted private baseline/follow-up
+ current original VIEW grant required. POST `/clinical-plans/{id}/evaluation`, key:

```json
{"expected_revision":3,"image_processing_consent":true}
```

202 queued acceptance is separate fresh processing consent. GET same route reads
current durable job; DELETE `?expected_revision=N` cancels with CAS. Existing
`/{id}/attempts/evaluate/{key}` reads original queue receipt. Worker transitions
increment plan revision; refresh before any next CAS write. Durable event states
include queued/running/unavailable/cancelled/pending_human_review; historical state
and effective cancellation are explicitly distinguished. No automatic routine-end
schedule. Revocation/cancellation/deletion fences returning worker completion.

POST `/clinical-plans/{id}/evaluation/review`, doctor + key:

```json
{"expected_revision":6,"job_id":"original-job-id","decision":"reviewed","assessment":"Clinician authored assessment"}
```

Explicit review/reject binds job/model version/artifact digest and human author.
Plan review alone is not inference signoff; withdrawn plan denies new signoff.
Comparison output is constrained to nonclinical image-quality evidence; no lesion
diagnosis, numerical improvement, treatment recommendation or accuracy claim.
Actual artifact verification/loading, private image transport and clinical validation
remain BLOCKED. Default model response is unavailable; synthetic fixtures are not
patient results. Agent/comparison adapter and isolated CLI details:
WAVE_AGENT_COMPARISON_HANDOFF.md.

## Preserved integration

Existing product/routine/experiment receipts, protected revision/If-Match headers,
check-in/capture/adherence reconciliation, private image ownership, H5 immutable
messaging and clinical-plan lifecycle, patient/doctor PG repeatable-read snapshots,
Safety and private-current precedence are retained. Detailed unchanged contracts:
CONFIGURATION_ATTEMPTS.md, PRODUCT_MUTATION_ATTEMPTS.md, MESSAGING_CONTRACT.md,
CLINICAL_PLAN_CONTRACT.md, DOCTOR_CLINICAL_SNAPSHOT.md and H1–H4 contracts.

Test mobile logout/account switching, current role/original grant revoke, consent
withdrawal after policy change, lost-response exact retries, stale CAS, UTC/local
labels and DST/travel, paged history cache reset, no-PHI notifications and explicit
unavailable model/provider UX. Backend local evidence grants no release approval.
