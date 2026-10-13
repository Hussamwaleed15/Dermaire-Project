# M3-F4 — Future Agent Integration Readiness

Source416207843c8811b47e5fa01f272d88ba61c8df4f (verified F3 commit/push).
Read F2 assistance, F3 typed stateless chat, PSM v2, M2-F3 comparison boundary,
existing routine/experiment/doctor APIs, consent/session and notification templates.
Existing direct user APIs are not executable AI tools. No broker/capability discovery,
conversation memory, purpose consent, notification or image-model contract exists.

Proposed domain ONLY: consent unknown/userRequested/locallySelected/awaitingServer/
serverConfirmed/revoked; context scopes; source authority AI/patient/clinician/safety/
server/unknown; proposal identity/owner/revision, exact string parameters, required
review, evidence, optional provided conversation/provider/version/result references;
action statuses including unknown/uncertain/cancelled/superseded. No JSON serializers,
HTTP paths, generated IDs, storage, provider SDK or real action result. A future
verified adapter must validate actual wire permissions/receipts before mapping.

AgentRepository offers future read/execute/cancel boundary; actual default throws
AgentUnsupported for all operations with zero HTTP. AgentController is session/
owner/consent/revision/request/disposal bound. Stale/cancelled/superseded and older or
conflicting same-revision proposals do not restore review. Local scope selection and
parameter review are explicitly local, reset on refresh/invalidation and never consent.
canExecute/canTransmitExpandedContext/durableMemoryAvailable always false. Execute/
cancel stay unsupported even with a fake repository or provided proposed receipt.
No speculative write/retry, auto clinical change or context expansion is possible.

Unwired reusable AgentProposalCard displays supplied proposal/parameters/purpose/
source, unknown metadata and explicit unavailable action. Proposed scopes are not
called server permission; server receipt references are not cryptographic proof.
Medical/doctor/scheduling action kinds cannot execute; clinician/backend review is
separate. Success can be represented only with provided result/completion references,
but no production result is invented: synthetic examples exist exclusively in tests.
No Home/chat/nav entry, proactive suggestion, notification schedule or medical-risk
classifier. Existing F2/F3 clinical panels and safety snapshots unchanged.

Verification: analyzer clean; full **1011 tests passed =973 preserved +38 new**.
Tests cover authority/consent/status/missing proof, unsupported defaults/no HTTP/no
writes, revoked/local consent, owner/late/current-generation isolation, old401/reused
B token, timeouts/concurrent reads, stale/superseded/revision conflicts, repeated
execution attempts and Light/Dark/reduced/320px/200%/disabled accessible controls.
No production API/OAuth, backend/provider/DB/Azure/Tester changes or device QA.
F4 architecture readiness complete; full agent, durable memory, consented execution,
notifications, medical/image analysis and scheduling remain unavailable. Stop after
these three authorized M3 milestones; no M4 work.
