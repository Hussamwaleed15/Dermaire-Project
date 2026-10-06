# Production release gate and rollback runbook

Status on 6 October 2026: **NOT READY**. This runbook authorizes no production changes. Staging must never use the production database or photo container for write rehearsals.

## Database adoption

Production configuration names PostgreSQL database `dermaire` on Azure Flexible Server PostgreSQL 18, using TLS `sslmode=require`. Bare PostgreSQL URLs now select the installed psycopg 3 driver. Seven-day Azure backup retention is configured; restore delivery and operational RPO/RTO remain unverified. Runtime role grants, schema and constraints have not been verified because the read-only connection from the audit host timed out.

Managed startup no longer runs `create_all`. A reviewed migration job, with separate DDL credentials, must prepare the database before starting the application. Runtime credentials should have only necessary DML/sequence permissions and no schema creation or role-management privilege. Keep TLS required; validate CA/hostname and move to `verify-full` after validating the trust chain in staging.

The frozen Alembic revision `20261006_01` represents the current ORM, including indexes, CHECKs, foreign keys and unique constraints. It is an initial baseline for **empty** databases. It is not an upgrade of an unknown existing schema. Its downgrade deliberately refuses destructive drops. Manual scripts in `docs/migrations/`, `docs/doctor-loop-v2-migration.sql` and `data/sql.sql` are historical evidence, not a safe automatic execution sequence.

For a new isolated database of PostgreSQL 18 with representative collation, extensions, permissions and TLS:

1. Set an explicit isolated `DATABASE_URL` in the migration process; keep credentials out of command arguments and logs. From `backend`, run `python -m alembic upgrade head`, then `python -m alembic check` and `python -m app.tools.schema_audit`.
2. Test populated records, consent/clinician update races, user-row locks, cross-account rejection, account deletion/retry, constraints, connection recovery and representative concurrency. The local rehearsal covers basic row locking, CHECK/FK rejection and account deletion with Blob mocked; consent/review races and realistic concurrency remain gates.
3. For an existing database, capture a read-only schema audit and schema-only dump. Compare columns/types/nullability/defaults, indexes, unique and foreign-key constraints, CHECK expressions, enums, triggers, extensions, row policies and grants against the frozen baseline. Alembic does not guarantee complete detection of CHECKs or server-specific objects. Review all manual migration preconditions and checksums.
4. If differences exist, write a reviewed additive revision for that exact schema and rehearse it on a sanitized representative copy. Do not rerun CREATE scripts blindly, drop data, or stamp to conceal differences.
5. Only after exact schema adoption is approved and a recoverable backup verified, run `python -m alembic stamp 20261006_01` against the existing database. Stamping writes migration bookkeeping; it does not repair the schema. Apply reviewed later revisions in a maintenance window using a single migration runner.
6. Readiness requires exactly the expected revision. Update the expected revision in code when adding migrations. `/health/live` verifies process life; `/health/ready` probes the DB, revision and private storage and returns 503 on failure. Provider degradation does not make the API unready because deterministic fallback remains supported.

## Release sequence

Before scheduling production, close every gate below and name a release owner, database restore owner and alert recipient. Archive the currently deployed production artifact and checksum, current settings in a secure vault, storage policy JSON, current schema inventory/revision and migration SQL/checksums. A source commit alone does not reconstruct installed packages: retain the built package and its dependency manifest. Pin dependencies for reproducible release packaging.

1. Create isolated staging PostgreSQL and photo storage, with production-like engine, collation, TLS and permissions. Rehearse populated-data migration and backup restore. Production-like Azure PITR must restore to a separate server with a measured RTO; do not overwrite the live server during a drill.
2. Deploy the tested artifact to staging, adopt/migrate its database explicitly, and configure Always On, startup `python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-access-log`, and Health Check `/health/ready`. Disable query-bearing access logs and SQL parameter logging. Inspect ASGI/server exception logging for PII before release. Bound DB connect/statement waits and Blob health retries.
3. Verify new boot IDs across repeated staging restarts, genuine idle cold starts where applicable, readiness/liveness failure behavior, bounded representative traffic, provider success/fallback and account cleanup. Current B1 has one worker and no deployment slots; Health Check does not provide spare capacity. Use a maintenance rollout with redeployment rollback or separately approved blue/green infrastructure.
4. Enable Azure-native telemetry/alerts and perform delivery drills on staging before production configuration. Apply no production changes until a separate rollout instruction.
5. During the authorized release: pause writes; record a consistent backup/checkpoint and deletion journal watermark; run the single migration job; deploy the exact artifact; apply reviewed settings; verify revision/readiness, privacy policy and provider flags; run synthetic smoke; resume writes gradually after all gates pass.

## Rollback mechanics and triggers

Abort before opening traffic if readiness fails, migration/audit disagrees, credentials/TLS fail, owned retained Blob copies exist, alert delivery is absent, or a privacy check fails. Suggested starting thresholds requiring owner acceptance: any persistent startup/readiness failure beyond 120 seconds; 5xx >1% with at least 20 requests over 5 minutes or >=5 errors; p95 interactive latency >10 seconds for 10 minutes; >=3 DB/Blob failures in 5 minutes; provider degradation >10% of invoked calls for 10 minutes. Any clinical-precedence or privacy regression triggers immediate traffic closure regardless of rates.

- **Code:** stop writes/close traffic, redeploy the archived previously verified package on B1, restore its securely archived startup/provider settings, and verify health and synthetic smoke. Do not assume checkout of `d2fee65` equals the deployed production package. If the previous code cannot read the migrated schema, keep traffic closed and execute the DB restore plan.
- **Database:** prefer code rollback while retaining additive schema. Never invoke a destructive baseline downgrade. For incompatible change, restore the verified backup/PITR to a separate target; validate schema, grants, TLS and revision; replay the deletion journal and any agreed recovery writes; change only the authorized production DB connection; run smoke before reopening. Record and explicitly accept writes lost after the restore point. No production RPO/RTO is certified by the local synthetic restore.
- **Providers:** restore the exact archived feature flags/endpoints/deployment/API version/secret references. Verify disabled/degraded behavior and clinician/Safety Engine precedence. Never log keys or raw prompts. Do not silently enable generation based on credential presence.
- **Storage:** code rollback must preserve fail-closed deletion behavior. Do not restore versioning/soft-delete settings that contradict the privacy promise. Inventory historical copies, snapshots, deleted blobs, legal holds and immutability before declaring deletion complete. Use approved targeted cleanup or wait for unavoidable retention; return failure until completion. Infrastructure changes require a separate authorized rollout and isolated rehearsal.

Restoring backups can resurrect deleted personal data. Maintain an access-controlled, privacy-reviewed deletion tombstone journal separate from restored application data, define its minimal identifiers and retention, and replay it before traffic. This journal and the operational ownership policy are not implemented yet. Do not weaken the application's current failure-on-unconfirmed-deletion guarantee or promise instant erasure of retained backups/audit pseudonyms.

## Monitoring gates

The audit found no Application Insights, Log Analytics workspace, action group or alert resources in `dermaire-rg`. Production HTTP logs retain three days; application logging is off. Resource-group inventory does not prove absence of subscription-wide alerts, so inspect inherited/out-of-group alert scopes too.

Use Azure Monitor App Service platform metrics for Http5xx/requests, response time, CPU/memory and health; an availability probe for `/health/ready`; Application Insights or diagnostic collection of structured operational JSON; and an owned Action Group. Code emits route-template request status/duration/request ID, startup completion, readiness DB/Blob states, and invoked provider state events without bodies, query strings, user IDs or exception text. These hooks are not an installed monitoring service.

Must-have alerts:

| Signal | Initial rule to validate | Required drill |
| --- | --- | --- |
| 5xx | >=5 errors or >1% with traffic floor over 5 minutes | Synthetic staging failure and confirmed notification |
| Startup/availability | Missing readiness for 2 minutes; new boot without startup completion | Staging restart and controlled startup failure |
| DB | 3 unavailable DB readiness events/5 minutes; connection saturation | Isolated DB interruption and recovery |
| Blob | 3 degraded Blob readiness events/5 minutes; cleanup/upload failures | Isolated storage denial/deletion partial failure |
| Providers | >10% degraded invoked OpenAI/Safety/Vision calls/10 minutes; configured provider unexpectedly disabled | Invalid staging credential/provider failure, then restore |
| Latency/capacity | p95 >10 seconds/10 minutes; sustained memory/CPU pressure | Representative bounded load |

Assign acknowledgement/response times and a real recipient, confirm each alert's delivery, restrict telemetry access, document retention/redaction and suppress request bodies/query strings/SQL parameters/raw exceptions. Provider, readiness and Blob upload/read/delete hooks cover recorded invocation/probe failures; connect them to alert rules and validate startup-failure platform rules before release.

Sources: [Alembic autogenerate limitations](https://alembic.sqlalchemy.org/en/latest/autogenerate.html), [Azure Health Check](https://learn.microsoft.com/en-us/azure/app-service/monitor-instances-health-check), [deployment slots](https://learn.microsoft.com/en-us/azure/app-service/deploy-staging-slots), [Blob versioning](https://learn.microsoft.com/en-us/azure/storage/blobs/versioning-overview), [soft delete behavior](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-overview).

## Continuation evidence (6 October 2026)

Read [azure-readiness-rehearsal-20261006.md](azure-readiness-rehearsal-20261006.md), [production-baseline-adoption.sql](production-baseline-adoption.sql), [least-privilege-postgresql.sql](least-privilege-postgresql.sql) and [deletion-journal-restore.md](deletion-journal-restore.md) before release. Uniqueness exists as a valid standalone index; normalize its representation only after separate production authorization. Do not use the old 231b339 build for unrestricted rollback after enabling the journal. The built privacy-compatible archive and its hash are documented in the continuation evidence. The 120-second startup budget failed repeated checks; no revised budget or production rollout is approved.
