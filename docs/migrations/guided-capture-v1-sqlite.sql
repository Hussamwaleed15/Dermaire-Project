-- Guided Capture v1: additive manual migration; apply before deploying.
BEGIN;

CREATE TABLE captures (
	id VARCHAR(36) NOT NULL,
	user_id VARCHAR(36) NOT NULL,
	state VARCHAR(20) NOT NULL,
	source VARCHAR(20) NOT NULL,
	"view" VARCHAR(20) NOT NULL,
	received_at DATETIME NOT NULL,
	quality JSON NOT NULL,
	storage VARCHAR(20) NOT NULL,
	image_blob_name VARCHAR(500),
	server_version VARCHAR(50) NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT ck_capture_state CHECK (state IN ('accepted','rejected')),
	CONSTRAINT ck_capture_origin CHECK (source IN ('camera','upload') AND view = 'front'),
	CONSTRAINT ck_capture_storage CHECK ((storage = 'not_persisted' AND image_blob_name IS NULL) OR (storage = 'azure_blob' AND image_blob_name IS NOT NULL AND state = 'accepted')),
	FOREIGN KEY(user_id) REFERENCES users (id)
)

;
CREATE INDEX ix_captures_user_id ON captures (user_id);
COMMIT;
