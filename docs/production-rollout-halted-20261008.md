# Production rollout — halted at Phase 0

Verdict: **ROLLOUT HALTED/ROLLED BACK** (halted; no rollback needed).

Fresh read-only preflight performed on 8 October 2026, approximately 14:02–14:05 Africa/Cairo (UTC+03:00). User separately authorized only the reviewed production rollout. No production mutation, restart, deployment, traffic switch, SQL write or fixture creation occurred.

## Failed gate and required evidence

Complete recoverable-copy inventory is unknown. Azure server retention of seven days does not establish the lifetime or absence of off-platform exports, restored targets, snapshots, archives or legal holds. No complete owner-attested inventory was found in the reviewed readiness documents or accessible resource inventory. The user's Phase 0 step 4 explicitly requires stopping on unknown inventory. No expiry or traffic changes were enabled.

To resume, provide an authoritative inventory/attestation covering all production DB/photo recoverable copies, locations, creation/expiry dates, holds, restored targets and quarantine lifetime, including off-platform copies (explicitly declare absence where applicable), with accountable release/recovery/privacy/on-call owners. Every recoverable horizon must satisfy <=35 days and quarantine <=7 days before the conditional policy can be accepted. Azure discovery alone cannot attest off-platform absence. Re-run fresh preflight after this evidence is available.

## Fresh results

- Local checkout clean at `7227f146cdf4619e7ea376bc2cec8efa0922cdd6`; `origin/main` matched after successful fetch.
- Azure authenticated to the intended subscription; production App Service `dermaire-api` Running, HTTPS only. Last modification metadata: 2026-10-05T16:41:23.916666.
- Python 3.12; startup `python -m uvicorn app.main:app --host 0.0.0.0 --port 8000`; Always On false; Health Check unset; HTTP logging enabled; detailed errors/request tracing disabled; minimum TLS 1.2.
- Fresh GET `/health/live` and `/health/ready` both returned HTTP 404. This legacy deployment cannot establish the new readiness gate; no restart timing was measured.
- PostgreSQL `dermaire-db-server`: Ready, version 18, retention 7 days, geo backup Disabled; earliest restore metadata `2026-10-02T07:14:08.190528+00:00`. Latest usable restore point/RPO not independently proved. A backup-list CLI attempt rejected its server-name argument; no backup mutation occurred and no successful backup inventory is claimed.
- Photo account `dermaireimg479341`: StorageV2, HTTPS only, TLS1_2, account public Blob access false. Blob soft delete explicitly false; versioning and container deletion retention returned null. Null is not explicit policy verification. Container access, historical object/version/snapshot/deleted inventory, holds and immutability are not verified.
- No production deletion-journal app-setting names were present. Independent journal durability, backup, network/key protection and completeness remain unverified.
- Production diagnostic-settings list returned empty. Subscription resource list showed the eight staging rules and staging action group; production monitoring installation/delivery not verified or changed.
- Exact read production flags: `ENVIRONMENT=production`, `DEBUG=False`, `CONTEXTUAL_AI_ENABLED=true`. Other real-provider enablement flags were absent from returned setting names; effective defaults/provider operation not verified. Credential presence is not enablement proof. All flags preserved.
- Resource discovery returned no matching backup/vault resource types; this is not proof of absent exports or recoverable copies.

## Unexecuted rollout work

Fresh DB catalog/version-patch/collation/TLS/grants/ownership/schema audit, role creation/separation, unique-index adoption, Alembic stamp/check and negative-permission smoke were not executed. Historical administrator use remains historical evidence; no new credential-separation result is claimed. No credentials were rotated.

Exact current production built artifact/dependency fingerprint and secure settings archive were not acquired before the stop; do not infer rollback readiness from a source commit. Historical privacy-compatible staging rollback archive remains documented at `/home/dermaire-rollback-0f97dc2.zip`, SHA256 `7ce9bbbd5a459fa73f2268f2e9cecd63af948d4ebf3639206402c6ea1b656ff8`; its current availability/hash was not reverified. Never reopen writes using a pre-journal build. No rollback was needed because nothing was changed.

Journal provisioning, Blob changes, operational settings, monitoring setup, deployment, traffic opening and production smoke were not performed. No deployment ID/hash or changed boot ID exists for this attempt. No disposable accounts/photos/blobs were created, so no fixture cleanup was necessary. Existing production traffic state was preserved; no new opening or privacy compliance claim is made.

## Validation and evidence handling

Read reviewed release runbook, least-privilege SQL, baseline adoption SQL, journal recovery design and continuation/closure evidence. Ran git cleanliness/commit/fetch checks and Azure read-only management/HTTP probes above. The previously reported 640-test pass belongs to readiness closure; backend tests were not rerun for this documentation-only halted attempt. No secrets, raw settings values beyond operational booleans/environment, production records or photo names were recorded. Documentation verification and push status are reported in the accompanying chat.
