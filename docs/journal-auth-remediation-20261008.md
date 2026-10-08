# Dermaire nonproduction Azure journal authorization milestone â€” 8 October 2026

**AZURE JOURNAL AUTH READY FOR PRODUCTION PHASE 2**

This verdict accepts the nonproduction journal authentication/authorization model as a prerequisite for a separately authorized production Phase 2. It does not certify production identity acquisition, networking, independent backups/completeness, historical coverage or Phase 2 completion. Production was untouched: zero production mutations; no deployment, app settings, credentials, identity, DB, photo policy or traffic changes. Management listing observed both apps without identities; no live data was read. Phase 3 did not start. Expiry remains disabled indefinitely.

## Root cause and access paths

The earlier test's first operation, Get Container Properties, used a Shared-Key-signed **service/container SAS**, HTTPS permissions read/create/list, on `https://dermairerehearsal261006.blob.core.windows.net/phase2-protection-2a58514a226a`. That API supports account SAS, not service/container SAS. Instrumented reproduction returned 403 AuthorizationFailure at this exact operation both with and without legal hold, including when write was added. Same-endpoint blob create/read/list succeeded under both SAS variants. Therefore this failure was an unsupported credential/API combination, not RBAC propagation, firewall, wrong endpoint, or a v2 concurrency defect. A second reproducible incompatibility: create-only SAS duplicate retry returns 403 UnauthorizedBlobOverwrite; adding write changes duplicate retry to expected 409 BlobAlreadyExists. No privacy check was removed or bypassed.

The management caller was Azure CLI signed-in **User**, object ID `54618e9f-4033-47e0-b642-ce415b8ba89a`, tenant `6845d6ca-1ec5-4c0e-9e9d-34130ce0a0b8`. Existing inherited subscription roles were Owner (two assignment records) and Contributor at `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c`. No broad role was added. Those control-plane rights fetched only the pinned nonproduction account key for synthetic fixture provisioning; the earlier data caller was the resulting SAS, not this user's RBAC identity. No key, token, connection string or HMAC value is recorded.

The successful journal data caller was **Microsoft Entra OAuth client credentials**, a separate ephemeral service principal: app ID `7d8b15df-bae0-4458-9934-be5b4d2fa67a`, object ID `42c20987-c42c-49a9-891b-153e779cd9ce`, tenant `6845d6ca-1ec5-4c0e-9e9d-34130ce0a0b8`. Its temporary credential stayed in memory and its app/service principal was deleted after the drill. Journal operations, source verification and replay all used this OAuth path. Synthetic photo fixture provisioning/deletion used a separate administrative nonproduction Shared Key client; that key was never passed to the journal writer/replay reader. No managed identity or production credential was used in this drill.

## Exact RBAC model and scope

Custom role **Dermaire Journal Read Write No Delete Nonprod**. Assignable scope (role-definition boundary, not an access grant): `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-readiness-nonprod-20261006`.

Effective journal assignment scope: `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-readiness-nonprod-20261006/providers/Microsoft.Storage/storageAccounts/dermairerehearsal261006/blobServices/default/containers/journal-concurrency-53e6f15af88f`.

The same principal temporarily received the same role on the isolated corruption fixture container at `/subscriptions/384c0376-d023-4a61-9dce-69ff8cbdcd0c/resourceGroups/dermaire-readiness-nonprod-20261006/providers/Microsoft.Storage/storageAccounts/dermairerehearsal261006/blobServices/default/containers/auth-corrupt-53e6f15af88f`. No account/resource-group/subscription data assignment was granted. All ephemeral assignments were removed after testing; the custom role definition remains restricted to the nonproduction resource group. No permanent staging identity or staging settings were changed.

Permissions:

- Control action: `Microsoft.Storage/storageAccounts/blobServices/containers/read` for the mandatory privacy/properties gate.
- Data actions: `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read` (read/list) and `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write` (block-blob create and compatible conditional duplicate conflicts).
- No delete, container write/create, policy management, keys, role management, Owner, Contributor or Storage Account Key Operator grant to this principal.

Write can otherwise replace blob contents; least privilege is enforced jointly by this custom role **and an independently provisioned indefinite container legal hold with protected append writes disabled**. Runtime cannot clear that hold. Existing protected intent overwrite was denied, and delete was denied. Access to a sibling photo container was denied with HTTP 403. Storage Blob Data Contributor would add delete and container administration, so it was not used. Azure exposes block creation/compatible retries through blob write; no claim is made that this action itself is create-only. Backup/checkpoint completeness remains an independent production requirement.

## Real Azure results

All test resources were in tagged `production=false` group `dermaire-readiness-nonprod-20261006`, account `dermairerehearsal261006`, Canada Central; account endpoint was correct and unchanged. The full successful rerun took 594.297 seconds and ran after firewall narrowing.

| Check | Observed result |
| --- | --- |
| OAuth container properties, signed v2 create/read/signature/content verification | PASS |
| Two concurrent writers, distinct canonical image sets | 2 acknowledged, 2 retained |
| Sixteen concurrent writers | 16 acknowledged, 16 retained |
| Ten further stress batches of sixteen writers | 210 successful calls including duplicate retries; 179 unique durable verified intents; zero lost |
| Thirty-two duplicate concurrent retries | One identical durable object; verified contents |
| Actual create-if-absent conflict | HTTP 409; original bytes unchanged |
| Lost response after successful write | Failure unacknowledged; deterministic retry verified; 180 unique intents |
| Replay fixture v2 added | 181 acknowledged/verified v2 intents before v1 addition |
| Protected overwrite denial | HTTP 409, BlobImmutableDueToLegalHold |
| Runtime delete denial | HTTP 403, AuthorizationPermissionMismatch |
| RBAC assignment removed | Actual access loss observed; write failed closed; replay callback never invoked |
| Same exact container assignment restored | Positive deterministic write/read retry passed |
| Mixed v1/v2 compatibility | Signed v1 in legacy path accepted; mixed replay passed |

The full first replay removed 1 restored synthetic account and 0 remaining matching image objects; normal account deletion handled both the explicit legacy image and the namespaced orphan. The kept synthetic account/photo survived. Orphan and legacy photo handling passed. Repeat replay removed zero accounts and zero images. Before/after source journal bytes were identical. Isolated SQLite data was synthetic, not exported production data.

Corruption rejection was tested on real Azure under the same OAuth/custom-role path after positive container access: invalid envelope raised the validation RuntimeError before callback invocation. Absent/inaccessible container also blocked replay without invoking callback. Effective access revocation used actual Azure role assignment deletion, not an in-process mock; restore used the same principal/role/container scope. Mixed legacy replay after the v1 fixture produced no further account/image mutations. Counts-only evidence is in `docs/evidence/journal-auth-20261008/azure-result.json`.

## Final nonproduction posture and cleanup

Network changed from default Allow/no IP restrictions to **default Deny**, bypass **None**, a single IPv4 host allowance **196.139.208.78** (one-host /32 equivalent; Azure stores a single IP), publicNetworkAccess **Enabled** for this restricted public endpoint. No VNet, resource-instance or IPv6 allowances were added. Private endpoint networking was not provisioned. If this device's public IP changes, this account will deny it until a deliberate scoped update.

Public blob access **false**; containers private; HTTPS-only **true**; minimum **TLS1_2**. Shared Key remains enabled by Azure default (`allowSharedKeyAccess=null`), confined to existing administrative fixture access rather than runtime. It is a residual administrative capability, not a grant to the test principal. Prefer disabling Shared Key on the future dedicated production account after proving all required management/backup workflows use Entra.

Temporary synthetic journal, photo and corruption containers were deleted and absence checked; temporary legal hold was cleared solely for fixture cleanup by the provisioning identity, never the runtime identity. Test app/service principal and assignments were removed. No durable nonproduction business journal or HMAC secret was created. Only the custom role definition and narrower network/privacy/TLS posture remain. An earlier harness run stopped on parsing an empty successful role-delete response; the helper now handles that response, the interrupted-run principal/assignments/containers were removed, and the complete rerun supplies the accepted evidence.

## Recommended production Phase 2

Use the application's system-assigned Managed Identity with `ManagedIdentityCredential`, dedicated independent journal account and equivalent container-scoped custom role; user-assigned identity is supported via explicitly selected client ID when isolation/reuse requires it. Current production and staging apps have no identity. The source now supports this path and rejects connection-string/identity ambiguity and credential-bearing or non-HTTPS account URLs. Nothing was deployed.

Exact staged enablement steps are in `docs/deletion-journal-restore.md`: separately authorize future Phase 2; provision independent account/protected backups/checkpoints; prefer private endpoint/VNet and disable public network; establish WORM outside runtime control; enable app identity; assign custom role only to container; configure account URL/container/independent HMAC/required flag; freeze legacy writers and verify actual app-identity token acquisition, synthetic operations, revoke/restore and off-live replay before enablement. Production storage/account keys, identities, settings and traffic remain unchanged here. This verdict permits preparation of that milestone, not automatic execution.

## Files and local checks

Changed: `backend/.env.example`, `backend/app/core/config.py`, `backend/app/services/deletion_journal.py`, `backend/requirements.txt`, new `backend/app/tools/validate_journal_auth_nonproduction.py`, new `backend/tests/test_journal_identity.py`, `docs/deletion-journal-restore.md`, this report and five safe evidence JSON files. Local relevant checks: **38 tests passed**, one existing Starlette deprecation warning; the first local run encountered temporary-folder access errors, resolved by using an isolated task temp path. Python compile and git whitespace checks passed. Final commit/push/clean state are recorded in the delivered copy to avoid a self-referential commit hash in the repository report.

References: [Get Container Properties authorization](https://learn.microsoft.com/en-us/rest/api/storageservices/get-container-properties), [Put Blob permissions](https://learn.microsoft.com/en-us/rest/api/storageservices/put-blob), [storage RBAC permissions](https://learn.microsoft.com/en-us/azure/role-based-access-control/permissions/storage), [immutable storage](https://learn.microsoft.com/en-us/azure/storage/blobs/immutable-storage-overview).
