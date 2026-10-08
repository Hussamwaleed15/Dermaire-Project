-- REVIEW TEMPLATE: no production changes are authorized by this file.
-- STOP: 8 Oct 2026 fresh ORM comparison found additional unresolved index drift:
-- production has ix_experiments_routine_entry_id, absent from frozen ORM/baseline;
-- production lacks ix_users_reset_token_hash, required by ORM/frozen baseline.
-- The unique-index conversion below alone cannot establish schema equivalence.
-- Review/rehearse an additive repair and preserve the useful existing index;
-- do not stamp, drop that index, or run empty-baseline CREATE statements.
-- Verified 6 Oct 2026: PostgreSQL 18.6, 16 business tables, no Alembic version.
-- Active-owner uniqueness ALREADY EXISTS as this valid, ready, nonpartial index.
-- No missing column, type, nullability or collation drift was detected.
-- Preserve the compatible users.reset_token_attempts server DEFAULT 0.
-- Final owner/function/schema grants review and a write pause are prerequisites.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
-- Stop if the index definition/validity/readiness differs from audited evidence.
SELECT i.indisunique, i.indisvalid, i.indisready, i.indnullsnotdistinct,
       pg_get_expr(i.indpred, i.indrelid) AS predicate,
       pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i
WHERE i.indexrelid = 'public.uq_experiments_active_owner'::regclass;
-- Expected: unique=true, valid=true, ready=true, nulls_not_distinct=false,
-- predicate NULL, btree(active_owner). Operator must check these before proceeding.
-- Run this ALTER only after separate production authorization and preflight checks.
ALTER TABLE public.experiments
    ADD CONSTRAINT uq_experiments_active_owner
    UNIQUE USING INDEX uq_experiments_active_owner;
COMMIT;
-- Next: readonly schema audit, reviewed CHECK/trigger/policy/index/owner evidence,
-- then ONE migration runner may stamp 20261006_01 and run upgrade/check.
-- Never apply the frozen empty-database CREATE baseline to existing tables.
-- This conversion was rehearsed on 361 relational synthetic rows: 0.578 s;
-- no rows changed, no post-normalization Alembic drift, uniqueness still enforced.
