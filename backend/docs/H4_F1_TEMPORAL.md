# H4-F1 temporal consistency — PARTIAL

Routine and adherence responses add `day_basis: UTC`. Routine adds `configuration_history: current_with_adherence_snapshots`. No user timezone is stored, and AM/PM are user-reported slots, not wall-clock appointments. DST changes never shift the server UTC calendar. New adherence snapshots contain the explicit basis; old stored snapshots are not rewritten. Configuration earliest-day validation and baseline today status normalize aware instants to UTC; naive stored instants retain UTC interpretation.

Existing If-Match/ETag/CAS and stopped history remain unchanged. Full revision event history and user-local calendar migration remain OPEN; do not back-project today's configuration into earlier dates.

Verification: 64 focused passed / 33 warnings; full 894 passed / 172 warnings / zero failures or skips, 163.14s, including 37 real PostgreSQL cases and seeded SQLite/PG current-schema upgrades/check. PG18.6 UTC READ COMMITTED, new task-owned loopback cluster. No DDL. compileall and diff --check pass; no configured lint. Preliminary focused run hit Windows temp access errors (59 passed, 5 setup errors), then passed using an isolated workspace basetemp. Security review: no change to owner filters, consent, grants or mutation authority; frozen adherence and protected stale-client behavior tested.
