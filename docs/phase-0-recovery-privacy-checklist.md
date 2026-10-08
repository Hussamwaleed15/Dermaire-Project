# Phase 0 recovery/privacy checklist

## Current policy decision - 8 October 2026 (supersedes earlier gate conclusions)

**Phase 0: PASS for policy/design readiness under indefinite fail-closed retention.** This is not production rollout or production compliance certification. No concrete unresolved Phase 0 policy blocker remains: uncertain legacy and undiscovered external copies are conservatively covered by indefinite retention and reviewed manual recovery. A complete bounded inventory is required only for future expiry re-enablement. Production remains untouched; historical evidence below is preserved and has not been refreshed through production access in this task.

OneDrive copies are **LEGACY/UNKNOWN-PROVENANCE**, potentially production-derived recoverable sources. Their retention/history/holds and quarantine are unknown; no <=35-day horizon is certified. **Deletion-journal and HMAC key expiry is FAIL-CLOSED / DISABLED INDEFINITELY** while any unknown recoverable source exists or its retention/hold state is unknown. No age-based cleanup or lifecycle expiry may be enabled. The 42-day rule is a future conditional target only: every source must have proven provenance, lifetime <=35d, quarantine <=7d and no hold; no surviving recoverable copy may need the intent, and keys must outlive retained signed intents. Unknown off-platform/other-device copies are also covered by this indefinite block; this does not assert they are absent.

Legacy sources are excluded from automatic restore selection and are **not valid operational production restore sources**. Any exceptional use requires explicit recovery/privacy review by the Primary project owner (temporary), registration of every derived target, isolated offline recovery with traffic/writes disabled, complete independent journal coverage and verified signed deletion-tombstone replay before any traffic/writes resume. Unknown journal completeness, an unverifiable legacy identity/image mapping, or failed replay means recovery cannot proceed. Legacy copies do not meet the operational RPO and cannot be selected as an automatic fallback. Neither these files nor their cloud history were edited/deleted.

MVP owner: **Primary project owner (temporary)** carries release, recovery, privacy and on-call responsibilities until explicitly delegated. No real-world identity is inferred. The working Gmail receiver is an alert destination only. Named delegation and verified contact/escalation details are required before broader production/on-call operations.

See [durable legacy inventory](legacy-recoverable-sources.json) and [restore procedure](deletion-journal-restore.md). Accepted startup 180s, DB RPO <=5m and RTO <=30m remain unchanged. Protected production journal/key provisioning, independent protection/backup, completeness and replay verification (including legacy mapping), runtime/migrator least privilege, health endpoints/deployment, production alert routing and traffic-opening smoke remain **unimplemented/unverified production rollout steps**, not completed Phase 0 evidence. A failed rollout preflight must keep traffic closed.

## Review checklist

- [x] Start from clean main `9989295339a4e27ba4bd2f4329fba01404d5e682`; fetch origin.
- [x] Preserve previous discovery/evidence without asserting new cloud observations.
- [x] Register legacy OneDrive DB/upload sets, empty test DB historical uncertainty and unknown external-copy scope without raw PII.
- [x] Disable journal/key expiry by default and require complete per-source evidence for any future eligibility review.
- [x] Exclude legacy sources from operational/automatic production recovery; require offline review, complete signed tombstone replay and verification for exceptional use.
- [x] Assign temporary project-owner role; distinguish alert destination from identity.
- [x] Re-evaluate Phase 0 under safer policy: PASS; no retention/provenance proof required while expiry stays disabled.
- [ ] Separate authorized rollout: protected production journal/key, legacy coverage/replay verification, permissions/TLS, health/deploy, named contacts and production smoke. These are rollout prerequisites, not evidence of execution.

No production connection, mutation, deployment or file deletion occurred in this task.

Validation: 32 focused retention/journal/replay/readiness tests passed in an isolated local test directory (one existing dependency deprecation warning). UTF-8, local documentation links, cross-document current policy, inventory privacy/restore flags and git diff whitespace checks passed. No production access occurred.
