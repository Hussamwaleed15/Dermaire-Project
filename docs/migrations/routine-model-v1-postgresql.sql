-- Routine Model v1: additive manual migration; apply before deploying.
BEGIN;

CREATE TABLE routine_entries (
	id VARCHAR(36) NOT NULL,
	user_id VARCHAR(36) NOT NULL,
	product_id VARCHAR(36) NOT NULL,
	schedule VARCHAR(4) NOT NULL,
	frequency VARCHAR(20) NOT NULL,
	start_date DATE NOT NULL,
	end_date DATE,
	active BOOLEAN NOT NULL,
	instructions TEXT,
	am_order INTEGER NOT NULL,
	pm_order INTEGER NOT NULL,
	active_am_product VARCHAR(36),
	active_pm_product VARCHAR(36),
	source VARCHAR(30) NOT NULL,
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
	updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT ck_routine_schedule CHECK (schedule IN ('AM', 'PM', 'BOTH')),
	CONSTRAINT ck_routine_frequency CHECK (frequency = 'daily'),
	CONSTRAINT ck_routine_order CHECK (am_order BETWEEN 0 AND 100 AND pm_order BETWEEN 0 AND 100),
	CONSTRAINT ck_routine_source CHECK (source = 'user_configured'),
	CONSTRAINT ck_routine_end CHECK ((active AND end_date IS NULL) OR (NOT active AND end_date IS NOT NULL AND end_date >= start_date)),
	CONSTRAINT uq_routine_active_am UNIQUE (active_am_product),
	CONSTRAINT uq_routine_active_pm UNIQUE (active_pm_product),
	FOREIGN KEY(user_id) REFERENCES users (id),
	FOREIGN KEY(product_id) REFERENCES products (id)
);

CREATE INDEX ix_routine_entries_product_id ON routine_entries (product_id);

CREATE INDEX ix_routine_entries_user_id ON routine_entries (user_id);

CREATE TABLE routine_adherence (
	id VARCHAR(36) NOT NULL,
	user_id VARCHAR(36) NOT NULL,
	routine_entry_id VARCHAR(36) NOT NULL,
	date DATE NOT NULL,
	slot VARCHAR(2) NOT NULL,
	status VARCHAR(10) NOT NULL,
	note TEXT,
	source VARCHAR(30) NOT NULL,
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
	configuration_snapshot JSON NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_adherence_entry_day_slot UNIQUE (routine_entry_id, date, slot),
	CONSTRAINT ck_adherence_slot CHECK (slot IN ('AM', 'PM')),
	CONSTRAINT ck_adherence_status CHECK (status IN ('completed', 'skipped')),
	CONSTRAINT ck_adherence_source CHECK (source = 'user_reported'),
	FOREIGN KEY(user_id) REFERENCES users (id),
	FOREIGN KEY(routine_entry_id) REFERENCES routine_entries (id)
);

CREATE INDEX ix_routine_adherence_routine_entry_id ON routine_adherence (routine_entry_id);

CREATE INDEX ix_routine_adherence_user_id ON routine_adherence (user_id);

COMMIT;
