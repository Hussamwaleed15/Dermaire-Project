# Dermaire index reconciliation, 8 October 2026

**INDEX RECONCILIATION READY FOR PRODUCTION** — design and nonproduction rehearsal only. Production remained untouched. This closes the specific index reconciliation blocker; production rollout, ownership/roles/credentials, PITR freshness, journal and remaining release gates still require their prescribed verification before execution.

Starting clean main: `7bf26c1`. No subagents were used. Current production was inspected through bounded read-only catalog sessions using the existing Azure-origin client. No production DDL, DML, stamp, role, password, setting, deployment, restart, traffic or firewall operation was issued. No production records were copied or printed. Before/after columns, indexes, constraints, validity, objects/ownership, grants, schema, roles/memberships, policies/triggers/functions, extensions and default privileges are identical. Actual application runtime remains `dermaireadmin`.

## Authoritative state and exact discrepancy

| Item | Intended state | Finding and decision |
| --- | --- | --- |
| `ix_experiments_routine_entry_id` | Full nonunique default btree on nullable `experiments.routine_entry_id`, no predicate/expression/include | Preserve unchanged; add `index=True` to ORM and reviewed revision `20261008_01` after immutable baseline. |
| `ix_users_reset_token_hash` | Full nonunique default btree on nullable `users.reset_token_hash`, no predicate/expression/include | Add the absent index concurrently; duplicate hashes and multiple NULLs remain permitted. No unique constraint or partial-index substitution. |
| `uq_experiments_active_owner` | Full btree backing a NOT DEFERRABLE, validated `UNIQUE(active_owner)` constraint; default NULLS DISTINCT | Attach the existing healthy standalone unique index; preserve index identity and existing uniqueness throughout. Multiple inactive/legacy NULL owners remain valid. |

The routine index is intentional, not legacy residue. Commit `c768bdd` introduced both the PostgreSQL/SQLite Experiment Engine v2 manual scripts, which explicitly create it, and the ORM column, which accidentally omitted `index=True`. The frozen `20261006_01` baseline inherited that omission. Current code uses it for the routine-entry active experiment query (`services/experiments.py:292`) and cross-owner deletion guard (`services/account_deletion.py:41`); it also supports referencing-row lookup for the FK. Benefit depends on planner selectivity; no production EXPLAIN ANALYZE or workload benchmark is claimed. Keeping it avoids a destructive, unnecessary rebuild and preserves historical intent.

Reset-token `index=True` already existed in the initial tracked commit `6162add`; the frozen baseline explicitly creates `ix_users_reset_token_hash` with `unique=False`. It is therefore a longstanding model/schema contract, not an Alembic generation artifact. Current reset-password finds the user by email then compares SHA-256 hashes in memory; this index is not required for that path's correctness or current performance. The live catalog nonetheless lacks the declared index. Available history has no dated production DDL ledger identifying whether initial provisioning omitted it or some later action removed it; that historical event cannot honestly be reconstructed. The exact observable cause of drift is the absent declared index, independent of that unknown event. A full nonunique index matches the adopted contract without tightening reset semantics; changing to a partial/unique index would create another contract change.

The active-owner mismatch is representation only: the same `c768bdd` manual script creates a standalone unique index, while ORM/baseline specifies a unique table constraint. Uniqueness was already enforced. `UNIQUE USING INDEX` changes catalog ownership/dependency, not row values or NULL semantics. Auto-generated remove-index/add-constraint suggestions must not be executed as drops.

The frozen baseline file is unchanged. New online migration validates the exact existing routine index plus validity/readiness/liveness before adopting it; on a fresh baseline it creates the missing index. A populated managed DB missing that index must pre-create it concurrently or use a maintenance write pause before ordinary upgrade. Wrong same-name definitions stop the revision. Its downgrade deliberately retains the historical index: application rollback does not justify removing it. Offline generation for this conditional revision is explicitly unsupported; use online validation. Readiness now requires exactly `20261008_01`; run adoption/upgrade before deploying the new build, including to staging.

## Reviewed production sequence and preconditions

The executable guarded sequence is [production-baseline-adoption.sql](production-baseline-adoption.sql), reproduced verbatim below. It is a **psql** file, not a single multi-statement DBAPI execution string. Use one dedicated connection with autocommit enabled and `ON_ERROR_STOP`; never `psql -1`, a surrounding transaction, `DO`, or Alembic's default transaction around concurrent creation. Session advisory lock serializes cooperating adoption runners; fresh catalog checks and exclusive table locking protect the attachment guard.

Before future execution: fresh full schema/owner/default/PUBLIC/extension/function/policy/trigger audit; current source identity/version/index definitions and no unexpected drift; backup/checkpoint/journal requirements from the release runbook; a reviewed migrator role owning required objects; no existing Alembic version; one runner; retained rollback artifact/settings. Preserve compatible `users.reset_token_attempts DEFAULT 0`. Obtain aggregate counts for all 16 business tables immediately before and after while writes are paused. In production do not emit/retain raw rows or per-record data hashes.

1. Safest whole-file execution: pause application writes and drain outstanding transactions before starting it. The reset index still uses CONCURRENTLY, minimizing write-blocking and providing a reusable online first stage.
2. Optional staged execution: run through reset-index validation online on the same locked session, then pause writes/drain before the explicit attachment boundary. Do not run past the boundary automatically while writes remain live. Whole-file execution cannot orchestrate the app pause itself.
3. Create and validate reset index. Preserve both existing experiment indexes. Attach active-owner inside the short explicit transaction with 5s lock timeout and 30s statement timeout.
4. Keep writes paused. Run full ORM schema_audit: zero differences required. Independently compare all CHECK/FK definitions, validation, nullability/defaults, indexes/constraints, policies/triggers and owners/grants; Alembic alone does not check everything. Confirm row-count invariants and valid/ready/live indexes.
5. Only then stamp **`20261006_01`**, upgrade to **`20261008_01`**, and run `alembic check`. The new revision validates/skips the already-present routine index. Never run frozen baseline CREATE statements on existing tables and never stamp the head to skip its validation.
6. Revoke unintended migration-metadata privileges, prove runtime restrictions and continue the separately scoped rollout gates. This task does not authorize production mutation.

The main SQL is:

```sql
CREATE INDEX CONCURRENTLY ix_users_reset_token_hash
    ON public.users USING btree (reset_token_hash);
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
LOCK TABLE public.experiments IN ACCESS EXCLUSIVE MODE;
-- Execute the exact catalog assertions from the guarded script here.
ALTER TABLE public.experiments
    ADD CONSTRAINT uq_experiments_active_owner
    UNIQUE USING INDEX uq_experiments_active_owner;
COMMIT;
```

Followed by one runner: `alembic stamp 20261006_01`, `alembic upgrade head`, `alembic check`. There is **no DROP** in the production adoption plan and **no production mutation occurred**.

## Locks, failure and recovery

Concurrent creation is a top-level statement: PostgreSQL forbids it inside a transaction. It can wait for old writers/snapshots and performs additional phases; monitor progress and long transactions. A 5s lock wait or 10min statement timeout is a fail-closed ceiling, not a performance promise. Ordinary CREATE INDEX blocks writes; concurrent creation allows DML and takes ShareUpdateExclusiveLock. These rules are supported by [PostgreSQL CREATE INDEX](https://www.postgresql.org/docs/18/sql-createindex.html) and [explicit locks](https://www.postgresql.org/docs/18/explicit-locking.html). If moving this operation into an Alembic revision, use its explicit [autocommit_block](https://alembic.sqlalchemy.org/en/latest/api/runtime.html#alembic.runtime.migration.MigrationContext.autocommit_block), which commits preceding transactional work; never pretend the concurrent build is atomic with the attachment.

Attachment takes AccessExclusiveLock and blocks readers as well as writers; there is no `ADD CONSTRAINT CONCURRENTLY` option. Pause/drain traffic for the attachment and keep the transaction short. Eligible existing full unique btree attachment is fast metadata work, documented by [PostgreSQL ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html). Local measured attachment: **0.001001s**; blocked reader timed out after **0.266s**. During concurrent creation a second users UPDATE completed in **0.002s** while an older writer delayed the builder. Actual observed locks were ShareUpdateExclusiveLock and AccessExclusiveLock. Exact guarded script completed in **0.088s** on synthetic data; not a production timing estimate.

- A failed concurrent build may leave a committed INVALID index. Rehearsal forced this with a bounded writer wait: valid=false, ready=false. Do not use IF NOT EXISTS or stamp. Inspect exact definition, validity/liveness, constraints and ownership; only for the newly created standalone reset index, use top-level `DROP INDEX CONCURRENTLY public.ix_users_reset_token_hash;` then rerun the absent-index stage after fixing the blocker. Never automatically drop either experiment index. An invalid index consumes maintenance overhead; do not leave it unattended.
- If attachment fails before COMMIT, rollback that transaction. The previously committed valid reset index remains. Keep it; re-audit it and resume from the attachment stage after the pause/drain. Whole-file retry intentionally refuses an existing reset index; it must not conceal partial completion. Connection termination releases the session advisory lock; use an explicit same-session unlock on handled aborts.
- If attachment COMMIT succeeded but stamp/upgrade/check fails, retain the attached constraint and both useful indexes, keep writes paused, and investigate/fix forward. Stamping is bookkeeping, not rollback. Do not DROP CONSTRAINT: it would drop its owned unique index and remove existing protection. A detach has no simple safe inverse; any exceptional reversal requires a separately reviewed protected uniqueness replacement sequence. No such reversal is proposed here.
- A privacy-compatible application rollback can retain additive indexes and uniqueness normalization. New migration downgrade keeps the historical index and may expose drift against the old frozen metadata; schema downgrade is not the production rollback procedure. Do not use destructive database restore to undo these additive metadata changes.

## Rehearsal evidence

Dedicated local PostgreSQL **18.6**, bound only to `127.0.0.1:55439`, databases `reconciliation` and `fresh`; no production credentials or rows used. Exact whole public index catalog matched the fresh production inventory. All column definitions (physical column order ignored), FK and CHECK expressions/names matched. Local C collation/plaintext loopback/Windows differs from Azure en_US.utf8/TLS/Linux and production roles/grants; this validates index semantics and operation behavior, not Azure performance, production collation equivalence, full privacy/recovery readiness or RTO.

Before repair, frozen-metadata comparison reproduced the same remove routine index / remove standalone owner index / add owner constraint / add reset index differences. After the ORM correction only the owner representation and absent reset index remained. The exact committed psql adoption file ran successfully. After reconciliation full ORM drift was **[]**; stamped baseline, upgraded to head and actual Alembic check reported **No new upgrade operations detected**. Fresh empty baseline+head upgrade/check also passed. Wrong same-name routine index was rejected by the actual migration. Both historical index OIDs survived adoption unchanged; all three indexes valid/ready/live, all full/no predicate, owner index unique with NULLS DISTINCT, other two nonunique. Attachment is validated and not deferrable. DEFAULT 0 remained intact.

| Table | Before | After |
| --- | ---: | ---: |
| audit_logs | 30 | 30 |
| captures | 30 | 30 |
| checkins | 60 | 60 |
| clinical_notes | 30 | 30 |
| daily_contexts | 30 | 30 |
| doctor_patient_access | 30 | 30 |
| doctor_review_actions | 30 | 30 |
| experiment_evaluations | 30 | 30 |
| experiments | 90 | 90 |
| measurements | 30 | 30 |
| product_intelligence | 30 | 30 |
| products | 30 | 30 |
| reward_redemptions | 30 | 30 |
| routine_adherence | 30 | 30 |
| routine_entries | 30 | 30 |
| users | 31 | 31 |

**571/571 rows preserved** across all 16 populated business tables; complete per-table row-content SHA256 hashes identical before/after. These are synthetic-only fingerprints. All **27 FK** and **16 CHECK** violation counts zero; all are validated and enforced. Duplicate non-null active owner rejected (23505), missing FK rejected (23503), invalid v2 definition/owner rejected (23514); multiple NULL active owners and duplicate reset hashes accepted. All probes rolled back. Concurrent creation inside a transaction rejected (25001); induced invalid-build recovery passed. Temporary databases/server are stopped/deleted after evidence collection.

Full backend tests: **654 passed**, 90 existing Starlette deprecation warnings, **88.11s**. Final readiness recheck after formatting: **11 passed in 0.58s**. External services remain mocked by existing tests. No live provider/Blob/production smoke was performed.

## Files and delivery

- `backend/app/models/__init__.py`: declare retained routine index.
- `backend/migrations/versions/20261008_01_preserve_experiment_routine_index.py`: reviewed online, guarded additive revision; frozen baseline unchanged.
- `backend/app/main.py`: readiness requires new head.
- `backend/tests/test_operational_readiness.py`: head acceptance and stale/empty/unknown/multiple revision rejection.
- `backend/app/tools/rehearse_index_adoption.py`: reproducible synthetic rehearsal with hard loopback/environment guard, exact SQL execution, integrity/lock/failure checks; executes only through its main entry point.
- `docs/production-baseline-adoption.sql`: exact guarded psql sequence.
- `docs/production-release-runbook.md`: new head, adoption sequence, resume gate.
- `docs/index-reconciliation-20261008.md`: this rationale/results/recovery review.
- `docs/evidence/index-reconciliation-20261008/`: before/after read-only catalogs, unchanged proof, rehearsal/test results, SHA256 manifest.

Commit/push hash is recorded in the final delivery report after committing; same `main`, no production rollout or PR. Repository cleanliness and remote hash equality are checked after push.

## Exact guarded SQL file

```sql
-- REVIEWED PREPARATION ONLY: execution on production needs the rollout gate.
-- psql script: one dedicated connection, autocommit ON, never psql -1/--single-transaction.
-- Preconditions: fresh full schema/owner/grant/backup audit; same audited indexes;
-- no Alembic version; one migrator; checkpoint/journal policy satisfied.
-- Do not run the empty-database frozen baseline on existing tables.
\set ON_ERROR_STOP on
SET lock_timeout = '5s';
SET statement_timeout = '10min';
SELECT pg_advisory_lock(20261008, 1);
DO $$
BEGIN
  IF to_regclass('public.alembic_version') IS NOT NULL THEN
    RAISE EXCEPTION 'Already managed database: use reviewed migration path';
  END IF;
  IF to_regclass('public.ix_users_reset_token_hash') IS NOT NULL THEN
    RAISE EXCEPTION 'Reset index already exists: inspect validity/definition before resuming';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indexrelid=to_regclass('public.ix_experiments_routine_entry_id')
      AND i.indisvalid AND i.indisready AND i.indislive
      AND pg_get_indexdef(i.indexrelid) =
        'CREATE INDEX ix_experiments_routine_entry_id ON public.experiments USING btree (routine_entry_id)'
  ) THEN RAISE EXCEPTION 'Unexpected routine-entry index'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indexrelid=to_regclass('public.uq_experiments_active_owner')
      AND i.indisvalid AND i.indisready AND i.indislive AND i.indisunique
      AND NOT i.indnullsnotdistinct AND i.indpred IS NULL AND i.indexprs IS NULL
      AND pg_get_indexdef(i.indexrelid) =
        'CREATE UNIQUE INDEX uq_experiments_active_owner ON public.experiments USING btree (active_owner)'
      AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid=i.indexrelid)
  ) THEN RAISE EXCEPTION 'Unexpected standalone active-owner index'; END IF;
END $$;
-- Top-level standalone statement; cannot be in BEGIN, DO, or Alembic's default transaction.
-- No IF NOT EXISTS: an invalid/incorrect same-name index must never be silently adopted.
CREATE INDEX CONCURRENTLY ix_users_reset_token_hash
    ON public.users USING btree (reset_token_hash);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indexrelid=to_regclass('public.ix_users_reset_token_hash')
      AND i.indisvalid AND i.indisready AND i.indislive AND NOT i.indisunique
      AND NOT i.indnullsnotdistinct AND i.indpred IS NULL AND i.indexprs IS NULL
      AND pg_get_indexdef(i.indexrelid) =
        'CREATE INDEX ix_users_reset_token_hash ON public.users USING btree (reset_token_hash)'
  ) THEN RAISE EXCEPTION 'Reset index is not the reviewed valid full nonunique index'; END IF;
END $$;
-- STOP AT THIS BOUNDARY until application writes are paused and transactions drained.
-- The automated rollout runner must pause/drain BEFORE launching this entire script,
-- or execute the two stages separately on this SAME locked session.
BEGIN;
SET LOCAL statement_timeout = '30s';
-- Acquire the actual ALTER lock before the guard to avoid schema-change races.
LOCK TABLE public.experiments IN ACCESS EXCLUSIVE MODE;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indexrelid=to_regclass('public.uq_experiments_active_owner')
      AND i.indisvalid AND i.indisready AND i.indislive AND i.indisunique
      AND NOT i.indnullsnotdistinct AND i.indpred IS NULL AND i.indexprs IS NULL
      AND pg_get_indexdef(i.indexrelid) =
        'CREATE UNIQUE INDEX uq_experiments_active_owner ON public.experiments USING btree (active_owner)'
      AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid=i.indexrelid)
  ) THEN RAISE EXCEPTION 'Active-owner attachment precondition changed'; END IF;
END $$;
ALTER TABLE public.experiments
    ADD CONSTRAINT uq_experiments_active_owner
    UNIQUE USING INDEX uq_experiments_active_owner;
COMMIT;
SELECT c.conname, c.contype, c.convalidated, c.condeferrable,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c WHERE c.conrelid='public.experiments'::regclass
  AND c.conname='uq_experiments_active_owner';
SELECT i.indexrelid::regclass AS index_name, i.indisvalid, i.indisready,
       i.indislive, i.indisunique, i.indnullsnotdistinct,
       pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i WHERE i.indexrelid IN (
  'public.ix_experiments_routine_entry_id'::regclass,
  'public.ix_users_reset_token_hash'::regclass,
  'public.uq_experiments_active_owner'::regclass);
SELECT pg_advisory_unlock(20261008, 1);
-- Still paused: full schema_audit (must have no differences), manual CHECK/FK/
-- owner/ACL/policy/trigger audit and unchanged row counts. Only then ONE runner:
-- alembic stamp 20261006_01
-- alembic upgrade head   -- 20261008_01 validates and retains historical index
-- alembic check          -- must report no new upgrade operations
-- See index-reconciliation-20261008.md for retries/recovery and limits.
```
