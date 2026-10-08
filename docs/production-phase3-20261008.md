# PHASE 3 HALTED/ROLLED BACK — 8 October 2026

**Halted at Phase 3A before production mutation/deployment. No rollback was needed.**
Phase 1 and Phase 2 remain complete. Phase 4 disposable production smoke has NOT
started. No real user data was modified. No traffic, write exposure, credentials,
permissions, journal/key expiry, storage policy or provider settings were changed.

## Failed source gate and correction

Clean local HEAD and independently queried remote main matched
`80707ec80e70a12027a7d6e9c2e25e8cd8eb3090`. Account deletion records a verified
v2 intent before external/DB deletion. Source review found both applied orphan
reconciliation and failed-upload cleanup called `storage.delete_image` without
recording a durable intent. This fails Phase 3A's complete photo-cleanup hook gate.
Recording a normal account intent here would incorrectly authorize account and
namespace deletion during recovery.

Corrected source introduces `record_photos`: the unchanged signed schema-2
envelope uses a domain-separated `photo-only-owner` HMAC token, which never
selects an account via replay's `owner` tokens. Replay cleans explicit image
tokens only. Both cleanup paths persist and read/verify before deleting a Blob.
No photo-delete API, schema migration, key rotation or resource changes occur.
Existing replay/checkpoint readers accept the v2 format. Source compatibility is
locally tested; no new Azure protected-store rehearsal or deployment is claimed.
The corrected source must be the target of the next fresh rollout; `80707ec`
itself does not pass this gate. This attempt did not resume later rollout phases.

## Ordered observations and production changes

**Production changes: none.** All observations are 8 October 2026 UTC; Cairo is
UTC+03:00. Repo verification preceded the fresh Azure checks.

| UTC observation | Result |
| --- | --- |
| 20:35:06.969845 | Fresh read-only DB catalog/WAL observation; TLSv1.3; WAL age 57.386334s, zero failures |
| 20:35:35.921236 | Resource/recovery/configuration gate PASS; no intervening DB configuration operations; PITR proof remains within 24h |
| 20:36:40.136044–20:36:55.428368 | App Service, settings, runtime MI assignments, monitoring inventory, health endpoints and artifact fingerprint captured |

Fresh columns/indexes/constraints/objects/schema/functions/triggers/policies,
runtime roles/memberships/grants and other catalog checks match Phase 1 after
normalizing observer visibility. PITR proof expires 9 October 15:03:38.626468 UTC
(18:03:38 Cairo). RTO ≤30 minutes remains uncertified.

## Production artifact and rollback

Requested target: `80707ec`; **new package/hash/deployment ID: not created**.
Current `/home/site/wwwroot/output.tar.zst` fingerprint:
`9a0e604b37507dfda5be119ae931a0f09f30fc3c28ef0cf3143b55e8ec7dff4b`,
145453718 bytes, mtime 3 October 19:06:44.283262 UTC.
Current deployed source lacks the journal service and deletion hooks. It is
**not privacy-compatible for unrestricted-write rollback after journal activation**.
Sanitized rollback metadata/settings names and hashes are archived in evidence;
the old package bytes/plaintext settings were not copied to local outputs.
An independently archived verified privacy-compatible rollback package has NOT
been established in this attempt. Do not deploy until that gate is closed; safe
fallback requires traffic/writes closed if no compatible package exists.

## App Service final observed state

App `dermaire-rg/dermaire-api`: Running, system-assigned MI, HTTPS-only true,
TLS and SCM minimum 1.2, FTPS-only, existing journal subnet integration and
route-all true. No changes applied.

| Setting | Final observed value |
| --- | --- |
| Startup | `python -m uvicorn app.main:app --host 0.0.0.0 --port 8000` |
| Always On | false |
| Health Check | absent |
| Native HTTP logging | true; directory limit 100 MB |
| Structured target logging | present in source; target not deployed |
| ENVIRONMENT / DEBUG | production / False |
| Provider timeout / startup time limit | absent from App Settings |
| SCM_DO_BUILD_DURING_DEPLOYMENT | true |
| Access restriction | existing Allow all; unchanged |

The reviewed `--no-access-log`, Always On, `/health/ready`, bounded startup and
production telemetry settings have NOT been applied.

## Providers

`CONTEXTUAL_AI_ENABLED=true` in production App Settings, unchanged.
`AZURE_VISION_ENABLED` absent; Vision endpoint/key absent from App Settings.
Content Safety endpoint/key absent from App Settings. OpenAI endpoint, key,
deployment and API-version settings present. No values disclosed.
Effective target defaults would disable Vision and use local safety rules;
effective old-worker settings, including possible embedded dotenv overrides,
were not fully introspected before halt. No enablement or provider calls occurred.
Target safety/clinician precedence and fail-soft deployment gate remain pending.

## Health, runtime, journal and Blob

`/health` HTTP 200; `/health/live` HTTP 404; `/health/ready` HTTP 404.
These are old-worker observations, **not new-build smoke**. New-worker boot ID,
startup/readiness timing against 180s and deployed hook activation: NOT PROVEN.
Current artifact source proves hooks inactive. No real/disposable account deleted.

Runtime Managed Identity has exactly two enumerated assignments: no-delete journal
role scoped to `dermairejrnlprod261008/blobServices/default/containers/intents`,
and Key Vault Secrets User scoped to the one HMAC secret. No broad roles added.
Journal account/container match Phase 2; required=true, pinned Key Vault reference
present, journal connection string absent. Phase 1 runtime catalog/grants match;
fresh read-only DB session reports `current_user=dermaire_runtime`, readonly=on, TLSv1.3. New deployed-process identity remains unproven because no deployment occurred.

Phase 2 proved private independent journal, nonexpiring HMAC, indefinite retention,
17/17 matching independent checkpoint, and private photo storage with all retention
policies disabled and zero retained copies. Those policies/resources were untouched.
Fresh journal/key data-plane health, expiry and Blob policy/inventory audit were
not completed before the source halt; Phase 2 evidence is historical, not relabeled
as fresh. No historical journal coverage is claimed.

## Monitoring and drill

Fresh subscription monitoring inventory contains the staging-only workspace,
action group and eight alerts; no production monitoring resources were found.
Production diagnostics/query scopes, retention/access, Gmail/school receiver
configuration and production-native availability/readiness/5xx/latency/startup/
DB/Blob/journal/provider rules: NOT installed/verified in this attempt.
Existing staging Gmail proof was not challenged or re-requested.
Alert drill: NOT run because rollout stopped before production monitoring setup;
no Fired/Resolved/ActionsTriggered or mailbox receipt claim is made.

## Validation and repository delivery

Relevant tests: 83 passed (one existing deprecation warning), including photo-only
replay preserving the account/sibling photos, retry/source immutability and both
cleanup paths refusing deletion on journal failure. Full backend suite: **684 passed**, 91 existing deprecation warnings, 82.94s. Python compilation and Git whitespace checks passed.
Sanitized evidence includes fresh resource/WAL gate, normalized catalog comparison,
App Service/provider/MI/monitoring inventory and artifact hashes. Commit/push and
clean status are recorded in the delivered report after commit to avoid a
self-referential source hash.

**Phase 3 is not complete. Phase 4 has NOT started.** Resume only with fresh
preflight, corrected tested source, privacy-compatible rollback archive and every
remaining Phase 3 deployment/operational/monitoring/health gate.
