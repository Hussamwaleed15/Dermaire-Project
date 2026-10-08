# Nonproduction deletion-journal concurrency hardening — 8 October 2026

Verdict: **JOURNAL CONCURRENCY FIX READY FOR PRODUCTION PHASE 2** (concurrency milestone only; no production enablement or deployment).

## Root cause

At baseline `db9beb5`, `DeletionJournal.record` downloaded `<owner-token>.json`, merged image tokens locally, signed its own merged subset and uploaded with `overwrite=True`, without ETag/lease/atomic append. Two writers could both read the same absent/previous state, successfully replace it, and the second replacement erased evidence acknowledged by the first. HMAC remained valid because the authorized second writer correctly signed its incomplete subset; signatures authenticate content, not completeness or write history. The original deterministic failure is retained in `docs/evidence/production-phase2-20261008/journal-concurrency-result.json`. Database row locks do not protect an independent journal across distinct restored databases/processes.

## Architecture and acknowledgement

Schema 2 writes one immutable-by-writer block blob per canonical owner/image set: `v2/<SHA256(canonical signed record)>.json`. Owner/image values remain domain-separated HMAC tokens; no raw identity/photo names enter stored envelopes. Images are sorted/deduplicated. Atomic Azure create-if-absent (`BlockBlob`, `overwrite=False`) removes shared read/merge/replace state. Same owner with new images creates a new intent; exact retries use the same deterministic object. No shared mutable index, queue, lease or conflict merge is needed.

Both new writes and existing-object conflicts require downloading the specific record, validating its HMAC and comparing its exact canonical content before returning acknowledgement. Conflicts never permit replacing existing evidence. Other upload/read/key/storage failures propagate before account/photo destruction. Crashes before persistence are unacknowledged; lost responses after persistence leave pending evidence, and explicit retries verify it. SDK transport retries are bounded; the application performs no unbounded retry loop.

The invariant counts **unique canonical intents**, not duplicate successful calls. Read-back establishes presence at acknowledgement time. Independent backup, protection from privileged deletion/rollback and trusted complete inventory/checkpoints remain production requirements: no HMAC format alone detects deletion of an entire record. Unacknowledged ambiguous writes can leave additional pending records which replay must enforce.

## Compatibility and replay

Schema 1 surviving records remain read-only at `<owner-token>.json`; schema 2 uses validated content-derived paths. Mixed-version inventories replay together with no database migration or automatic rewrite. Invalid/unknown schema, signature, canonical v2 shape or path binding is rejected. Old overwrite writers must be stopped before adoption. Surviving legacy records cannot prove historical completeness or reconstruct evidence already lost by the prior race.

Replay verifies the entire journal before mutation. The real account deletion service receives the source journal in read-only mode, revalidates owner/legacy image coverage and never appends/replaces its source. Restored account-associated rows, explicitly recorded legacy images and owner-namespaced orphan uploads are removed. Unattributable anonymous legacy objects require reviewed mapping before rollout. Pause source writers for a recovery snapshot and rerun all intents before opening traffic. Inventory and per-account revalidation cost must be benchmarked at production scale.

## Validation

- Local deterministic simultaneous start: **2 acknowledged / 2 durable** and **16 / 16**, including retention of every distinct image token for one owner.
- Local stress: **50 batches × 16 writers**, four owner identities, plus 32 concurrent duplicate attempts: **832 successful calls, 801 unique acknowledged intents, 801 durable signature-verifiable records, zero lost**.
- Concurrent account-only plus image intents for the same/different owners; duplicate retry; corrupt conflicting object; valid signed wrong-content collision; fail before upload, after upload, read-back failure and disappearance; invalid/missing signature/key; unavailable store; legacy v1 compatibility/path binding; legacy coverage refusal before deletion; repeat source-read-only replay all pass.
- Real Azure: separately created private containers in `dermairerehearsal261006`, group `dermaire-readiness-nonprod-20261006` verified `production=false`. Never used a production journal or existing staging journal container. Counts-only final Azure evidence is `docs/evidence/journal-concurrency-20261008/azure-result.json`.
- Azure concurrency: **2/2 and 16/16**; **10 × 16** stress batches plus duplicate retries: **210 successful calls, 179 unique acknowledged / 179 durable**, zero lost. Actual create conflict returned **409 ResourceExistsError**, and original bytes were unchanged. A real persisted write followed by simulated lost response was unacknowledged; retry verified the existing object, giving **180/180**.
- Off-live replay: in-memory synthetic restored SQLite database using actual account deletion service and real private Azure photo blobs. Removed one account and its dependent rows, explicit legacy fixture and orphan upload; preserved the unrelated account/photo. Repeat returned **zero accounts / zero image cleanup calls**. Source journal bytes unchanged. Corruption and nonexistent Azure container rejected before callback mutation. Final complete journal: **181 unique acknowledged / 181 durable verifiable intents**. The first replay scan count can be zero because the real account service already removed the legacy/orphan blobs; final photo inventory proves cleanup.
- Both temporary Azure containers deleted and absence verified. No account/service policy, staging app setting or existing staging evidence was changed. HMAC/credentials stayed in process memory; counts-only results disclose no keys/tokens/raw records.
- Relevant tests: **36 passed**. Full backend: **671 passed**. Initial full attempt had seven fixture setup errors from Windows default temporary-directory permissions; workspace-local temporary paths resolved them. Deprecation warnings are recorded in local evidence and did not fail tests.

## Files changed

- `backend/app/services/deletion_journal.py`: v2 immutable writer, exact signed read-back acknowledgement, mixed-version/path-bound inventory and source-read-only replay callback.
- `backend/app/services/account_deletion.py`: read-only recovery mode and owner/legacy coverage guard.
- `backend/tests/test_deletion_journal.py`: concurrency, stress, persistence faults, idempotency, compatibility and integrity tests.
- `backend/tests/test_account_deletion.py`: actual account deletion recovery coverage/source-read-only regression.
- `backend/app/tools/validate_journal_nonproduction.py`: repeatable isolated real-Azure rehearsal with resource-scope guards and cleanup.
- `docs/deletion-journal-restore.md` and `docs/production-release-runbook.md`: architecture, durability, recovery, compatibility and adoption prerequisites.
- This report and counts-only Azure/local evidence under `docs/evidence/journal-concurrency-20261008/`.

## Delivery and scope

Started clean on `main` at `db9beb50b7bd0c5361a7792b6aa56ca95dda6114`; fresh fetch confirmed origin/main matched. Code/docs/tests/evidence are delivered together to the same main branch. The final user-facing delivery report records the non-self-referential commit hash, remote push and clean-tree verification.

**Production remained untouched.** No production app settings, DB, photo/journal storage, traffic or credentials were mutated. No real user record or production data was read by the test tools. Azure account inventory was management-metadata-only; all credential access and data-plane operations targeted the verified nonproduction account. No deployment or Phase 3 started. Journal/key expiry remains disabled indefinitely; existing unknown/legacy copies still block expiry. Production Phase 2 requires separate authorization and its fresh protection/provisioning/completeness gates.

Azure API source: [Microsoft BlobClient reference](https://learn.microsoft.com/python/api/azure-storage-blob/azure.storage.blob.blobclient) documents block-blob create conflicts when overwrite is false. This behavior was independently verified against real Azure in this milestone.
