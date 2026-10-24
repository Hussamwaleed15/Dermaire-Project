# Backend F7 → Flutter handoff

Date: 2026-10-24. Implementation commit:
`7e7cd166b972af28eb60eeaf3b2c79b6ed91dbc2`.

## Required Flutter integration

1. On the first and every retry of a clinical note/review write, preserve and send
   the page/editor's verified grant as `Original-Grant-Id`. Treat 403 as loss of
   that original authority. Do not silently substitute a replacement grant.
   Inspect `Original-Grant-Binding`; `explicit` is the hardened path and
   `legacy-current` is only the compatibility path.
2. Discover recoverable Agent sessions with `GET /agent/sessions`. Follow
   `next_before`; the response intentionally contains metadata only. Fetch a known
   session explicitly if its private context is needed.
3. Page doctor requests with `limit` and `before`. Navigate only from the returned
   `patient_ref` and re-authorize at the destination. Never derive a patient from
   payload text.
4. For notification inbox navigation, use `target`, particularly
   `target.thread_id` for messages. Never infer a thread from `source_id` because
   the message `source_id` is not a thread ID.
5. Cache each notification `state_revision`. Send it as `expected_revision` on
   read/unread changes. On 412, refresh and resolve using current state; do not
   replay a stale opposite intent. Legacy calls without the query still work.
6. For evaluation cancellation recovery, preserve the original
   `Idempotency-Key`, plan ID and expected revision. Read
   `/clinical-plans/{plan_id}/attempts/evaluation_cancel/{key}` after uncertainty.
   The receipt proves that cancellation attempt only, not a newer evaluation.

## Unchanged safety boundaries

- VIEW never implies EXPORT.
- Receipts are original committed snapshots, not current PHI or current authority.
- `unknown` is not `rejected`, `in_flight`, or permission to create a new key.
- Agent model inference and comparison clinical inference remain unavailable.
- Push provider delivery remains disabled/unconfirmed.
- Do not execute clinical actions from an Agent request or notification.

## Validation available

Baseline at `8a3f49d`: 1047 passed, 90 PostgreSQL-gated skips. Final implementation:
1053 passed, 90 PostgreSQL-gated skips. Focused new-contract tests: 5 passed.
SQLite seeded migration rehearsal through `20261024_14`, compileall, OpenAPI and
`git diff --check` passed. The dedicated local PostgreSQL gate at 127.0.0.1:55441
was unavailable because Docker Desktop's daemon was not running; no F7 PostgreSQL
atomicity claim is made.
