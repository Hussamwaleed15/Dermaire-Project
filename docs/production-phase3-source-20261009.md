# Fresh Phase 3 source gate — 9 October 2026 Cairo

This run starts from clean/pushed fea3960, which contains eed61b8 and the subsequent
fresh-attempt Blob-key correction. Historical Phase 3 halts are not this result.
Production mutation/deployment and fixes are explicitly authorized in this run.

## Call-chain audit

| Destructive path | Current ordering and replay boundary |
| --- | --- |
| DELETE /users/me -> delete_account | Owner row lock, cross-owner/reference checks, immutable signed v2 account intent and exact read-back before Blob or SQL deletion. Failure returns 503; ownership rows remain until external cleanup succeeds. Replay re-verifies coverage without writing source. |
| Explicit photo DELETE | No standalone endpoint. Account cleanup and image maintenance below are the actual removers. |
| reconcile_images --apply -> reconcile | PostgreSQL owner serialization, at least 24-hour grace, Capture/CheckIn reference checks, photo-only v2 intent/read-back before storage.delete_image. Dry run never deletes. |
| Failed capture -> cleanup_failed_upload | Rollback then owner lock/reference check, photo-only v2 intent/read-back before Blob deletion. A journal failure leaves cleanup pending. |
| Failed check-in -> cleanup_failed_upload | Same audited service and ordering. |
| Upload retry | Stable request ID remains in DB; each actual upload uses UUID4 Blob key and atomic create-only upload. A prior intent cannot cover a later successful upload. Committed retries return existing row. |
| Storage delete_image / delete_owned_images | Only runtime callers are guarded account cleanup, photo cleanup, or offline signed replay. Versioning/soft-delete policy and retained-copy checks fail closed. Local cleanup is likewise called after intent in required mode. |
| Offline restore replay | Whole inventory signatures/path bindings verified first. Account intents cover matching accounts and their namespaces; photo-only intent owner uses separate HMAC domain, so only explicit image tokens match. Siblings/account/other records preserved. |
| Product DELETE -> delete_product | NEW uncovered hard delete found in fea3960. Now verifies history/foreign-owner links and persists a typed signed product intent before ProductIntelligence/Product deletion; failure returns sanitized 503. |
| Product restore replay | Owner and immutable product ID both matched with separate HMAC domains. All target history/foreign-owner checks precede mutation. Only target intelligence/product removed; account, siblings, photos preserved. Conflicting restored history fails closed for offline repair. |
| Experiment/routine/doctor DELETE | History-preserving lifecycle/access-state transitions; no permanent row/photo removal. |
| Background/maintenance | No other runtime permanent remover found. Only reconcile_images apply and explicit offline replay tools call audited services. |
| Nonproduction rehearsal tools | Explicit isolated synthetic fixtures/resources; test DB teardown is local SQLite. Not production deletion entry points. |

The product intent is schema 3 with exactly schema/owner/products and v3 content-addressed
paths. Account/image writers remain immutable schema 2. Old readers reject schema 3
instead of silently omitting erasure. Restore/checkpoint tools now verify mixed 1/2/3
inventories. No DB migration, new secret, provider enablement, journal retention,
or journal permission change. Pre-schema-3 artifacts cannot be a recovery reader
once a product intent exists; retain this release as the minimum rollback reader.

## Privacy logging

logging-production.json suppresses unstructured server/SDK message text and exception
stacks while retaining operational JSON. Uvicorn access logging must be disabled.
Journal persistence now emits safe available/degraded events for production alerting.

## Validation

Fresh full backend suite: 695 passed, 91 existing deprecation warnings, 90.68s.
New tests prove intent-before-delete, fail-closed product/intelligence preservation,
owner isolation, repeat replay, unchanged journal source, preserved sibling photos
and records, mixed checkpoint protection, and server exception redaction.
Existing image retry/cleanup and Safety Engine/clinician/provider tests pass.
No real production data is used by these tests. Source gate: PASS.

Deployment/preflight/final gates belong to the new timestamped execution evidence;
this document alone does not claim Phase 3 complete or authorize Phase 4.
