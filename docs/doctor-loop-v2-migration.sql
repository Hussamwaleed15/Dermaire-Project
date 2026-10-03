-- Doctor Loop v2. Apply ONCE, against main 2a9f946 schema, before backend release.
-- PostgreSQL uses timestamp WITHOUT time zone, matching the existing ORM convention (UTC).
BEGIN;
ALTER TABLE doctor_patient_access ALTER COLUMN access_token TYPE varchar(512);
ALTER TABLE doctor_patient_access
    ADD COLUMN granted_by varchar(36),
    ADD COLUMN claimed_at timestamp without time zone,
    ADD COLUMN revoked_at timestamp without time zone,
    ADD COLUMN revoked_by varchar(36);
-- Do not fabricate historical consent actors or claim/revoke timestamps: legacy values stay NULL.
CREATE TABLE doctor_review_actions (
	id VARCHAR(36) NOT NULL,
	patient_id VARCHAR(36) NOT NULL,
	doctor_id VARCHAR(36) NOT NULL,
	access_id VARCHAR(36) NOT NULL,
	sequence INTEGER NOT NULL,
	state VARCHAR(30) NOT NULL,
	recommendation VARCHAR(30),
	rationale TEXT,
	patient_visible BOOLEAN NOT NULL,
	safety_snapshot JSON NOT NULL,
	created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT ck_doctor_review_state CHECK (state IN ('pending','in_review','reviewed','follow_up_needed')),
	CONSTRAINT ck_doctor_recommendation CHECK (recommendation IS NULL OR recommendation IN ('track','low_risk_self_care','doctor_review','urgent')),
	CONSTRAINT uq_doctor_review_sequence UNIQUE (patient_id, sequence),
	FOREIGN KEY(patient_id) REFERENCES users (id),
	FOREIGN KEY(doctor_id) REFERENCES users (id),
	FOREIGN KEY(access_id) REFERENCES doctor_patient_access (id)
);
CREATE INDEX ix_doctor_review_actions_access_id ON doctor_review_actions (access_id);
CREATE INDEX ix_doctor_review_actions_doctor_id ON doctor_review_actions (doctor_id);
CREATE INDEX ix_doctor_review_actions_patient_id ON doctor_review_actions (patient_id);
ALTER TABLE clinical_notes
    ADD COLUMN category varchar(50),
    ADD COLUMN patient_visible boolean,
    ADD COLUMN timeline_item_id varchar(255),
    ADD COLUMN review_action_id varchar(36) REFERENCES doctor_review_actions(id),
    ADD COLUMN updated_at timestamp without time zone;
-- Legacy notes remain INTERNAL. Preserve their real creation timestamp.
UPDATE clinical_notes SET patient_visible = false, updated_at = created_at;
-- Aborts if legacy creation timestamps are NULL: investigate rather than invent clinical history.
ALTER TABLE clinical_notes ALTER COLUMN patient_visible SET NOT NULL;
ALTER TABLE clinical_notes ALTER COLUMN updated_at SET NOT NULL;
-- Defaults, UUIDs and timestamps are application-side, exactly as in the ORM.
COMMIT;
