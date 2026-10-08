# Dermaire production-source isolated PITR verification — 8 October 2026

**RPO: PASS (service-backed checkpoint evidence; exact final committed-transaction timestamp not independently certified). Recoverable-checkpoint gate: CLEARED for this observed checkpoint. No rollout was executed. Production remained read-only and untouched by this drill.**

## Exact source and offline target

- Subscription: `384c0376-d023-4a61-9dce-69ff8cbdcd0c`.
- Source: `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/dermaire-db-server`; database `dermaire`.
- Target: `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-readiness-nonprod-20261006/providers/Microsoft.DBforPostgreSQL/flexibleServers/dermaire-prod-pitr-verify-20261008-1451`; restored database `dermaire`, Canada Central, PostgreSQL 18.6, Standard_B1ms/32 GiB.
- Target registered exclusively for offline verification, with no app connection, traffic switch, deployment, photograph restore, user-row export or on-demand backup. Existing nonproduction resource group was reused; no group was deleted.
- Starting local/remote main: `f6738e0c39e99f67c6a18e910dc4347918737fe2`, clean.

## Fresh checkpoint and evidence limits

Observation: **2026-10-08T14:51:08.626887+00:00 UTC**, **2026-10-08T17:51:08.626887+03:00 Cairo**. Requested custom PITR checkpoint: **2026-10-08T14:50:08.626887+00:00 UTC**, **2026-10-08T17:50:08.626887+03:00 Cairo**. Intended data-point lag: **60 seconds** from observation; request lag: **60.690 seconds**. RPO is measured against observation/request, not against the later completion time.

Fresh native retention: seven days, geo backup disabled, earliest restore date `2026-10-02T07:14:08.190528+00:00`. Seven automatic Full backup entries were observed, latest `2026-10-08T07:19:42.755562+00:00`. Source WAL observation `2026-10-08 14:51:08.948373+00`: last successful archive `2026-10-08 14:48:13.230588+00`, archived_count=5315, failed_count=0. Last archive age **175.718 seconds**. These are archive/backup facts, not usability proof by themselves.

The evidence chain is the explicit production resource ID and custom checkpoint in the submitted PITR request, successful provisioning, a reachable restored `dermaire` database under verify-full TLS, matching PostgreSQL system identifier, a timestamped read-only repeatable-read catalog/data-integrity verification, and exact source/target schema equivalence. Request acceptance alone was not used as proof.

Azure's server/backups API does not expose a latest-usable restore watermark or independently attest the exact final replayed transaction/checkpoint time here. Server GET returns nullable request-origin/checkpoint fields. On the promoted target, **last_xact_replay_timestamp and last_wal_replay_lsn both returned null**. The source and restored target system identifiers match (`7687509194730582065`); the target reports timeline 2 versus source timeline 1 and in_recovery=false. Timestamped invariant checks at `2026-10-08 15:03:37.679789+00:00` prove accessible consistent origin metadata, not an exact independently measured replay stop time. **60 seconds is the service-backed requested checkpoint delta, not an independently measured lost-write interval.** No synthetic production marker was written. This establishes this successfully usable custom restore under the user's allowed strongest-supported evidence standard, not a continuous five-minute guarantee or proof of every transaction near the boundary.

## Timings and RTO

| Milestone | UTC | Seconds from restore request |
| --- | --- | --- |
| requestUTC | 2026-10-08T14:51:09.316588+00:00 | — |
| firstProvisionedUTC | 2026-10-08T14:57:36.487256+00:00 | 387.171 |
| networkDisabledReadyUTC | 2026-10-08T14:57:39.418756+00:00 | 390.102 |
| reachableUTC | 2026-10-08T15:03:37.596150+00:00 | 748.28 |
| verifiedUTC | 2026-10-08T15:03:38.626468+00:00 | 749.31 |
| verifierDeletedUTC | 2026-10-08T15:03:44.600736+00:00 | 755.284 |
| cleanupVerifiedUTC | 2026-10-08T15:04:55.629644+00:00 | 826.313 |

The first Ready observation is the final target's provisioning event; Disabled-network readiness is separately recorded. Polling intervals add observation uncertainty. Database verification elapsed **749.31 seconds** from request. This is within the accepted 1,800-second isolated DB drill budget. Current production-origin replay was not executable; replay completion/time is **N/A**. The historical synthetic staging replay took 9.141 seconds and its complete drill 493.573 seconds; neither is a fresh production replay measurement.

**End-to-end production RTO <=30 minutes is not certified.** This drill excludes production journal replay, runtime/migrator grants, migration adoption, app startup/smoke, photographs, a traffic switch and final recovery operations.

The first target `dermaire-prod-pitr-verify-20261008-1430` in the same nonproduction group failed device reachability and was deleted at `2026-10-08T14:40:57.821934+00:00` (404). Its requested checkpoint was `2026-10-08T14:29:25.030289+00:00`; it does not establish RPO. The second target `dermaire-prod-pitr-verify-20261008-1443` requested checkpoint `2026-10-08T14:41:49.245306+00:00`, provisioned, but the client log API was polled before readiness and returned HTTP 400. The target and its Azure verifier were deleted (target 404 at `2026-10-08T14:49:54.207671+00:00`). This is an orchestration failure, not a failed-backup proof. The final fresh target above uses readiness-aware log polling and compact schema hashes to avoid ACI stopped-log truncation. All prior attempts and deletion proofs are retained. Total exercise time through final verification, including the two earlier attempts: **2010.551 seconds**, **exceeding the 30-minute objective**. The final attempt completed DB verification in 749.310 seconds (12m29s), within 30 minutes; the complete multi-attempt exercise did not meet that elapsed-time budget. Production end-to-end RTO remains uncertified.

## TLS, access and isolation

PITR requested Disabled public networking. Azure initially ignored the requested Disabled network flag. On the first attempt, it reported Enabled during Provisioning and firewall enumeration returned ResourceNotFound: absence of rules could not be observed until Ready. No firewall was created during provisioning; Microsoft documents source firewall rules are not copied. A first-attempt disable while busy was rejected. That first target became Ready with zero rules, was restricted to the device, but TCP reachability timed out and it was deleted; no RPO usability claim was based on that attempt. The second and final attempts used temporary isolated Azure verifiers. At first Ready, the verifier confirmed **zero firewall rules**, requested Disabled, and waited for Disabled/Ready. This deviation is recorded rather than claiming the initial network flag was honored.

An initial target-only password PATCH was submitted while network was disabled, but its Ready probe did not prove usable authentication: the Azure verifier later reported password authentication failure. A second target-only reset explicitly awaited ARM async **Succeeded at 2026-10-08T15:02:56.853149+00:00**, then replaced the verifier secure credential and refreshed its exact egress rule. The successful verify-full DB connection at 15:03:37 independently proves the resulting target-specific credential worked. The second reset occurred under the single-verifier firewall restriction. No source credential was exported to or shared with the Azure verifier. Secrets existed only in process memory and Azure secureValue. No app runtime credential or source password was read for target access. Only one exact Azure verifier egress IP firewall rule was created, with equal start/end addresses; no `0.0.0.0` Azure-services rule or broad range was added. Verifier IP values are withheld from published evidence. The temporary Azure Container Instance had no public ingress and received its secret through ARM secureValue; no secret was put in command arguments or retained logs. Public networking was enabled only after that restriction was installed. Verify-full used the exact target hostname and Mozilla CA trust; the server reports TLS 1.3/TLS_AES_256_GCM_SHA384. Target DB sessions defaulted to read-only with bounded statements. The target was not granted production app access or connected to any application. No credential was persisted locally or in the repository; the Azure secure credential resource was deleted.

## Schema, integrity and recovery suitability

Sixteen business tables were readable through full table COUNT scans; only counts were retained. Column/type/nullability/default, index definition and constraint comparisons against the fresh production catalog, using normalized SHA256 hashes computed independently on source metadata and target metadata: **{'columns': True, 'indexes': True, 'constraints': True}**. JSON comparison normalizes libpq string/null representations to psycopg native values; this normalization fixes representation differences and makes no schema changes.

All inspected public indexes valid/ready/live; zero unvalidated constraints; **27 foreign-key orphan checks and 16 CHECK-expression scans returned zero violations**. Version, collation, ownership/catalog metadata, origin identifier and replay fields were captured. No raw user records, IDs, emails, names, tokens, image paths, medical values or SQL error diagnostics were exported. No schema adoption or baseline stamp was performed. `alembic_version` is absent, consistently with the legacy production source; reviewed adoption remains a rollout prerequisite. No corruption indicator appeared in these bounded reads/catalog/constraint checks; this is not an exhaustive physical page/checksum or amcheck certification.

The complete multi-attempt exercise also includes device timeout and verifier orchestration retries; its elapsed duration is explicitly reported above and must not be mistaken for a proven <=30-minute final recovery process.

The restored DB is usable for recovery inspection. It is **not ready for application recovery traffic** without privacy journal completeness/replay and the reviewed runtime/schema preparation.

## Signed deletion tombstones

Fresh production app-setting names contain **no DELETION_JOURNAL settings**. A production independent journal/watermark/completeness/key protection was not provisioned. Applying staging tombstones to production-origin business rows would not prove production deletions and was not done. No production-origin deletion replay or zero-loss deletion guarantee is claimed.

Procedural coverage uses the existing documented real Azure staging PITR rehearsal only: signed independent intents removed a resurrected synthetic account and simulated restored photo; independent inventory became zero, repeat replay removed zero further accounts, and its target was deleted. See `docs/azure-readiness-rehearsal-20261006.md` and `docs/deletion-journal-restore.md`. This is historical procedural evidence, **not a fresh replay, production-origin journal coverage, or verified legacy mapping**. No staging journal/key was copied into this production-data target. Privacy recovery remains fail-closed until protected independent production journal/key provisioning, durability/completeness and signed replay verification are completed in the separately authorized rollout. Phase 0 policy remains PASS and indefinite expiry disablement remains in force.

## Cleanup and retained-copy limit

After sanitized evidence capture, public network disable was requested, the sole temporary firewall rule deleted, and empty firewall enumeration independently captured. A Ready response alone was not treated as proof of credential correctness or instantaneous setting propagation. The exact restored server and temporary Azure verifier were deleted; GET returned **404 at 2026-10-08T15:04:55.629644+00:00**, and a later list/activity check supplements that proof. All three restored servers and both temporary Azure verifiers were deleted and returned 404; no restored DB, temporary firewall, photograph copy, export or local database file is retained. Existing staging/source infrastructure was not removed.

**404 proves logical resource deletion, not immediate Azure backup erasure.** Microsoft documents deleted-server backups can be recoverable in the same subscription for five days. Provider-managed remnants may therefore persist until approximately **2026-10-13T15:04:55.629644+00:00**, with no immediate physical purge proved. This derived target and its residual window are registered in this report/evidence; it is excluded from automatic recovery selection and must never be revived without recovery/privacy review. There is no operator-selected retained production-data copy. Automatic backup purge is controlled by Azure; journal/key expiry remains disabled indefinitely. Documentation: [restore a deleted server](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/how-to-restore-deleted-server).

## Gate and remaining rollout prerequisites

The previous halted rollout's **usable production-origin recoverable-checkpoint gate is cleared for this drill, within the stated service-evidence limits**. Fresh preflight/checkpoint evidence must be captured again before a later maintenance/adoption because this observed checkpoint becomes stale. This report does not start or authorize the rollout by itself.

Remaining rollout prerequisites include production independent deletion journal/key protection, completeness and signed replay; runtime/migrator least privilege and TLS settings; reviewed baseline adoption; photo policy verification; runtime health/deployment; production monitoring/access/redaction/routing; and the reviewed maintenance/smoke/traffic sequence. Previously accepted Phase 0 policy and 180-second startup target are unchanged. Production privacy-safe recovery and final production RTO remain unproven.

## Production nonmutation and repository delivery

Mutation guards allowed ARM writes only to the exact isolated target/child firewall resources and the specifically named temporary verifier. All three attempts retained separate source before/after checks. Source DB catalog/WAL reads ran with default_transaction_read_only=on; no production SQL DML/DDL, setting, credential, firewall, deployment, provider, traffic or maintenance change was issued. Fresh before/after server/firewall/app-setting hashes agree: **{'serverMetadata': True, 'firewall': True, 'appSettings': True}**. Production's existing runtime continues independently; this is not a claim that its app was paused or placed in read-only maintenance mode.

Repository changes are documentation and sanitized evidence only. No code, migration, secret or user-row file is committed. Final commit/push status is recorded in the delivered chat after commit, avoiding a self-referential commit hash.

Service behavior references: [PITR backup/restore and network behavior](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore), [ARM PITR request](https://learn.microsoft.com/en-us/rest/api/postgresql/servers/create?view=rest-postgresql-2024-08-01). These describe service semantics; drill evidence supports this source/checkpoint result.
