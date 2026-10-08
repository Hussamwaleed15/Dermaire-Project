# Dermaire authorized production rollout: fresh preflight halted

> Follow-up (8 October 2026, 15:04 UTC): the separately authorized [production-source isolated PITR verification](production-source-pitr-verification-20261008.md) now establishes a usable requested checkpoint 60 seconds before its fresh observation, under documented Azure service-evidence limits. This clears the recoverable-checkpoint evidence gap for that drill; it does not alter this historical halted rollout or certify production deletion-journal coverage/RTO. Production remained untouched. A later rollout needs fresh preflight/checkpoint evidence.

**Binary verdict: ROLLOUT HALTED/ROLLED BACK. Actual outcome: HALTED before production mutation; no rollback performed.**

8 October 2026, fresh observations 14:03–14:11 UTC (17:03–17:11 Africa/Cairo).

## Decision and precise gate

Production rollout authorization was accepted, including the reviewed maintenance, least-privilege, adoption, journal, deployment and opening sequence. The run did not seek repeated mutation approval. Phase 0 policy/design PASS remains valid. OneDrive unknown retention is not the reason for this halt.

The fresh operational preflight is **INCOMPLETE / HALTED** at recoverable-checkpoint verification. Successful Azure backup metadata and successful PostgreSQL WAL archival are positive evidence, but neither independently identifies a *usable production restore point* within the accepted five-minute RPO. No production-origin PITR verification or restored-target checkpoint evidence was obtained. The previous successful 493.573-second isolated recovery rehearsal is not fresh proof for this production source. Therefore no claim of a failed backup, exceeded RPO, corrupt WAL, or unexpected schema drift is made: the required recovery gate was not established.

The reviewed production preparation checklist requires a verified recoverable checkpoint before the authorized write pause/adoption. The user requires stopping at any failed gate and limits this phase to read-only production audit. An isolated production-source PITR exercise would create a restored copy and needs a reviewed privacy-safe verification procedure with explicit offline target registration, access/cleanup controls and journal coverage. It was not improvised inside the read-only phase. General Azure service documentation describes up-to-five-minute WAL archival delay; that is not independent verification of this particular usable checkpoint.

No production mutation was attempted. The existing Running app and pre-existing traffic state were preserved; traffic was not newly opened. This is **not** a claim that production was placed in maintenance/read-only mode or that its legacy running build satisfies the journal/privacy rollout requirements.

## Ordered activity and changes

| Time (UTC; Cairo +03:00) | Activity | Production change |
| --- | --- | --- |
| Before 14:03 | Verified clean local main at 73d38a6cdb90069a97229e6326c3e80bb9e783b9 and matching origin/main remote ref; read reviewed runbook, policy, baseline and least-privilege templates | None |
| 14:03:03–14:03:25 | Management/settings metadata, backup inventory, Blob data-plane inventory, health probes and SCM deployment metadata | None |
| 14:03:42 | Read deployed dotenv in memory; retained names, safe operational flags and whole-file hash only | None |
| 14:08:14 | Fresh Azure-origin read-only DB catalog and pg_stat_archiver inspection using existing app environment; no credential in commands or reports | None |
| During preflight | Stream-hashed current built production package/dependency manifest and existing compatible staging rollback archive; retained metadata, no artifact bytes locally | None |
| 14:11:09 | Monitoring metadata captured; halt recorded before Phase 1 | None |
| After halt | Wrote sanitized local evidence/documentation | Repository documentation only |

Times identify observations and recording windows, not every individual request start. SCM commands used system Python/libpq, obtained DATABASE_URL from existing environment, enabled default_transaction_read_only=on, connect timeout 15s and statement timeout 20s. A server-collation catalog query was corrected for PostgreSQL 18 and rerun successfully. No tables/rows were read for user data, and no DB writes, production files, cloud infrastructure or app configuration were changed.

## Fresh production findings

- App `dermaire-api` Running, HTTPS only; last modification 2026-10-05T16:41:23.916666. Python 3.12, startup `python -m uvicorn app.main:app --host 0.0.0.0 --port 8000`, Always On false, health check unset, native HTTP logging enabled, TLS minimum 1.2. Detailed logging/redaction/RBAC/suppression audit was not completed. These known legacy operational settings were not treated as unexpected drift.
- Both `/health/live` and `/health/ready` return 404 on the current legacy deployment. No restart was requested, no changed boot ID observed and no 180-second readiness timing measured.
- PostgreSQL 18.6, en_US.utf8, TLS 1.3 / TLS_AES_256_GCM_SHA384, catalog transactions read-only. Sixteen business tables, all owned by dermaireadmin; no Alembic metadata table. No public functions, noninternal triggers or row policies were observed.
- Fresh column type/nullability/default comparison and exact index-definition comparison against the 6 October production inventory: no differences. Active-owner uniqueness still appears as the existing unique btree index, before reviewed constraint attachment. CHECK/FK/unique definitions and grants were captured, but comprehensive schema-equivalence/Alembic validation was not completed.
- `public` schema owner azure_pg_admin; PUBLIC has USAGE, not CREATE. Application role dermaireadmin is NOSUPERUSER but has CREATEROLE, CREATEDB, BYPASSRLS, inheritance and privileged admin membership/SET ROLE routes. Separate migrator/runtime roles do not exist in the inspected role set. **Proof of runtime no longer using admin: FAIL / not achieved; current app still uses admin.**
- DB native retention seven days, geo backup disabled, earliest restore metadata 2026-10-02T07:14:08.190528+00:00; seven daily full backups through 2026-10-08T07:19:42.755562+00:00. At 14:08:14.608873 UTC pg_stat_archiver reported last success 14:04:11.51099 UTC, age 243.098s, archived_count 5305, failed_count 0. This is archival evidence, not restored-target usability proof or a guarantee at later times. No RTO or lost-write measurement for production.
- Photo account dermaireimg479341: HTTPS only, TLS1_2, public Blob access false, network default Allow. Container skin-images private and empty; zero live objects, versions, snapshots, deleted objects, object legal holds or object immutability found. Blob soft delete explicitly false; versioning/container soft-delete/restore policy return null, not explicit false. No policy changes or historical cleanup performed. Account/container retention/immutability policy verification remains incomplete.
- No DELETION_JOURNAL setting names are present in production app settings. Protected journal, separate key, independent backup/network/secret protection, durability/completeness and replay are not provisioned or verified. Policy remains expiry disabled indefinitely while unknown/held sources exist; no lifecycle expiration or key expiration was enabled. Runtime enforcement cannot be claimed on this legacy deployed build.

## Monitoring and providers

Production diagnostic settings are empty. Discovered alert resources are the existing staging Action Group and eight staging rules (three metrics, five logs), not newly installed production rules. Staging Action Group dermaire-readiness-owners is enabled, with Gmail hussamwaleed15@gmail.com and school receiver 2022170636@cis.asu.edu.eg, both common schema enabled. Receiver values were not changed. Production rule scopes, inherited access/suppression and delivery are not certified. No alert drill or temporary rule was created, and no mailbox re-proof was requested.

Exact production **app-setting flags**: CONTEXTUAL_AI_ENABLED=`true`; AZURE_VISION_ENABLED absent. OpenAI endpoint/key settings present. Vision endpoint/key settings absent. Content Safety endpoint/key settings absent; the target build has no separate enable flag and uses credential presence. In target commit defaults Vision is false; Content Safety is unconfigured from app settings. The deployed dotenv has development/True defaults overridden by production app settings; it contains provider setting names, so effective legacy-code provider operation is not fully certified from management flags alone. No external provider was invoked, enabled, disabled or reconfigured. No provider secret, endpoint credential, prompt or record was exported.

## Deployment and rollback metadata

Target source: 73d38a6cdb90069a97229e6326c3e80bb9e783b9. No new production build, deployment or deployment ID was created.

Current production OneDeploy ID: a1051873-4635-46aa-8fa8-7230b79a6097; status 4, active; received 2026-10-03T19:04:20.3004553Z, completed 19:06:47.1373198Z. Its original source commit was not independently established.

| Existing remote artifact | SHA256 | Bytes |
| --- | --- | --- |
| Production `/home/site/wwwroot/output.tar.zst` | 9a0e604b37507dfda5be119ae931a0f09f30fc3c28ef0cf3143b55e8ec7dff4b | 145453718 |
| Production `oryx-manifest.toml` | 01c9e625fde374ee55b657939517d2d45e31ed76487b0a5017c0791c6528d1b6 | 261 |
| Production `requirements.txt` | 59f55b35111034a84ae8d71b9fae53573b2eb32e652a5e96bf498d9bd3b256c7 | 479 |
| Staging `/home/dermaire-rollback-0f97dc2.zip` | 7ce9bbbd5a459fa73f2268f2e9cecd63af948d4ebf3639206402c6ea1b656ff8 | 144249200 |

Compatible rollback archive availability/hash matches prior evidence. Metadata includes remote paths, ETags, last-modified timestamps, settings names/slot flags and nonsecret operational settings. **This is a sanitized metadata archive with existing remote artifact references, not a new independently retained exact package/settings recovery copy.** Secret values were never saved or printed. Current pre-journal production package must not be used to reopen writes after journal adoption. No rollback was needed or attempted.

## Unexecuted steps, cleanup and checks

No role creation, ownership/grant repair, index normalization, baseline stamp, Alembic upgrade/check, negative-permission smoke, credential rotation, journal provisioning, Blob policy mutation, web/logging/monitoring settings change, deployment, write pause, traffic opening or post-opening smoke occurred. No disposable production accounts, blobs or temporary cloud resources were created; fixture cleanup is not applicable. No live user data was modified/exported.

Checks: clean HEAD and remote main equality; reviewed-policy/runbook/SQL inspection; read-only Azure/SCM management and package hashing; health GETs; full photo object/history inventory; read-only PostgreSQL roles/memberships/ownership/grants/columns/constraints/indexes/functions/triggers/policies/WAL statistics; column/index historical comparison; JSON evidence hashing and documentation whitespace/secret review. Backend tests were not rerun for this evidence-only halted attempt; historical 32/640-test results are not presented as fresh tests.

Evidence folder: `docs/evidence/production-preflight-20261008-1403/`. Documentation commit/push outcome is recorded in the companion final status. No claim of rollout completion, production privacy compliance, usable production checkpoint, measured recovery RTO, readiness timing or successful production smoke is made.

Reference: Microsoft [PostgreSQL backup and restore](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore) describes the general WAL archival/RPO behavior; it does not establish this run's usable checkpoint.
