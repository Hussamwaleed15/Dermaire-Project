# M3-F3 — Future chat requirements

Existing /chat and embedded assistance are supported, not missing. Current contract
sends one question and has no durable conversation/history/streaming promise.
Future durable conversations need server-owned IDs, account-scoped ordered history,
explicit context inclusion/omissions/retention/purpose consent, bounded pagination,
message idempotency and lost-response reconciliation, erasure/restore semantics and
current owner/role checks. Streaming needs an actual versioned protocol/cancel/error
contract before UI supports it. No history endpoint or streaming model is invented.
F2 source-manifest and English-only server-prose handoff still applies. New action,
notification or image-analysis capabilities remain separately authorized future work.
