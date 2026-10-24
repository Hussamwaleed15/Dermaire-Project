# Backend F7 contract matrix

Date: 2026-10-24 (Africa/Cairo). API prefix: `/api/v1`.

| Area | Status | Contract and authority | Recovery / concurrency |
|---|---|---|---|
| Clinical note/review original grant | PARTIAL | `POST /doctor/patients/{patient_id}/notes` and `/reviews` accept optional `Original-Grant-Id`. When supplied, the authenticated doctor, patient, exact active/unexpired VIEW grant and policy dependencies are checked. Response `Original-Grant-Binding` is `explicit` or `legacy-current`. | Patient then exact grant are locked in the write transaction. `Idempotency-Key` remains optional and payload-bound. Committed receipts remain 30 days, subject to current authorization. Flutter must send the header to obtain the hardened guarantee. |
| Operation lifecycle | PARTIAL / ALREADY IMPLEMENTED | Existing domain receipts prove committed original SQL results; unknown remains honest and is not retry permission. | No fabricated universal rejected/in-flight state or exactly-once claim was added. Durable generic fencing remains OPEN. |
| Agent session discovery | DONE (source/SQLite) | `GET /agent/sessions?limit=&before=` returns only active sessions owned by the patient after original login, credential, expiry, scope and revocation checks. It omits context and turns. | Stable `(expires_at,id)` descending cursor; invalid/cross-account cursor is 422. |
| Doctor Agent requests | DONE (source/SQLite) | `GET /agent/requests?limit=&before=` returns currently authorized original-grant-bound requests and `patient_ref {patient_id,access_id,authority}`. | Stable `(previewed_at,id)` descending pagination; replacement grants cannot revive a request. |
| Notification target | DONE (source/SQLite) | Inbox items include server-built `target`. Message targets are `{type:conversation,thread_id,message_id,authority}` only after current thread/grant/participant authorization. | Deleted/closed/revoked sources are filtered. Client text/deep links are never trusted. |
| Notification read state | DONE (source/SQLite), PG BLOCKED | Inbox adds `state_revision`. `PUT /notifications/{id}/read|unread?expected_revision=N` returns 412 on stale state; omitting the precondition retains legacy behavior. | Row lock + revision increment prevents a hardened stale device intent from overwriting newer state. Migration `20261024_14`. |
| Evaluation cancellation receipt | DONE (source/SQLite), PG BLOCKED | `DELETE /clinical-plans/{id}/evaluation?expected_revision=N` accepts optional `Idempotency-Key`. `GET /clinical-plans/{id}/attempts/evaluation_cancel/{key}` returns the immutable original cancellation result. | Key is actor/owner/plan/operation bound and payload-bound, retained 30 days. A later evaluation/current state is distinct. |

Authentication is bearer authentication through existing dependencies. Private
responses remain `Cache-Control: no-store`. Existing 401/403/404/409/410/412/422/
503 meanings are preserved. No endpoint claims AI inference, Push delivery,
clinical clearance, or current authority merely from a historical receipt.

OpenAPI after F7: 114 paths and 117 component schemas. The query/header additions
are backward compatible. Migration head/readiness is `20261024_14`.
