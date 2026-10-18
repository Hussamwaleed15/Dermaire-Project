# Verified backend/external boundaries — integration wave2026-10-18

Source8ad2ceafced5b1f06ade5a082d4939503d31c687. Amr edits app/ only.
Historical M4–M6 'missing messaging/consent/scheduling/notifications/Agent' reports
are superseded by real source contracts. Do not recreate those implemented APIs.

- BLOCKED external: genuine push provider/mobile token transport/configuration,
  hosted worker/scheduler and actual device delivery proof. Default provider disabled;
  provider_accepted is not delivered. No credentials/native/provider edits authorized.
- BLOCKED external: validated comparison model artifact/loading/private model image
  transport/clinical validation, and genuine constrained Agent inference transport.
  Backend local broker/job lifecycle is usable independently, not medical inference.
- OPEN actual source: durable committed receipts do not prove rejected/in-flight
  attempts. Unknown cannot permit a new key. General rejected/in-flight registry,
  doctor Agent inbox pagination beyond100 and complete all-domain historic MVCC
  reconstruction remain open in the latest backend ledger.
- Product/server contract for future unauthenticated safety-policy publication:
  register/accept requests have a legacy1.0 default; authenticated GET /users/me
  supplies required_version/current state, but a public versioned policy text
  publication contract is absent. Flutter uses server metadata after login and
  explicit user acceptance; it does not fabricate changed policy text/version.

No live backend/DB/provider verification or deployment performed. Additional gaps
will be added only after source verification during implementation.

## F3 verified boundaries
- Message notification source_id is a message ID without thread_id or a resolution route. Add an authorized thread/deep-link reference to avoid requiring manual conversation selection. Flutter currently opens authorized conversations honestly.
- Read/unread has no revision/attempt identity: cross-device/late-write ordering cannot be proven. If ordered edits are required, add CAS plus current-state/attempt semantics.
- Push provider remains disabled and mobile token configuration is absent. No fake registration. Confirm provider/token/plugin plan separately; no configuration changed.

## F5 verified contract needs
- Agent session GET needs a known ID; there is no active-session list/discovery or revoke-all endpoint. Flutter intentionally does not persist PHI/auth sessions. Add authenticated minimal session discovery + explicit bulk revocation if process-restart recovery is required; define original-login/TTL behavior without reviving old authority.
- Doctor Agent request responses omit patient_id, so Flutter cannot safely link a request to authorized patient context. Add an authorized patient reference/deep link (still bound to original session/grant).
- Doctor request inbox is bounded to100 with no cursor. Add authorized pagination before claiming complete historical request retrieval.
- Model/provider transport remains unavailable. Flutter displays real broker outcomes, not generated assistant replies or autonomous clinical actions.

## Continuation source recheck and actionable priority

Rechecked during F6 continuation from3efe4b5/cdfc8da against current registered
agent_platform/notifications routes, action_out DTO, model_providers and disabled
notification provider. No backend edits or live calls. Existing foundation
product/routine/experiment committed receipt APIs are implemented: they are NOT
backend blockers, and Flutter is now consuming them.

| Priority / endpoint | Verified limitation | Required contract / Flutter consequence |
|---|---|---|
| P0 recovery: foundation attempt GET routes and current domain services | Only committed/unknown/expired; missing row does not fence an earlier in-flight request | If definitive abandonment/replacement is required, design owner-bound server reservation/fencing or terminal rejection semantics. Flutter cannot safely equate unknown with failed or issue a replacement key; current exact replay/unknown lock remains intentional |
| P1 Agent: GET /agent/sessions/{id}, no list route | Known ID and original login/TTL required; no restart discovery or revoke-all | Authenticated minimal scoped discovery plus explicit revocation, defining cross-login behavior without reviving authority; otherwise restart session restoration remains unavailable |
| P1 Doctor Agent: GET /agent/requests and action_out | Newest100 only, no cursor and no patient_id/authorized patient link in output | Add authorized patient reference and cursor. Bind to original session/grant; Flutter otherwise opens no guessed patient context and cannot claim complete history |
| P1 Messaging notice: GET /notifications item | source_id is a message ID; no authorized thread reference | Add thread_id or authenticated resolution, with current original consent/grant recheck. Flutter currently opens authorized conversation list, not an invented direct thread |
| P1 read ordering: PUT /notifications/{id}/read and /unread | No version or attempt identity | If cross-device ordering is required, add CAS/current-state/attempt semantics; UI serialization alone cannot guarantee remote ordering |
| External: provider/model adapters | DisabledPushProvider, unavailable Agent inference and unvalidated comparison artifact/transport remain | Supply reviewed provider/model setup and real device/clinical evidence separately; no frontend synthetic delivery, response or diagnosis |

Secure local restart storage and unavailable mobile emulators are Flutter/platform
constraints documented in FLUTTER_F6_RECOVERY_CONTRACTS.md, not new API tasks for
Hussam. No claim that unknown is rejected, that a new VIEW grant restores an old
request, or that reviewed synthetic output establishes clinical validation.

## F6g-2 withdrawal contract recheck

Actual deps safety exceptions and doctor revoke/consent-attempts routes already
support patient bulk withdrawal before current safety acceptance. Flutter now
consumes them at the real entry gate; no backend work is requested for that flow.
Original committed/expired receipts describe the original operation only, not
new grants or the current permission list. General unknown/rejected/in-flight
limitations and Agent/provider requirements above remain distinct.

## F6-L source recheck —2026-10-18

At dc24dfc, rechecked current registered doctor/clinical_plans/agent_platform/
notifications APIs and services. Selective revoke/list and patient plan cancellation
already exist, including policy-loss exceptions and original receipts; implemented
in Flutter, not backend requests. Patient cancellation does not require restoring a
revoked clinician grant; doctor plan access still requires its original grant.
Evaluation DELETE has CAS/current-job semantics, not a synthetic keyed receipt.

Existing P0/P1 table remains current: Agent GET session needs a known ID (no list),
action_out omits patient identity, doctor inbox bounded100/no cursor; notification
read/unread lacks CAS/attempt and message notice lacks thread context; model provider
still returns unavailable and push provider is not proof of delivery. Required
contracts/security impact/priorities are listed above; no already implemented APIs
are requested again. Durable local storage/native runtime are Flutter/platform
constraints, not additional backend tasks. No live backend verification performed.
