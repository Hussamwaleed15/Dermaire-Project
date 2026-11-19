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
  application build requires exactly `20261024_14`. Both builds use an exact
  equality gate, not an additive revision range. Therefore a rolling
  mixed-version migration is **known to fail readiness**, even though the DDL is
  additive. The selected plan for this PR is a bounded maintenance cutover; an
  expand/deploy/activate rollout would first require a separately reviewed
  compatibility release of the old application. B6-A does not authorize either
  rollout.

### Compatibility matrix

| Application build | DB `_14` | DB `_15` | DB `_16` |
| --- | --- | --- | --- |
| `main@6c6255b` requiring `_14` | ready, subject to other health gates | **503** | **503** |
| PR #22 requiring `_15` | **503** | ready, subject to other health gates | **503** |

`_15` does not alter a legacy table or endpoint contract, so the incompatibility
is caused by the deliberate exact readiness gate rather than by old code reading
the new table. Readiness failure still removes an instance from service and must
be treated as operational incompatibility.

### Selected release sequence: maintenance cutover

This is a plan only; no managed database or deployment was changed by B6-A.

1. Confirm the release artifact SHA, independent approval, PostgreSQL CI on that
   SHA, current DB revision `_14`, zero drift, backup/PITR validity, migration
   owner, rollback owner, and an accepted write-unavailability window.
2. Close traffic and pause all application workers and background writers. Do
   not leave `_14` and `_15` builds sharing the database.
3. Record the deletion-journal watermark and recoverable DB checkpoint, then run
   exactly one reviewed migrator from `_14` to `_15`.
4. Run `alembic current`, `alembic check`, schema/constraint audit, and confirm
   the new table is empty before application activation.
5. Start only the reviewed `_15` artifact. Require `/health/build` to report the
   exact artifact SHA and required revision `_15`, then require readiness and
   privacy-safe synthetic smoke to pass before reopening traffic.
6. Keep B6-B inactive. The presence of `_15` does not authorize any endpoint to
   write reservation rows.

Failure handling:

- Before migration commit: abort, retain `_14`, verify revision/readiness, and
  reopen only after the original state is confirmed.
- After `_15`, while `operation_reservations` is empty: keep traffic closed,
  downgrade to `_14`, verify exact revision/audit, redeploy the archived `_14`
  artifact, then smoke before reopening.
- If the table is non-empty: downgrade intentionally fails. Keep traffic closed;
  do not truncate or bypass the guard. Prefer roll-forward with the reviewed
  `_15` artifact. A DB restore requires the separately approved recovery and
  deletion-journal replay procedure, with explicit data-loss/RPO acceptance.
- If `_15` readiness or smoke fails for a non-schema reason: code rollback alone
  is insufficient because `_14` rejects DB `_15`; either correct/roll forward or
  perform the guarded empty-table downgrade before restoring `_14`.

### Alternative not selected: expand/deploy/activate

A no-downtime sequence is possible only with a preceding compatibility release
based on the old application that accepts both `_14` and `_15` while continuing
to ignore the new table. All old exact-`_14` instances must first be drained.
Only then may the additive migration run, followed by PR #22 deployment. Endpoint
activation remains a later B6-B change. PR #22 alone cannot make the already
released `_14` build accept `_15`, so that strategy is outside this PR.

## Verification at this branch

- Original local verification: **1076 passed, 100 skipped**; focused final suite:
  **41 passed**; seeded SQLite Alembic rehearsal preserved all eight seeded rows.
- On exact head `156f757748a729aa8c67b4292a5869d90b7294bb`, Backend CI,
  Backend B3 CI and Backend B4-B5 CI passed with PostgreSQL 18. Backend Core
  reported PostgreSQL 18.7 and **1177 passed** with no skips reported.
- The exact `_14`/`_15`/newer compatibility boundary is covered by an explicit
  unit matrix. After adding the matrix and runbook, the full local backend suite
  passed with **1081 passed, 100 skipped**. No managed database migration,
  deployment, or rollback was run.

## B6-A acceptance tests for an authorized rehearsal

1. Static/unit: exact gate accepts only `_15`; `_14`, `_16`, empty and multiple
   heads fail closed. `/health/build` declares `_15` without exposing DB state.
2. Migration: populated representative `_14` upgrades to `_15` without changing
   legacy row counts/content; `alembic check` is clean and constraints/indexes
   match the reviewed revision.
3. Empty rollback: `_15 -> _14` succeeds only with zero reservation rows, and the
   archived `_14` build becomes ready again.
4. Guarded rollback: one synthetic reservation causes downgrade refusal, leaves
   revision `_15`, and preserves the row.
5. Deployment: during the cutover no `_14` and `_15` workers overlap; before
   traffic, every instance reports the same reviewed SHA and readiness 200.
6. Inactivity: OpenAPI has no B6 reservation endpoint and representative legacy
   traffic leaves `operation_reservations` empty.
7. Failure drill: induced migration, readiness and smoke failures keep traffic
   closed and follow the matching branch above without destructive cleanup.

## B6-B admission gates

Do not connect this service to an endpoint until an independent review confirms:

- real PostgreSQL tests pass on the exact PR head, including lock-wait evidence;
- the future endpoint canonicalizes its payload without hiding meaningful input;
- result snapshot retention/erasure is approved for that domain;
- all domain writes and reservation completion share one transaction;
- error/recovery contracts for `in_flight`, expired and erased results are agreed;
- a mixed-version deployment/rollback plan is approved; and
- Salma has reviewed the PR independently. No approval is recorded by this file.
