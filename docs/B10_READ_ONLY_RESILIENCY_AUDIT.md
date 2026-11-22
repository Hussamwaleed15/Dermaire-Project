# B10 read-only resiliency and recovery audit

Date: 2026-11-13 (Africa/Cairo). Scope: metadata and existing evidence only.
No backup, restore, database connection, deployment, migration, network change,
resource creation, or cost-bearing action was performed.

## Current observations

- Azure identity: `2022170636@cis.asu.edu.eg`, subscription `Azure for
  Students`, enabled.
- Production database `dermaire-db-server` and retained nonproduction database
  `dermaire-rehearsal-20261006` both report PostgreSQL 18, Ready,
  `Standard_B1ms`, 32-GiB-class rehearsal design, seven-day backup retention,
  geo-redundant backup disabled, and public network access enabled.
- Production and staging App Services are Running and HTTPS-only. Their public
  `/health/build` endpoints return 404, so deployed commit provenance and live
  required revision are not available through the application contract.
- Existing October evidence records a real isolated PostgreSQL PITR rehearsal,
  deletion-journal replay, synthetic fixtures only, and cleanup of temporary
  restore targets. It also records that privacy-recovery coverage was not
  certified for production and that unknown/legacy recoverable copies keep
  deletion-journal/key expiry disabled indefinitely.

These observations are not a new restore proof. Backup metadata says a restore
window exists; only a completed isolated restore plus verification proves
recoverability.

## Live Alembic revision channel assessment

The safe public channel is absent: `/health/build` is 404 and readiness
intentionally does not reveal the observed database revision. Azure Resource
Manager exposes database service metadata but not the application Alembic row.
Reading App Service settings or publishing profiles would expose credentials and
is prohibited for this audit.

A technically viable next channel is an authenticated App Service console/SSH
session that runs a bounded command inside the deployed process context and
prints only the single Alembic revision token (and optionally `alembic check`),
without printing environment variables, connection strings, SQL, hostnames, or
application rows. That command still causes the live application identity to
open a database connection. It was not executed because database access against
production/staging requires separate confirmation. Until then, the live revision
remains **unproven**.

## Disposable rehearsal plan (not executed)

1. Obtain explicit approval for cost, region, source server, restore timestamp,
   network boundary, and cleanup owner.
2. Restore into a uniquely named server in the existing nonproduction resource
   group, never over production or staging. Keep application traffic and writes
   disabled.
3. Permit only a short-lived audit client. Use TLS verification and a dedicated
   least-privilege audit/migrator identity; never export settings or rows.
4. Record only service metadata, restored Alembic revision, `alembic check`,
   schema-only drift, migration duration/locks, invariant counts, and redacted
   readiness results. Use synthetic fixtures for any mutation test.
5. Replay the independent signed deletion journal before considering any
   recovered data usable. Fail closed if journal completeness or key validity is
   uncertain.
6. Exercise the reviewed package and PostgreSQL 18 concurrency suite against the
   isolated target. Verify `/health/build`, required revision `20261024_14`, and
   the 116/119 OpenAPI contract.
7. Capture resource IDs, timestamps, evidence hashes, costs, and deletion proof;
   then delete the temporary audit client and restore target under the approved
   cleanup step. Do not leave derived recovery copies unregistered.

## Cost boundary for Azure for Students

The retained B1ms nonproduction server is already cost-bearing. The last checked
public Canada Central compute snapshot in project evidence was USD 0.0185/hour,
about USD 13.51 for 730 hours, before provisioned storage, backup overage,
transactions, logs, alerts, and temporary audit compute. A PITR rehearsal adds a
second database for its lifetime, so even a short run is not assumed free and
student credit availability is not inferred. Pricing and remaining credit must
be rechecked immediately before approval. No new spend was started here.

## B10 status

Read-only inventory: started and documented. Existing rehearsal evidence:
located but historical. Current live Alembic revision: blocked pending separate
authorization for the bounded database-read channel. New restore evidence:
blocked pending explicit cost-bearing/resource-change approval. Production
resiliency and privacy recovery remain **not certified**.
