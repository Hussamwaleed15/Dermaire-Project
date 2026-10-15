# Post-expanded completion wave — source verification and acceptance DAG

Baseline independently fetched: origin/main `275e753b3d07cbe86f0aed08d558802355ce2c6d`.
Isolated clone under this chat; original clean tree. No Flutter/native/Tester edits,
provider calls, deployed resources, live DB or preserved PG clusters authorized.
Reference report is orientation; source and current tests determine status.

## Dependencies

Current credential/session + provisioned role -> original live grant + explicit
scope -> clinical write and durable original receipt -> consented clinician request
inbox -> explicit doctor decision. Current Safety and private-current precedence
remain upstream of clinical read/write results. Patient consent never provisions
a doctor or authorizes autonomous treatment.

Routine/product/experiment writers -> transactional future configuration events ->
owner history and declared freshness. Prospective local calendar events do not
rewrite UTC adherence dates. Explicit per-routine wall-time approval -> bounded
occurrence generation -> domain-current inbox/outbox -> fenced worker -> disabled
provider boundary. Real accepted delivery and delivered proof are separate states.

Consented comparison plan + owned accepted private baseline/follow-up -> explicit
processing consent -> durable leased evaluation -> typed model boundary -> human
review. Absent verified model artifacts keeps inference unavailable.

## Exhaustive acceptance inventory at this baseline

| Domain | Required acceptance checks | Baseline status |
|---|---|---|
| H1 grant issue/revoke | patient/credential/payload/key-bound receipt; one-use QR; never resurrect claimed/revoked/expired invite; explicit VIEW/EXPORT and current role | committed issue/revoke receipts OPEN; existing one-use/scope checks retained |
| Clinical notes/reviews | actor/patient/original grant/payload-bound SQL receipt, replay/readback, original output, private-current, review sequence CAS, concurrent duplicate/changed payload, rollback, bilateral erasure | receipt OPEN |
| Safety/onboarding | version binding, current policy, consent revoke, receipt and lost-response semantics | existing versioned state; durable attempt registry OPEN |
| Existing H2-H4 receipts | product/check-in/capture/adherence and routine/experiment committed receipt contracts; signed deletion/restore; unknown/expired truthful | bounded existing implementation; universal rejected/inflight registry OPEN |
| H5 messages/followups | explicit independent consent; original grant; immutable sends/page/read watermarks; schedule/ack/capture/review CAS; erasure | implemented bounded source; no clinical certification |
| Snapshots | patient and doctor PG RR; current final auth; one Safety/clock; private-current precedence | implemented; external atomicity unsupported |
| M2 routine events | all writers create/edit/stop/archive/intervention; transaction/rollback; frozen configuration/product evidence; no invented history; owner cursor/cutoff; delete/restore privacy | OPEN |
| Local calendar | prospective zone/travel policy, immutable effective history, DST midnight/gap/overlap tests; never rewrite legacy UTC keys | OPEN |
| H6 consent/device | default off, session/expiry/credential encrypted device, quiet hours and generic no-PHI payload; logout/revoke/delete | existing source |
| Recurring reminders | explicit AM/PM/BOTH/local IANA/fold/gap; bounded generation, stable identity, no missed backfill, concurrent duplicate; edit/stop/consent invalidation | OPEN |
| H6 worker/inbox | read/unread; cancellation state readback; executable worker, leases/retry/fencing, unavailable/accepted/delivered distinction | worker entrypoint/unread/history OPEN; live provider BLOCKED |
| H8 consent/request lifecycle | bounded untrusted context and urgent Safety; explicit patient preview+confirmation; original grant consented routing; doctor inbox/accept/reject/review/CAS; TTL/revoke/erasure; notification only committed | preview/request exists; routing/doctor lifecycle OPEN |
| H8 nonmedical broker | per-tool authorization, preview/confirm/idempotency/CAS, actual execution distinguished from proposal; memory/session revoke | bounded request-only source; wider tool execution OPEN |
| H8 real inference | strict versioned provider config, no generated real response without genuine call; mocked integration explicitly synthetic | adapter OPEN; live inference BLOCKED |
| H7 evaluation | private images and fresh processing consent; async durable jobs, human review, provenance/retry/cancel; no routine-end auto schedule | jobs/adapter OPEN; real model/clinical validation BLOCKED |
| H7 artifacts | inspect actual artifact presence/version/contract, never invent diagnosis/improvement/accuracy | source scan required; no validated model assumed |
| Migration/regression | fresh isolated PG, seeded migration, drift, SQLite compatibility, all-suite zero failures/skips with PG enabled, compile/OpenAPI/diff/security review | execute per stable milestone |
| Integration docs | current routes/headers/examples/errors/reconciliation/calendar; exact unsupported states and PG counts, separate Amr and Arabic report | update after verified implementation |

## Execution and evidence policy

Independent source tracks: receipts, history/calendar, agent/comparison; notification
integration and final review are coordinated centrally. Shared migrations ordered
10 clinical/grant receipts -> 11 history/calendar -> 13 recurring notifications.
Tests execute serially because legacy autouse fixtures share a SQLite file.
Only the newly initialized chat-owned PG cluster is used (loopback 55441, user gate,
fresh randomly named disposable databases). Preserved cluster directories remain
untouched. A failed/interrupted baseline under concurrent edits is not certification.

A committed receipt proves that SQL domain transaction only. Missing receipt is
unknown, never evidence of rejection or permission to replay with a new identity.
No durable in-flight/rejected status may be claimed without a transactional registry.
Source completion never implies live-provider, device or clinical release approval.
