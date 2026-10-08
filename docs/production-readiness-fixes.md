# Readiness fixes and remaining rollout gates

**Latest authorized rollout: HALTED before production mutation.** [Fresh 8 October preflight and policy report](production-rollout-policy-halted-20261008-1548.md): 24-hour PITR validity adopted, full PITR skipped, backup/WAL healthy, but ORM/frozen-baseline index mismatch blocks Phase 1. Runtime remains admin; no stamp, journal, deployment or traffic changes.

## Checkpoint-validity policy — authorized 8 October 2026

For an ordinary additive rollout, reuse a successful production-source PITR drill for at most **24 hours**, measured from its timestamped DB integrity verification to the start of production mutation. This conservative one-day MVP window bounds reliance on historical recovery evidence without creating a new production-data copy for every deployment. It is a policy decision, not an Azure guarantee. Recheck the gate immediately before mutation and after a prolonged interruption.

ALL conditions are mandatory: the drill proved an accessible, consistent restored database from the exact same production resource ID; backup configuration and restore semantics are unchanged; there has been no material change to region, server identity/version, retention, encryption, network configuration or recovery path; a fresh read-only server/backup/activity/catalog audit and `pg_stat_archiver` observation show healthy completed backups and advancing WAL archives with no failed backup/archive indicators. Require last successful archive age <=300 seconds, zero archive failures, no counter reset obscuring failures, and a completed automatic full backup within 24 hours. Compare source identity/catalog and archived configuration evidence; missing comparison evidence fails the gate. Check for intervening configuration operations, including changes later reverted. Normal advance of the earliest restore boundary and successful archive counters is expected, not configuration drift.

If any condition fails, evidence is stale/incomplete, or a materially destructive/high-risk data migration is proposed, STOP before mutation and require a new full isolated production-source PITR drill with usable DB/integrity verification. An isolated target credential/orchestration failure alone does not invalidate an earlier successful drill, but a backup corruption/failure indicator does. Never stamp over schema drift.

This **backup-metadata preflight** authorizes reliance on recent historical usability evidence for an ordinary rollout; it does not independently prove a fresh latest usable watermark, exact replay-stop/lost-write interval, continuous RPO compliance, or full disaster-recovery certification. DB RPO <=5 minutes remains an objective; **end-to-end production RTO <=30 minutes remains NOT CERTIFIED**. A real recovery still requires offline restore, complete signed deletion replay, retained-photo inventory, grants/TLS/revision/readiness/smoke before traffic.

Phase 0 legacy-copy exclusions, rollback/privacy gates and indefinite deletion-journal/HMAC-key expiry disablement remain unchanged. No pre-journal rollback build may reopen unrestricted writes after journal adoption. Initial journal absence is recorded, never represented as a valid completeness watermark. Maintenance write pause and all later privacy gates still apply. This policy supersedes older wording requiring a new full drill before every ordinary rollout; earlier reports remain historical evidence.

Today's eligible drill is recorded in commit `4948a91`: requested checkpoint `2026-10-08T14:50:08.626887+00:00`, successful verification `2026-10-08T15:03:38.626468+00:00`; expiry `2026-10-09T15:03:38.626468+00:00` (18:03:38 Cairo). The 60-second delta is service-backed requested lag, not independently measured lost writes.


These fixes do not authorize a production deployment.

Unhandled error responses omit exception text in every environment. Driver and
provider exceptions may contain credentials or patient data. The generic response
also no longer claims that an engineering notification was sent; no notification
pipeline is wired in this code.

The Docker command now uses valid JSON exec syntax. Compose requires an explicit
database password and DATABASE_URL instead of shipping a known password. Use
`postgresql+psycopg://` for the installed psycopg 3 driver; URL-encode credential
components. Both supplied credentials must refer to the same database. These are
local deployment templates, not evidence of live production configuration.

Before rollout, rehearse migrations and rollback against a separate instance of
the actual production database engine/version. `create_all` at startup does not
upgrade existing tables. Verify TLS, connection recovery, constraints, concurrency,
backups, a restore drill and explicit RPO/RTO. Do not point staging at production.

On B1, use a documented redeploy/maintenance rollback or separately provisioned
blue/green apps; slot swap requires Standard or higher. Prove cold start, restart,
bounded readiness and provider-enabled request latency on the selected plan.

`/health/ready` now probes database/revision, private photo storage and the independent required deletion journal; `/health/live` reports process life and boot ID. Readiness is not a live AI-provider test. Configure privacy-safe metrics, alerts with an owner,
and a synthetic check without real patient text. Do not log authorization headers,
credentials, request bodies or raw provider exception messages.

Account deletion fails closed for retained/historical Blob copies. Decide and
verify infrastructure policy, private access, historical-copy remediation and
backup retention/deletion semantics before promising permanent deletion.

## Accepted readiness continuation (8 October 2026)

See [production-release-runbook.md](production-release-runbook.md) for accepted startup 180s, DB RPO <=5min, recovery RTO <=30min and journal 42d conditional on all recoverable backups/exports <=35d and quarantine <=7d, plus the review-only least-privilege/TLS/adoption/photo/protected-journal checklist. No production change is authorized. Current alert diagnosis and test evidence: [readiness-closure-20261008.md](readiness-closure-20261008.md).

Current binary MVP infrastructure verdict: **READY FOR PRODUCTION ROLLOUT** after human-confirmed Gmail Fired/Resolved receipt and verified staging drill cleanup. See the closure report for gate decisions, evidence and mandatory separately authorized production preflight. Production rollout itself is not authorized.
