# Dermaire Production Rollout Phase 2 — 8 October 2026

**PHASE 2 COMPLETE. Phase 3 was NOT started.** This verdict covers the protected production journal/key infrastructure, actual production identity/network plumbing, synthetic acknowledgement and recovery gates, explicit production photo policy, and independently protected checkpoint/backup validation. It does not mean the new application build or live user-deletion hooks were deployed. No real user rows or image contents were read or modified; DB queries were read-only metadata. The only production photo content was a disposable non-sensitive fixture, now absent.

## Boundaries and current application state

- Clean starting main and fresh GitHub remote matched `ce5fd17bb5e6c7c34d601e40b62f09f66bb75485`. No target build deployment was issued. Final deployment-source audit found no linked repository/branch or GitHub auto-deployment, and no repository workflow was present.
- Configuration-ready boundary: **2026-10-08T18:26:52.969103+00:00 UTC**. Journal synthetic-path first validation: **2026-10-08T18:33:12.468754+00:00 UTC** (21:33:12 Cairo). Live business-deletion hook boundary: **NONE / not activated in Phase 2**. Historical deletions and current legacy-build deletions are not claimed covered. Phase 3 must freeze legacy business writers, switch to the reviewed v2 hooks, prove readiness and record a distinct live coverage boundary before restoring traffic/writes. Existing legacy application writes remained open; there were no legacy v1 journal writers on the deployed build.
- The actual app system identity and production HMAC/storage path were used from an Azure-authenticated SSH session inside the production application container, rather than an administrator credential or SCM-only identity approximation. Target source was loaded as a verification-only class, outside the deployed application. SDK dependencies were temporary; no target application artifact was deployed.
- Existing `/health` remains 200; `/health/live` and `/health/ready` remain 404 on the legacy build. The controlled unchanged-build restart plus actual journal read/write/key readiness passed in **52.203s**, inside 180s. Earlier settings-update legacy-health proof took 174.7s; that observation alone did not certify journal readiness. The later controlled restart supplies the stronger measured proof.

## Production journal, independence and retention

| Boundary | Actual production resource / posture |
| --- | --- |
| Dedicated resource group | `dermaire-journal-prod`, separate from application DB/photo resource group `dermaire-rg` |
| Primary journal | Azure Blob Storage `dermairejrnlprod261008`, Canada Central, `Standard_ZRS`, private container `intents` |
| Independent journal copy | Azure Blob Storage `dermairejrnlbkprod261008`, Canada East, `Standard_LRS`, private container `intents-copy`, 17 independently verified objects |
| Protected evidence/key backup | Same independent backup account, private `protected-evidence`: one Azure-encrypted secret backup and one signed inventory checkpoint |
| Primary secret vault | `dermaire-journal-prod-kv`, Canada Central, RBAC, purge protection, 90-day soft-delete protection, `CanNotDelete` control-plane lock |
| Independent recovered key | `dermaire-jrnl-backup-kv`, Canada East, same protective posture; encrypted backup was restored and its value matched the original only in memory |
| Journal legal holds | All three journal/evidence containers have indefinite `privacyretention` legal hold; protected append writes are false. Runtime overwrite returned 409 and delete returned 403. |
| Network | Primary default Deny / bypass None, one device IPv4 egress and one dedicated app subnet; backup default Deny / bypass None, one device egress, no runtime subnet. Vaults default Deny / bypass None; primary permits that app subnet plus device, recovery vault device only. |
| App integration | `dermaire-journal-prod-vnet/app-integration`, `10.87.0.0/26`, delegated only to `Microsoft.Web/serverFarms`, `Microsoft.Storage.Global` and `Microsoft.KeyVault` service endpoints; outbound route-all enabled |
| Transport/privacy | Public Blob access false, HTTPS-only true, TLS1_2, public endpoints restricted by explicit firewall rules, Shared Key false on both journal accounts. No journal account key or SAS fallback. |
| Expiration | **DISABLED INDEFINITELY**: no lifecycle policy on either journal account; primary and recovered HMAC have no expiry. No 42-day deletion rule was installed. |

Accounts/vaults and the independent copied journal are outside DB/photo restore and must never be rolled back with them. Regional separation and primary ZRS provide different protection from a logical journal copy/checkpoint. They remain in the same Azure subscription/tenant and administrative trust domain; this is not an air-gapped or separate-administrator guarantee. Privileged management identities can change holds/roles, so exceptional recovery requires the owner’s privacy/completeness review.

The protected copy/checkpoint is a **verified frozen-writer snapshot**, not a newly deployed continuous replication/scheduling service. No automatic backup cadence or continuous journal recovery interval is claimed. Before every recovery snapshot, freeze all journal writers, perform a full signed checkpoint with the provided tool, reconcile it with the protected copy, and remain offline on any completeness uncertainty. After live hooks are enabled, the release/recovery owner must repeat this operational checkpoint procedure; a stale snapshot is not evidence that later requests are absent. The primary append-only WORM journal remains the current authoritative durable source.

## Identity and exact least-privilege role

Production authentication: **system-assigned Managed Identity / Microsoft Entra OAuth** on `dermaire-api`. Object ID `c519ee0d-f1d3-4c2d-ba24-d204eb1fd976`; tenant `6845d6ca-1ec5-4c0e-9e9d-34130ce0a0b8`. Token object ID was checked inside the real app container. No client secret/certificate was issued to this runtime identity.

Exact role: **`Dermaire Journal Read Write No Delete Prod`**.

Exact runtime journal assignment scope:

`/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-journal-prod/providers/Microsoft.Storage/storageAccounts/dermairejrnlprod261008/blobServices/default/containers/intents`

Assignable role-definition boundary is only `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-journal-prod`; this definition boundary is not an access grant.

- Control action: `Microsoft.Storage/storageAccounts/blobServices/containers/read`.
- Data actions: `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read` and `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write`.
- No delete, append, container creation/write, role management, key retrieval, storage policy administration or unrelated control-plane action. Write can otherwise overwrite; the separately managed indefinite hold prevents this and cannot be changed by runtime.

The runtime has precisely two audited assignments: this custom role on `intents`, and **Key Vault Secrets User** at the single secret scope `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-journal-prod/providers/Microsoft.KeyVault/vaults/dermaire-journal-prod-kv/secrets/deletion-journal-hmac-v1`. It has no assignment or permitted subnet on the backup account/recovery vault. Provisioning/checkpoint owner data access is the same no-delete custom role at the three specific containers plus read-only access to the one primary secret. Both temporary Key Vault Secrets Officer assignments were removed and absence verified. Existing provisioning management permissions were not granted to runtime.

## HMAC and settings

An independent random 32-byte HMAC signing secret was generated in memory and written directly to supported Azure Key Vault secret `deletion-journal-hmac-v1`. Its value was never printed, committed, written to a local file or placed as a literal app-setting value. The app setting uses a **pinned secret-version Key Vault reference**. Actual runtime resolution was `Resolved`, system identity, and the resolved key matched the version fetched with that identity in memory. No unreviewed key rotation took place.

Only these journal setting names were added: `DELETION_JOURNAL_ACCOUNT_URL`, `DELETION_JOURNAL_CONTAINER`, `DELETION_JOURNAL_HMAC_KEY`, `DELETION_JOURNAL_REQUIRED`. Managed-identity client-ID override and journal connection-string settings remain absent. Other production setting values were preserved; sanitized rollback evidence retains names/structural state only.

Native Key Vault backup is Azure-encrypted, stored under the independent WORM account and read-back verified. Same-vault restore returned expected existing-secret conflict 409 and was not counted as recovery proof. The later **new Canada East vault restore passed**, with no expiry and an in-memory value match. Azure secret-backup restore is constrained to the same subscription/geography; this Canada-to-Canada proof satisfies that path. The recovered copy is retained, protected and inaccessible to runtime.

## Actual synthetic/recovery results

| Gate | Result |
| --- | --- |
| v2 conditional create / post-write read / HMAC and content verification | PASS, actual production identity/storage/key path |
| Identical retry / reordered-duplicate images | PASS; same canonical object |
| Conflicting conditional create | HTTP 409; original bytes unchanged |
| Concurrency | 2 writers: 2/2; 12 writers: 12/12; initial unique acknowledged = durable verified = **15**, lost **0** |
| Runtime deletion / overwrite denial | 403 `AuthorizationPermissionMismatch`; 409 `BlobImmutableDueToLegalHold` |
| Actual assignment revoke | Effective 403 observed at 2026-10-08T18:36:46.290244+00:00; record and replay fail closed; deletion callback never called |
| Exact assignment restore | Same ID/principal/role/scope restored; deterministic write/read recovery at 2026-10-08T18:37:56.051129+00:00; no intent lost |
| Additional signed compatibility fixtures | One synthetic v2 and one synthetic v1; final **16 v2 + 1 v1 = 17** |
| Off-live replay from primary | PASS, local in-memory SQLite synthetic DB and disposable private nonproduction Azure photos; 2 synthetic accounts removed; legacy/orphan photos removed; kept account/photo survived |
| Repeat replay | 0 account and 0 image cleanup calls; source bytes unchanged |
| Complete verification / v1 compatibility / v2 completeness | PASS; all 17 signed records verified before callback |
| Corruption / unavailable-storage | Rejected before callback; fail closed |
| Independent backup | 17 copied records byte-equal and fully verified; source unchanged; HMAC-signed immutable full inventory checkpoint |
| Replay from independent copied journal | Same complete replay, repeat no-op, compatibility, legacy/orphan, corruption and unavailable-store gates PASS |
| HMAC backup recovery | Azure-encrypted backup restored to independent purge-protected vault; in-memory equality PASS |

All 17 retained intent objects carry immutable create-time `synthetic=true` and a Phase 2 purpose marker in both source and copy. Their owners/images use reserved disposable synthetic identifiers; they do not represent real privacy requests. Replay **still verifies all signatures** and does not trust metadata to bypass validation. Synthetic owners/images match the isolated test fixtures and otherwise perform no deletion; do not repurpose those identifiers as business IDs. Do not delete these protected audit records to clean the test.

Protected manifest: `checkpoints/2026-10-08T201642.467868_0000.json`, SHA256 `85da8c8bb93cc3b787828d20025c093c45b049a99b7ea634b00c9c4210970071`. The new `app.tools.checkpoint_journal` tool copies only verified signed intents, never overwrites/deletes evidence, preserves synthetic metadata, verifies both complete inventories, rejects a source missing any retained backup record, rechecks source stability, and acknowledges only an exactly verified signed manifest. It requires explicit frozen-writer attestation and the pinned secret-version URI. Recovery may read `intents-copy` directly; key backups/checkpoints are kept separately in `protected-evidence`, outside the replay inventory.

## Explicit photo policy and final inventory

Production account `dermaireimg479341`, container `skin-images`: private; public Blob access false; HTTPS-only true; TLS1_2. ARM explicitly stores versioning **false**, Blob soft delete **false**, container soft delete **false**, restore policy **false**. Photo legal hold/immutability is absent; no retained version/snapshot/deleted objects or deleted container were observed.

The update used the documented Blob service **PUT** contract and existing supported fields. An earlier unsupported PATCH request was rejected without policy mutation; no policy was weakened. Data-plane SDK `Get Service Properties` omits some disabled fields and returns null, whereas the fresh ARM read confirms explicit false. This representation difference is documented rather than treated as restored retention.

The production drill uploaded/read only a disposable non-sensitive fixture, used the current source deletion service, retried deletion and enumerated live/deleted/version/snapshot history. Final fixture copies **0**; final entire photo inventory **0 objects, 0 versions, 0 snapshots, 0 deleted objects, 0 holds/immutability**. No real user photograph was touched. Photo fixture operations used the existing administrative photo storage credential in process memory, not the journal identity or a journal key/SAS fallback.

Target source account/photo deletion hooks were reviewed and tested: journal v2 intent precedes destructive image/DB work; replay verifies source without recording a replacement intent and covers owner namespaces/explicit legacy image tokens. None of that target build was deployed in this phase.

## Fresh DB/backup and legacy-source policy

Fresh initial and post-interruption preflights verified revision `20261008_01`, `dermaire_runtime`, verify-full and TLSv1.3. Catalog/roles/grants match the completed Phase 1 metadata after observer-visibility normalization; no DB configuration operations were found since Phase 1. The original production-source usable PITR proof at `2026-10-08T15:03:38.626468Z` remains inside its 24-hour policy, expiring **9 October at 15:03:38 UTC / 18:03:38 Cairo**. Full PITR was correctly skipped; no new production-derived restored DB copy was created. Native backup retention is seven days, latest completed full backup is within 24h, WAL advances with zero failures and unchanged stats reset. Final archive age was **210.21786s**, within <=300s. This is fresh policy evidence, not a certification of a continuously measured lost-write interval.

OneDrive and other unknown/held recoverable copies remain LEGACY/UNKNOWN-PROVENANCE and excluded from operational automatic restore selection. Residual deleted-server backups, exports and unknown off-platform copies are conservatively covered by **indefinite intent/key retention**, not a claim that they are absent or historical deletion evidence exists. Retention cannot reconstruct pre-boundary deletions. Any exceptional legacy restore still requires recovery/privacy owner review, registered isolated copies, complete signed tombstone coverage/replay and verification before traffic/writes resume; unknown mapping/completeness blocks recovery. 42 days remains a future conditional target only if every recoverable copy is <=35 days, quarantine <=7 days and no hold survives. No expiration was enabled.

Primary project owner (temporary) retains release/recovery/privacy/on-call responsibility. DB RPO <=5m is unchanged. End-to-end RTO <=30m remains a target and **is not fully certified** by small synthetic replay or the 52.2s unchanged-build restart.

## Ordered production mutations and evidence times

All dates below are **8 October 2026 UTC**, unless stated otherwise. Cairo = UTC+03:00. Requested/acknowledged times come from device evidence; selected Azure/app observations have subsecond clock skew and are not artificially reordered. A verification timestamp is identified where an individual write-start timestamp was not separately retained. An interval between the early gates and later completion included a user continuation; the DB/backup/catalog preflight was refreshed afterward.

| Requested / observation UTC | Completed / acknowledgement UTC | Action | State |
| --- | --- | --- | --- |
| 2026-10-08T18:14:35.408118+00:00 | 2026-10-08T18:14:37.299960+00:00 | create independent production journal resource group | SUCCESS |
| 2026-10-08T18:14:37.302962+00:00 | 2026-10-08T18:16:33.627668+00:00 | create production journal VNet | SUCCESS |
| 2026-10-08T18:14:43.2252554Z | 2026-10-08T18:14:43.2252554Z | Microsoft.Network/register/action | SUCCESS (provider activity timestamp) |
| 2026-10-08T18:16:25.5274022Z | 2026-10-08T18:16:25.5274022Z | Microsoft.KeyVault/register/action | SUCCESS (provider activity timestamp) |
| 2026-10-08T18:16:33.628669+00:00 | 2026-10-08T18:16:48.559236+00:00 | create delegated app subnet and service endpoints | SUCCESS |
| 2026-10-08T18:16:48.560235+00:00 | — | create protected storage boundary dermairejournalprod261008 | REJECTED_ACCOUNT_NAME_INVALID |
| 2026-10-08T18:19:02.846942+00:00 | 2026-10-08T18:19:26.469585+00:00 | create protected storage boundary dermairejrnlprod261008 | SUCCESS |
| 2026-10-08T18:19:26.473583+00:00 | 2026-10-08T18:19:29.429697+00:00 | allow single provisioning egress on dermairejrnlprod261008 | SUCCESS |
| 2026-10-08T18:19:29.430700+00:00 | 2026-10-08T18:19:33.146494+00:00 | allow production app subnet on primary journal | SUCCESS |
| 2026-10-08T18:19:33.146494+00:00 | 2026-10-08T18:19:35.236473+00:00 | create private container dermairejrnlprod261008/intents | SUCCESS |
| 2026-10-08T18:19:35.236473+00:00 | 2026-10-08T18:19:37.492333+00:00 | set indefinite legal hold dermairejrnlprod261008/intents | SUCCESS |
| 2026-10-08T18:19:37.493334+00:00 | 2026-10-08T18:20:00.759038+00:00 | create protected storage boundary dermairejrnlbkprod261008 | SUCCESS |
| 2026-10-08T18:20:00.761041+00:00 | 2026-10-08T18:20:03.875689+00:00 | allow single provisioning egress on dermairejrnlbkprod261008 | SUCCESS |
| 2026-10-08T18:20:03.875689+00:00 | 2026-10-08T18:20:06.188671+00:00 | create private container dermairejrnlbkprod261008/protected-evidence | SUCCESS |
| 2026-10-08T18:20:06.189672+00:00 | 2026-10-08T18:20:08.334295+00:00 | set indefinite legal hold dermairejrnlbkprod261008/protected-evidence | SUCCESS |
| 2026-10-08T18:20:09.833820+00:00 | 2026-10-08T18:20:12.944703+00:00 | create no-delete production journal role | SUCCESS |
| 2026-10-08T18:20:12.945704+00:00 | 2026-10-08T18:20:16.910101+00:00 | grant provisioning caller narrow evidence data role dermairejrnlprod261008 | SUCCESS |
| 2026-10-08T18:20:16.911099+00:00 | 2026-10-08T18:20:22.441498+00:00 | grant provisioning caller narrow evidence data role dermairejrnlbkprod261008 | SUCCESS |
| 2026-10-08T18:20:22.442498+00:00 | 2026-10-08T18:20:57.394355+00:00 | create purge-protected journal secret vault | SUCCESS |
| 2026-10-08T18:20:57.396355+00:00 | 2026-10-08T18:20:59.515783+00:00 | allow single provisioning egress on key vault | SUCCESS |
| 2026-10-08T18:20:59.516783+00:00 | 2026-10-08T18:21:04.891160+00:00 | allow production app subnet on key vault | SUCCESS |
| 2026-10-08T18:21:04.892162+00:00 | 2026-10-08T18:21:08.910793+00:00 | temporary provisioning secret officer | SUCCESS |
| 2026-10-08T18:21:13.983661+00:00 | 2026-10-08T18:21:26.633167+00:00 | generate independent nonexpiring HMAC in purge-protected Key Vault | SUCCESS |
| 2026-10-08T18:21:31.315307+00:00 | 2026-10-08T18:21:31.315307+00:00 | Encrypted Azure HMAC backup stored and byte-read-verified in protected-evidence | PASS; verification timestamp |
| 2026-10-08T18:21:32.444396+00:00 | 2026-10-08T18:21:38.851162+00:00 | enable production app system-assigned Managed Identity | SUCCESS |
| 2026-10-08T18:21:39.815818+00:00 | 2026-10-08T18:21:44.238020+00:00 | grant app no-delete role only on production intents container | SUCCESS |
| 2026-10-08T18:21:44.239019+00:00 | 2026-10-08T18:21:47.871653+00:00 | grant app read-only secret access scoped to one HMAC secret | SUCCESS |
| 2026-10-08T18:21:47.873652+00:00 | 2026-10-08T18:22:27.977509+00:00 | integrate production app with dedicated journal subnet | SUCCESS |
| 2026-10-08T18:22:29.051995+00:00 | 2026-10-08T18:22:34.551019+00:00 | route production outbound through integration subnet | SUCCESS |
| 2026-10-08T18:22:35.662210+00:00 | — | configure production journal names and pinned Key Vault reference | LOCAL_CMD_ARGUMENT_PARSING_REJECTED |
| 2026-10-08T18:23:58.263087+00:00 | 2026-10-08T18:23:59.976381+00:00 | configure production journal settings via structured ARM API | SUCCESS |
| 2026-10-08T18:33:12.468754+00:00 | 2026-10-08T18:33:25.961569+00:00 | Actual app MI writes/reads/verifies 15 synthetic v2 intents; conflict and 2/12-writer tests | PASS |
| 2026-10-08T18:34:38.557634+00:00 | 2026-10-08T18:34:42.553706+00:00 | Remove production runtime journal assignment for synthetic fail-closed drill | PASS; effective 403 observed 2026-10-08T18:36:46.290244+00:00 |
| 2026-10-08T18:36:46.145097+00:00 | 2026-10-08T18:36:48.752652+00:00 | Restore exact original assignment ID, principal, role and scope | PASS; recovery 2026-10-08T18:37:56.051129+00:00 |
| 2026-10-08T18:38:42.473183+00:00 | 2026-10-08T18:38:42.473183+00:00 | Add synthetic replay fixtures: one v2 and one signed v1; total 17 | PASS; verification timestamp |
| 2026-10-08T18:40:52.710153+00:00 | 2026-10-08T18:40:53.786747+00:00 | Explicitly disable photo versioning, Blob/container retention and restore policy using PUT | PASS |
| 2026-10-08T18:40:53.786747+00:00 | 2026-10-08T18:41:03.304437+00:00 | Disposable production photo upload/read/delete/retry/history drill | PASS; zero remaining fixture/history copies |
| 2026-10-08T18:42:30.075364+00:00 | 2026-10-08T18:43:05.052430+00:00 | create separate purge-protected recovery key vault | SUCCESS |
| 2026-10-08T18:43:05.053427+00:00 | 2026-10-08T18:43:08.036588+00:00 | allow one recovery/provisioning device egress | SUCCESS |
| 2026-10-08T18:43:08.036588+00:00 | 2026-10-08T18:43:12.613538+00:00 | temporary backup-restore officer on recovery vault | SUCCESS |
| 2026-10-08T18:43:15.596654+00:00 | 2026-10-08T18:43:16.852922+00:00 | Restore Azure-encrypted HMAC backup into independent recovery vault | PASS; value compared only in memory |
| 2026-10-08T18:43:18.754652+00:00 | 2026-10-08T18:43:22.023121+00:00 | remove temporary recovery-vault officer | SUCCESS |
| 2026-10-08T20:10:57.185374+00:00 | 2026-10-08T20:11:01.564087+00:00 | create separate private backup intents container | SUCCESS |
| 2026-10-08T20:11:01.565088+00:00 | 2026-10-08T20:11:03.784428+00:00 | protect backup intents with indefinite legal hold | SUCCESS |
| 2026-10-08T20:11:03.784428+00:00 | 2026-10-08T20:11:09.206536+00:00 | grant checkpoint owner no-delete access on backup intents only | SUCCESS |
| 2026-10-08T20:16:42.467868+00:00 | 2026-10-08T20:16:42.467868+00:00 | Verified independent 17-record backup and signed immutable inventory checkpoint | PASS; acknowledgement timestamp |
| 2026-10-08T20:18:23.513217+00:00 | 2026-10-08T20:19:15.728409+00:00 | Restart unchanged deployed app; actual journal readiness verified | PASS; 52.203 seconds |
| 2026-10-08T20:20:33.201533+00:00 | 2026-10-08T20:20:37.461718+00:00 | narrow checkpoint owner secret access to one read-only HMAC secret | SUCCESS |
| 2026-10-08T20:20:37.462720+00:00 | 2026-10-08T20:20:40.615493+00:00 | remove temporary primary-vault Secrets Officer | SUCCESS |
| 2026-10-08T20:20:40.616494+00:00 | 2026-10-08T20:20:42.557931+00:00 | protect vault control-plane deletion dermaire-journal-prod-kv | SUCCESS |
| 2026-10-08T20:20:42.558932+00:00 | 2026-10-08T20:20:44.739834+00:00 | protect vault control-plane deletion dermaire-jrnl-backup-kv | SUCCESS |
| 2026-10-08T20:23:22.850951+00:00 | 2026-10-08T20:23:37.770243+00:00 | Remove verification-only dependency archive and verify temporary SDK absence | PASS; no journal/key evidence deleted |

Setup corrections retained in evidence: rejected overlength storage-account name (no account created), Windows local command parsing of a Key Vault reference (no request sent; structured ARM update used), verification harness dependency/syntax preparation before any successful synthetic write, unsupported photo-policy PATCH (no policy changed), and first new backup-container listing error immediately after its role assignment. That last setup error recorded exception type only; its HTTP code was not retained. Fresh read-only properties/list succeeded at `2026-10-08T20:12:14.146885Z` with the same role/network and matching device egress, before any backup copy; delayed RBAC activation is an inference, not an instrumented root cause. No actual acknowledgement, privacy, signature, completeness or replay failure was accepted or bypassed. A local same-clock checkpoint collision test initially found a retry defect; exact-byte read-back now handles identical retries and rejects differing content.

Temporary dependency archive last-modified evidence: `2026-10-08T18:24:32.722627+00:00`; exact first upload time was not retained. It contained verification SDK packages only, no secret/.env/application build. Cleanup proved its absence and current temporary SDK absence. These limits are stated instead of inventing exact timestamps.

## Rollback, checks and release state

No production rollback was required. All accepted Phase 2 journal/key/holds/backups/roles and explicit safe photo policy remain protected. Runtime permission revocation was reversed exactly and recovery proved. Temporary broad secret-officer assignments and synthetic nonproduction photo/corruption containers were removed. Retained production synthetic intents, encrypted key backup, recovered key and checkpoint were deliberately preserved. Rollback metadata records original app identity/subnet/route state, setting names and photo policy state; safely reversing configuration must never remove evidence, expire keys, clear holds or re-enable retained photo copies. No plaintext rollback settings were saved.

Checks: starting HEAD/remote equality; fresh metadata/canonical catalog/role/PITR-window/WAL/health audits; actual MI key/network/journal operations; signed acknowledgement/idempotency/conflict/concurrency; real revoke/restore; explicit ARM photo policy and zero-copy drill; primary and independent-copy replay; Azure encrypted-key restore; protected full checkpoint and source stability; exact runtime assignments and temporary-role absence; lifecycle absence; unchanged deployment source/build; 180s restart proof; temporary harness cleanup. Local relevant checks **43 passed**; final full backend suite **678 passed**, 91 existing deprecation warnings. Python compilation and Git whitespace/secret-exposure checks are recorded with final delivery metadata.

Repository changes: checkpoint tool and five meaningful failure/verification tests; this report, sanitized evidence and production checkpoint/restore runbook additions. Commit/push/clean status is recorded in the delivered copy after commit to avoid a self-referential repository hash.

**Phase 3 was NOT started.** No target build, migration, traffic switch or live deletion-hook enablement occurred.

References: [storage firewall/service endpoint behavior](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security), [indefinite immutable storage legal holds](https://learn.microsoft.com/en-us/azure/storage/blobs/immutable-storage-overview), [Managed Identity in App Service](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity), [Blob service properties PUT](https://learn.microsoft.com/en-us/rest/api/storagerp/blob-services/set-service-properties?view=rest-storagerp-2025-08-01).
