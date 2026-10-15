> Foundation closure update2026-10-15: see FOUNDATION_MASTER_STATUS.md for the current ledger. Product CREATE now has bounded durable committed receipts (migration20261015_03); other domain attempt gaps remain OPEN. Patient-only GET /clinical-snapshot provides PostgreSQL transaction consistency; standalone endpoints remain non-atomic. H4 temporal/all-domain history and broad H2 receipts remain PARTIAL. The text below is the historical checkpoint and is superseded only for these delivered subsets. No H5 or managed rollout.

# H1-PG and H2 execution ledger

## Current completion status � 2026-10-15 (Cairo)

This table supersedes the historical H0/H1/H2 ledger below. Backend only; no deployment, Flutter/native/Tester/Azure/provider changes or live DB/HTTP. Original main d60dcb35eefd820262053a1844ff6b45fcd166de. Current contracts: H2_COMPLETION_AMR_API_HANDOFF.md; migration head20261014_04.

| Gate/resource | Status | Verified scope / remaining |
|---|---|---|
| PG-01 H1/H2 local security/migration | DONE | PG18.6/psycopg3.3.6, UTC/READ COMMITTED,31 final PG cases, observed locks/deadlock rollback/seeded migrations; no managed rollout certification |
| H1 QR scopes/grant security | DONE in local tested source | view/export consent, actor isolation, replay/revoke/expiry, clinical locks; no new export endpoint/linking |
| H2-F1 Home observation vs measurement | DONE in tested source | previous additive contract preserved |
| H2-F2 check-in attempts | PARTIAL | committed/unknown/expired replay+lookup now PG verified; persisted reservation/rejection registry absent |
| H2-F3 products | DONE opt-in revision subset | current If-Match/ETag/protection, duplicate422, PG CAS; durable attempt receipts absent |
| H2-F3b routine | DONE opt-in revision subset | all-writer CAS, history, headers, guarded product archive/experiment intervention, SQLite/PG seeded migration |
| H2-F3b experiment | DONE opt-in revision subset | draft/lifecycle/evaluation/legacy writers, immutable evidence, SQLite/PG CAS/migration |
| H2-F4b adherence receipts | DONE bounded committed subset; F4 overall PARTIAL | owner+actor+payload-bound attempt,30-day replay/history/erasure, typed lookup, SQLite/PG; no durable in-flight/rejected |
| Other operation receipts | OPEN | product create/edit/delete; routine configuration; experiment lifecycle/evaluate; clinical/grant attempt-specific registry/tombstones |
| H2-F5 current schema rehearsal | DONE isolated current-schema subset |16 business tables,8 synthetic rows, all original columns preserved on SQLite3.49.1/PG18.6; historical production index-adoption tool retired, no live adoption/DR claim |
| Safety currency/onboarding; histories/PSM completeness; notifications/messaging; typed scheduling; AI memory/tool execution | PARTIAL/OPEN/DEFERRED as historical inventory | unchanged; no H3 started |
| Production/Staging rollout/managed deployment/DR | OPEN separate authorization/verification | no live calls/migrations; no deployment-readiness claim |

Full verification gates: PG initial793 passed/112 warnings/120.40s; routine797/122/126.70s; experiment815/132/130.38s; adherence830/144/134.20s; final851/150/144.67s. All final runs zero failed/skipped. Final31 cases use real PG; remaining suite includes SQLite, pure and mocked tests. Dependency deprecations only; no configured linter; compileall, Alembic check/seeded migration and git diff --check passed. Details and failed preliminary fixture repairs are in milestone docs/report.

Independent normal-push commits verified with ls-remote: d9529f529f72b6ee4dfbe58963866dd1995c8076 PG initial;25415f73d24837e1424c68f6d9dea2f0434f7f78 routine;f2c875484f4fdf790c1b96709f51e9b51a03a4de experiment;f61ba1500246554af84d0b389f9e72150e0e6c9f adherence;df2ce500416b3c838eb25000aacb0f14999c98b7 product duplicate preconditions;8c38fb33dac8c2dedaae8b9a4ec88f2af4100646 PG completion. Final rehearsal/docs commit and remote/worktree verification are recorded in the Codex Arabic report after push. No concurrent teammate advancement was observed at fetches; no force push or history rewrite.

## Historical ledger (superseded where noted above)




Authorized repository: Hussamwaleed15/Dermaire-Project; baseline main bf5379be2dca9e130a0d342a9d5bf2a2ee31f8b3, clean after fetch. Backend only. No deployment, Azure, provider settings, live DB or production HTTP.



## H1-PG — BLOCKED



Rechecked Docker: client exists, desktop-linux engine pipe absent. No psql command or PostgreSQL Windows service found. Docker Desktop was found under AppData/Local/Programs/DockerDesktop and launched from the existing installation. Startup failed at initializing Ingest server: sailor-ingest.sock cannot be accessed by the system; daemon pipe remains absent. No socket deletion, system reset, privileged repair or installation attempted. SQLite is not PostgreSQL verification and H1 is not cleared for rollout.



Prerequisite: an available local Docker Linux engine or an existing disposable local PostgreSQL service. Do not use backend/docker-compose.yml: it includes a production API and persistent database volume. For disposable DB only, choose a fresh synthetic password in the process environment, then:



```powershell

docker run --rm --name dermaire-h1-pg -e POSTGRES_PASSWORD -e POSTGRES_USER=gate -e POSTGRES_DB=dermaire_gate -p 127.0.0.1:55432:5432 postgres:16-alpine

# In another terminal set DATABASE_URL to postgresql+psycopg://gate:<local-password>@127.0.0.1:55432/dermaire_gate

# Set ENVIRONMENT=test; disable/clear cloud credentials for the process.

python -m alembic upgrade head

python -m alembic check

```



These commands prepare an isolated DB only; existing pytest fixtures hardcode SQLite and must be replaced by an explicit loopback-only PostgreSQL fixture before a PG coverage claim. Required gate: real independent sessions, row-lock wait/timeout, explicit SHOW TimeZone and UTC day-boundary storage/readback verification, two claims one winner, replay, revoke/expiry versus claim, notes/reviews versus revoke/deletion, rollback, bounded lock order/deadlock outcomes, current actor and scoped consent evidence. Do not infer PG coverage from running today's SQLite suite with DATABASE_URL changed.



## F1 — observation Home contract



GET /api/v1/home adds observation_status {schema_version:1, day_basis:"UTC", today_completed:boolean, recent:[{id,created_at,time_of_day,kind,measurement_available}]}. Recent <=2, newest owned structured reports only. kind is report_only or report_and_measurement. Missing structured report is not observation completion; manual metric-only records still populate existing measurement fields. Empty recent is known absence at this successful read, not medical clearance. Failure remains failure. All times converted from stored UTC (naive DB values interpreted as UTC). Server UTC day, not phone/Cairo day.



Legacy today_checked_in and journal remain confirmed tracking measurements; GET /baseline still requires five distinct owned/unlinked confirmed measurement UTC days and creates no scores from reports. Manual values are user-entered tracking, image_proxy estimates are not clinical measurements. Fixed baseline distinct-day normalization to use normalized UTC timestamp.



No DDL, no Flutter modifications. Amr may consume the additive observation fields independently; he must retain separate baseline/measurement state and unknown/error handling. Validation and commit evidence recorded below after completion.



F1 validation: focused 15 passed / 1 dependency warning; full final isolated serial run 737 passed / 99 dependency deprecation warnings / 198.08s. Initial full run 736 passed, 1 registration DB failure while a focused process shared the same SQLite fixtures; discarded as a passing gate and rerun serially. compileall and diff --check pass. Alembic upgrade/check on workspace-only h2-f1-migration.db passes, head 20261008_01, no new operations. No configured lint tool found. Security review: owner filter retained, no sensitive report content included in Home summary, no synthetic measurements or role changes. F1 COMPLETE in tested source; H1 PostgreSQL release gate remains BLOCKED.


## F2 — bounded report/manual idempotency (SQLite verified subset; PG gate BLOCKED)

POST /api/v1/checkins without photo now honors optional Idempotency-Key (16-128 ASCII letters/digits/_/-; UUID string accepted). Existing no-key clients keep original semantics; they receive receipt:null and no new guarantee. Photo/capture implementation remains separate. Header is a random attempt token, never clinical data/credential.

Stable UUID5 identity binds operation/version, authenticated owner and key; existing checkins PK is the atomic unique constraint. Canonical SHA256 payload includes time_of_day, exact notes (empty distinct from null), experiment_id (empty normalized to null), validated report/default nullable fields, sorted deduplicated symptoms, all finite normalized manual scores. Same key/hash returns original ID/observation/time, original receipt and 201; changed hash 409. Request validation and owner-bound experiment checks remain mandatory. Simultaneous insert collision rolls back losing transaction then reads winner; all business changes/audit are in the same original transaction. Unknown DB/provider failure remains 503, not a durable rejection.

GET /api/v1/checkins/attempts/{key} authenticates current account. committed includes result CheckInResponse and receipt (schema_version, attempt_id, operation=checkin_report_manual, owner_id, actor_id, resource_id, committed_at, expires_at). POST and owned history also include nullable receipt. Raw key/hash are not returned or audited. Internal observation JSON stores only schema/hash; typed response strips it. No DDL/new table. User.checkins cascade and existing deletion/recovery journal erase record/metadata together.

Replay window 30 days from immutable server created_at UTC. Expired POST returns 410 and never recreates the same identity; GET returns expired, result:null, original resource_id/time. Key binding/hash/tombstone remains for the record lifetime, not automatically removed after 30 days; record/report retention follows existing account erasure. GET unknown (200/result:null) means no committed receipt currently visible; may include uncommitted request, rolled back request, never submitted key or erased record. It does NOT permit choosing a fresh key or guessing success. Retry only the same key and canonical payload within window. DB failure produces an unsuccessful read, not unknown success.

No persisted reservation/lease or rejected registry: in_flight and rejected are not asserted by this subset. An unknown can be in-flight. Auth expiry/deletion returns 401; foreign experiment 404 follows current owned endpoint semantics. These routes intentionally preserve existing roles; no new patient/doctor permission or fabricated 403 is introduced. No exactly-once claim for arbitrary unkeyed writes, live PG, image/provider effects or expired/erased records. F2 remains PARTIAL against the full requested cross-database/reservation gate; durable committed recovery and replay subset is implemented.

Amr: persist the random key with the normalized draft and account before first send; keep it on timeout/restart; use GET attempts then same-key POST if still unknown. committed result is authoritative; expired requires original-resource/history reconciliation. Do not mark success for unknown, 5xx or auth failure. Existing structured safety nulls remain unknown. Flutter is unchanged.

Focused final: 15 passed / 2 dependency warnings / 4.54s (12 new attempt cases plus 3 vision boundary cases). Initial collection had a Windows source-encoding issue in a non-ASCII negative fixture; fixed to an escaped literal. The client itself rejects non-ASCII header strings, so validator negative is tested directly. Full suite evidence follows after completion.

F2 final gate: full 749 passed / 100 dependency deprecation warnings / 202.36s; compileall and diff --check passed; fresh isolated SQLite Alembic upgrade/check passed at 20261008_01 with no new upgrade operations. No PG tests passed/skipped by this run: fixtures are SQLite; gate explicitly BLOCKED. Security review: owner-scoped identity/readback, payload hash internal only, unchanged photo cleanup path, audit/checkin commit atomic, account cascade erasure verified. F1 commit/push verified: 73746910c3dee8e00b75a9f902d50b88ecae0f0a.

## F3 — Products opt-in atomic revisions; Routine/Experiments PARTIAL

Products add revision:int and revision_protected:bool to POST/GET/PATCH/list responses; entity GET/POST/PATCH emit ETag as a strong quoted decimal. PATCH/DELETE accept If-Match. First successful PATCH with a matching header permanently sets revision_protected=true; that response explicitly tells the caller that subsequent direct product PATCH/DELETE requires a header. A stale header returns 412, missing on protected product 428, malformed/weak/wildcard header 422, foreign resource 404. No expected_version body field is available. Never send an unsupported field assuming protection.

Untouched/legacy products begin revision=1/revision_protected=false; old-client mutations retain behavior in this explicitly unprotected mode. Clients must not claim stale sequential protection there. A stale If-Match is rejected even before opt-in. Protection cannot be disabled through the API. All ORM product UPDATE/DELETE writers participate in SQLAlchemy version_id_col CAS; experiment product-flag transitions therefore advance revisions too. Existing owner locks/business guards remain. Account erasure is an authoritative owner-locked bulk removal and is not blocked by per-product preconditions.

PATCH audit now shares the business/revision transaction. DELETE reserves a version with flush before recording independent deletion journal intent, so a stale competing delete cannot journal an updated product. Delete audit shares the committed deletion transaction. Journal versus DB failure remains the existing independent-journal recovery boundary; no durable client attempt receipt is promised for product deletion.

New backend-only migration 20261014_01 (parent 20261008_01) adds non-null products.revision default 1 and revision_protected default false. Managed readiness code now requires that migration head; no managed environment/settings were changed or called. SQLite populated upgrade/check/downgrade/re-upgrade preserved the synthetic existing product. Downgrade refuses while any protected product exists, preventing silent removal of the promised protection. PG execution/DDL locking and migration adoption remain BLOCKED. Historical index-adoption PostgreSQL rehearsal assumes the pre-revision metadata/head and needs revision-aware modernization before it can certify this schema; its historical report is not reused as current evidence.

Product receipt/reconciliation limit: GET confirms current saved resource/version after lost PATCH response; it cannot establish which client attempt caused a matching value. Retrying a stale version returns 412 instead of duplicating/overwriting. Lost DELETE with GET404 is not proof of that attempt; a durable tombstone receipt is F4 follow-up. No blind stale retry or premature success. Existing routine immutable stopped history, adherence UNIQUE and experiment immutable active definitions/lifecycle remain tested, but no new routine/experiment expected revision is shipped. Those resources remain PARTIAL and need all-writer migrations plus precondition cutover as specified in H2_REVISION_AND_RECEIPT_CONTRACT.md.

F3 focused final: 74 passed / 20 dependency warnings / 12.48s, including 13 new product revision/migration cases and existing product/experiment/readiness suites. Real separate SQLite sessions/barrier: same-field, different-field and delete/update races each have exactly one winning mutation and one 412; stale delete never records a losing journal intent. Rollback restores revision/protected flag and audit together. Initial migration test omitted required legacy reset_token_attempts in a synthetic raw insert; corrected fixture, rerun green. Full final gate follows after completion.

Amr: consume revision and revision_protected; derive/store the quoted ETag from a successful entity read. Opt in only when the client supports all subsequent direct product edit/delete preconditions. On 412 reload and surface conflict; on 428 request a revision-aware edit flow. Handle 409 business conflicts separately. Routine/experiment schemas are unchanged. Flutter remains untouched.

F3 final gate: full 762 passed / 106 dependency deprecation warnings / 205.14s; compileall and diff --check passed; fresh SQLite upgrade/check at 20261014_01 passes, no drift. Populated upgrade/downgrade and protected downgrade rejection are focused acceptance tests. Security review retained authenticated owner checks and journal/audit boundaries; no arbitrary revision/protection update field exposed. PG coverage zero/current gate BLOCKED. F2 commit/push verified: 6587c71e57deb1fd1a33f522c63af86c29e86069.

## F4 — PARTIAL: typed check-in receipts and exact owned GET; cross-domain contract

GET /api/v1/checkins/attempts/{key} now publishes CheckInAttemptLookup in OpenAPI. It enforces coherent actor=owner, attempt/resource/result identity and committed receipt binding. Unknown always has resource_id/committed_at/expires_at/result:null. Committed includes the original owned result. Expired carries identity/times but result:null. Stored attempt metadata must have supported schema and canonical 64-character hash; corrupt/unsupported metadata cannot assert committed and returns unknown, while ordinary owned resource readback remains available without a claimed receipt.

New GET /api/v1/checkins/{checkin_id} returns CheckInResponse for authenticated owner only (foreign/missing/quarantined legacy row 404; absent/invalid/deleted identity 401). It returns existing saved report/metrics/image metadata with no new measurement or SAS token; photos retain the existing authenticated image route. Expired attempt can be reconciled by its original resource_id via this GET; it is not permission to re-create the observation. No patient selector, doctor grant proxy or export execution is introduced.

No new F4 table/DDL or generalized sensitive-mutation decorator. Implemented stable receipts are the F2 non-photo report/manual subset only; existing H1 revoke/consent evidence and capture/review/adherence contracts remain separate. Products/routines/experiments/adherence/clinical notes/reviews/bulk revoke/safety consent still lack generalized client-attempt lookup. Exact inventory and lease/rejection/retention/erasure/grant-safe design are in H2_REVISION_AND_RECEIPT_CONTRACT.md. Rejected and in_flight states require new durable storage/fencing and are not falsely inferred here. F4 is PARTIAL, not COMPLETE.

F4 focused: 36 passed / 2 dependency warnings / 6.81s (3 new typed readback/expiry/ownership/corrupt-proof cases plus attempt, vision and account-erasure regressions). No SQLite/PG substitution; all current runtime fixtures are SQLite. Full final gate follows. F3 commit/push verified: e249940a955be65daacf7f79ce9f758d5796e6d1.

Amr: unknown null fields are uncertainty, not a failed/committed check-in; GET-by-ID is current resource readback and cannot prove a different unrelated mutation attempt. Use committed receipt for the exact saved check-in. Resource readback remains owner-only even for clinicians with unrelated grants. Do not cache one account's receipt across account switches; erase the queued key/draft/result after account deletion. No Flutter files changed.

## Final requested scope matrix

| Milestone | Status | Delivered / remaining |
|---|---|---|
| H1-PG | BLOCKED | existing Docker installation failed startup on inaccessible ingest socket; no PG runtime/migration/row-lock gate passed |
| H2-F1 | COMPLETE (tested source) | additive typed report completion on UTC Home, independent confirmed baseline |
| H2-F2 | PARTIAL | durable owner/payload-bound committed replay and lookup, races/rollback/expiry/erasure on SQLite; PG and explicit durable reservations/rejection registry absent |
| H2-F3 | PARTIAL | opt-in protected Products revision CAS and isolated SQLite migration; Routine/Experiment resource revisions and PG migration gate remain |
| H2-F4 | PARTIAL | typed report/manual receipt and exact owned GET, complete endpoint gap inventory/design; other mutation families and reservation states deferred |

No production readiness verdict. No H3 started. Next wave stays H1/H2: restore local Docker engine or provide existing isolated local PG; build guarded PG fixtures rather than changing DATABASE_URL under SQLite fixtures; close H1 concurrency/migration gates; modernize historical index adoption rehearsal for revision schema; finish Routine/Experiment all-writer revisions with explicit client compatibility; add durable rejected/reservation/tombstone receipts per domain. Notifications, live provider changes, clinical messaging and H3 remain outside this execution.

F4 final gate: full 765 passed / 106 dependency deprecation warnings / 203.18s; no failed/skipped tests in final run. compileall and diff --check pass; fresh isolated SQLite migration upgrade/check at 20261014_01 passes with no drift. Security/privacy review: owner-only exact reads, nullable unknown semantics, internal payload hash stripped, typed actor/resource receipt checks and corrupt-proof fail-closed behavior, account erasure denial, existing capture/clinical/revoke regression suite retained. No PostgreSQL runtime gate passed. All changes since baseline are under backend/ only.
