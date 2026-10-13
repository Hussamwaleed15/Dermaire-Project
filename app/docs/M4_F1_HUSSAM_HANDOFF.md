# M4-F1 — Hussam handoff

1. Add expected_version/If-Match to product PATCH with atomic409/412 conflict
   semantics. Current updated_at GET preflight cannot close a concurrent race.
2. Add owner-scoped idempotency key and operation lookup for POST/products.
   Unknown transport outcome currently blocks further creation until reviewed;
   Flutter must not blindly replay a possibly persisted create.
3. Separate product markers from real linked routine/experiment identities in
   future API read models. Flutter never interprets marker flags as evidence.
4. Publish verified-catalog provenance/safety metadata only if a real catalog
   is planned. Current personal records remain explicitly user-entered.
5. Document naive database timestamp UTC serialization; include timezone on wire.
