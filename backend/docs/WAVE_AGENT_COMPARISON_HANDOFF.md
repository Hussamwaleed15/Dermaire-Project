# H8 clinician requests and H7 comparison evaluation contracts

These additions are backend integration foundations. No model/provider transport,
clinical validation, device delivery or deployment was performed.

## Clinician-directed requests

Existing `/api/v1/agent/sessions/{session_id}/actions/preview` and
`.../actions/{action_id}/confirm` produce user confirmed requests, without changing
clinical resources. A confirmed `propose_followup` or
`propose_routine_adjustment` may now be sent to a specific current doctor grant:

* `POST /api/v1/agent/requests/{action_id}/submit` (patient):
  `{"expected_revision":2,"access_id":"grant-id","clinician_request_consent":true}`.
  Submission records explicit consent version 1 and revision 3. Repeat the exact
  original grant/revision to reconcile a lost response. Grant/payload changes
  return 409. Self-tracking check-in actions cannot be sent as clinical requests.
* `GET /api/v1/agent/requests` (doctor): bounded newest 100 requests for that
  doctor, with current patient session, credential/logout, original VIEW grant
  and TTL checked. Expired or revoked authority produces no inbox item. This
  is a bounded inbox; pagination beyond 100 remains OPEN.
* `POST /api/v1/agent/requests/{action_id}/decision` (doctor):
  `{"expected_revision":3,"decision":"accepted"}`. Pending accepts/rejects;
  accepted requests may become reviewed using current revision. Decisions are
  CAS protected and repeat the original revision/decision for reconciliation.
  Accepted/reviewed requests never authorize treatment changes.
* `DELETE /api/v1/agent/requests/{action_id}` (patient): revoke and erase proposal
  payload/result even after session/grant expiry. Existing session deletion also
  erases these requests. Bilateral account deletion removes directed content.

Every committed transition adds a content-free audit entry in the same
transaction. Request TTL uses the original session's maximum one-hour expiry;
new login or new doctor grant never revives it. Existing capability contracts are
preserved. The separate `agent_request` notification preference is off by default. Submission
enqueues a doctor inbox/outbox notice only when opted in; decisions enqueue a
patient notice only when opted in. These are committed with the event. Superseded
notices are cancelled. Original session/grant/TTL fence delivery and bilateral
deletion erases notices. `notification_enqueued` records actual queue insertion;
`clinician_notified` remains false because delivery has no proof. Agent model output
remains unavailable. Tools remain a strict allowlist with explicit preview and
confirmation; untrusted turn text cannot invoke tools. The `mark_notification_read` nonclinical tool now requires an owned currently
unread due notification, preview and explicit confirmation. Confirmation locks
the notification and compares unread state; concurrent changes return 409. Action
receipt and read transition commit atomically. Broader nonclinical tool execution
and provider inference remain OPEN.

## Comparison evaluation queue

Only a captured clinician comparison plan with accepted private baseline and
follow-up images, original active VIEW grant and prior scheduling consent is
eligible. No automatic routine-end scheduling exists.

* `POST /api/v1/clinical-plans/{plan_id}/evaluation` (patient), one
  `Idempotency-Key` header and
  `{"expected_revision":3,"image_processing_consent":true}` -> 202 queued.
  The image-processing consent is separate from plan acknowledgement. A queued,
  running or pending-review job prevents a second active queue entry. Retry an
  unavailable/cancelled evaluation with a new key and current plan revision.
* `GET /api/v1/clinical-plans/{plan_id}/evaluation` (patient/current doctor):
  durable last job. `not_requested` contains no inference. Plan cancellation or
  completed human review makes outstanding jobs effectively cancelled.
* `DELETE /api/v1/clinical-plans/{plan_id}/evaluation?expected_revision=N`:
  patient or current doctor, CAS cancellation, clears inference and lease.
* `GET /api/v1/clinical-plans/{plan_id}/attempts/evaluate/{key}`:
  original queue acceptance receipt; current job state must be reconciled via
  the evaluation status endpoint. Unknown is not proof of nonexecution.

Queue/lease/completion/cancellation are append-only `clinical_plan_events`
operation `evaluation`, incrementing the plan revision; they do not rewrite
source snapshots or backfill history. Queue receipts use existing durable
clinical plan attempts. No database migration is required. Flutter must refresh
plan revision after worker transitions before any plan CAS write.

`ENVIRONMENT=test python -m app.tools.comparison_worker --database-url URL --plan-id ID` performs one bounded local
iteration against an explicitly passed disposable database target, restricted to the
existing rehearsal loopback PG gate or named synthetic SQLite targets. Ambient
application database configuration cannot select the worker target. It defaults to the
unavailable adapter and makes no network or image-storage call. Worker lease is
committed before adapter work; completion rechecks original grant, consent,
private images, captured plan state and a two-minute lease token. Cancellation
fences a returning adapter. A crashed lease can be reclaimed after expiry, up to
three claims. No automatic scheduler/deployment was added. Providers must honor
bounded timeouts; the adapter protocol alone does not enforce process timeouts.

`app.services.model_providers` defines strict versioned agent/comparison input
and output envelopes and adapter protocols. Unavailable envelopes reject results;
generated agent responses require provider/version/invocation provenance.
Comparison results require model version, artifact SHA-256 and human review;
clinical clearance is always false. No verified model artifact was found in the
repository scan. Actual loading, artifact verification, secure image retrieval,
clinical/model validation, provider transport and production operations remain
BLOCKED/OPEN. Explicit inference-result signoff is available as described below. Existing clinician-authored plan
review is distinct from validating machine inference. Synthetic tests exercise
contracts and concurrency fences only; they establish no clinical accuracy.

Agent TTL cleanup: the isolated comparison worker runs a bounded `expire_requests`
pass, clearing expired context, turns and action content and cancelling request
notifications with one content-free expiry audit. Authorization enforces expiry
even before cleanup. Additional scheduler integration remains an operations task.

Provider config: `DERMAIRE_AGENT_MODEL_PROVIDER` defaults to `disabled`. An
unsupported configured name reports `configured_provider_adapter_unavailable`;
it never enables transport. Capabilities expose only nonsecret typed config.
Comparison evidence is constrained to capture IDs, image-quality flags and
`nonclinical_image_quality_only` provenance; arbitrary diagnoses/scores are rejected.


Explicit inference review: `POST /api/v1/clinical-plans/{plan_id}/evaluation/review`
requires current doctor authority, one Idempotency-Key, and
`{"expected_revision":6,"job_id":"job-id","decision":"reviewed","assessment":"Clinician authored assessment"}`.
Only `pending_human_review` evidence can be reviewed/rejected. The immutable event
binds assessment to job ID, model version and artifact SHA, with separate durable
attempt replay. This is a clinician assessment of limited nonclinical evidence,
not certification of model accuracy, diagnosis or clinical clearance. Reviewing a
plan separately never implies inference signoff. A future model must undergo
artifact/model/clinical approval before live integration.

Concurrency recovery: patient request submission takes a PostgreSQL NOWAIT
clinician-row lock before routing. A clinician account busy with another write or
deleting returns 409 without mutation; refresh/reconcile and retry the original
submission. This avoids auth patient-row/doctor-row lock inversion. Original
clinician deletion fences new JSON-directed requests. Session and request rows
are refreshed after acquiring locks, preventing stale consent/withdrawal state
from being overwritten. Comparison phase-two readback discards stale identity-map
objects before checking for account/plan deletion; no result commits afterward.
Grant revocation gives evaluation status an explicit effective cancellation while
preserving the original historical worker event.

Patient plan cancellation also fences inference human signoff: queued/running/
pending-review jobs report effective cancellation, and review attempts return 409
without a human-review event. Doctor inbox authorization locks patients in stable
account order while keeping the displayed list newest first. Concurrent account
erasure returning after a grant lookup produces 403 instead of an unhandled
missing-row error.

Validation evidence before final full regression: the first focused H8/H7 run
passed 46 tests including six real PostgreSQL cases. The subsequent combined
reminders/H8/H7 focused run passed 65 tests, including the new PostgreSQL doctor
deletion/submission NOWAIT race. One further withdrawal-signoff branch was added
for final regression. These are isolated synthetic correctness tests, with no
clinical accuracy or live delivery evidence.
