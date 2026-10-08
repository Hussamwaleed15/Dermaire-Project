# Readiness fixes and remaining rollout gates

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
