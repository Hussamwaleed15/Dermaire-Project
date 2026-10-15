# Foundation product PATCH/DELETE committed receipts v1

Optional `Idempotency-Key` is additive to existing PATCH/DELETE `/api/v1/products/{id}`.
Existing Product/Routine/Experiment guards and If-Match enforcement are retained.
Keys use the existing 16..128 ASCII identifier grammar. Duplicate keys or duplicate
If-Match headers are422. Identity binds owner=actor, product id, operation and key;
fingerprint binds the effective typed payload plus exact original If-Match.
PATCH list order and exact text are not given invented semantic equivalence.

GET `/api/v1/products/{id}/operation-attempts/{patch|delete}/{key}` returns owner-only
committed/unknown/expired. Unknown does not assert rejection, absence of in-flight
work, or absence of independently persisted privacy intent. No reservation or
durable rejection table. Readback does not require a surviving product row.
Foreign owner sees unknown;401 for invalid session. Current safety consent still
gates mutations; readback remains available to the authenticated owner.

Committed PATCH stores the original ProductOut/revision in the business transaction
with product, routine-deactivation side effects and audit. Exact replay returns
that original result/ETag even if current state has advanced; GET product supplies
current state. Different payload or precondition409, erased original content410,
replay older than30 days410, stale new operation412, protected missing If-Match428.
No key retains existing behavior and does not create a receipt.

Committed DELETE stores only `{deleted:true,id,revision}` with deletion audit and
DB deletion. Replay returns204 with the same Operation-Attempt-Id and tombstone
revision; it does not repeat the independent deletion-journal write. The minimal
tombstone contains no product content. Product erase clears every retained PATCH
snapshot and original CREATE snapshot; account erase removes attempts entirely.
Offline journal replay clears orphan PATCH/CREATE snapshots even when product is
already absent, while retaining minimal committed DELETE identity. No API exposes
the independent journal as a successful DB operation.

Deletion privacy intent is durably recorded before DB deletion. If DB commit fails,
the journal may still require erasure on restore/retry while DB operation readback
is unknown. This is intentional privacy-first behavior, not a claim of atomicity
across blob journal and SQL. Retry same key/body/If-Match after503; do not manufacture
a new operation or infer success merely because the product is absent. A privacy
journal replay may erase a row whose original DELETE DB transaction never committed.

30-day replay/read-result window; minimal identities/hashes retained until account
erase, product content until product/account erase. No automatic TTL purge or legal
retention certification. Source revision08 follows agent07; populated downgrade
refuses data loss. Foundation routine, experiment, legacy note/review and grant/
consent attempt gaps are separate and remain explicitly OPEN.
