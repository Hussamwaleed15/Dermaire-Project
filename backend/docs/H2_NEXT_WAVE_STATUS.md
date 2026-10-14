# H1-PG and H2 execution ledger



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



These commands prepare an isolated DB only; existing pytest fixtures hardcode SQLite and must be replaced by an explicit loopback-only PostgreSQL fixture before a PG coverage claim. Required gate: real independent sessions, row-lock wait/timeout, two claims one winner, replay, revoke/expiry versus claim, notes/reviews versus revoke/deletion, rollback, bounded lock order/deadlock outcomes, current actor and scoped consent evidence. Do not infer PG coverage from running today's SQLite suite with DATABASE_URL changed.



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
