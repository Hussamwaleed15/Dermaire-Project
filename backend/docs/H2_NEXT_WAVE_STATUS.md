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
