-- Additive manual migration: apply once before backend deployment.
BEGIN;

CREATE TABLE measurements (
	id VARCHAR(36) NOT NULL,
	user_id VARCHAR(36) NOT NULL,
	capture_id VARCHAR(36) NOT NULL,
	algorithm_version VARCHAR(50) NOT NULL,
	status VARCHAR(30) NOT NULL,
	measured_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
	results JSON NOT NULL,
	quality_reference JSON NOT NULL,
	comparison JSON NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_measurement_capture_version UNIQUE (capture_id, algorithm_version),
	CONSTRAINT ck_measurement_status CHECK (status IN ('measured','insufficient_quality','unavailable','failed')),
	FOREIGN KEY(user_id) REFERENCES users (id),
	FOREIGN KEY(capture_id) REFERENCES captures (id)
)

;
CREATE INDEX ix_measurements_capture_id ON measurements (capture_id);
CREATE INDEX ix_measurements_user_id ON measurements (user_id);
COMMIT;
