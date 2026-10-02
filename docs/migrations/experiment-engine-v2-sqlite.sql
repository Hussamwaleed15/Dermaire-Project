-- Experiment Engine v2. Run once after Routine Model v1, with API writes stopped.
-- Back up and inspect legacy active/paused/baseline rows first; no evidence is fabricated.
PRAGMA foreign_keys = ON;
BEGIN;
ALTER TABLE experiments ADD COLUMN engine_version INTEGER;
ALTER TABLE experiments ADD COLUMN routine_entry_id VARCHAR(36) REFERENCES routine_entries(id);
ALTER TABLE experiments ADD COLUMN intervention JSON;
ALTER TABLE experiments ADD COLUMN goal TEXT;
ALTER TABLE experiments ADD COLUMN notes TEXT;
ALTER TABLE experiments ADD COLUMN source VARCHAR(30);
ALTER TABLE experiments ADD COLUMN activated_at TIMESTAMP;
ALTER TABLE experiments ADD COLUMN stopped_at TIMESTAMP;
ALTER TABLE experiments ADD COLUMN definition_snapshot JSON;
ALTER TABLE experiments ADD COLUMN active_owner VARCHAR(36);
CREATE UNIQUE INDEX uq_experiments_active_owner ON experiments(active_owner);
CREATE INDEX ix_experiments_routine_entry_id ON experiments(routine_entry_id);
CREATE TABLE experiment_evaluations (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL REFERENCES users(id),
    experiment_id VARCHAR(36) NOT NULL REFERENCES experiments(id),
    result JSON NOT NULL,
    created_at TIMESTAMP NOT NULL
);
CREATE INDEX ix_experiment_evaluations_user_id ON experiment_evaluations(user_id);
CREATE INDEX ix_experiment_evaluations_experiment_id ON experiment_evaluations(experiment_id);
-- SQLite cannot add table CHECK constraints; equivalent triggers protect upgraded databases.
CREATE TRIGGER ck_experiment_v2_insert BEFORE INSERT ON experiments WHEN NEW.engine_version IS NOT NULL AND (NEW.engine_version <> 2 OR NEW.intervention IS NULL OR NEW.routine_entry_id IS NULL OR NEW.product_id IS NULL OR NEW.source IS NOT 'user_configured' OR NEW.status IS NULL OR NEW.target_days IS NULL OR NEW.status NOT IN ('draft','active','completed','stopped','cancelled') OR NEW.target_days NOT BETWEEN 7 AND 90 OR (NEW.status = 'active' AND (NEW.active_owner IS NOT NEW.user_id OR NEW.activated_at IS NULL OR NEW.definition_snapshot IS NULL)) OR (NEW.status <> 'active' AND NEW.active_owner IS NOT NULL)) BEGIN SELECT RAISE(ABORT, 'Invalid v2 experiment'); END;
CREATE TRIGGER ck_experiment_v2_update BEFORE UPDATE ON experiments WHEN NEW.engine_version IS NOT NULL AND (NEW.engine_version <> 2 OR NEW.intervention IS NULL OR NEW.routine_entry_id IS NULL OR NEW.product_id IS NULL OR NEW.source IS NOT 'user_configured' OR NEW.status IS NULL OR NEW.target_days IS NULL OR NEW.status NOT IN ('draft','active','completed','stopped','cancelled') OR NEW.target_days NOT BETWEEN 7 AND 90 OR (NEW.status = 'active' AND (NEW.active_owner IS NOT NEW.user_id OR NEW.activated_at IS NULL OR NEW.definition_snapshot IS NULL)) OR (NEW.status <> 'active' AND NEW.active_owner IS NOT NULL)) BEGIN SELECT RAISE(ABORT, 'Invalid v2 experiment'); END;
COMMIT;
