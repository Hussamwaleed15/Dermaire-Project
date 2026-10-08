# Phase 0 recovery/privacy checklist

Current decision (8 October 2026, continuation from `239f6480aca35d8845c5deeb7ea696a267215d60`): **BLOCKED**. See [complete discovered inventory](recoverable-copy-inventory-20261008.md) and its read-only evidence. Earlier infrastructure-readiness PASS does not waive this production gate.

- [x] Confirm starting main `99ca9ce56fb7ff59ddbb3e4f5c72e75a4031b2a6`, clean checkout and fetch remote.
- [x] Enumerate accessible subscription resources, production/staging servers, backups, replicas, database names, vault APIs, storage including deleted accounts, containers and object history.
- [x] Record explicit native production DB 7d retention, geo Disabled, seven Automatic Full backups. Latest usable PITR/RPO remains a separate rollout/recovery check.
- [x] Verify account public Blob access false, container private, no legal hold/immutability and zero enumerated photo history.
- [x] Obtain **explicit** production versioning/container soft-delete evidence: authenticated Portal shows both Disabled (also blob soft delete and change feed Disabled); API omitted/null was not inferred as false.
- [x] Inspect App Service home/site metadata, local project/common directories, ZIP embedded databases, reachable Git history and GitHub downloadable artifacts without printing secrets or records.
- [x] Perform privacy-preserving OneDrive schema/content/fixture/date/ID/image comparison; both DBs and images remain unresolved / possibly production-derived.
- [x] Inspect local account/policy metadata and attempt browser/Graph access; authoritative cloud retention is unavailable, not assumed.
- [x] Refresh scoped project copy discovery, ten known Codex DBs and Azure resource/native backup metadata; no additional populated local DB found. See current continuation evidence in the inventory.
- [x] Reinspect exact Personal OneDrive project paths and third related Flutter folder; confirm direct DB byte equality, image hash equality and account/image linkage; no extra data-bearing set discovered. See [local inspection](recoverable-copy-inventory-20261008.md#local-personal-onedrive-inspection-8-october-2026-baseline-244ee20). Both populated sets remain unresolved.
- [ ] Resolve production lineage and maximum lifetime of both populated OneDrive DBs and their two upload photos, including remote versions/recycle bin; unknown is fail-closed.
- [x] Revalidate staging rollback ZIP/hash and nested zstd tar: code/dependencies only, no application DB/photos. Deleted rehearsal targets evidenced synthetic; preserve staging replay protection until all recoverability is gone. Excluded/out-of-band surfaces remain attestation scope.
- [ ] Attest every off-platform/manual/other-device copy absent or register custodian, location, restore ability, max lifetime, holds and deletion impact.
- [ ] Nominate release/recovery/privacy/on-call (each **TBD**, existing alert contact **TBD confirmation**). Recommend explicit temporary acceptance by the user if no teammate is designated. One named primary can hold all four; record existing alert contact. Recommended alternate is not a four-person requirement.
- [ ] Prove every recoverable application-data copy <=35d, quarantine <=7d, with no unbounded/unknown/held source. No universal quarantine expiry/cleanup enforcement, cloud recycle/history bound or hold exclusion is proven; seven days is a target. Global max horizon currently **unknown**; native DB proven **7d**.
- [ ] Before separately authorized rollout: provision/protect independent production deletion journal and key; ensure replay completeness. Production journal setting names absent; not provisioned in this task.
- [ ] Re-run fresh Phase 0 after closure; no deployment/traffic opening from this document. Legacy health probes are not new-build readiness.

**Journal retention 42d only if all recoverable copies <=35d and quarantine <=7d. Never expire intents/keys while any recoverable copy remains. Keys must also outlive retained signed intents.** Unknown inventory, legal holds, restored copies and unknown cloud history deny expiry. No lifecycle expiration was installed or enabled.

Validation: documentation/evidence consistency and git diff/secret checks; docs/evidence commit only. Production remained untouched. Final commit/push/clean status is reported in the accompanying completion message; do not embed a self-referential commit hash.
