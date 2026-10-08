# Production Phase 2 — halted at source durability gate, 8 October 2026

**PHASE 2 HALTED/ROLLED BACK.** Halted before any production mutation; no rollback was necessary. Phase 3 was NOT started. The new application build was NOT deployed. No real user data was read or modified in this attempt.

## Fresh preflight and ordered actions

- Local repository was clean at `1d01bfaf44d503377a64745297c984a96969ae07`; cached origin/main matched. A fresh `git ls-remote origin refs/heads/main` independently confirmed that exact remote commit.
- Azure CLI authentication was available and subscription Enabled. Read-only Azure resource inventory found existing production app `dermaire-api`, DB `dermaire-db-server`, and photo account `dermaireimg479341` in `dermaire-rg`. No dedicated production journal account appeared in that inventory; this is not a complete external journal inventory.
- Reviewed `deletion-journal-restore.md`, `production-release-runbook.md`, Phase 1 evidence, journal source, account-deletion hook, replay command and journal tests.
- **2026-10-08T17:15:15.530316+00:00 UTC / 20:15:15.530316 Cairo:** exact source class executed against a deterministic isolated in-memory storage double with two concurrent synthetic writers. Both writers succeeded, expected two image tokens, retained only one; remaining envelope signature verified. **Durability gate FAIL.** Production execution stopped immediately.

Earlier read-only action instants were not captured individually; no exact mutation times exist because there were no production mutations. Full live DB role/revision/grant, health, backup/WAL, settings, Blob policy/history and rollback-metadata preflight was NOT completed. Phase 1 reports remain historical evidence, not a refreshed attestation from this attempt.

## Failed gate and scope

`DeletionJournal.record` downloads the existing owner envelope, merges tokens in memory, then calls `upload_blob(..., overwrite=True)` without an ETag condition or atomic append. Two writers can read the same previous state; the last replacement erases a token acknowledged by the other writer. HMAC detects altered content, but cannot detect a valid older/subset envelope signed by an authorized writer. The included counts-only evidence records two successful writers, one retained token, and a valid signature; no production records or credentials are included.

Reproduction: load only the exact `DeletionJournal` class from the current source AST, provide hashlib/hmac/json and a synthetic ResourceNotFoundError, inject a private fake container and synthetic key. Place a two-party barrier in download readall so both writers capture the absent initial state before either upload. Call record for one synthetic owner with distinct synthetic legacy image names. Join both writers, validate the final stored envelope and count its image tokens. Both calls return successfully; only one of the two tokens remains. No application configuration, database or Azure data-plane service is loaded by this probe.

The live account-deletion path takes a user row lock, which can serialize writers sharing that database transaction boundary. This probe does **not** establish that ordinary live requests currently race. Separate restored databases/replay processes do not share that row lock, and the replay callback uses the normal delete-account service, which writes the same independent journal. The journal itself therefore fails the required independent durability guarantee under multiple authorized writers. A lost explicit image token can prevent matching a legacy/orphan photo outside the owner's namespace on future recovery.

Before another production attempt, repair and review the journal's concurrency/protection model: preserve every acknowledged intent using an immutable per-intent format or conditional writes with verified merge/retry, prevent replay from rewriting its source journal, and validate concurrent writers and independently protected recovery coverage. Do not install immutability that simply makes the current overwrite-based implementation fail. No repair or production retry was performed after this failed gate, in accordance with the immediate-stop instruction.

## Required exit-gate status

| Item | Result |
| --- | --- |
| Journal provider/resource/independence | Not provisioned. Reviewed architecture requires dedicated Azure Blob account outside application DB/photo restore boundary, separate access and independently protected backup. |
| HMAC handling | No production key generated or stored. Required setting name is `DELETION_JOURNAL_HMAC_KEY`; separate secure secret, never app SECRET_KEY; no direct rotation without reviewed dual-key migration. |
| Setting changes | None. Planned names only: `DELETION_JOURNAL_CONNECTION_STRING`, `DELETION_JOURNAL_CONTAINER`, `DELETION_JOURNAL_HMAC_KEY`, `DELETION_JOURNAL_REQUIRED`. |
| Expiry | FAIL-CLOSED / DISABLED INDEFINITELY under accepted policy. No lifecycle/expiration rule installed; no key expiry configured by this attempt. Existing live lifecycle state was not refreshed. |
| Production enablement boundary | None: production journal was not enabled. No historical completeness or zero-loss claim. Deletions before eventual verified enablement remain outside native coverage unless separately reconstructed. |
| Fail-closed unavailable/key/write tests | Production-safe verification not run; existing unit tests were reviewed only. This attempt proved a different failure: successful writes can lose an acknowledged token. |
| Signed synthetic intent | Isolated fake-storage envelope signature PASS; concurrent image-token preservation FAIL. No synthetic production journal intent written. |
| Blob public/container access, HTTPS/TLS | Unchanged and not freshly verified. |
| Blob versioning, blob/container soft delete, retention/restore, holds/immutability | Unchanged and not freshly verified. Historical Phase 1 observations are not substituted for current policy inventory. |
| Disposable production Blob drill | Not run; no fixture uploaded and no fixture inventory claim. |
| Replay scope/result | Tool/source reviewed only; production-key off-live replay not run. No replay against production business data. |
| Backups/deleted-server copies | No copy created/deleted. Residual windows not refreshed; unknown/held/legacy sources continue to block expiry indefinitely. OneDrive remains unapproved for operational restore; exceptional recovery requires review, verified complete signed replay and offline verification before traffic/writes. |
| Rollback | None needed: zero production changes, no resource/settings/traffic mutation. Phase 1 state left untouched, without a new live-state attestation. |
| Checks | Local/remote commit agreement and clean starting tree PASS; authenticated Azure resource inventory; deterministic source-level durability probe FAIL as above. Full relevant test suite not run after stop; no application source changed. |
| Phase 3 | NOT started; no operational settings, alerts, monitoring or new deployment. |

Documentation/evidence only are committed to the same main branch. Delivery commit and push/clean verification are reported separately to avoid a self-referential hash. The primary project owner retains release/recovery/privacy/on-call responsibility. DB RPO <=5 minutes and end-to-end RTO <=30 minutes remain targets; this attempt certifies neither.
