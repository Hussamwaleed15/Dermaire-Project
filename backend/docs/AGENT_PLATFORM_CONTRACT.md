# H8 consented local agent foundations v1

This is a durable local request broker with disabled model adapter, not an
autonomous medical agent. Existing stateless /chat and deterministic PSM are not
renamed or represented as an agent. No model/provider calls occur here.

Patient-only registered prefix `/api/v1/agent`; all success responses no-store:

| Method/path | Input/result |
|---|---|
| GET /capabilities | explicit unavailable model, supported typed requests and limits |
| POST /sessions | longitudinal_read_consent true, proposal_actions_consent bool, one Idempotency-Key;201 stable session identity |
| GET /sessions/{id} | owner-only context snapshot, revision, expiry, scopes, freshness/provenance |
| POST /sessions/{id}/context | expected_revision; refresh bounded projection, increment session revision/tool budget |
| POST /sessions/{id}/turns | message (1..1000), one Idempotency-Key; durable untrusted user text, unavailable response, zero executed actions |
| GET /sessions/{id}/turns | up to40 durable user turns, no fabricated generated assistant turns |
| POST /sessions/{id}/actions/preview | expected_session_revision, kind, rationale; optional routine_id/routine_revision required only for routine adjustment proposal; one Idempotency-Key |
| GET /sessions/{id}/actions | up to8 previews/confirmed requests; owner only |
| GET /sessions/{id}/action-attempts/{key} | committed/unknown action identity and current action state |
| POST /sessions/{id}/actions/{id}/confirm | expected_revision1, confirm true; durable duplicate-safe request confirmation |
| DELETE /sessions/{id} | revoke all scopes, erase context/raw turns/action payloads; available after policy change |

Allowed typed requests: request_checkin, propose_followup,
propose_routine_adjustment. Confirmation records a self_tracking_request or
pending_clinician_review request only. It does not create a check-in observation,
modify a routine/product/experiment, create a clinician plan, enqueue a notification
or notify a doctor. Those false fields are explicit in the result. No arbitrary
tool names, commands, export, URLs or medication fields are accepted. Review and
actual medical changes still require the existing authorized clinical workflows.
Urgent safety blocks treatment/follow-up proposals and preserves escalation.

Each session binds owner, creating JWT jti/credential, explicit scopes and minimum
of JWT expiry/one hour. Original logout, password change, expiry or scope revoke
blocks subsequent retrieval/actions, including readback. Different accounts404;
doctor/support/admin403. Raw text is untrusted memory only; it never changes tool
authority or becomes an executable prompt. Offline injection tests prove this
disabled typed boundary, not the safety of any future model integration.

Context uses existing bounded redacted `context-1.0` projection (240 facts/24KB
fact budget, freshness and source provenance). It excludes identifiers, private
notes, image bytes and sensitive disclosures from any model input; adapter is
never invoked. A local hash of all relevant owned DB rows detects source changes;
the row vector is capped5000, failing unavailable if exceeded, and is neither
stored in conversation memory nor sent externally. Source hashing includes
private data only inside the server process. Owner locks fence ordinary API
writers; this is explicitly multiple reads, not a PostgreSQL atomic clinical
snapshot or guarantee about concurrent external DB writers.

Preview requires context age under5 minutes and matching evidence hash. Confirm
requires preview age under5 minutes and matching current hash; otherwise409 and a
new preview is required. Refresh CAS/8 total retrieval+preview calls and40 turns
bound tool work per session. Lost preview/confirmation response503 is reconciled
via action-attempts or action list. Same-key different input409; confirm false403;
unknown is not a durable rejection/in-flight reservation. Confirm replay returns
the previously recorded request and never executes another effect.

Session create replay returns the same resource with its current snapshot, not an
immutable original-context receipt. Refresh timeout needs GET/revision
reconciliation, not blind retry. Expired memory is inaccessible but retained until
explicit session revoke/account erasure; automatic TTL purge and broader memory
policy remain OPEN. No cross-session memory learning or clinician request inbox
is implemented. Audit stores ids/kinds/consent version only, not prompt/rationale.
Account deletion/journal replay erases all session/turn/action records and scrubs
related audit identifiers. Migration07 follows06 and populated downgrade refuses.

Model `agent-model-boundary-1`: unavailable, invoked false, null provider/version/
response, reason agent_model_not_integrated. A future genuine integration needs
separate scoped tool-output validation, live provider evidence and clinical
approval; offline synthetic tests are not clinical validation.
