# Dermaire production rollout — checkpoint policy and schema halt, 8 October 2026

**Binary verdict: ROLLOUT HALTED/ROLLED BACK. Actual outcome: HALTED before production DB/settings/traffic mutation; no rollback required or performed.**

User authorization covered the policy change and guarded production rollout. Starting local main was clean at `6c1a08460521469e4f7d25dd131144b8b355e8d5`; live origin/main matched. No extra user approval or command was required.

## Policy adopted

An ordinary additive rollout can rely on a successful usable/integrity-verified PITR drill for **24 hours from DB verification to production mutation**, for the same production resource, backup configuration and restore semantics. The one-day MVP window is deliberately conservative and avoids unnecessarily creating production-derived restored copies for each deployment. Fresh server/backup/WAL/activity/catalog/configuration audit is mandatory: last archive <=300 seconds old, zero failed archives and unchanged stats reset, completed automatic full backup within 24h, no material identity/version/region/retention/encryption/network/recovery drift or intervening configuration operations. Recheck immediately before mutation and after prolonged interruption. Missing/stale/failed evidence or a materially destructive/high-risk migration requires a new full isolated usable PITR drill before mutation. The release and both readiness documents contain the complete policy.

Metadata preflight is distinct from full disaster-recovery certification. It supplies current health evidence alongside historical usability evidence; it does not certify a fresh latest-usable watermark, exact lost-write/replay-stop interval, continuous RPO <=5m, or production end-to-end RTO <=30m. **RTO <=30m remains NOT CERTIFIED.** Phase 0 legacy-copy exclusions, privacy-compatible rollback and indefinite journal/HMAC-key expiry disablement remain unchanged.

## Fresh preflight and PITR comparison

Read-only audit began `2026-10-08T15:48:54.667474+00:00` (18:48:54 Cairo). Eligible commit `4948a91` drill requested `14:50:08.626887 UTC` (17:50:08 Cairo), successfully verified at `15:03:38.626468 UTC` (18:03:38 Cairo), and expires **9 October 2026 at 18:03:38 Cairo**. Fresh management audit at `2026-10-08T15:50:12.661132+00:00` found drill age **0.776 hours**. Requested lag 60s was service-backed, not an independently measured lost-write interval.

Source resource is `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/dermaire-db-server`, database `dermaire`. Canada Central, PostgreSQL 18.6, Standard_B1ms, 32 GiB, system identifier `7687509194730582065` match the successful drill. Seven-day native retention, geo backup Disabled, earliest restore `2026-10-02T07:14:08.1905287+00:00`, seven completed automatic full backups, latest `2026-10-08T07:19:42.755562+00:00`.

WAL observed `15:49:15.363899 UTC`: archived_count **5328**, increased from **5315**; failed_count **0**, no last-failure timestamp, unchanged stats-reset `2026-09-20T07:02:00.858492+00:00`; last archive `15:48:54.260771 UTC`, age **21.103128 seconds**. TLS 1.3 observed in catalog audit; separate exact-model comparison used verify-full CA/hostname validation. Backup/WAL validity: **PASS**.

Identity, backup/storage/network/auth/HA/zone/FQDN, secure-transport setting, app-settings fingerprint, columns/indexes/constraints/object owners/ACL/functions/triggers/policies and roles/memberships match the successful drill. Firewall rule IDs/names and nonredacted properties match; the prior client-IP address is deliberately withheld, so direct historical address-value equality is unavailable. Current before/after full fingerprints agree. The resource-group activity log since the drill returned four entries, no source-server or child operations, without reaching the 1000-entry cap. Current encryption is SystemManaged; the original sanitized drill omitted dataEncryption, so unchanged encryption is supported indirectly by that intervening operation audit, not a retained encryption-value baseline. No material configuration drift or backup-failure indicator was detected.

**Full PITR correctly SKIPPED** for this ordinary rollout under the new validity policy. No new restore server/verifier, firewall or production-data copy was created. The subsequent schema-equivalence failure is not a backup failure and cannot be repaired by repeating PITR.

## Concrete halt: existing production differs from reviewed frozen baseline

Exact current repository ORM metadata compared against production via Alembic `compare_metadata(compare_type=True)` reports:

| Difference | Production | Reviewed ORM/frozen baseline |
| --- | --- | --- |
| `ix_experiments_routine_entry_id` | Existing btree index on routine_entry_id | Not declared |
| `uq_experiments_active_owner` | Valid unique standalone index | Unique constraint; attachment already reviewed |
| `ix_users_reset_token_hash` | Missing | Required nonunique index |

These are **pre-existing differences**, preserved in today's earlier catalog evidence, not newly introduced drift. Earlier exact source/restore equivalence proved the restored copy matched production; it did not prove production matched the intended Alembic baseline. The fresh complete ORM comparison makes this distinction concrete. The reviewed uniqueness attachment alone cannot yield empty Alembic drift. No stamp/CREATE/DDL/DML was attempted. The adoption SQL now carries an explicit STOP note so this mismatch cannot be hidden by a baseline stamp.

Required next repair: review and rehearse an additive adoption plan that preserves the useful routine-entry index (including its ORM/frozen-baseline representation) and safely adds the reset-token index, then proves full equivalence after reviewed uniqueness attachment. Do not execute autogenerated remove_index suggestions or rerun empty-baseline CREATE statements. No repair is claimed executed or reviewed by this report.

## Ordered actions and production state

Production mutations in order: **none**. No maintenance/stop, DB role creation, password rotation, ownership/PUBLIC remediation, uniqueness attachment, revision stamp, app-setting update, journal provisioning, Blob-policy change, monitoring installation, deployment, restart or traffic opening was issued. Existing app remains Running; no maintenance/read-only status is implied.

Preparatory SCM scratch actions only: a large migration-environment command did not yield a usable result; dependency probing showed the legacy SCM Python did not provide psycopg. A direct device verify-full read-only connection timed out. An isolated `/tmp/dermaire-release-libs-20261008` runner then received hash-verified pinned psycopg 3.2.13 wheels for system Python 3.11, using existing SQLAlchemy 2.0.54/Alembic 1.20.0. Exact repository model source was compressed/transmitted in memory and loaded with the same declarative Base; this bypassed unrelated app startup configuration, without changing model declarations or live application imports. All DB sessions were read-only and bounded. Only catalog/model differences and origin metadata were emitted; no raw rows/IDs/image paths/credentials. The scratch directory was removed and absence verified; `/tmp/dermaire-reviewed-rollout-20261008` was never created. Application files remained unchanged.

DB runtime remains **dermaireadmin** with CREATEROLE/CREATEDB/BYPASSRLS and privileged memberships. Restricted runtime/migrator roles absent; sixteen business tables still admin-owned. PUBLIC schema has USAGE, not CREATE; no public functions, noninternal triggers or policies; no default privilege rows; plpgsql is the only audited extension. No-admin runtime proof, negative-permission/DML smoke, ownership transfer, normalization, baseline stamp or post-adoption Alembic check: **NOT REACHED**. A real read-only Alembic metadata comparison failed as above; this is not a successful Alembic check.

Production deletion journal/HMAC settings absent. Durability/completeness/signed replay and independent protection: NOT REACHED. Journal/key expiry policy remains DISABLED INDEFINITELY; no expiry enabled and no historical deletion coverage fabricated.

Photo container `skin-images` remains private and empty: zero live objects/versions/snapshots/deleted objects/object holds/immutability. Blob soft-delete false; versioning/container-soft-delete/restore-policy values null, not explicit disabled certification. Account/container ARM policy captured read-only; no storage policy adoption or retained-history purge. Privacy gate not declared passed for traffic.

App: HTTPS only, minimum TLS 1.2, Python 3.12; Always On false, Health Check unset, HTTP logging true, legacy uvicorn startup. `/health/live` and `/health/ready` return 404; no restart/readiness timing or production smoke. Active deployment unchanged: `a1051873-4635-46aa-8fa8-7230b79a6097` (status 4). Production diagnostics empty; discovered Action Group/eight alert rules are staging-only; no production alert drill/recipient message sent. No disposable production fixtures were created.

Final provider state unchanged: `CONTEXTUAL_AI_ENABLED=true`; OpenAI endpoint/key configured in App Settings. `AZURE_VISION_ENABLED` absent; Vision endpoint/key absent. Content Safety endpoint/key absent, target-code activation credential-driven. No provider enabled/reconfigured/invoked. Deployed dotenv credential pairs were not freshly re-audited; previous documented observations remain historical.

## Rollback, testing and delivery

Rollback needed/performed: **no/no**. Current server/firewall/app-settings/secure-transport before/after fingerprints agree: `{'server': True, 'firewall': True, 'settingsHash': True, 'secureTransport': True}`. No secret settings snapshot was retained because mutation was never reached; sanitized name/slot/provider/fingerprint references are archived. Existing remote rollback/package bytes were hashed without local retention: production output `9a0e604b37507dfda5be119ae931a0f09f30fc3c28ef0cf3143b55e8ec7dff4b`, manifest `01c9e625fde374ee55b657939517d2d45e31ed76487b0a5017c0791c6528d1b6`, requirements `59f55b35111034a84ae8d71b9fae53573b2eb32e652a5e96bf498d9bd3b256c7`, privacy-compatible staging rollback `7ce9bbbd5a459fa73f2268f2e9cecd63af948d4ebf3639206402c6ea1b656ff8`; all match previous hashes. Legacy pre-journal build cannot reopen unrestricted writes after journal adoption.

Relevant tests: **62 passed, one deprecation warning**, production_config/operational_targets/deletion_journal/operational_readiness. Global Python first lacked cv2; rerun using the existing test environment passed. Documentation-only policy/adoption warnings; no product code or migration revision changed. SHA256 evidence manifest, diff whitespace check and commit/push verification performed. Evidence directory: `docs/evidence/production-rollout-policy-20261008-1548/`.

Documentation/evidence commit and push to the same main branch are recorded in the delivery message. No secrets, keys, tokens or raw production rows are committed.
