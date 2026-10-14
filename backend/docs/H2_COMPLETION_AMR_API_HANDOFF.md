# Amr — Android/iOS Flutter backend contract, H1/H2 completion

Backend owner Hussam; Flutter owner Amr. Backend API handoff only: no mobile implementation/cutover/deployment. All routes use /api/v1 and current authentication. Existing registered routers are exercised by API tests. No expected_version body field was added.

## Configuration revisions

| Resource | Read/create contract | Direct mutating preconditions |
|---|---|---|
| Products | POST /products, GET /products/{id}; list adds revision/revision_protected; entity ETag | PATCH /products/{id}, DELETE /products/{id}: If-Match |
| Routine | POST /routine/entries, GET /routine/entries/{id}; list adds revision/revision_protected; entity ETag | PATCH /routine/entries/{id}, DELETE /routine/entries/{id}: If-Match |
| Experiment | POST /experiments, GET /experiments/{id}, GET /experiments/current when present; list adds revision/revision_protected; entity ETag | PATCH /experiments/{id}; POST activate/finish/evaluate; DELETE /experiments/{id}; legacy PATCH toggle-pause: If-Match |

Header is strong quoted positive decimal, e.g. If-Match: "7". Supplied stale =>412; absent on protected row =>428; malformed/weak/wildcard/comma/duplicate =>422. Foreign ID =>404; missing/expired auth =>401. Business conflicts remain409. Never treat these errors as saved.

New/legacy rows start revision_protected=false for backward compatibility. First successful matching direct mutation permanently opts in: product PATCH; routine PATCH/active DELETE; experiment successful direct mutations. Old clients then receive428 for that resource. Opt in only when the account's Android/iOS flows support all subsequent affected mutations. Protection cannot be disabled. Unprotected legacy writes have no stale sequential-edit guarantee. Store server ETag/revision from entity read, send with intended edit and replace from successful response. Revisions can jump across multiple flushes; never calculate next revision from timestamps/engine_version.

On412 retain draft, reload and surface conflict; no blind overwrite with guessed version. On428 use revision-aware flow. ETag fences persisted configuration/lifecycle, not derived coverage/product_name/other evidence or conditional GET caching.

POST /experiments/{id}/activate also accepts Routine-If-Match: protected routine requires it (428 absent/412 stale/422 malformed or duplicate). Send both headers when both resources are protected. Product archival that would stop a protected active routine returns409: stop that entry with current revision first.

Routine DELETE is204+ETag and preserves history. Experiment DELETE is200+ExperimentOut, draft->cancelled or active->stopped; terminal conflict409, no physical erasure. Active definitions/notes and frozen evaluations stay immutable. POST /experiments/{id}/evaluate is201+EvaluationOut+Experiment-ETag for parent revision; GET experiment exposes same ETag/result ID. Stale repeat412; valid newer/unprotected repeat can create another evaluation. Revision readback is not attempt-specific receipt.

## Durable receipt subsets

| Operation | Optional header | Durable lookup | Replay/status |
|---|---|---|---|
| Report/manual check-in without photo | Idempotency-Key | GET /checkins/attempts/{key}; owned GET /checkins/{id} | same owner/key/payload original201; changed409; expired410; committed/unknown/expired |
| Adherence report | Idempotency-Key | GET /routine/adherence/attempts/{key}; original GET /routine/adherence?routine_entry_id={id}, paginate as usual | same owner/actor/key/payload original201/snapshot; changed409; expired410; committed/unknown/expired |

Key is16-128 ASCII letters/digits/_/-, random UUID text suitable. Persist key+normalized validated payload+account BEFORE send; retain on timeout/restart. Same-key replay checks original result before today's configuration checks. Unknown can include in-flight and never proves failed/not_committed: reconcile then retry only SAME key/payload. Never choose a new key after uncertain response. Expired requires original resource/history reconciliation. No-key keeps old behavior with receipt:null.

Receipt schema_version1: attempt_id, operation, owner_id=actor_id, resource_id, committed_at/expires_at UTC, status committed/expired. Adherence adds configuration_revision of ORIGINAL snapshot. Lookup unknown has result/resource/times null; committed has typed original result; expired has result:null but known resource/times. Replay30 days from immutable created_at; at/after expiry410. Metadata/tombstone remain for record lifetime; account erasure removes record/attempt and auth denies replay. Raw key/hash never returned/audited. No persisted reservation/rejection: in_flight/rejected/exactly-once are not asserted. Occupied adherence slot with ANOTHER key =>409 and lookup unknown; UNIQUE is not an attempt proof. Adherence does not edit configuration and does not require If-Match.

Products/routine configuration/experiment/clinical/grant operations still lack generalized attempt receipts. GET after lost response confirms current state, not which attempt caused it. Lost DELETE+404 is not attempt proof. Preserve uncertainty and reconcile; CAS does not solve every lost response. Clinical expected_sequence409 and adherence UNIQUE(entry,date,slot) retain separate existing contracts.

## H1/observation and rollout compatibility

QR grants VIEW by default; EXPORT requires separate patient consent and selected doctor. Replay/foreign/expired/revoked grants cannot broaden scopes. No export endpoint/linking activation/mobile change. Clinical permissions and locks remain.

Home observation_status schema_version1/day_basisUTC/today_completed/recent stays independent of confirmed measurements/baseline. Report completion does not invent scores. Capture idempotency and M1-M6/security gates remain.

Migration order:20261008_01 ->20261014_01 products ->20261014_02 routines ->20261014_03 experiments ->20261014_04 adherence attempts. Managed readiness requires head20261014_04. For any separately authorized rollout: reviewed backup/role/DDL/restore/journal gates, migration, backend, then compatible Android/iOS consumption. No live migration/cutover occurred. Downgrade refuses protected rows/durable receipts; SQLite multi-step DDL rollback is not fully transactional.

Evidence: isolated PG18.6/psycopg3.3.6 and SQLite3.49.1 migration/rehearsal/regression. No production/TLS/roles/collation/performance/DR certification. H3 not implemented.
