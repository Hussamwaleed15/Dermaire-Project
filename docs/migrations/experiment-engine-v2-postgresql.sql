-- Experiment Engine v2. Run once after Routine Model v1, with API writes stopped.
-- Back up and inspect legacy active/paused/baseline rows first; no evidence is fabricated.
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
ALTER TABLE experiments ADD CONSTRAINT ck_experiment_v2_definition CHECK (engine_version IS NULL OR (engine_version = 2 AND intervention IS NOT NULL AND routine_entry_id IS NOT NULL AND product_id IS NOT NULL AND source IS NOT NULL AND source = 'user_configured' AND status IS NOT NULL AND target_days IS NOT NULL AND status IN ('draft','active','completed','stopped','cancelled') AND target_days BETWEEN 7 AND 90));
ALTER TABLE experiments ADD CONSTRAINT ck_experiment_v2_owner CHECK (engine_version IS NULL OR ((status = 'active' AND active_owner IS NOT NULL AND active_owner = user_id AND activated_at IS NOT NULL AND definition_snapshot IS NOT NULL) OR (status <> 'active' AND active_owner IS NULL)));
COMMIT;
