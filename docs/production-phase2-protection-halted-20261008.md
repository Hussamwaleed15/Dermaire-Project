# Production Phase 2 — protection/access gate halted, 8 October 2026

**PHASE 2 HALTED/ROLLED BACK.** No production mutation occurred and no production rollback was needed. Phase 3 was NOT started; no new app build was deployed. No real user rows or photo contents were read or modified. The journal v2 concurrency milestone remains valid; this attempt did not pass the additional production protection/access gate.

## Ordered observations and changes

All timestamps are UTC on 8 October 2026; Cairo is UTC+03:00.

| Timestamp | Action and result |
| --- | --- |
| Before 17:36:45.910401 | Clean local main `efeb41e5adc604907ee2888d671b9cc49a8e0cd1`; cached origin/main and fresh `git ls-remote origin refs/heads/main` matched. Exact individual repository-read times were not captured. |
| 17:36:45.910401 | First read-only management preflight started. Its remote metadata probe had a locally introduced indentation error; no production mutation or DB query resulted from that probe. Corrected the harness before the completed preflight. |
| 17:37:17.978522–17:37:35.881008 | Completed read-only Azure management/settings, production DB metadata, Blob policy/count inventory, and health preflight. |
| 17:37:30.893798 | Read-only runtime DB observation: revision `20261008_01`, `dermaire_runtime`, transaction read-only on, TLSv1.3. WAL archived_count 5349, failed_count 0, no last failure, unchanged reset `2026-09-20T07:02:00.858492Z`; last archive `17:34:04.704911Z`, age 206.188887 seconds. |
| 17:39:32.255401–17:39:38.369032 | Nonproduction protection/access compatibility probe only: created a fresh private synthetic container in `dermairerehearsal261006`, verified group tag `production=false`, set container legal hold with protected append writes disabled, and tested the exact source `DeletionJournal` class using HTTPS container SAS permissions read/create/list and an ephemeral synthetic signing key. The record/retry/inventory sequence returned HTTP **403 AuthorizationFailure** before its combined success checkpoint. Gate FAIL; no production provisioning followed. |
| By 17:39:38.369032 | Cleared only that temporary nonproduction hold and deleted its synthetic container. Both cleanup calls returned success; a separate post-delete absence lookup was not run after the stop. No production audit evidence was deleted. |
| 17:40:41 (completion observed) | Relevant local journal/account-deletion tests: 36 passed, one deprecation warning. |

**Exact production changes in order: none.** No resource creation, policy change, credential generation, settings update, app stop/restart, traffic restriction, DB write, deletion drill, or production synthetic journal write occurred.

## Failed gate and limitations

The proposed production protection/access combination was not certified: indefinite container legal hold, no protected append writes, and a container-scoped HTTPS read/create/list SAS rather than sharing an account key with the application. The rehearsal used the current source class loaded from its AST, without loading application configuration or production credentials. Account credentials were retrieved only for the verified nonproduction account and stayed in process memory.

The probe recorded the combined `record` / duplicate `record` / verified `inventory` checkpoint, not the exact failing SDK sub-operation. Therefore it does **not** establish whether a first object was persisted or which sub-operation needs another permission. It establishes that this access/protection combination did not complete the required acknowledgement/retry validation. The exception prevented the combined success result; there was no false PASS. No business deletion callback was invoked. Do not infer a production durability defect, a new v2 concurrency regression, or successful protected acknowledgement from this result.

Per the authorized immediate-stop rule, no permission widening, policy weakening, alternative protection retry, or production continuation was attempted. A separate preparation milestone must instrument the exact failing operation and validate a compatible least-privilege protection model, including independent protected backup and inventory completeness, before another production Phase 2 attempt.

Azure documents indefinite container legal holds as permitting creation/read and preventing modification/deletion until explicitly cleared: [immutable storage](https://learn.microsoft.com/en-us/azure/storage/blobs/immutable-storage-overview). SAS rights have distinct scopes and permissions: [service SAS](https://learn.microsoft.com/en-us/rest/api/storageservices/create-service-sas). These documents informed the candidate design; the actual 403 result means that candidate is not accepted as production-ready.

## Preflight and exit-gate status

| Requirement | Observed result / remaining limit |
| --- | --- |
| Production app | `dermaire-api`, Running, HTTPS-only; `/health` 200, `/health/live` 404, `/health/ready` 404. Current legacy build remains in place. No restart/startup budget measured in this attempt. |
| Production DB | `dermaire-db-server`, Canada Central, PostgreSQL 18, Ready, revision and runtime identity verified as above; DATABASE_URL verify-full flag present. No business-row reads. Fresh manual role/grant/catalog drift audit was not completed before halt. |
| Backups / PITR | Seven completed automatic full backups; latest `2026-10-08T07:19:42.755562Z`. Seven-day retention, geo backup Disabled, SystemManaged encryption. Prior usable production-source PITR verification `15:03:38.626468Z` is inside its 24h window, expiring `2026-10-09T15:03:38.626468Z`. Full PITR was skipped; intervening activity/full configuration comparison was not finished, so the complete fresh 24h reliance gate is **not declared PASS**. Fresh WAL age/counters passed the observed thresholds. |
| Journal resource/provider/independence | No production journal resource provisioned. Subscription storage-account inventory contained the production photo account, the known nonproduction rehearsal account and Cloud Shell account; it found no dedicated journal account. This is not an inventory of all possible external stores. Reviewed target is dedicated Azure Blob storage outside application DB/photo backup/restore, with separate restricted credentials, protected inventory/checkpoints and independent protected backup. None was established in production. |
| HMAC storage/handling | No production HMAC key generated or stored. Nonproduction probe key was ephemeral process memory only. Planned production setting name `DELETION_JOURNAL_HMAC_KEY`; separate secure secret, never SECRET_KEY, no direct unreviewed rotation. No key value persisted or reported. |
| Journal settings | Production settings with `DELETION_JOURNAL` prefix: **none**. Planned names: `DELETION_JOURNAL_CONNECTION_STRING`, `DELETION_JOURNAL_CONTAINER`, `DELETION_JOURNAL_HMAC_KEY`, `DELETION_JOURNAL_REQUIRED`. No setting was added or changed. No rollback setting envelope was necessary because mutation was never reached; names-only preflight metadata is archived. |
| Expiry | Accepted journal/key expiry policy remains **FAIL-CLOSED / DISABLED INDEFINITELY**. No journal/key exists from this attempt; no expiration/lifecycle deletion rule was installed. This is not an attestation of a provisioned production retention policy. 42 days remains a conditional future target, never enabled here. |
| Enablement boundary / historical coverage | **No production enablement boundary was established.** No native production journal completeness claim exists. Historical deletions before eventual verified activation remain outside native coverage unless independently reconstructed and verified. Configuration of plumbing alone must not be represented as live app hook activation; Phase 3 remains separate. |
| Production synthetic v2 test | NOT RUN: production create/read/signature/content verify/conflict/duplicate retry remain unverified. No production synthetic records left. Prior Azure 181/181 evidence is nonproduction concurrency evidence, not a substitute for this gate. |
| Production fail-closed harness | NOT RUN. Nonproduction candidate access failure propagated and invoked no deletion callback; this does not certify production missing-key/storage/write tests. Relevant local regression tests passed. |
| Photo public access / TLS | Account `dermaireimg479341`: allowBlobPublicAccess false, HTTPS-only true, min TLS1_2, Standard_LRS. Container `skin-images`: private (`public_access=null` means no anonymous container access). |
| Photo versioning / soft delete / restore | Blob soft delete explicitly disabled; days absent. Versioning null/omitted, container soft-delete retention null/omitted, restore policy null/omitted. They were **not changed to explicit false/disabled**, and the explicit policy gate remains incomplete. |
| Photo holds / immutability / inventory | Count inventory: one live container, zero blobs, zero versions, zero snapshots, zero deleted objects, zero object-level hold/immutability indicators. Container-level legal hold/immutability management properties were not separately audited; do not interpret empty object counts as proof of absent container policy. |
| Disposable production photo drill | NOT RUN; no fixture created. Observed empty preflight inventory is not a drill result. |
| Target hooks | Source v2 writer and read-only replay design reviewed. Current deployed hook contents and complete target account/photo policy integration were not verified during this halted attempt; no target deployment. |
| Off-live replay | Production-key-path replay NOT RUN because no production key/journal was provisioned. Local 36-test suite covers journal/account recovery including v1/v2 compatibility and source-read-only behavior. Prior isolated Azure replay evidence remains historical nonproduction evidence only; no replay against live rows. |
| Rollback | No production rollback required; zero production mutations. Phase 1 DB/runtime and ordinary app traffic left unchanged. Only the nonproduction probe resources were cleaned as described above. |
| Checks / delivery | Relevant local tests 36 passed. First test invocation from repository root could not import app.core; rerunning from backend passed. No application source change; full suite not repeated for documentation-only delivery. Diff/secret-content checks and commit/push verification reported in final delivery. |
| Phase 3 | **NOT started.** No deployment, operational monitoring/alerts configuration or traffic switch. |

## Residual recovery/privacy constraints

Seven-day managed DB backups and potential deleted-server backup residuals from earlier drills remain recoverable-source considerations; this attempt created no production-derived restore/server/export. The earlier inventory of residual windows was not fully refreshed. OneDrive and unknown/off-platform copies remain LEGACY/UNKNOWN-PROVENANCE and excluded from operational restore selection. All unknown/held recoverable sources continue to block journal and key expiry indefinitely.

Exceptional legacy recovery requires explicit recovery/privacy review, complete verifiable signed tombstone coverage, offline replay, retained-photo verification and approval before traffic/writes. Missing historical journal coverage cannot be repaired merely by provisioning v2 now. Primary project owner (temporary) remains release/recovery/privacy/on-call owner. DB RPO <=5m remains the target; this observation does not certify continuous RPO. End-to-end RTO <=30m remains a target, not fully certified. Startup/readiness budget remains 180s.

Counts-only evidence: `phase2-preflight.json` and `protection-probe.json`. Documentation/evidence only are delivered to the same main branch; the final commit hash is reported separately to avoid self-reference.
