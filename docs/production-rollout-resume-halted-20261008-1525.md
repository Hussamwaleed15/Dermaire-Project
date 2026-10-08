# Dermaire production rollout resume — 8 October 2026

**Binary verdict: ROLLOUT HALTED/ROLLED BACK. Actual outcome: HALTED during fresh checkpoint verification, before any production mutation. No rollback was needed or performed.**

The authorized rollout started from clean local `main` at `4948a91a5b9218745cc3cf22596dd05d594192cb`; the live GitHub `origin/main` ref matched exactly. Authorization was accepted without another approval request. Phase 0 policy remains PASS. The earlier successful production-source PITR observation remains RPO PASS within its documented evidence limits; this attempt does not invalidate it.

## Halt and fresh checkpoint result

Fresh native backup/WAL metadata does not expose a latest usable production restore watermark. The earlier verified checkpoint was `2026-10-08T14:50:08.626887+00:00`; it was not treated as a fresh checkpoint for this later rollout. Under the user's authorization to perform a drill when fresh evidence is inadequate, one isolated target was registered and created. No additional attempt was made after failure.

Source: `dermaire-rg/dermaire-db-server`, database `dermaire`, subscription `384c0376-d023-4a61-9dce-69ff8cbdcd0c`.

Target: `dermaire-readiness-nonprod-20261006/dermaire-prod-pitr-verify-20261008-1529`. Observation `15:28:37.585471 UTC` / `18:28:37.585471 Cairo`; requested custom checkpoint `15:27:37.585471 UTC` / `18:27:37.585471 Cairo`, requested lag 60 seconds.

Azure accepted the PITR request and the target reached Ready. The subsequent target-only credential operation returned a terminal unsuccessful async status. The detector stops on either `Failed` or `Canceled`; its retained evidence does not distinguish these two values or retain the provider error code. An immediate activity-log lookup returned an empty array, so no root cause is inferred. This is an access/provisioning verification failure, **not proof of backup corruption or measured RPO failure**. No target DB connection, TLS/schema verification, production-origin replay, or fresh checkpoint usability proof was achieved. The fresh checkpoint gate is NOT ESTABLISHED, and production phases 1–5 were not entered.

Azure initially did not honor the requested Disabled public-network flag, as previously observed in the reviewed drill. At first Ready, zero firewall rules were observed; Disabled was then requested and Ready observed before the target-only credential operation; that readiness poll alone did not independently verify the network flag. A later independent server GET during cleanup showed network Disabled and state Dropping. No broad firewall rule or verifier access was created. The target was never connected to an application or used for traffic, photos, user-row export, or operational recovery.

## Ordered activity and exact changes

All times are 8 October 2026. Cairo is UTC +03:00. **Production changes, in order: none.**

| UTC | Cairo | Activity / nonproduction change |
| --- | --- | --- |
| Before 15:25:45 | Before 18:25:45 | Clean HEAD and live remote ref verified; reviewed runbook, policies, SQL and prior evidence |
| 15:25:45.483669–15:26:10.517257 | 18:25:45–18:26:10 | Read-only management/settings, backup, Blob inventory, health and deployment audit |
| 15:26:06.939145 | 18:26:06.939145 | Read-only production DB catalog/WAL observation, TLS 1.3, no user records |
| 15:27:31.978684–15:27:36.214197 | 18:27:31–18:27:36 | Sanitized dotenv/provider metadata and monitoring audit |
| 15:28:23.723856 | 18:28:23.723856 | Isolated verification began; source metadata/settings/firewall fingerprints captured |
| 15:28:38.533530–15:28:40.048964 | 18:28:38–18:28:40 | Exact isolated target PITR PUT submitted and accepted (HTTP 202) |
| 15:32:39.124726 | 18:32:39.124726 | Extended read-only DB ACL/default-privilege/extension/index audit |
| 15:34:18.714183 | 18:34:18.714183 | Isolated target Ready; initial firewall inventory empty |
| 15:34:22.416242 | 18:34:22.416242 | Ready observed after target network-disable request; target-only credential reset attempted |
| 15:34:24.746836 | 18:34:24.746836 | Terminal credential-operation failure detected; rollout halted immediately |
| 15:34:24.748836–15:34:45.009985 | 18:34:24–18:34:45 | Target cleanup: network-disable requested, empty firewall verified, exact target DELETE submitted |
| 15:35:50.992384 | 18:35:50.992384 | Target deletion verified with HTTP 404 |
| After cleanup | After cleanup | Source server metadata, firewall and App Settings before/after checks all equal |
| 15:37:07.302842 | 18:37:07.302842 | Independent GETs: target 404; named verifier 404 (verifier was never provisioned) |
| 15:38:38.773473 | 18:38:38.773473 | Provider credential-pair presence clarified from deployed dotenv in memory; values withheld |
| After verification | After verification | Sanitized report/evidence written; repository documentation delivery recorded separately |

The restored target may leave Azure-managed deleted-server backups recoverable for five days, approximately through `2026-10-13T15:35:50.992384+00:00` (`18:35:50.992384 Cairo`). A 404 proves resource deletion, not physical backup erasure. This derived source is excluded from automatic recovery and requires the existing recovery/privacy review and verified signed replay before exceptional reuse. No local production DB copy or verifier remains. Journal/key expiry remains disabled indefinitely.

## Production preflight findings and unexecuted phases

| Area | Fresh result / final state |
| --- | --- |
| DB schema/ownership/grants | Columns, indexes, constraints, objects, table grants, schema ACL, functions, triggers and policies match the earlier audited catalog exactly. Sixteen business tables remain owned by `dermaireadmin`. No public functions, noninternal triggers or row policies. Only `plpgsql` extension observed, owned by `azuresu` in `pg_catalog`. Default-privilege catalog empty; DB ACL null/default. Public index validity/readiness/live metadata captured. |
| Roles and no-admin proof | Runtime still uses `dermaireadmin`, with CREATEROLE, CREATEDB, BYPASSRLS and privileged membership/SET ROLE routes. Separate runtime/migrator roles are absent. **No-admin proof NOT ACHIEVED**; role creation, credential rotation, ownership/PUBLIC repair and negative-permission smoke were not executed. |
| Baseline/Alembic | Existing active-owner uniqueness remains a unique index; no `alembic_version`. No normalization, constraint attachment, stamp, upgrade, Alembic check or production ORM-equivalence assertion was performed. No empty-baseline CREATE or destructive schema operation was issued. |
| Native backup/checkpoint | Server Ready, PostgreSQL 18.6; seven-day native retention, geo backup Disabled, earliest restore metadata 2 October 2026; seven automatic full backup entries, latest `07:19:42.755562 UTC`. At `15:26:06.939145`, last WAL archive `15:21:23.083672`, age 283.855473 seconds, failed_count 0. At `15:32:39.124726`, last archive `15:28:53.975508`, failed_count 0. Archival metadata is not standalone usability proof. |
| Journal/key | No production DELETION_JOURNAL settings. Independent protected storage/key/backup, durability, completeness and signed replay were not provisioned or certified. Policy expiry for journal and HMAC keys remains DISABLED INDEFINITELY; no cleanup/expiry rule or key expiry was enabled. Historical deletions are not fabricated or claimed covered. |
| Legacy policy | OneDrive sources remain LEGACY/UNKNOWN-PROVENANCE and excluded from approved operational restore selection. Exceptional recovery still needs recovery/privacy review, complete verified signed tombstone replay and verification before traffic/writes. Primary project owner (temporary) retains release/recovery/privacy/on-call responsibility. |
| Blob inventory/policy | `skin-images` remains private and empty: zero live objects, versions, snapshots, deleted objects, object holds and object immutability. Blob soft-delete explicitly false; versioning/container-soft-delete/restore policy returned null, not an explicit disabled certification. No policy or historical-copy cleanup changes. Account/container management holds/immutability audit remains incomplete. Prior HTTPS/TLS/public-access findings were not newly certified at account level in this run. |
| App operational settings | Running, HTTPS only, TLS minimum 1.2, Python 3.12; Always On false; Health Check unset; HTTP logging true; startup `python -m uvicorn app.main:app --host 0.0.0.0 --port 8000`. No operational/logging settings change or restart. Both new health endpoints return 404 on the legacy build. |
| Monitoring/action groups | Production diagnostics empty. Discovered Action Group and eight alert rules are staging resources; no production rules installed or production alert drill. Existing staging group enabled, Gmail `hussamwaleed15@gmail.com` and school `2022170636@cis.asu.edu.eg`, common schema enabled. Recipient path unchanged; no mailbox re-proof requested. Production scoping/suppression/access and Fired/Resolved execution unverified. |
| Exact provider settings | App Settings: `CONTEXTUAL_AI_ENABLED=true`; OpenAI endpoint/key present. `AZURE_VISION_ENABLED` ABSENT; Vision endpoint/key absent. Content Safety endpoint/key absent, no separate flag in target build (credential-driven). Deployed dotenv has no nonempty Vision/OpenAI/Content Safety credential pair and no Vision/contextual enable flags. Vision target-code default is false. No provider was invoked, enabled, disabled or reconfigured; legacy runtime behavior was not exercised. |
| Deployment | Target source `4948a91a5b9218745cc3cf22596dd05d594192cb`. No new build/deployment/artifact hash/deployment ID. Current production ID remains `a1051873-4635-46aa-8fa8-7230b79a6097`, status 4, active; original source commit not independently established. |
| Startup/readiness | No production restart or changed boot ID; no 180-second readiness measurement. The legacy endpoints remain 404. |
| Production smoke/cleanup | Registration/login/profile/assistance/account-deletion/auth-denial/Blob/runtime-permission/alert smokes were not executed. No disposable production accounts, blobs or temporary rules created. The one isolated DB target was deleted; no verifier created. |
| Traffic/write opening | No traffic/write opening, pause, stop or rollback issued. Existing production running state was preserved. **This is not a claim that production is in maintenance/read-only mode or that its legacy build enforces journal privacy.** No pre-journal build was deployed or reopened with writes. |

## Rollback artifact/settings references

Fresh metadata and hashes were captured without secret values. No independently retained production settings/package recovery copy was created before the halt. The existing compatible staging rollback archive was downloaded for member inspection, hash-verified, then the local scratch copy was removed. Its nested archive contains 13,199 entries, no `.env`, and built source/dependencies; no new rollout package was generated. The pre-journal production package cannot reopen writes after journal adoption.

| Remote reference | SHA256 | Bytes |
| --- | --- | --- |
| Production `/home/site/wwwroot/output.tar.zst` | `9a0e604b37507dfda5be119ae931a0f09f30fc3c28ef0cf3143b55e8ec7dff4b` | 145453718 |
| Production `/home/site/wwwroot/oryx-manifest.toml` | `01c9e625fde374ee55b657939517d2d45e31ed76487b0a5017c0791c6528d1b6` | 261 |
| Production `/home/site/wwwroot/requirements.txt` | `59f55b35111034a84ae8d71b9fae53573b2eb32e652a5e96bf498d9bd3b256c7` | 479 |
| Staging `/home/dermaire-rollback-0f97dc2.zip` | `7ce9bbbd5a459fa73f2268f2e9cecd63af948d4ebf3639206402c6ea1b656ff8` | 144249200 |

Settings references: sanitized `fresh-preflight.json`, `deployed-dotenv-metadata.json` and source App Settings before/after fingerprints. Artifact ETags/last-modified timestamps are in `rollback-artifact-metadata.json`. These are metadata references; secret values were not stored. **Rollback needed/performed: no/no.**

## RTO, tests and evidence delivery

Request-to-target-Ready: **340.181 seconds (5m40s)**. Request-to-failure observation: **346.213 seconds (5m46s)**. Request-to-deletion proof: **432.459 seconds (7m12s)**. Full preflight start-to-target-deletion proof: **605.509 seconds (10m06s)**. These are orchestration/cleanup times for an unsuccessful verification; they are not successful recovery or readiness measurements.

**End-to-end production RTO <=30 minutes remains NOT CERTIFIED.** No production-origin DB verification, journal replay, image recovery/inventory, migration/grants, application startup, smoke or traffic switch completed. No lost-write interval was measured. Earlier PITR/RTO evidence and its limits remain unchanged.

Fresh tests: **62 passed, one deprecation warning** across `test_production_config.py`, `test_operational_targets.py`, `test_deletion_journal.py`, `test_operational_readiness.py`. Initial test setup encountered a denied default temporary directory; rerun with a workspace temporary directory passed. A preliminary command referenced a nonexistent test filename and collected no tests; neither setup issue is claimed as a production/product failure. Full backend suite was not rerun for this documentation-only halt.

Checks: clean HEAD/remote equality; reviewed SQL/policy/runbook; fresh read-only ARM/SCM/DB and Blob audits; exact catalog historical comparison; native archive observations; production package and compatible rollback hashes; compatible archive member inspection; single guarded isolated PITR; explicit credential async completion gate; empty target-firewall and cleanup proofs; production server/firewall/App Settings before/after equality; sanitized JSON manifest and documentation checks. No secrets, HMAC keys, credentials or raw production records are included.

Evidence: `docs/evidence/production-rollout-resume-20261008-1525/`, with SHA256 manifest. Documentation-only commit/push status is reported in the delivery message, avoiding a self-referential commit hash. No code, SQL, production credential, setting or deployed artifact changes are part of the documentation commit.

**Required next execution boundary:** resolve the isolated target credential-operation failure and establish a fresh usable checkpoint before production mutation. This run performed no retry after the failed gate and requires no human browser/device approval or user-run commands.
