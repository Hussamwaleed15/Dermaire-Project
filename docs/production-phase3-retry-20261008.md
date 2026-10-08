# PHASE 3 HALTED/ROLLED BACK — retry on 8 October 2026

Halted at Phase 3A before production mutation. No deployment or rollback occurred;
no real user data was modified. Phase 4 disposable production smoke has NOT started.
The new source correction is preparation only and is not an authorized rollout-only
replacement for the requested eed61b8 build.

## Source privacy gate: FAIL on eed61b8

Initial local HEAD and independently queried origin/main both matched
`eed61b89c4a4dcdad2dc1d63afb02eacd726377b`; working tree was clean.

Fresh audit found a storage identity gap beyond the earlier missing cleanup hooks.
Capture and check-in request IDs are deterministic and were also used as Blob names.
Failed-upload cleanup records a photo intent for that name. Retrying an uncommitted
request reused the same name; upload_capture allowed overwrite=True. A completed
cleanup followed by a successful retry therefore leaves the new active photo covered
by the old permanent deletion intent. Offline replay can delete that new photo.
With pending cleanup, retry could also overwrite the orphan bytes without a new
journal intent. This is not safe to deploy as eed61b8.

Four synthetic regression cases fail on original eed61b8 API source, and pass with
the correction: captures/check-ins, each with completed/pending external cleanup.
The tests check active-photo readability, preserved DB row, no account deletion,
removal of only retired orphan keys, immutable source journal, and idempotent
successful-request retry. No Azure provider calls or production data are used.

Correction: keep deterministic request IDs in DB; allocate a fresh UUID4 Blob name
for every actual upload attempt; use atomic create with overwrite=False. Existing
committed retries return their stored row and do not upload again. Storage names
still match the owner namespace and orphan reconciliation grammar. No migration,
new journal schema, provider flag, key, retention or infrastructure change.

| Audited path | Source finding |
| --- | --- |
| Account DELETE /users/me | Owner lock; v2 signed durable account intent verified before photo namespace/explicit image/DB deletion |
| Explicit photo deletion API | No standalone endpoint exists |
| Applied orphan reconciliation | Owner lock, age >=24h, reference check, verified photo-only intent before delete |
| Failed-upload cleanup, capture and check-in | Reacquired owner lock/reference check; verified photo-only intent; retry identity gap corrected in this attempt |
| Storage delete_image/delete_owned_images | Low-level permanent-delete primitives; application callers are account intent or photo intent guarded; retention/version checks fail closed |
| Storage upload/retry | Original overwrite/name reuse failed gate; fresh attempt keys and create-only upload now tested |
| Offline replay | Full signed inventory verification; explicit image intents do not authorize account deletion; independent source remains unchanged |
| Background/maintenance | Only identified photo maintenance command is reconcile_images; apply requires PostgreSQL locks and uses audited service; no separate background photo remover found |
| Nonproduction rehearsal deletion | Explicit isolated nonproduction accounts/resources and synthetic fixtures; test DB teardown is local SQLite |
| Other DELETE endpoints | Experiment/routine/doctor deletion routes preserve history via state transitions |

The user's broader requirement also says every permanent removal of *user* data
must be journal-covered or proven non-user/nonrecoverable. Product DELETE still
hard-deletes the owner-specific Product and can cascade ProductIntelligence;
it has no journal intent and is not proven non-user/nonrecoverable. It is not a
photo/account deletion path, but cannot be silently excluded from that broader
requirement. No full all-user-data gate PASS is claimed. This path remains a
source-scope blocker requiring a reviewed privacy-compatible treatment before a
future rollout; it was not changed into an account-delete intent.

## Exact production changes and fresh observations

Production changes in order/timestamps: **none**. No traffic/write, settings,
permissions, policy, data, monitoring or deployment mutations were submitted.
Read-only observation window: 2026-10-08 20:46:58.214355–20:47:16.140165 UTC
(23:46:58–23:47:16 Cairo). Full sanitized resource IDs/settings names and current
artifact metadata are in the adjacent evidence/production-phase3-retry-20261008
folder. Observed configuration/artifact agrees with the prior Phase 3 inventory.

Target: eed61b89c4a4dcdad2dc1d63afb02eacd726377b. Target package/hash and new
deployment ID: **not created**. Current production output.tar.zst SHA-256:
`9a0e604b37507dfda5be119ae931a0f09f30fc3c28ef0cf3143b55e8ec7dff4b`;
145453718 bytes; modified 2026-10-03 19:06:44.283262 UTC. Not replaced.

## App Service final observed settings

App: dermaire-rg/dermaire-api, Running, system Managed Identity, route-all enabled
and journal subnet integration preserved. Startup remains
`python -m uvicorn app.main:app --host 0.0.0.0 --port 8000`.
Always On=false; Health Check path absent; native HTTP logging=true, directory
limit 100 MB. Structured target application logging not deployed; reviewed
no-access-log change not applied. HTTPS-only=true; minimum site/SCM TLS=1.2;
FTPS-only. ENVIRONMENT=production, DEBUG=False. App Settings provider timeout and
container startup time limit absent; deployment remote build=true. No security
settings weakened. Logging remains the old configuration, not certified privacy-safe.

## Provider guard

CONTEXTUAL_AI_ENABLED=`true`, unchanged. AZURE_VISION_ENABLED absent, unchanged;
Vision endpoint/key both absent. Content Safety endpoint/key both absent. OpenAI
endpoint/key/deployment/API-version all present (values withheld). Source defaults
Vision to false; target provider timeout default=20 seconds. Effective old-process
settings, including embedded dotenv overrides, were not introspected. No effective
old-worker/provider-call success is claimed. Target Safety Engine/clinician
precedence/fail-soft deployment checks were not reached. No provider was enabled.

## Health, runtime, hooks and journal/blob

Fresh /health=200; /health/live=404; /health/ready=404. These are old-worker
observations. No new worker or changed boot ID; readiness <=180 seconds is NOT
measured/proven. The unchanged artifact previously audited lacks journal hooks;
deployed account/photo cleanup hook activation is NOT proven and remains pending.

Phase 1 historical evidence proves DB revision 20261008_01, dermaire_runtime,
verify-full and separated migrator grants. No fresh DB session/catalog audit or
new deployed-process role proof was completed after this source-gate halt.

Fresh settings match Phase 2 journal account/container, required=true, Key Vault
HMAC reference present and journal connection string absent. Fresh app MI role
inventory contains exactly two assignments: Journal Read Write No Delete scoped
to dermairejrnlprod261008/blobServices/default/containers/intents, and Key Vault
Secrets User scoped to deletion-journal-hmac-v1. No broad role was introduced.
Role-definition internals/data-plane health were not re-proven this attempt.

Phase 2 historical evidence: independent protected private journal, nonexpiring
HMAC, indefinite journal retention, protected checkpoint and private photo storage
with retention/versioning disabled and no retained copies. All untouched. Fresh
journal/key data-plane, key expiry and Blob policy/inventory audit were NOT
completed after source failure; historical evidence is not relabeled fresh.
RTO <=30m remains a target, not fully certified.

## Monitoring/action group/drill

Fresh monitoring inventory shows only the staging workspace, action group and
eight staging alert rules; no production monitoring resources found. Production
availability/readiness, 5xx, latency/startup, DB, Blob, journal and provider rules
not installed. Production action group not created; Gmail/school receiver and
production privacy/retention/query scopes not freshly verified. Historical Gmail
proof was not challenged. Alert drill NOT run; no Fired/Resolved/ActionsTriggered
claim and no temporary drill rule to clean up.

## Rollback

Sanitized current artifact metadata/settings names archived. The unchanged old
production artifact is pre-journal and cannot reopen unrestricted writes as a
rollback after activation. No independently verified privacy-compatible built
rollback archive was created here. A future deploy must close that gate; without
a compatible archive, failure requires closed traffic/writes. Rollback not needed
because no production deployment/mutation occurred. Old package bytes/plaintext
settings were not copied into evidence or outputs.

## Tests and delivery

Original-source regressions: 4 failed as expected (source restored immediately).
Corrected regressions: 4 passed. Focused journal/deletion/image suite: 105 passed,
one existing deprecation warning. Initial focused run: 98 passed/3 setup errors
caused by default Windows temporary-folder permissions; corrected via a workspace
basetemp and rerun successfully, without production access.

Full backend suite: **688 passed**, 91 existing deprecation warnings, 88.21 seconds.

Git whitespace/compilation checks: PASS. Source correction/evidence commit identity and verified main push/clean status
are recorded in the delivered output report after commit to avoid a self-reference. This is not a deployment.

**Phase 3 remains HALTED. Phase 4 has NOT started.**
