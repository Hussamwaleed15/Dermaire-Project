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
