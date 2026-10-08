-- REVIEW TEMPLATE ONLY. Do not run against production without separate authorization.
-- Run as server admin against a dedicated dermaire DB after schema/ownership audit.
-- Obtain random secrets from a secret store; never put passwords in source/control/logs.
CREATE ROLE dermaire_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE dermaire_runtime LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT CONNECT ON DATABASE dermaire TO dermaire_migrator, dermaire_runtime;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO dermaire_migrator;
GRANT USAGE ON SCHEMA public TO dermaire_runtime;
-- Existing production objects: reviewed per-object ALTER OWNER to migrator first.
-- Do not REASSIGN OWNED globally or grant admin membership to runtime.
-- Scope the current grants to the audited 16 business tables, not unrelated tables.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
    public.users, public.products, public.product_intelligence,
    public.experiments, public.experiment_evaluations, public.checkins,
    public.doctor_patient_access, public.doctor_review_actions, public.clinical_notes,
    public.audit_logs, public.reward_redemptions, public.daily_contexts,
    public.routine_entries, public.routine_adherence, public.captures, public.measurements
    TO dermaire_runtime;
REVOKE ALL PRIVILEGES ON TABLE public.alembic_version FROM dermaire_runtime;
GRANT SELECT ON TABLE public.alembic_version TO dermaire_runtime;
-- Dedicated application schema only; review sequence inventory before this grant.
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO dermaire_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE dermaire_migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dermaire_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE dermaire_migrator IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO dermaire_runtime;
-- Future migration metadata tables must be excluded/revoked individually.
-- Repeat metadata REVOKE ALL + GRANT SELECT after each migration: defaults above
-- grant CRUD to new tables. Reject any unrelated/new unreviewed schema objects.
-- Audit inherited memberships, PUBLIC privileges, functions/SECURITY DEFINER,
-- extensions and other schemas. Verify runtime DDL denial and migration head.
-- NOINHERIT is not a substitute for membership review: runtime must have no
-- admin/migrator membership, including SET ROLE paths. Audit PUBLIC function
-- EXECUTE/SECURITY DEFINER and remove any route to elevated application access.
-- Retain migration secrets only in release-runner secret storage, not web settings.
-- After separate approval, replace app DB URL with runtime + verify-full CA trust;
-- smoke consent/review/delete, readiness/outage and rollback BEFORE revoking old access.
