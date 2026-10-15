# C2 freshness/history — PARTIAL

PSM sufficiency recency now uses the same elapsed UTC 14-day threshold as typed source freshness (exactly14d fresh;14d+1s stale), while age_days remains explicitly a UTC calendar difference. Sufficiency adds typed freshness. Finding adds earliest_evidence_at and freshness_basis=latest_referenced_evidence; latest reference recency does not certify every reference as fresh or clinically valid. source_read_consistency defaults to multiple_reads_not_atomic_snapshot; no model/contract algorithm version is presented as a database evidence revision.

Adherence cursor parsing now rejects naive positions/cutoffs, positions beyond cutoff, noninteger expiry and an expiry inconsistent with the original one-hour cutoff. Existing signed account/filter scope, owner predicates, deletion behavior, ordering and legacy offset route remain unchanged. A real PostgreSQL test commits an older-timestamp row and deletes a row between pages, demonstrating why the cursor is NOT a database snapshot. All-domain mutable history and arbitrary historical as_of reconstruction remain OPEN.

Focused:77 passed/1 dependency warning,2 real PG cases. No DDL, no expansion of doctor grants or sensitive PSM outputs. Full execution evidence follows.
`nFinal full:929 passed/189 dependency warnings/168.59s,43 real PG cases,zero failures/skips. Seeded SQLite/PG migration preservation and Alembic check passed at20261015_02; no new DDL. compileall and diff --check passed; no configured linter.
