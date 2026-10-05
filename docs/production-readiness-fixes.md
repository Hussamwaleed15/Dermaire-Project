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

Health currently probes Blob metadata only. It is not a database readiness check
or a live AI-provider test. Configure privacy-safe metrics, alerts with an owner,
and a synthetic check without real patient text. Do not log authorization headers,
credentials, request bodies or raw provider exception messages.

Account deletion fails closed for retained/historical Blob copies. Decide and
verify infrastructure policy, private access, historical-copy remediation and
backup retention/deletion semantics before promising permanent deletion.
