# Dermaire production rollout Phase 1 — 8 October 2026

**PHASE 1 COMPLETE.** Normal production writes/traffic are open. The existing deployed build now connects as `dermaire_runtime`, with no application sessions as `dermaireadmin`. Phase 2 was not started. Starting clean/pushed main and live origin/main were `2931dd3a40060e622230a001300cc0209a7f6bfa`. No subagents, new deployment, production-derived restore, raw row export, provider invocation or journal provisioning was used.

## Ordered production actions and timestamp evidence

All times below are UTC on 8 October; add three hours for Cairo. Request, commit acknowledgement and independent observation times are labeled explicitly.

| UTC timestamp | Action/result |
| --- | --- |
| 16:51:17.946243 request; 16:51:25.073863 confirmation | Production app stopped; write/traffic pause. Dedicated runner verified zero other DB client sessions before SQL. |
| 16:52:29.594148 independent confirmation | Guarded reviewed psql adoption file ran once: full nonunique `ix_users_reset_token_hash` created CONCURRENTLY outside a transaction; existing `uq_experiments_active_owner` attached with UNIQUE USING INDEX inside its guarded short transaction. Both valid/ready/live. No index drop/rebuild. |
| 16:53:50.408607 independent confirmation | Frozen baseline `20261006_01` stamped, then actual revision `20261008_01` executed. Independent read-only Alembic check and full metadata comparison clean; row counts and FK/CHECK scans passed. Routine-entry index preserved. |
| 16:54:13.984180 commit acknowledgement | Separate runtime/migrator roles, individual ownership transfers, scoped grants/default grants, PUBLIC database CREATE/TEMPORARY revocation and separate SCRAM credentials committed. |
| 16:54:24.088941 acknowledgement | Runtime negative-permission and rollback-only CRUD/duplicate/NULL smoke PASS. |
| 16:56:12.864838 request | Temporary main-site traffic restriction installed for operator verification; SCM policy unchanged. |
| 16:56:16.891988 request; 16:56:20.682688 confirmation | Only production App Setting `DATABASE_URL` changed to runtime, TLS verify-full and system CA trust. All other setting values identical. |
| 16:56:46.979711 request; 16:56:55.677992 confirmation | App started behind temporary traffic restriction. No deployment. |
| 16:58:36.891420 health; 16:58:44.192022 DB proof | Legacy /health 200; one actual application DB session as runtime, backend_start 16:58:34.094389; zero non-runner admin sessions. Startup health observed after 109.912 seconds. |
| 17:01:29.659442 request; 17:01:34.550954 confirmation | Original effective access policy restored; temporary restrictions removed; normal writes/traffic reopened, /health 200. |
| 17:02:52.130131 acknowledgement | Final independent full catalog/manual grant comparison and read-only Alembic check using the migrator credential PASS. |
| 17:06:05.561740 confirmation | Release scratch libraries/client/source/encrypted envelope and temporary RSA private key removed from production/staging SCM; absence independently checked. |

**Timestamp limitation:** the original adoption response contained Alembic's human-readable success line before JSON. The client initially rejected its framing and did not retain the original per-statement acknowledgement timestamps. Execution stopped for independent read-only verification; SQL was never replayed. The first two adoption entries above are exact observation timestamps, not invented commit instants. Mutation occurred after the pause confirmation and before those observations. PostgreSQL track_commit_timestamp is off; exact individual commit instants could not be recovered. This is an evidence/observability limitation, not a failed SQL/schema gate. Subsequent independent audits established successful adoption before any role/credential action.

## Fresh preflight and PITR policy

Read-only preflight began 16:36:05.875737; management/configuration/activity audit refreshed at 16:50:23.737386 immediately before maintenance. Canada Central, PostgreSQL 18.6, exact source resource ID, system identifier `7687509194730582065`, collation, backup/network/auth/storage configuration and production settings/catalog matched reviewed evidence. Only the known reset-index/standalone-owner representation differed from current ORM; routine-entry was already represented correctly. Business columns/defaults, ownership/grants, plpgsql extension, functions/triggers/policies and default privileges were reviewed.

Today's production-source drill was successfully DB-verified at 15:03:38.626468, and expires 9 October at that UTC time (18:03:38 Cairo). It was about 1h48m old at mutation. Latest automatic full backup: 07:19:42.755562 today; seven completed automatic full backups, seven-day retention, geo backup Disabled. Archived WAL advanced from 5315 at the drill to 5337/5338 in fresh reads and 5342 at final audit; failed_count zero, no failure timestamp, unchanged reset. Recorded fresh archive ages 150.312 seconds and 13.813 seconds. The guarded runner revalidated archive age <=300 seconds and continuity immediately before DDL.

Identity/configuration comparisons and intervening source/child operation review passed. Historical PITR firewall JSON withheld a client address; an exact retained local raw preflight snapshot matched current rules, and the activity audit found zero intervening production-source/child operations. No addresses are committed. Original sanitized PITR encryption field was absent; unchanged SystemManaged encryption continuity is supported by the intervening operation audit. These limits match the adopted prior policy evidence and are stated rather than hidden.

**24h PITR-validity policy PASS; full PITR SKIPPED.** No new restored server/verifier/production-data copy was created. This does not certify exact lost writes, continuous RPO, privacy-safe recovery or end-to-end RTO; existing runbook limitations remain.

## Schema and integrity

- Reset index is the exact reviewed full default btree, nonunique, no expression/predicate; valid/ready/live. Transactional synthetic smoke proved duplicate hashes and multiple NULLs accepted.
- Owner constraint is validated, NOT DEFERRABLE UNIQUE(active_owner), backed by the existing healthy unique index with NULLS DISTINCT. Duplicate non-NULL owner rejected (23505); multiple NULL owners accepted. No DROP/rebuild.
- `ix_experiments_routine_entry_id` remained present and valid/ready/live. Revision validated/adopted it. Frozen baseline source was unchanged; no empty-baseline CREATE statements were run on populated production.
- Stamp `20261006_01` → real upgrade `20261008_01`; clean complete ORM audit and independent read-only Alembic checks before roles and again using migrator afterward.
- All **399 business rows across 16 tables** preserved against counts captured after pause/drain. No production per-row/content hashes or raw records exported. Synthetic role smoke rolled back entirely. **27 FK and 16 CHECK scans: zero violations**, all validated/enforced; all indexes valid/ready/live. Business columns and FK/CHECK definitions unchanged; reset_token_attempts DEFAULT 0 retained.

## Roles, ownership and permission proof

`dermaire_runtime`: LOGIN, NOINHERIT, NOSUPERUSER, NOCREATEROLE, NOCREATEDB, NOREPLICATION, NOBYPASSRLS. No memberships, privileged SET ROLE path or object/database/schema/extension ownership. Scoped SELECT/INSERT/UPDATE/DELETE on exactly 16 business tables; revision SELECT only. No TRUNCATE/REFERENCES/TRIGGER. Sequence inventory is empty; reviewed sequence/default grants are retained for migration-created application sequences.

`dermaire_migrator`: LOGIN, default INHERIT, NOSUPERUSER, NOCREATEROLE, NOCREATEDB, NOREPLICATION, NOBYPASSRLS. Owns the 16 individually transferred business tables, Alembic metadata and associated indexes; public schema USAGE/CREATE and scoped migration defaults. System/database/schema/extension ownership was retained. Admin's SET membership in migrator was granted solely to execute the reviewed per-object owner transfer; runtime has no membership in either role. Migrator credentials remain only in encrypted release-owner storage, never web settings.

The reviewed least-privilege SQL was applied, with its required per-object transfers and PUBLIC/inherited/function review. PUBLIC schema CREATE remains revoked; PUBLIC database CREATE/TEMPORARY also revoked to close CREATE SCHEMA/temporary-table DDL routes. No public functions/SECURITY DEFINER functions, noninternal triggers or policies existed; plpgsql unchanged. Metadata write grants were explicitly excluded/revoked after migration. Repeat that metadata revocation after future migrations, because reviewed defaults grant business CRUD on new tables.

**11 actual runtime negative SQL probes passed:** permanent table CREATE, schema CREATE, temporary CREATE, ALTER, DROP, revision UPDATE, TRUNCATE, SET ROLE into admin/migrator/azure_pg_admin/pg_database_owner. Expected SQLSTATE 42501. CRUD privileges verified on every business table; actual synthetic user/experiment insert/select/update/delete and uniqueness/NULL probes completed inside a transaction then rolled back. Separate runtime and migrator secure logins succeeded.

## App switch, maintenance and rollback

Fresh random credentials were generated securely, stored as PostgreSQL SCRAM verifiers, and retained in a Windows DPAPI/current-user-ACL encrypted archive alongside original settings and access policy. A temporary RSA-3072 OAEP encrypted envelope allowed the isolated SCM release process to hold credentials only in memory; native /tmp private-key directory/file were 0700/0600, later removed. No plaintext credential file, command argument or repository secret was used.

Only DATABASE_URL changed among App Settings. Existing driver syntax was preserved for legacy build compatibility; sslmode=verify-full with the exact production hostname and system CA path. Runtime account confirmed both in securely inspected app settings and actual non-runner pg_stat_activity session after boot; no non-runner dermaireadmin session remained. Startup create_all in the legacy build only inspected already-present tables, and health succeeded under runtime restrictions. Deployed artifact/deployment ID `a1051873-4635-46aa-8fa8-7230b79a6097`, status 4/active, unchanged.

Safe current-build checks: / and /health 200; unauthenticated /api/v1/users/me 401; /health/live and /health/ready 404 expected until the new build. This proves current-build process/DB compatibility, not new-build full privacy/storage readiness.

Write/traffic pause lasted **616.605 seconds (10m16.6s)** from stop request to reopen confirmation. The app was first stopped, then started under operator-only traffic access. Azure ignored null default-action restoration and generated a deny catch-all; traffic stayed closed while the restore was completed. Original implicit Allow was explicitly restored as Allow, with the same effective catch-all rule and temporary rules removed. This is a configuration-representation normalization; normal access semantics were restored. All Phase 1 gates passed before normal writes reopened.

**No database/application rollback was needed or performed.** Additive indexes/constraint/revision and least privilege remain. Maintenance controls were restored; no destructive constraint/index reversal or restore was attempted. Secure rollback archive reference and ciphertext SHA256 are in phase1-result.json; current hash `c07b9b55548bffa5d75d89e8452bede721950cf367e5dc4d9864bab1d3386f20`. Original artifact hashes and settings references are retained without secret values. Old administrative credential remains a protected rollback reference, not the application runtime identity. Do not rerun the adoption script: the DB is now managed at 20261008_01 and roles already exist. Future migrations must use the reviewed migrator path.

## Checks and delivery

Relevant local operational-readiness/production-config tests: **41 passed**. Initial Windows default pytest temp access failure was resolved using workspace scratch; no code fix was necessary. Production negative SQL probes, rollback-only CRUD/semantics, catalog invariants, TLS/identity, startup/API safety and role-specific Alembic checks passed. Temporary SCM libraries/client/source/credential envelope/private key deleted and absence checked. Documentation/evidence only; reviewed SQL and migration/product source unchanged. Sanitized evidence manifest and git whitespace check are included/required. Commit/push/clean remote verification is recorded in the delivery response to avoid a self-referential hash.

**Phase 2 was NOT started:** no journal/HMAC provisioning, Blob changes, monitoring installation, new build deployment or provider activation. App Service work here was limited to the Phase 1 DB setting and temporary maintenance/start controls. Journal absence, private empty photo container and production monitoring gaps remain as observed; journal/key expiry stays disabled indefinitely. Phase 1 completion does not certify those later privacy/release gates.
