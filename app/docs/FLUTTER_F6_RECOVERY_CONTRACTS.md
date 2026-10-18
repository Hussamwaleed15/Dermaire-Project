# F6d–F6e — Operation recovery contract and storage decisions

Continuation start2026-10-18 at3efe4b5a36e793e12628d8d3d4f8aafe6a75d3e5.
Fetch verified identical origin/main, correct fetch/push URLs, clean main. Read
AGENTS and all wave execution reports, current expanded handoffs and relevant
registered API/schema/service source. Fresh baseline:1625 tests, analyzer clean,
pub get succeeded. No live service/device/provider/backend execution.

## Source-backed operation inventory

All endpoints below use authenticated /api/v1. Optional means legacy requests
without a key remain supported; not a guarantee of safe lost-response replay.

| Operation | Actual mutation and identity | Actual reconciliation | Existing Flutter / remaining |
|---|---|---|---|
| Product create | POST /products; optional key, typed creation payload | GET /products/attempts/key; owner/actor, product_create, original revision1 | F6d-1 exact frozen key/body and actual product recovery UI |
| Product edit/delete | PATCH/DELETE /products/id; optional key, exact payload field presence + original If-Match | GET /products/id/operation-attempts/patch-or-delete/key; original snapshot or minimal delete tombstone | F6d-1 preserves original CAS; independently reads current state |
| Routine create/edit/stop | POST /routine/entries; PATCH/DELETE /routine/entries/id; optional key; exact typed body/If-Match | GET /routine/configuration-attempts/create-or-update-or-stop/key?resource_id=id (create omits id) | Original revisions implemented; keyed receipts/recovery remain to integrate. UI stop uses PATCH active:false, so its receipt operation is update |
| Experiment create/edit/activate/finish/cancel/evaluate | POST /experiments; PATCH/DELETE /experiments/id; POST id/activate,finish,evaluate; optional key binds exact typed payload/If-Match/Routine-If-Match | GET /experiments/operation-attempts/operation/key?resource_id=id; create omits id; evaluate original result is EvaluationOut, parent revision separately identified | Dual original revisions/review implemented; keyed receipt/recovery remains. UI draft cancellation via POST finish differs from DELETE cancel identity |
| Routine adherence | POST /routine/adherence; optional key, exact original report | GET /routine/adherence/attempts/key; original config snapshot, configuration revision | F6d-4 exact keyed reports/recovery integrated; legacy history readable, UNIQUE409 is not attempt proof; restart boundary remains blocked |
| Doctor message | POST /messaging/threads/id/messages; required key + exact original content/thread/actor | GET /messaging/threads/id/attempts/key; original message, original thread consent/grant | Current session-memory reconciliation implemented; restart boundary pending |
| Follow-up create | POST /clinical-plans; required key + exact body/original grant | GET /clinical-plans/creation-attempts/patient/key; original plan | Session-memory reconciliation implemented; restart boundary pending |
| Plan acknowledge/reschedule/cancel/review/capture | POST /clinical-plans/id/operation; required key + body expected_revision and exact fields | GET /clinical-plans/id/attempts/operation/key | Session-memory reconciliation implemented; retain original plan/grant; restart boundary pending |
| Comparison evaluation/review | POST /clinical-plans/id/evaluation or evaluation/review; required key, body revision/consent or exact job/decision | GET /clinical-plans/id/attempts/evaluate-or-evaluation_review/key | Existing typed operation/current-job separation; restart boundary pending |
| Evaluation cancellation | DELETE /clinical-plans/id/evaluation?expected_revision=N | Current job/plan readback, no general keyed-delete receipt supplied | Existing CAS; preserve uncertainty, policy-loss withdrawal extension pending |
| VIEW invitation | POST /doctor/generate-qr; optional key, exact consent/body/query and issuing session | GET /doctor/consent-attempts/issue/key | Current memory-only issue recovery; never revive claimed/revoked/expired bearer token |
| Claim invitation | POST /doctor/claim; optional key, exact bearer code/actor | GET /doctor/patients/patient/attempts/claim/key; original grant/session/current VIEW | Existing exact retry/readback; no stored token or restored authorization |
| Selected/bulk revoke | DELETE /doctor/access/id or /doctor/revoke/patient; optional key | GET /doctor/consent-attempts/revoke-or-revoke_all/key | Existing older revocation path; receipt/policy-loss hardening pending |
| Clinical note/review | POST /doctor/patients/patient/notes-or-reviews; optional key; exact content or expected_sequence | GET /doctor/patients/patient/attempts/note-or-review/key; original access_id | Existing older clinical flow; receipt hardening pending; replacement grant cannot revive original write |
| Agent create/user turn/preview | POST sessions, sessions/id/turns, sessions/id/actions/preview; keys and exact body | Preview GET sessions/id/action-attempts/key; session/turn recovery uses exact original supported repeat + current read, not invented universal lookup | Existing session-memory recovery; original login/TTL/scope remain required |
| Agent confirm/submit/doctor decision | POST /agent/sessions/session/actions/id/confirm, /agent/requests/id/submit-or-decision; original CAS/body and defined repeat semantics | Actual current action/session and exact supported repeat; no general synthetic attempt route | Existing memory-only exact confirmation/routing/decision handling; not clinical execution or restart discovery |

Actual source: api/v1/products.py,messaging.py,clinical_plans.py,doctor.py,
agent_platform.py,routine.py,experiments.py; services/product_attempts.py,
product_mutations.py,configuration_attempts.py and current domain services.
CONFIGURATION_ATTEMPTS and PRODUCT_MUTATION_ATTEMPTS supersede older handoffs
claiming those receipts are absent. Do not reuse a generic receipt schema across
these intentionally different APIs.

Foundation receipts expose unknown/committed/expired; erased content can be a
committed receipt with null result. Unknown is never rejection or proof no in-flight
write exists. Original committed result is historical; fetch current authorized
resource separately. Current original-grant/session/consent checks still apply.
30-day retention is not permission to invent replay after expiry. No client claims
SQL receipt proves an independent deletion journal or external delivery outcome.

## Increment plan and gates

F6d-1: real product create/edit/delete keyed requests + typed original receipts +
current-state readback + explicit check/retry/review UI. New operations block while
the original is unresolved. Test before/after commit loss, exact body/key/header,
newer current data, current absence, malformed/scope/error states, late sessions,
controller reconstruction (explicitly not process persistence), actual UI.

Next: integrate routine/experiment receipts with their own domain-specific original
projections and revisions, then the F6e storage audit and persistence-boundary verification when an
approved suitable storage mechanism is available (verified blocker below). Extend already implemented messaging/plan/clinical/
Agent recovery without rebuilding their architecture or restoring stale authority.

## Storage audit and policy

Current dependencies include shared_preferences and crypto; there is no configured
secure payload/token store. Auth and existing pending payloads are memory-only;
legacy plaintext tokens/private caches are removed. No clinical text, raw messages,
medical details, bearer invitations, images or auth credentials may be placed in
SharedPreferences. No native/configuration change is authorized by this task.

F6d-1 adds no disk storage and makes no restart-recovery claim. A controller rebuilt
within the same login can reuse the memory intent; process restart cannot yet do
that. Correct future persistence must preserve only privacy-appropriate operation
identity, reauthenticate under the correct owner, and reconcile read-only before
considering replay. Exact replay whose sensitive body cannot be recovered safely
must stay unavailable rather than invent a payload or issue a replacement key.
Full encrypted payload restoration may require separately approved secure-storage
configuration; a minimal-handle design must not claim that capability.

F6d-1 gate:27 new regressions; all1652 tests pass, analyzer clean. Fresh pub get succeeded at continuation baseline. Expired/erased receipt review rereads receipt and current state before explicit Finish receipt review; it neither replays nor fabricates original content. Unknown cannot be dismissed by that action. No restart claim in this increment.

## F6e storage investigation — BLOCKED durable identity/payload persistence

The installed shared_preferences2.5.5 README explicitly says writes may reach disk
asynchronously and are not guaranteed persisted when the call returns; it must not
store critical data. A read-after-write from its cache is not a durable receipt.
Both old and newer preferences APIs remain preference storage, not a transactional
secure operation journal. The application has no configured secure payload store
or transactional mobile database. Source audit found only existing preferences
and memory state. No native dependency/configuration was added.

Therefore this wave does not store critical operation keys/body snapshots in
preferences and claim restart safety. Clinical/message/invitation/token payloads
also remain prohibited there. Safe full F6e needs a reviewed durable journal and,
for sensitive exact replay, platform-appropriate protected storage, its persistence
and deletion guarantees and real device verification. Native setup requires Amr's
explicit approval under this task. This is a Flutter/platform blocker, not a new
API requirement for Hussam. Other independent F6d/F6f–k work continues.

Until implemented: logout/account switch/session expiry clear memory, operation
keys and sensitive bodies; no old-account payload is restored. Process death loses
memory; no restart-safe claim is made, nor are keys synthesized as replacements.
There is no on-disk recovery schema to migrate or corrupt in this increment. Future
storage must fail closed on corrupt/unsupported schema, verify owner/role/current
consent before any lookup, preserve original scopes/preconditions, and erase scoped
content on logout/withdrawal/account deletion under an explicit retention policy.
Pending encrypted-body restoration and real persistence-boundary tests remain
BLOCKED rather than being replaced by controller-recreation tests.

F6d-2 routine configuration:29 new tests, all1681 pass; analyzer clean, pub get succeeded. Fresh runtime inspection lists macOS only; flutter emulators reports no emulator sources. Android/iOS runtime validation is BLOCKED, not performed.

F6d-3 experiment gate1713 (+32) and F6d-4 adherence gate1741 (+28) passed with clean analyzers and pub get. Durable SQL receipts now used for all current product/routine/experiment/adherence UI mutations; this does not establish client process-restart persistence.

## F6-M typed metadata boundary

OperationIdentity stores owner/role, original path/receipt base/key, client payload
fingerprint and allowlisted resource/grant/job/revisions. No raw body or bearer data.
Fingerprint is not a backend-comparable digest. ProductReceiptReader supports only
actual product contracts. It reuses strict parseIdentity and never creates a new
PendingIntent/key. JournalCoordinator requires a real durable insert/CAS adapter;
none is wired in production. Unknown/expiry/denial keep identities locked. Comparison
DELETE cancellation still has no keyed receipt: history review is a distinct actual
clinical-plan history contract, not a synthetic universal receipt. Original Agent
login/TTL and invitation validity are not revived by memory quarantine or journal.
