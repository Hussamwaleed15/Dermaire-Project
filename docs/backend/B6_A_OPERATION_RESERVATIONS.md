# B6-A — Operation reservation foundation

Status: implemented in source for review; **inactive** and not approved for B6-B or deployment.

## Scope boundary

This increment adds an additive `operation_reservations` table and an internal
state-machine service. No endpoint calls it, no legacy request/response changes,
and no migration was run against a managed or live database.

## Invariants

1. One durable identity exists for `(owner, domain, operation, key_hash)`. The
   raw client key is never stored. Domain/operation names are stable and bounded.
2. The identity is permanently bound to one canonical SHA-256 payload digest
   during its retention window. A different payload is a conflict.
3. Every worker claim has a monotonically increasing `generation` and an
   unpersisted lease token. Only its SHA-256 digest is stored.
4. A worker may finish only while its exact generation/token lease is live.
   Expired or superseded workers are fenced.
5. Lock order is always owner row, then reservation row. Account deletion starts
   with the same owner lock and explicitly erases the owner's reservations.
6. For database mutations, the fenced `commit()` call, domain write, and caller
   commit must share one transaction. Committing the domain write first is not
   supported and cannot provide exactly-once behavior.
7. `reserved -> committed|failed`; an expired `reserved` or `failed` row may be
   reclaimed as `reserved` with `generation + 1`. `committed` is terminal until
   retention expiry. Identity reuse after expiry is refused until reconciliation
   and explicit purge.
8. `retain_until` is fixed at creation. Purge is owner-scoped and follows the
   same lock order. Result snapshots are optional and must already be privacy
   reviewed by the future endpoint integration.

## Migration and rollback

- Alembic `20261024_15` only creates a table, two indexes, uniqueness, FK, state
  shape, hash length, generation and retention checks. Existing tables/data are
  not rewritten.
- Downgrade succeeds only when the table is empty. It refuses a populated table
  to prevent silent loss of attempt identities or retained results.
- The application readiness contract now requires `20261024_15`. The previous
  application build requires exactly `20261024_14`; therefore a rolling
  mixed-version migration is **not proven safe**. Any later rollout needs an
  approved compatibility strategy or a bounded maintenance cutover. B6-A does
  not authorize either.

## Verification at this branch

- Unit/state/migration tests: passed locally on SQLite.
- Existing account deletion and readiness tests: passed locally.
- Seeded SQLite Alembic rehearsal: passed and preserved the eight seeded rows.
- PostgreSQL concurrency tests were authored for unique claims, owner-lock
  serialization versus takeover, fencing, and guarded downgrade. They were
  skipped because the dedicated loopback gate at port `55441` was unavailable;
  Docker Desktop was also unavailable. No PostgreSQL success is claimed.

## B6-B admission gates

Do not connect this service to an endpoint until an independent review confirms:

- real PostgreSQL tests pass on the exact PR head, including lock-wait evidence;
- the future endpoint canonicalizes its payload without hiding meaningful input;
- result snapshot retention/erasure is approved for that domain;
- all domain writes and reservation completion share one transaction;
- error/recovery contracts for `in_flight`, expired and erased results are agreed;
- a mixed-version deployment/rollback plan is approved; and
- Salma has reviewed the PR independently. No approval is recorded by this file.
