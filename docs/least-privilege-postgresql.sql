-- REVIEW TEMPLATE ONLY. Do not run against production without separate authorization.
-- Run as server admin against a dedicated dermaire DB after schema/ownership audit.
-- Obtain random secrets from a secret store; never put passwords in source/control/logs.
CREATE ROLE dermaire_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE dermaire_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
GRANT CONNECT ON DATABASE dermaire TO dermaire_migrator, dermaire_runtime;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO dermaire_migrator;
GRANT USAGE ON SCHEMA public TO dermaire_runtime;
-- Existing production objects: reviewed per-object ALTER OWNER to migrator first.
-- Do not REASSIGN OWNED globally or grant admin membership to runtime.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO dermaire_runtime;
REVOKE INSERT, UPDATE, DELETE ON alembic_version FROM dermaire_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO dermaire_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE dermaire_migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dermaire_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE dermaire_migrator IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO dermaire_runtime;
-- Future migration metadata tables must be excluded/revoked individually.
-- Audit inherited memberships, PUBLIC privileges, functions/SECURITY DEFINER,
-- extensions and other schemas. Verify runtime DDL denial and migration head.
-- Retain migration secrets only in release-runner secret storage, not web settings.
-- After separate approval, replace app DB URL with runtime + verify-full CA trust;
-- smoke consent/review/delete, readiness/outage and rollback BEFORE revoking old access.
