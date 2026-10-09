# DERMAIRE PRODUCTION ROLLOUT COMPLETE — Phase 5, 9 October 2026 Cairo

All final gates passed. Phase 1–4 evidence remains valid for the freshly verified
same deployment and policies. The accepted-image production gap is now closed
through the actual product contract: **there is no standalone image DELETE API;
accepted stored images are deleted through DELETE /api/v1/users/me**. No source,
deployment, external provider enablement, retention, RBAC or key setting changed.
Only two fresh disposable synthetic accounts, one synthetic check-in and one
AI-rendered silicone mannequin image were created. No real person image was used.
No direct SQL/storage deletion or validation bypass was used.

## Fingerprint and exact verification window

- Source: `5b5c7b694a4e6e55ff338a72c88e53848e778cc5`.
- Starting docs/main: `92f45a7e7893b8c2a31fcaa70f04b07a69ab8341`, clean and origin/main matching.
- Deployment: `36572db2-b7b5-4557-a82c-65caff6201a1`, status 4, active/complete.
- Freshly verified all **119 deployed manifest files** before and after the test.
- Built ZIP SHA256: `789749b6b26db786d636098388601bb68d713b93d5026496cb121e0fc6efa813`, 143,160,195 bytes. Retained local rollback ZIP freshly hash-verified.
- Worker unchanged: `b8d0f702-15e9-4f1c-9499-c400282b7c90`.
- Precheck UTC: 2026-10-09T06:47:57.442429+00:00–2026-10-09T06:48:48.832264+00:00; Cairo: 2026-10-09T09:47:57.442429+03:00–2026-10-09T09:48:48.832264+03:00.
- Synthetic run UTC: 2026-10-09T06:52:20.172825+00:00–2026-10-09T06:52:48.940315+00:00; Cairo: 2026-10-09T09:52:20.172825+03:00–2026-10-09T09:52:48.940315+03:00.
- Final runtime/manifest verification UTC: 2026-10-09T06:54:19.990930+00:00–2026-10-09T06:55:03.542100+00:00.
- Final policy verification UTC: 2026-10-09T06:54:52.297277+00:00–2026-10-09T06:55:37.250450+00:00.
- Final configuration observation UTC: 2026-10-09T06:55:16.116288+00:00.
- Synthetic run identifier: `fe1e5e7b-f569-4793-bfee-768dd1021698`; account/capture/blob identifiers are represented only by hashes or synthetic labels in committed evidence.

## Accepted image, ownership and deletion evidence

Original generated opaque PNG: **1024×1536**, SHA256
`64ae129386e4773a8d857f2ceb2d9932b5127122e2688ed804ab79342c825bdf`. Exact production quality rules accepted
it locally and in the deployed runtime; the actual multipart POST /captures
returned **201, accepted, azure_blob**. The first generated candidate was rejected
locally for excessive face scale; only the reframed accepted fixture was submitted
to production. Validation thresholds were unchanged.

The private stored image had **1708444 bytes**, LastModified
2026-10-09T06:52:41+00:00; inventory after upload was **one live object,
zero deleted/versions/snapshots**. The application strips metadata and re-encodes
PNG, so its byte hash differs from the uploaded original. Owner application read
returned **200**, correct stored length, SHA256 `bb9a51ba8a1ee246b422a6c99e876485a537c3a7ace2248de7d938e973553c34`.
Anonymous application read returned **401**; cross-account image and capture reads
returned **404**. Account A and its independent check-in remained intact until
intended account deletion; account B remained accessible after A was deleted.

No photo-only intent is claimed: the public product contract uses an **account-v2
intent including the accepted image token**. The hash-verified deployed chain
`delete_account -> journal.record -> _persist` creates and verifies an exact signed
read-back before any Blob delete or business-row removal. Live signed inventory
then independently verified owner/path binding and exact image-token inclusion.
Blob LastModified preceded the successful response. This is deployed-source ordering
plus live durable evidence, not separate instrumentation of the exact destructive
call or SQL commit timestamp. No production code was instrumented or patched.

| Synthetic account | Signed v2 intent path SHA256 | LastModified UTC | DELETE response completed UTC | Image tokens covered |
| --- | --- | --- | --- | --- |
| A | `30c656b9e09b1b79a4db1e8b13ac89c04a69da0a955773bee729f12c647ae826` | 2026-10-09T06:52:44+00:00 | 2026-10-09T06:52:44.350931+00:00 | 1 |
| B | `a2059d80200b40a90edc1729a58f31c0ba89dc364107af91be6b97ecbcbc927d` | 2026-10-09T06:52:46+00:00 | 2026-10-09T06:52:46.793355+00:00 | 0 |

Both real account deletes returned **204**; retries returned **204** and created no
additional intent. Prior tokens returned **401** for profile/Home; A's image read
also returned **401**. The journal increased **25→27** verified signed intents.

Final fixture Blob inventory through Azure include-deleted/version/snapshot listing:
**live=0, deleted=0, versions=0, snapshots=0** for both namespaces. Fresh final
whole photo-container counts were also **0/0/0/0**. Photo versioning, blob/container
soft-delete and restore policy remain disabled under the explicit privacy policy.

## Cleanup and unrelated-data preservation

Every owned/linked business model and both user records: **zero live synthetic rows**;
raw actor audit rows: **zero**. Five scrubbed synthetic audit rows remain by design
(A=3, B=2), with empty details/null IP/pseudonymous actor. Two append-only signed
synthetic account intents remain indefinitely. Neither retention artifact was deleted.
No temporary alert rule or disposable Blob remains.

All **16 unrelated business/audit tables'** counts and deterministic aggregate
hashes matched before upload and immediately before/after each account deletion.
Only aggregate counts/hashes left PostgreSQL; no unrelated raw record was returned
or inspected. No real-user row was modified by this run. This establishes preservation
across the measured test window and does not claim a whole-day activity audit.

## Final health, identity, security and providers

Pre/post `/health/live=200` and `/health/ready=200`; database, storage and deletion
journal available. Both current_user/session_user remain **dermaire_runtime**;
revision **20261008_01**, TLSv1.3 with verify-full. Same worker remains stable;
no disruptive restart was needed to repeat the historical startup measurement.

Required signed journal healthy; primary/independent containers private with
indefinite legal holds, protected append overwrite disabled, lifecycle absent.
HTTPS/TLS1.2 minimum; shared-key disabled; network default Deny/bypass None.
Key Vault HMAC reference resolved, matches enabled vault secret, expiry null.
Journal/key expiry remains **disabled indefinitely**. Managed Identity auth passes;
runtime retains exactly Journal Read Write No Delete on the intents container and
Key Vault Secrets User on the single HMAC secret, without broad runtime access.

Providers unchanged: **CONTEXTUAL_AI_ENABLED=true**; **AZURE_VISION_ENABLED absent,
effective false**; Vision endpoint/key absent; Content Safety endpoint/key absent.
OpenAI endpoint/key/deployment/API version remain configured (values withheld).
Phase 4 provider/safety evidence is preserved; Phase 5 did not invoke a provider.

All **11** production monitoring rules enabled, **zero** unresolved/Fired alerts,
**zero** temporary rules. Prior Phase 3 alert delivery evidence remains documented;
no unnecessary delivery/failure drill was repeated.

Production logging: **21/21** request events, **29** scoped structured events;
zero unexpected keys, raw emails, token/body/exception markers, raw route/actor/user/
patient identifiers, or HTTP 5xx. Two journal-write-available events. Only aggregate
telemetry counters were exported. Native request-bearing HTTP logs/detailed errors/
failed-request tracing remain off; structured logging and bounded retention intact.
Final health observations UTC: live 2026-10-09T06:55:08.094708+00:00,
ready 2026-10-09T06:55:08.707595+00:00, with subsequent final config
health also **200/200**.

## Rollback, recovery and residual operational limits

Privacy-compatible exact built rollback is available and freshly hash-verified;
Phase 3 documented OneDeploy path/staging restoration remains applicable. Keep
reviewed journal/runtime/provider settings, close traffic until readiness/privacy
checks pass. Older pre-journal or earlier audit-isolation-defective builds are not
approved unrestricted-write rollback targets. No rollback was required/performed.

Independent backup remains **17 signature-verified records**, exactly matching the
signed checkpoint SHA256 `85da8c8bb93cc3b787828d20025c093c45b049a99b7ea634b00c9c4210970071`;
protected evidence still has the checkpoint and encrypted key backup (two objects).
This is the frozen Phase 2 snapshot at **2026-10-08T20:16:42.467868+00:00**, not a
claim of continuous replication or coverage of all 27 current intents. The primary
append-only journal is authoritative. Before recovery, freeze writers and repeat
the complete signed checkpoint/reconciliation; remain offline on uncertainty.

**Full end-to-end RTO <=30 minutes is still NOT certified.** No new restore/RTO
proof was performed. Legacy/unknown OneDrive copies remain **unapproved restore
sources**. Exceptional restore requires recovery/privacy review, complete signed
tombstone replay and verification before traffic/writes resume. Journal/key expiry
remains disabled indefinitely because legacy recoverable copies cannot be excluded.

Historical current-worker startup **179.672s <=180s**, only **0.328s headroom**,
remains a post-rollout optimization/risk. Stable current health does not establish
extra cold-start capacity, sustained load tolerance or a better RTO. Checkpoint
freshness/manual cadence remains an operational responsibility.

## Checks and delivery

**130 relevant isolated synthetic tests passed**, 3 existing deprecation warnings,
20.04s: capture quality, account deletion, signed journal, image infrastructure and
error privacy. No application source changed. JSON parsing, evidence sanitization,
secret/raw-data screening and Git whitespace checks are required before the docs
push. Documentation/evidence are delivered to the same main; final commit/push/
clean matching status is supplied in the user-facing delivery report to avoid
self-referential commit identity in this file.

**DERMAIRE PRODUCTION ROLLOUT COMPLETE.**
